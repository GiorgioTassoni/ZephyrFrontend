import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../api/zephyr_api.dart';
import '../models/models.dart';
import '../utils/offline_storage.dart';
import '../utils/app_logger.dart';
import 'auth_provider.dart';
import 'player_provider.dart';

class LibraryState {
  final List<Track> downloadedTracks;
  final List<Playlist> playlists;
  final List<Track> favorites;
  final int? totalFavoritesCount;
  final List<HistoryEntry> history;
  final bool isLoading;
  final bool favoritesLoading;
  final bool hasMoreFavorites;
  final int favoritesOffset;
  final String? errorMessage;

  static const int _pageSize = 50;

  int get effectiveFavoritesCount => totalFavoritesCount ?? favorites.length;

  LibraryState({
    this.downloadedTracks = const [],
    this.playlists = const [],
    this.favorites = const [],
    this.totalFavoritesCount,
    this.history = const [],
    this.isLoading = false,
    this.favoritesLoading = false,
    this.hasMoreFavorites = true,
    this.favoritesOffset = 0,
    this.errorMessage,
  });

  LibraryState copyWith({
    List<Track>? downloadedTracks,
    List<Playlist>? playlists,
    List<Track>? favorites,
    int? totalFavoritesCount,
    List<HistoryEntry>? history,
    bool? isLoading,
    bool? favoritesLoading,
    bool? hasMoreFavorites,
    int? favoritesOffset,
    String? errorMessage,
  }) {
    return LibraryState(
      downloadedTracks: downloadedTracks ?? this.downloadedTracks,
      playlists: playlists ?? this.playlists,
      favorites: favorites ?? this.favorites,
      totalFavoritesCount: totalFavoritesCount ?? this.totalFavoritesCount,
      history: history ?? this.history,
      isLoading: isLoading ?? this.isLoading,
      favoritesLoading: favoritesLoading ?? this.favoritesLoading,
      hasMoreFavorites: hasMoreFavorites ?? this.hasMoreFavorites,
      favoritesOffset: favoritesOffset ?? this.favoritesOffset,
      errorMessage: errorMessage,
    );
  }
}

class LibraryNotifier extends Notifier<LibraryState> {
  final ZephyrApi _api = ZephyrApi();

  @override
  LibraryState build() {
    final isAuthenticated = ref.watch(authProvider.select((s) => s.isAuthenticated));

    if (!isAuthenticated) {
      return LibraryState();
    }
    Future.microtask(() => _startupLoad());
    return LibraryState(isLoading: true);
  }

