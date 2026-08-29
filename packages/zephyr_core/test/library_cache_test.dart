import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:zephyr_core/models/models.dart';
import 'package:zephyr_core/providers/library_provider.dart';

Track _track({String id = 'dz_3135551', String title = 'Song A'}) {
  return Track(
    videoId: id,
    title: title,
    artists: const ['Alice', 'Bob'],
    album: 'Album X',
    albumId: 'alb_1',
    duration: const Duration(seconds: 185),
    downloadStatus: 'completed',
    isDownloaded: true,
    videoType: 'ATV',
    coverUrl: '/api/tracks/cover/$id',
    favoritedAt: DateTime.utc(2026, 1, 2, 3, 4, 5),
  );
}

void main() {
  group('Track toJson/fromJson round trip', () {
    test('preserves identity, metadata and status', () {
      final track = _track();
      final restored = Track.fromJson(track.toJson());

      expect(restored.videoId, track.videoId);
      expect(restored.title, track.title);
      expect(restored.artists, track.artists);
      expect(restored.album, track.album);
      expect(restored.albumId, track.albumId);
      expect(restored.duration, track.duration);
      expect(restored.downloadStatus, track.downloadStatus);
      expect(restored.isDownloaded, track.isDownloaded);
      expect(restored.videoType, track.videoType);
      expect(restored.coverUrl, track.coverUrl);
      expect(restored.favoritedAt!.isAtSameMomentAs(track.favoritedAt!), true);
    });
  });

  group('Playlist.toJson/fromJson round trip', () {
    test('preserves fields incl. dz_ id and embedded tracks', () {
      final playlist = Playlist(
        id: 'dz_90819',
        userId: 7,
        name: 'Road Trip',
        description: 'desc',
        ownerName: 'Deezer',
        isOwner: false,
        isSaved: true,
        coverUrl: '/api/playlists/dz_90819/cover',
        isPublic: true,
        trackCount: 12,
        downloadedCount: 3,
        createdAt: '2026-01-01T00:00:00Z',
        updatedAt: '2026-01-02T00:00:00Z',
        tracks: [_track()],
      );

      final restored = Playlist.fromJson(playlist.toJson());

      expect(restored.id, playlist.id);
      expect(restored.userId, playlist.userId);
      expect(restored.name, playlist.name);
      expect(restored.description, playlist.description);
      expect(restored.ownerName, playlist.ownerName);
      expect(restored.isOwner, playlist.isOwner);
      expect(restored.isSaved, playlist.isSaved);
      expect(restored.coverUrl, playlist.coverUrl);
      expect(restored.isPublic, playlist.isPublic);
      expect(restored.trackCount, playlist.trackCount);
      expect(restored.downloadedCount, playlist.downloadedCount);
      expect(restored.createdAt, playlist.createdAt);
      expect(restored.updatedAt, playlist.updatedAt);
      expect(restored.tracks?.length, 1);
      expect(restored.tracks!.first.videoId, 'dz_3135551');
    });

    test('re-prefixed dz_ ids are not double-prefixed', () {
      final playlist = Playlist(
        id: 'dz_42',
        userId: 1,
        name: 'P',
        isPublic: false,
        ownerName: 'Deezer',
      );
      expect(Playlist.fromJson(playlist.toJson()).id, 'dz_42');
    });
  });

  group('HistoryEntry.toJson/fromJson round trip', () {
    test('preserves entry and embedded track', () {
      final entry = HistoryEntry(
        id: 42,
        userId: 7,
        trackId: 'dz_3135551',
        listenedAt: DateTime.utc(2026, 1, 2, 3, 4, 5),
        track: _track(),
      );

      final restored = HistoryEntry.fromJson(entry.toJson());

      expect(restored.id, entry.id);
      expect(restored.userId, entry.userId);
      expect(restored.trackId, entry.trackId);
      expect(restored.listenedAt.isAtSameMomentAs(entry.listenedAt), true);
      expect(restored.track?.videoId, entry.track?.videoId);
      expect(restored.track?.title, entry.track?.title);
    });

    test('survives a null embedded track', () {
      final entry = HistoryEntry(
        id: 1,
        userId: 1,
        trackId: 'loc_x',
        listenedAt: DateTime.utc(2026, 1, 1),
      );
      final restored = HistoryEntry.fromJson(entry.toJson());
      expect(restored.trackId, 'loc_x');
      expect(restored.track, isNull);
    });
  });

  group('LibraryCache', () {
    test('encode → jsonEncode → decode round trip', () {
      final payload = LibraryCache.encode(
        tracks: [_track(), _track(id: 'loc_9', title: 'Local Song')],
        playlists: [
          Playlist(
            id: '42',
            userId: 1,
            name: 'Mine',
            isPublic: false,
            tracks: [_track()],
          ),
        ],
        favorites: [_track(id: 'dz_777')],
        totalFavoritesCount: 123,
        history: [
          HistoryEntry(
            id: 1,
            userId: 1,
            trackId: 'dz_3135551',
            listenedAt: DateTime.utc(2026, 2, 3),
            track: _track(),
          ),
        ],
      );

      final decoded = LibraryCache.decode(json.encode(payload));
      expect(decoded, isNotNull);
      expect(decoded!['v'], LibraryCache.version);
      expect(decoded['total_favorites'], 123);

      final tracks = (decoded['tracks'] as List)
          .map((e) => Track.fromJson(Map<String, dynamic>.from(e)))
          .toList();
      expect(tracks.length, 2);
      expect(tracks[0].videoId, 'dz_3135551');
      expect(tracks[1].videoId, 'loc_9');

      final playlists = (decoded['playlists'] as List)
          .map((e) => Playlist.fromJson(Map<String, dynamic>.from(e)))
          .toList();
      expect(playlists.single.id, '42');
      expect(playlists.single.tracks?.single.title, 'Song A');

      final history = (decoded['history'] as List)
          .map((e) => HistoryEntry.fromJson(Map<String, dynamic>.from(e)))
          .toList();
      expect(history.single.trackId, 'dz_3135551');
    });

    test('decode returns null for null / empty / garbage / non-object', () {
      expect(LibraryCache.decode(null), isNull);
      expect(LibraryCache.decode(''), isNull);
      expect(LibraryCache.decode('not json at all'), isNull);
      expect(LibraryCache.decode('[1, 2, 3]'), isNull);
      expect(LibraryCache.decode('"just a string"'), isNull);
    });

    test('decode rejects foreign payload versions', () {
      final payload = LibraryCache.encode(
        tracks: [_track()],
        playlists: const [],
        favorites: const [],
        totalFavoritesCount: null,
        history: const [],
      );
      payload['v'] = LibraryCache.version + 1;
      expect(LibraryCache.decode(json.encode(payload)), isNull);
    });

    test('history is capped to maxHistoryEntries', () {
      final entries = List.generate(
        LibraryCache.maxHistoryEntries + 40,
        (i) => HistoryEntry(
          id: i,
          userId: 1,
          trackId: 't_$i',
          listenedAt: DateTime.utc(2026, 1, 1).add(Duration(minutes: i)),
        ),
      );

      final payload = LibraryCache.encode(
        tracks: const [],
        playlists: const [],
        favorites: const [],
        totalFavoritesCount: null,
        // Upstream contract: history arrives sorted newest-first.
        history: entries.reversed.toList(),
      );

      final history = payload['history'] as List;
      expect(history.length, LibraryCache.maxHistoryEntries);
      // Keeps the most recent entries (list is sorted newest-first upstream).
      expect(
        HistoryEntry.fromJson(
          Map<String, dynamic>.from(history.first),
        ).trackId,
        't_${entries.length - 1}',
      );
    });
  });
}
