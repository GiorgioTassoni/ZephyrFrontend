import 'package:flutter_test/flutter_test.dart';
import 'package:zephyr_core/models/models.dart';

void main() {
  group('Track.fromJson', () {
    test('canonicalizes numeric ids to dz_ prefixed', () {
      final track = Track.fromJson({'id': '3135551', 'title': 'Song'});
      expect(track.videoId, 'dz_3135551');
    });

    test('keeps non-numeric / already-prefixed ids as-is', () {
      expect(
        Track.fromJson({'track_id': 'dz_90819', 'title': 'A'}).videoId,
        'dz_90819',
      );
      expect(
        Track.fromJson({'video_id': 'loc_abc123', 'title': 'A'}).videoId,
        'loc_abc123',
      );
    });

    test('prefers track_id over id over video_id over videoId', () {
      final track = Track.fromJson({
        'track_id': 'dz_first',
        'id': '2',
        'video_id': '3',
        'videoId': '4',
        'title': 'A',
      });
      expect(track.videoId, 'dz_first');
    });

    test('falls back to Unknown Track when empty', () {
      final track = Track.fromJson(const {'title': 'A'});
      expect(track.title, 'A');
      expect(track.videoId, isEmpty);
    });

    test('parses artists from a string list', () {
      final track = Track.fromJson({
        'title': 'A',
        'artists': ['Alice', 'Bob'],
      });
      expect(track.artists, ['Alice', 'Bob']);
    });

    test('parses duration from total seconds', () {
      final track = Track.fromJson({'title': 'A', 'duration': 185});
      expect(track.duration, const Duration(seconds: 185));
    });

    test('parses m:ss duration string', () {
      final track = Track.fromJson({'title': 'A', 'duration': '3:05'});
      expect(track.duration, const Duration(minutes: 3, seconds: 5));
    });

    test('extracts album from nested map', () {
      final track = Track.fromJson({
        'title': 'A',
        'album': {'name': 'Album X'},
      });
      expect(track.album, 'Album X');
    });

    test('toJson round-trips the canonical id', () {
      final track = Track.fromJson({'track_id': 'dz_42', 'title': 'A'});
      expect(track.toJson()['track_id'], 'dz_42');
    });
  });

  group('Playlist.fromJson', () {
    test('prepends dz_ for numeric Deezer ids', () {
      final pl = Playlist.fromJson({
        'id': 42,
        'owner_name': 'Deezer',
        'name': 'My Mix',
        'user_id': 1,
        'is_public': true,
      });
      expect(pl.id, 'dz_42');
    });

    test('keeps non-numeric ids', () {
      final pl = Playlist.fromJson({
        'id': 'abc-1',
        'name': 'Custom',
        'user_id': 1,
        'is_public': false,
      });
      expect(pl.id, 'abc-1');
    });

    test('does not dz_-prefix numeric id without Deezer owner', () {
      final pl = Playlist.fromJson({
        'id': 42,
        'name': 'Local',
        'user_id': 1,
        'is_public': true,
      });
      // Non-Deezer numeric ids keep their raw form as a String.
      expect(pl.id.toString(), '42');
    });

    test('copyWith preserves other fields', () {
      final pl = Playlist.fromJson({
        'id': 'k1',
        'name': 'A',
        'user_id': 1,
        'is_public': true,
      });
      final updated = pl.copyWith(name: 'B');
      expect(updated.name, 'B');
      expect(updated.id, 'k1');
      expect(updated.isPublic, isTrue);
    });
  });
}