  Future<void> loadLibrary({bool quiet = false}) async {
    if (!quiet && state.favorites.isEmpty && state.playlists.isEmpty) {
      state = state.copyWith(isLoading: true, errorMessage: null);
    }
    unawaited(flushOfflineHistory());
    try {
      // The four requests are independent — run them concurrently instead of
      // sequentially. Startup latency becomes the slowest single round trip
      // instead of the sum of all four. Each degrades independently on
      // failure (null → keep previous state / empty), preserving the old
      // per-request error tolerance.
      final serverTracksF = _guard(_api.getDownloadedTracks());
      final playlistsF = _guard(_api.getPlaylists());
      final favoritesF = _guard(_api.getFavoritesWithCount());
      final historyF = _guard(_api.getHistory());

      final serverTracks = await serverTracksF ?? const <Track>[];
      final playlists = await playlistsF ?? state.playlists;
      final favsResult = await favoritesF;
      final history = await historyF ?? state.history;

      List<Track> favorites = state.favorites;
      int? totalFavs = state.totalFavoritesCount;
      if (favsResult != null) {
        favorites = List.from(favsResult.tracks);
        totalFavs = favsResult.totalCount;
      }

      final offlineTracks = OfflineStorageService().getAllOfflineTracks();
      final Map<String, Track> mergedTracks = {
        for (final t in serverTracks) t.videoId: t,
        for (final t in offlineTracks) t.videoId: t,
      };
      final tracks = mergedTracks.values.toList();

      // Enrich history entries with track metadata
      final List<HistoryEntry> enrichedHistoryList = [];

      for (final entry in history) {
        Track? matchedTrack = entry.track;
        if (matchedTrack == null || matchedTrack.artists.isEmpty) {
          // search in downloaded
          try {
            matchedTrack =
                tracks.firstWhere((t) => t.videoId == entry.trackId && t.artists.isNotEmpty);
          } catch (_) {
            // search in favorites
            try {
              matchedTrack =
                  favorites.firstWhere((t) => t.videoId == entry.trackId && t.artists.isNotEmpty);
            } catch (_) {}
          }
        }

        if (matchedTrack != null && matchedTrack.artists.isNotEmpty) {
          enrichedHistoryList.add(HistoryEntry(
            id: entry.id,
            userId: entry.userId,
            trackId: entry.trackId,
            listenedAt: entry.listenedAt,
            track: matchedTrack,
          ));
        } else {
          enrichedHistoryList.add(entry);
        }
      }

      // Sort history entries back to descending listenedAt order
      enrichedHistoryList
          .sort((a, b) => b.listenedAt.compareTo(a.listenedAt));

      final bool hasMoreFavs = totalFavs != null && favorites.length < totalFavs && favorites.length >= LibraryState._pageSize;

      state = LibraryState(
        downloadedTracks: tracks,
        playlists: playlists,
        favorites: favorites,
        totalFavoritesCount: totalFavs,
        favoritesOffset: favorites.length,
        hasMoreFavorites: hasMoreFavs,
        history: enrichedHistoryList,
        isLoading: false,
      );

      // Persist the freshly loaded library so the next app start can render
      // instantly from cache (stale-while-revalidate) instead of blocking on
      // the network.
      unawaited(_persistLibraryCache(
        tracks: tracks,
        playlists: playlists,
        favorites: favorites,
        totalFavoritesCount: totalFavs,
        history: enrichedHistoryList,
      ));

      if (!quiet) {
        // If player has no track loaded, load the last listened track from history paused
        final playerNotifier = ref.read(playerProvider.notifier);
        if (playerNotifier.state.currentTrack == null && enrichedHistoryList.isNotEmpty) {
          final lastTrack = enrichedHistoryList
              .map((e) => e.track)
              .firstWhere(
                (t) => t != null && t.title != 'Unknown Track' && t.title.isNotEmpty,
                orElse: () => null,
              );
          if (lastTrack != null) {
            final queue = enrichedHistoryList
                .map((e) => e.track)
                .whereType<Track>()
                .where((t) => t.title != 'Unknown Track' && t.title.isNotEmpty)
                .toList();
            playerNotifier.loadTrackPaused(lastTrack, queue);
          }
        }
      }
    } catch (e, stackTrace) {
      debugPrint("Library load error: $e");
      debugPrint(stackTrace.toString());
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Failed to load library: $e',
      );
    }
  }

  Future<void> refreshLibrary() async {
    await loadLibrary();
  }

  /// Awaits [future], converting any failure into null so one failed request
  /// cannot take down the whole (parallel) library load.
  Future<T?> _guard<T>(Future<T> future) async {
    try {
      return await future;
    } catch (e) {
      debugPrint('Library partial load failure: $e');
      return null;
    }
  }

  /// Startup path: render instantly from the last persisted library when one
  /// exists, then refresh from the network (stale-while-revalidate).
  Future<void> _startupLoad() async {
    await _hydrateFromCache();
    await loadLibrary();
  }

  /// Restores the previous session's library from the local cache so the UI
  /// has content before the first network response arrives. Returns true
  /// when a non-empty cache was applied.
  Future<bool> _hydrateFromCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final data = LibraryCache.decode(prefs.getString(LibraryCache.prefKey));
      if (data == null) return false;

      final tracks = ((data['tracks'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => Track.fromJson(Map<String, dynamic>.from(e)))
          .toList();
      final playlists = ((data['playlists'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => Playlist.fromJson(Map<String, dynamic>.from(e)))
          .toList();
      final favorites = ((data['favorites'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => Track.fromJson(Map<String, dynamic>.from(e)))
          .toList();
      final history = ((data['history'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => HistoryEntry.fromJson(Map<String, dynamic>.from(e)))
          .toList();
      final totalFavs =
          data['total_favorites'] is int ? data['total_favorites'] as int : null;

      if (tracks.isEmpty &&
          playlists.isEmpty &&
          favorites.isEmpty &&
          history.isEmpty) {
        return false;
      }

      final bool hasMoreFavs = totalFavs != null &&
          favorites.length < totalFavs &&
          favorites.length >= LibraryState._pageSize;

      state = LibraryState(
        downloadedTracks: tracks,
        playlists: playlists,
        favorites: favorites,
        totalFavoritesCount: totalFavs,
        favoritesOffset: favorites.length,
        hasMoreFavorites: hasMoreFavs,
        history: history,
        isLoading: false,
      );
      AppLogger.instance.logSystem('library_cache_hydrated', data: {
        'tracks': tracks.length,
        'playlists': playlists.length,
        'favorites': favorites.length,
        'history': history.length,
      });
      return true;
    } catch (e) {
      debugPrint('Library cache hydration failed: $e');
      return false;
    }
  }

  Future<void> _persistLibraryCache({
    required List<Track> tracks,
    required List<Playlist> playlists,
    required List<Track> favorites,
    required int? totalFavoritesCount,
    required List<HistoryEntry> history,
  }) async {
    try {
      final encoded = jsonEncode(LibraryCache.encode(
        tracks: tracks,
        playlists: playlists,
        favorites: favorites,
        totalFavoritesCount: totalFavoritesCount,
        history: history,
      ));
      // Safety valve: an absurdly large library would make the
      // SharedPreferences write slower than the cache saves.
      if (encoded.length > LibraryCache.maxEncodedBytes) {
        AppLogger.instance.logSystem('library_cache_skipped_too_large');
        return;
      }
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(LibraryCache.prefKey, encoded);
    } catch (e) {
      debugPrint('Library cache persist failed: $e');
    }
  }

  // --- Favorites ---

  /// Returns the canonical ID used by the backend for favorite identity.
  /// Numeric Deezer IDs are normalized to the documented `dz_<id>` form;
  /// every other ID remains an exact, case-sensitive identifier.
  static String _canonicalTrackId(String videoId) {
    final id = videoId.trim();
    if (id.isEmpty) return '';
    return RegExp(r'^\d+$').hasMatch(id) ? 'dz_$id' : id;
  }

  /// Favorite state is identity-based only. Titles and artist names are not
  /// unique enough to identify a track (versions, remixes, and live recordings
  /// commonly share similar metadata).
  bool isFavorite(String videoId, {String? title, List<String>? artists}) {
    final targetId = _canonicalTrackId(videoId);
    if (targetId.isEmpty) return false;
    return state.favorites.any((track) => _canonicalTrackId(track.videoId) == targetId);
  }

  /// Resets pagination and fetches the first page of favorites (offset=0).
  /// Reads X-Total-Count directly from the response header to know the exact
  /// total count without needing to load all pages upfront.
  Future<void> loadFavorites() async {
    state = state.copyWith(
      favoritesLoading: true,
      hasMoreFavorites: false,
      favoritesOffset: 0,
    );
    try {
      final favsResult = await _api.getFavoritesWithCount();
      final List<Track> tracks = List.from(favsResult.tracks);

      state = state.copyWith(
        favorites: tracks,
        totalFavoritesCount: favsResult.totalCount,
        favoritesOffset: tracks.length,
        hasMoreFavorites: false,
        favoritesLoading: false,
      );
    } catch (e) {
      state = state.copyWith(
        favoritesLoading: false,
        errorMessage: 'Failed to load favorites: $e',
      );
    }
  }

  /// Fetches the next page and appends it to the list.
  /// Safe to call even if already loading or if there are no more pages.
  Future<void> loadMoreFavorites() async {
    if (state.favoritesLoading || !state.hasMoreFavorites) return;
    state = state.copyWith(favoritesLoading: true);
    try {
      final currentOffset = state.favorites.length;
      final page = await _api.getFavoritesWithCount(offset: currentOffset);

      final existingIds = state.favorites.map((t) => t.videoId).toSet();
      final newUniqueTracks = page.tracks.where((t) => !existingIds.contains(t.videoId)).toList();
      final merged = [...state.favorites, ...newUniqueTracks];

      final bool hasMore = page.tracks.isNotEmpty && (merged.length < page.totalCount);
      state = state.copyWith(
        favorites: merged,
        totalFavoritesCount: page.totalCount,
        favoritesLoading: false,
        favoritesOffset: merged.length,
        hasMoreFavorites: hasMore,
      );
    } catch (e) {
      state = state.copyWith(
        favoritesLoading: false,
        errorMessage: 'Failed to load more favorites: $e',
      );
    }
  }

  Future<void> toggleFavorite(Track track) async {
    final videoId = track.videoId;
    final isFav = isFavorite(videoId, title: track.title, artists: track.artists);

    // Optimistic UI update — insert at index 0 so newly-added tracks appear
    // at the top of the list (matching server order: newest first).
    final currentFavorites = List<Track>.from(state.favorites);
    if (isFav) {
      final targetId = _canonicalTrackId(videoId);
      currentFavorites.removeWhere(
        (favorite) => _canonicalTrackId(favorite.videoId) == targetId,
      );
    } else {
      currentFavorites.insert(
        0,
        track.copyWith(favoritedAt: DateTime.now().toUtc()),
      );
    }
    final currentTotal = state.totalFavoritesCount ?? state.favorites.length;
    final newTotal = isFav ? (currentTotal > 0 ? currentTotal - 1 : 0) : currentTotal + 1;
    state = state.copyWith(
      favorites: currentFavorites,
      totalFavoritesCount: newTotal,
    );

    AppLogger.instance.logFavorite('toggle_requested', data: {
      'trackId': _canonicalTrackId(videoId),
      'wasFavorite': isFav,
    });

    try {
      if (isFav) {
        await _api.removeFavorite(videoId);
      } else {
        await _api.addFavorite(videoId);
      }
      // Reload authoritative favorites list with metadata from backend
      await loadFavorites();
      // Reload downloaded tracks, since adding to favorites might auto-download
      final updatedTracks = await _api.getDownloadedTracks();
      state = state.copyWith(downloadedTracks: updatedTracks);
    } catch (e) {
      // Revert on error
      await loadFavorites();
    }
  }

  // --- Playlists ---

  Future<void> createPlaylist(
      String name, String description, bool isPublic, {File? coverImage}) async {
    try {
      final playlist = await _api.createPlaylist(name, description, isPublic);
      if (coverImage != null) {
        await _api.uploadPlaylistCover(playlist.id, coverImage);
      }
      await loadLibrary();
    } catch (e) {
      state = state.copyWith(errorMessage: 'Failed to create playlist: $e');
    }
  }

  Future<void> updatePlaylist(dynamic id,
      {String? name, String? description, bool? isPublic}) async {
    try {
      await _api.updatePlaylist(id,
          name: name, description: description, isPublic: isPublic);
      await loadLibrary();
    } catch (e) {
      state = state.copyWith(errorMessage: 'Failed to update playlist: $e');
    }
  }

  Future<void> deletePlaylist(dynamic id) async {
    try {
      await _api.deletePlaylist(id);
      await loadLibrary();
    } catch (e) {
      state = state.copyWith(errorMessage: 'Failed to delete playlist: $e');
    }
  }

  Future<void> savePlaylist(dynamic id) async {
    try {
      final pId = (id is int) ? id : (int.tryParse(id.toString()) ?? 0);
      if (pId <= 0) return;
      await _api.savePlaylist(pId);
      await loadLibrary();
    } catch (e) {
      state = state.copyWith(errorMessage: 'Failed to save playlist: $e');
    }
  }

  Future<void> unsavePlaylist(dynamic id) async {
    try {
      final pId = (id is int) ? id : (int.tryParse(id.toString()) ?? 0);
      if (pId <= 0) return;
      await _api.unsavePlaylist(pId);
      await loadLibrary();
    } catch (e) {
      state = state.copyWith(errorMessage: 'Failed to unsave playlist: $e');
    }
  }

  Future<void> toggleSavePlaylist(Playlist playlist) async {
    if (playlist.isSaved) {
      await unsavePlaylist(playlist.id);
    } else {
      await savePlaylist(playlist.id);
    }
  }

  Future<void> uploadPlaylistCover(dynamic id, File imageFile) async {
    try {
      await _api.uploadPlaylistCover(id, imageFile);
      await loadLibrary();
    } catch (e) {
      state = state.copyWith(
          errorMessage: 'Failed to upload playlist cover: $e');
    }
  }

  Future<void> addTrackToPlaylist(dynamic playlistId, Track track) async {
    try {
      final pId = (playlistId is int) ? playlistId : (int.tryParse(playlistId.toString()) ?? 0);
      await _api.addTrackToPlaylist(pId, track.videoId);
      await loadLibrary();
    } catch (e) {
      final errStr = e.toString().toLowerCase();
      final isDuplicate = errStr.contains('duplicate') ||
          errStr.contains('already') ||
          errStr.contains('400') ||
          errStr.contains('409');
      final userMessage = isDuplicate
          ? 'Track is already in this playlist'
          : 'Failed to add track to playlist: $e';
      state = state.copyWith(errorMessage: userMessage);
      rethrow;
    }
  }

  Future<void> removeTrackFromPlaylist(dynamic playlistId, String trackId) async {
    try {
      final pId = (playlistId is int) ? playlistId : (int.tryParse(playlistId.toString()) ?? 0);
      await _api.removeTrackFromPlaylist(pId, trackId);
      await loadLibrary();
    } catch (e) {
      state = state.copyWith(errorMessage: 'Failed to remove track: $e');
    }
  }

  Future<void> reorderPlaylistTracks(
      dynamic playlistId, List<String> newOrder) async {
    try {
      final pId = (playlistId is int) ? playlistId : (int.tryParse(playlistId.toString()) ?? 0);
      await _api.reorderPlaylistTracks(pId, newOrder);
      // Update playlist tracks in state locally
      final updatedPlaylists = state.playlists.map((p) {
        if (p.id.toString() == playlistId.toString()) {
          final tracks = List<Track>.from(p.tracks ?? []);
          final reorderedTracks = <Track>[];
          for (final id in newOrder) {
            final t =
                tracks.firstWhere((element) => element.videoId == id);
            reorderedTracks.add(t);
          }
          return Playlist(
            id: p.id,
            userId: p.userId,
            name: p.name,
            description: p.description,
            coverPath: p.coverPath,
            isPublic: p.isPublic,
            createdAt: p.createdAt,
            updatedAt: p.updatedAt,
            tracks: reorderedTracks,
          );
        }
        return p;
      }).toList();
      state = state.copyWith(playlists: updatedPlaylists);
    } catch (e) {
      state = state.copyWith(errorMessage: 'Failed to reorder tracks: $e');
      loadLibrary();
    }
  }

  String _generateUuidV4() {
    final random = Random.secure();
    final values = List<int>.generate(16, (i) => random.nextInt(256));
    values[6] = (values[6] & 0x0f) | 0x40; // version 4
    values[8] = (values[8] & 0x3f) | 0x80; // IETF variant
    return [
      values.sublist(0, 4).map((b) => b.toRadixString(16).padLeft(2, '0')).join(),
      values.sublist(4, 6).map((b) => b.toRadixString(16).padLeft(2, '0')).join(),
      values.sublist(6, 8).map((b) => b.toRadixString(16).padLeft(2, '0')).join(),
      values.sublist(8, 10).map((b) => b.toRadixString(16).padLeft(2, '0')).join(),
      values.sublist(10, 16).map((b) => b.toRadixString(16).padLeft(2, '0')).join(),
    ].join('-');
  }

  static const String _offlineHistoryBufferKey = 'offline_history_buffer';

  Future<void> recordListen(String trackId, [Track? track]) async {
    if (track != null) {
      await addListeningHistory(track);
    }
    final clientId = _generateUuidV4();
    final playedAt = DateTime.now().toUtc().toIso8601String();
    try {
      await _api.recordListen(trackId);
    } catch (_) {
      // Offline or network error: buffer locally for sync
      await _bufferOfflineListen({
        'track_id': trackId,
        'played_at': playedAt,
        'client_id': clientId,
      });
    }
  }

  Future<void> _bufferOfflineListen(Map<String, dynamic> entry) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final rawList = prefs.getStringList(_offlineHistoryBufferKey) ?? [];
      rawList.add(jsonEncode(entry));
      await prefs.setStringList(_offlineHistoryBufferKey, rawList);
    } catch (_) {}
  }

  Future<void> flushOfflineHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final rawList = prefs.getStringList(_offlineHistoryBufferKey) ?? [];
      if (rawList.isEmpty) return;

      final List<Map<String, dynamic>> buffered = [];
      for (final item in rawList) {
        try {
          buffered.add(Map<String, dynamic>.from(jsonDecode(item)));
        } catch (_) {}
      }
      if (buffered.isEmpty) {
        await prefs.remove(_offlineHistoryBufferKey);
        return;
      }

      // Max 1000 items per request
      const int batchCap = 1000;
      for (var i = 0; i < buffered.length; i += batchCap) {
        final end = (i + batchCap < buffered.length) ? i + batchCap : buffered.length;
        final chunk = buffered.sublist(i, end);
        await _api.syncHistory(chunk);
      }

      await prefs.remove(_offlineHistoryBufferKey);
      await handleLibraryEvent(scope: 'history');
    } catch (_) {
      // Keep in buffer for next retry
    }
  }

  Future<void> addListeningHistory(Track track) async {
    // Add listening history entry locally to feel instantaneous
    final currentHistory = List<HistoryEntry>.from(state.history);

    // Check if it was already in history and remove to move to top
    currentHistory.removeWhere((entry) => entry.trackId == track.videoId);

    currentHistory.insert(
      0,
      HistoryEntry(
        id: DateTime.now().millisecondsSinceEpoch,
        userId: 0,
        trackId: track.videoId,
        listenedAt: DateTime.now(),
        track: track,
      ),
    );

    if (currentHistory.length > 75) {
      currentHistory.removeLast();
    }

    state = state.copyWith(history: currentHistory);
  }

  Future<void> handleLibraryEvent({
    String? scope,
    String? action,
    dynamic playlistId,
    String? trackId,
  }) async {
    try {
      if (scope == 'favorites') {
        await loadFavorites();
      } else if (scope == 'playlists') {
        final playlists = await _api.getPlaylists();
        state = state.copyWith(playlists: playlists);
      } else if (scope == 'history') {
        final history = await _api.getHistory();
        final List<HistoryEntry> enrichedHistoryList = [];
        for (final entry in history) {
          Track? matched = state.downloadedTracks.cast<Track?>().firstWhere(
            (t) => t?.videoId == entry.trackId,
            orElse: () => null,
          ) ?? state.favorites.cast<Track?>().firstWhere(
            (t) => t?.videoId == entry.trackId,
            orElse: () => null,
          );
          if (matched != null) {
            enrichedHistoryList.add(HistoryEntry(
              id: entry.id,
              userId: entry.userId,
              trackId: entry.trackId,
              listenedAt: entry.listenedAt,
              track: matched,
            ));
          } else {
            enrichedHistoryList.add(entry);
          }
        }
        enrichedHistoryList.sort((a, b) => b.listenedAt.compareTo(a.listenedAt));
        state = state.copyWith(history: enrichedHistoryList);
      }
    } catch (_) {}
  }

  Future<void> handleTrackStatusEvent({
    required String trackId,
    required String downloadStatus,
  }) async {
    final bool isCompleted = downloadStatus == 'completed';

    // 1. Update favorites list
    final updatedFavorites = state.favorites.map((t) {
      if (t.videoId == trackId || t.videoId == 'dz_$trackId' || trackId == 'dz_${t.videoId}') {
        return t.copyWith(
          downloadStatus: downloadStatus,
          isDownloaded: isCompleted,
        );
      }
      return t;
    }).toList();

    // 2. Update playlists tracks
    final updatedPlaylists = state.playlists.map((p) {
      if (p.tracks == null || p.tracks!.isEmpty) return p;
      final updatedTracks = p.tracks!.map((t) {
        if (t.videoId == trackId || t.videoId == 'dz_$trackId' || trackId == 'dz_${t.videoId}') {
          return t.copyWith(
            downloadStatus: downloadStatus,
            isDownloaded: isCompleted,
          );
        }
        return t;
      }).toList();
      return Playlist(
        id: p.id,
        userId: p.userId,
        name: p.name,
        description: p.description,
        coverPath: p.coverPath,
        isPublic: p.isPublic,
        createdAt: p.createdAt,
        updatedAt: p.updatedAt,
        tracks: updatedTracks,
      );
    }).toList();

    // 3. Update downloaded tracks
    List<Track> updatedDownloaded = List.from(state.downloadedTracks);
    final downloadIndex = updatedDownloaded.indexWhere(
      (t) => t.videoId == trackId || t.videoId == 'dz_$trackId' || trackId == 'dz_${t.videoId}',
    );

    if (downloadIndex != -1) {
      updatedDownloaded[downloadIndex] = updatedDownloaded[downloadIndex].copyWith(
        downloadStatus: downloadStatus,
        isDownloaded: isCompleted,
      );
    } else if (isCompleted) {
      try {
        final newMeta = await _api.getTrackMetadata(trackId);
        if (!updatedDownloaded.any((t) => t.videoId == newMeta.videoId)) {
          updatedDownloaded.insert(0, newMeta);
        }
      } catch (_) {}
    }

    state = state.copyWith(
      favorites: updatedFavorites,
      playlists: updatedPlaylists,
      downloadedTracks: updatedDownloaded,
    );
  }
}

/// Local persistence for the last successfully loaded library.
///
/// Enables stale-while-revalidate startup: the UI renders the previous
/// session's tracks/playlists/favorites/history immediately while a network
/// refresh runs. Payloads are versioned; undecodable or foreign-version
/// payloads decode to null and the app falls back to a cold load.
class LibraryCache {
  static const int version = 1;
  static const String prefKey = 'zephyr_library_cache_v1';
  static const int maxHistoryEntries = 60;

  /// Refuse to persist payloads beyond ~5 MB — a SharedPreferences write of
  /// that size would stall startup more than the cache saves.
  static const int maxEncodedBytes = 5 * 1024 * 1024;

  static Map<String, dynamic> encode({
    required List<Track> tracks,
    required List<Playlist> playlists,
    required List<Track> favorites,
    required int? totalFavoritesCount,
    required List<HistoryEntry> history,
  }) {
    return {
      'v': version,
      'saved_at': DateTime.now().toUtc().toIso8601String(),
      'tracks': tracks.map((t) => t.toJson()).toList(),
      'playlists': playlists.map((p) => p.toJson()).toList(),
      'favorites': favorites.map((t) => t.toJson()).toList(),
      'total_favorites': totalFavoritesCount,
      'history':
          history.take(maxHistoryEntries).map((h) => h.toJson()).toList(),
    };
  }

  /// Returns null for missing, malformed or foreign-version payloads.
  static Map<String, dynamic>? decode(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final Object? data = jsonDecode(raw);
      if (data is! Map<String, dynamic>) return null;
      if (data['v'] != version) return null;
      return data;
    } catch (_) {
      return null;
    }
  }
}

final libraryProvider =
    NotifierProvider<LibraryNotifier, LibraryState>(LibraryNotifier.new);
