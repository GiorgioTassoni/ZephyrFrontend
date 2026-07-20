import 'dart:async';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../api/zephyr_api.dart';
import '../models/models.dart';
import 'auth_provider.dart';
import 'player_provider.dart';

class LibraryState {
  final List<Track> downloadedTracks;
  final List<Playlist> playlists;
  final List<Track> favorites;
  final List<HistoryEntry> history;
  final bool isLoading;
  final bool favoritesLoading;
  final bool hasMoreFavorites;
  final int favoritesOffset;
  final String? errorMessage;

  static const int _pageSize = 50;

  LibraryState({
    this.downloadedTracks = const [],
    this.playlists = const [],
    this.favorites = const [],
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
  Timer? _pollTimer;

  @override
  LibraryState build() {
    final authState = ref.watch(authProvider);

    ref.onDispose(() {
      _pollTimer?.cancel();
    });

    if (!authState.isAuthenticated) {
      _pollTimer?.cancel();
      _pollTimer = null;
      return LibraryState();
    }
    Future.microtask(() => loadLibrary());
    return LibraryState(isLoading: true);
  }

  Future<void> loadLibrary({bool quiet = false}) async {
    if (!quiet) {
      state = state.copyWith(isLoading: true, errorMessage: null);
    }
    try {
      final tracks = await _api.getDownloadedTracks();
      final playlists = await _api.getPlaylists();
      // Favorites are NOT fetched here — they are loaded on-demand when the
      // user opens the Favorites tab via loadFavorites().
      final favorites = state.favorites; // keep existing stale list for isFavorite()
      final history = await _api.getHistory();

      // Enrich history entries with track metadata
      final List<HistoryEntry> enrichedHistoryList = [];
      final List<Future<void>> enrichmentFutures = [];

      for (final entry in history) {
        Track? matchedTrack = entry.track;
        if (matchedTrack == null) {
          // search in downloaded
          try {
            matchedTrack =
                tracks.firstWhere((t) => t.videoId == entry.trackId);
          } catch (_) {
            // search in favorites
            try {
              matchedTrack =
                  favorites.firstWhere((t) => t.videoId == entry.trackId);
            } catch (_) {}
          }
        }

        if (matchedTrack != null) {
          enrichedHistoryList.add(HistoryEntry(
            id: entry.id,
            userId: entry.userId,
            trackId: entry.trackId,
            listenedAt: entry.listenedAt,
            track: matchedTrack,
          ));
        } else {
          // If we couldn't match locally, fetch from the API!
          final future =
              _api.getTrackMetadata(entry.trackId).then((trackMeta) {
            enrichedHistoryList.add(HistoryEntry(
              id: entry.id,
              userId: entry.userId,
              trackId: entry.trackId,
              listenedAt: entry.listenedAt,
              track: trackMeta,
            ));
          }).catchError((_) {
            // If API fetch fails, still add the entry (without track metadata)
            enrichedHistoryList.add(entry);
          });
          enrichmentFutures.add(future);
        }
      }

      if (enrichmentFutures.isNotEmpty) {
        await Future.wait(enrichmentFutures);
      }

      // Sort history entries back to descending listenedAt order
      enrichedHistoryList
          .sort((a, b) => b.listenedAt.compareTo(a.listenedAt));

      state = LibraryState(
        downloadedTracks: tracks,
        playlists: playlists,
        favorites: favorites,
        history: enrichedHistoryList,
        isLoading: false,
      );

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

      // Check if we need to start/stop quiet background status checking
      _checkAndStartDownloadPolling(tracks, favorites);
    } catch (e, stackTrace) {
      print("Library load error: $e");
      print(stackTrace);
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Failed to load library: $e',
      );
    }
  }

  bool _hasActiveDownloads(List<Track> downloaded, List<Track> favorites) {
    final activeInDownloaded = downloaded.any((t) =>
        t.downloadStatus == 'downloading' || t.downloadStatus == 'pending');
    final activeInFavorites = favorites.any((t) =>
        t.downloadStatus == 'downloading' || t.downloadStatus == 'pending');
    return activeInDownloaded || activeInFavorites;
  }

  void _checkAndStartDownloadPolling(
      List<Track> downloaded, List<Track> favorites) {
    if (_hasActiveDownloads(downloaded, favorites)) {
      if (_pollTimer == null || !_pollTimer!.isActive) {
        _pollTimer = Timer.periodic(const Duration(seconds: 4), (timer) async {
          // Check if we are still authenticated before polling
          final auth = ref.read(authProvider);
          if (!auth.isAuthenticated) {
            timer.cancel();
            _pollTimer = null;
            return;
          }
          await loadLibrary(quiet: true);
        });
      }
    } else {
      _pollTimer?.cancel();
      _pollTimer = null;
    }
  }

  Future<void> refreshLibrary() async {
    await loadLibrary();
  }

  // --- Favorites ---

  bool isFavorite(String videoId) {
    return state.favorites.any((t) => t.videoId == videoId);
  }

  /// Resets pagination and fetches the first page of favorites (offset=0).
  /// Call this whenever the user opens the Favorites tab so the list is
  /// always accurate and correctly ordered (newest first from the server).
  Future<void> loadFavorites() async {
    state = state.copyWith(
      favoritesLoading: true,
      hasMoreFavorites: true,
      favoritesOffset: 0,
    );
    try {
      final page = await _api.getFavorites(offset: 0);
      state = state.copyWith(
        favorites: page,
        favoritesLoading: false,
        favoritesOffset: page.length,
        hasMoreFavorites: page.length >= LibraryState._pageSize,
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
      final page = await _api.getFavorites(offset: state.favoritesOffset);
      final merged = [...state.favorites, ...page];
      state = state.copyWith(
        favorites: merged,
        favoritesLoading: false,
        favoritesOffset: merged.length,
        hasMoreFavorites: page.length >= LibraryState._pageSize,
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
    final isFav = isFavorite(videoId);

    // Optimistic UI update — insert at index 0 so newly-added tracks appear
    // at the top of the list (matching server order: newest first).
    final currentFavorites = List<Track>.from(state.favorites);
    if (isFav) {
      currentFavorites.removeWhere((t) => t.videoId == videoId);
    } else {
      currentFavorites.insert(0, track);
    }
    state = state.copyWith(favorites: currentFavorites);

    try {
      if (isFav) {
        await _api.removeFavorite(videoId);
      } else {
        await _api.addFavorite(videoId);
      }
      // Reload downloaded tracks, since adding to favorites might auto-download
      final updatedTracks = await _api.getDownloadedTracks();
      state = state.copyWith(downloadedTracks: updatedTracks);
      // Kick off background status checking in case auto-download began
      _checkAndStartDownloadPolling(updatedTracks, state.favorites);
    } catch (e) {
      // Revert on error
      loadLibrary();
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

  Future<void> updatePlaylist(int id,
      {String? name, String? description, bool? isPublic}) async {
    try {
      await _api.updatePlaylist(id,
          name: name, description: description, isPublic: isPublic);
      await loadLibrary();
    } catch (e) {
      state = state.copyWith(errorMessage: 'Failed to update playlist: $e');
    }
  }

  Future<void> deletePlaylist(int id) async {
    try {
      await _api.deletePlaylist(id);
      await loadLibrary();
    } catch (e) {
      state = state.copyWith(errorMessage: 'Failed to delete playlist: $e');
    }
  }

  Future<void> uploadPlaylistCover(int id, File imageFile) async {
    try {
      await _api.uploadPlaylistCover(id, imageFile);
      await loadLibrary();
    } catch (e) {
      state = state.copyWith(
          errorMessage: 'Failed to upload playlist cover: $e');
    }
  }

  Future<void> addTrackToPlaylist(int playlistId, Track track) async {
    try {
      await _api.addTrackToPlaylist(playlistId, track.videoId);
      await loadLibrary();
    } catch (e) {
      state = state.copyWith(
          errorMessage: 'Failed to add track to playlist: $e');
    }
  }

  Future<void> removeTrackFromPlaylist(int playlistId, String trackId) async {
    try {
      await _api.removeTrackFromPlaylist(playlistId, trackId);
      await loadLibrary();
    } catch (e) {
      state = state.copyWith(errorMessage: 'Failed to remove track: $e');
    }
  }

  Future<void> reorderPlaylistTracks(
      int playlistId, List<String> newOrder) async {
    try {
      await _api.reorderPlaylistTracks(playlistId, newOrder);
      // Update playlist tracks in state locally
      final updatedPlaylists = state.playlists.map((p) {
        if (p.id == playlistId) {
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
}

final libraryProvider =
    NotifierProvider<LibraryNotifier, LibraryState>(LibraryNotifier.new);
