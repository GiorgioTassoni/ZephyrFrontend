import 'package:flutter_test/flutter_test.dart';
import 'package:zephyr_core/providers/queue_policy.dart';

void main() {
  group('QueuePolicy.isStaleContextResolution', () {
    test('is false when either id is null (nothing to compare)', () {
      expect(QueuePolicy.isStaleContextResolution(null, null), isFalse);
      expect(QueuePolicy.isStaleContextResolution('B', null), isFalse);
      expect(QueuePolicy.isStaleContextResolution(null, 'A'), isFalse);
    });

    test('is false when ids match', () {
      expect(
        QueuePolicy.isStaleContextResolution('ctx-42', 'ctx-42'),
        isFalse,
      );
    });

    test('is true when the snapshot belongs to an older resolution', () {
      // We are tracking B; a late snapshot for A is stale and must not
      // clobber B's queue or metadata (F1 regression guard).
      expect(
        QueuePolicy.isStaleContextResolution('ctx-A', 'ctx-B'),
        isTrue,
      );
    });
  });

  group('QueuePolicy.contextMatches', () {
    test('matches on equal type + id', () {
      final a = {'type': 'playlist', 'id': 'pl-1', 'order': 'as_listed'};
      final b = {'type': 'playlist', 'id': 'pl-1', 'order': 'as_listed'};
      expect(QueuePolicy.contextMatches(a, b), isTrue);
    });

    test('does not match different id (even with overlapping tracks)', () {
      final active = {'type': 'playlist', 'id': 'pl-A'};
      final requested = {'type': 'playlist', 'id': 'pl-B'};
      expect(QueuePolicy.contextMatches(active, requested), isFalse);
    });

    test('does not match different type', () {
      final active = {'type': 'playlist', 'id': '1'};
      final requested = {'type': 'album', 'id': '1'};
      expect(QueuePolicy.contextMatches(active, requested), isFalse);
    });

    test('does not match when either is null', () {
      expect(QueuePolicy.contextMatches(null, {'type': 'playlist'}), isFalse);
      expect(
        QueuePolicy.contextMatches({'type': 'playlist'}, null),
        isFalse,
      );
    });
  });

  group('QueuePolicy.isSameContext', () {
    test('false for search origin even with matching context', () {
      expect(
        QueuePolicy.isSameContext(
          origin: 'search',
          hasRequestedContext: true,
          contextMatches: true,
          hasTrackInQueue: true,
        ),
        isFalse,
      );
    });

    test('true when requested context matches (same playlist tap)', () {
      expect(
        QueuePolicy.isSameContext(
          origin: 'context',
          hasRequestedContext: true,
          contextMatches: true,
          hasTrackInQueue: false,
        ),
        isTrue,
      );
    });

    test(
        'false when requested context DIFFERS even if the track is already '
        'in the queue (overlapping playlists must switch queues - the bug '
        'fixed for playlist-switch)', () {
      expect(
        QueuePolicy.isSameContext(
          origin: 'context',
          hasRequestedContext: true,
          contextMatches: false,
          hasTrackInQueue: true,
        ),
        isFalse,
      );
    });

    test('context-less tile falls back to queue membership', () {
      expect(
        QueuePolicy.isSameContext(
          origin: null,
          hasRequestedContext: false,
          contextMatches: false,
          hasTrackInQueue: true,
        ),
        isTrue,
      );
      expect(
        QueuePolicy.isSameContext(
          origin: null,
          hasRequestedContext: false,
          contextMatches: false,
          hasTrackInQueue: false,
        ),
        isFalse,
      );
    });
  });

  group('QueuePolicy.shouldApplyServerQueue', () {
    test('rejects a stale resolution window (F1)', () {
      expect(
        QueuePolicy.shouldApplyServerQueue(
          isRadioSnapshot: false,
          isStaleResolution: true,
          hasServerContextRef: true,
          isShuffled: false,
          localQueueLength: 50,
        ),
        isFalse,
      );
    });

    test('applies a fresh radio snapshot when not shuffled', () {
      expect(
        QueuePolicy.shouldApplyServerQueue(
          isRadioSnapshot: true,
          isStaleResolution: false,
          hasServerContextRef: false,
          isShuffled: false,
          localQueueLength: 1,
        ),
        isTrue,
      );
    });

    test('does not apply radio snapshot when shuffled', () {
      expect(
        QueuePolicy.shouldApplyServerQueue(
          isRadioSnapshot: true,
          isStaleResolution: false,
          hasServerContextRef: false,
          isShuffled: true,
          localQueueLength: 5,
        ),
        isFalse,
      );
    });

    test('applies when the snapshot carries a server context ref', () {
      expect(
        QueuePolicy.shouldApplyServerQueue(
          isRadioSnapshot: false,
          isStaleResolution: false,
          hasServerContextRef: true,
          isShuffled: false,
          localQueueLength: 50,
        ),
        isTrue,
      );
    });

    test('applies to replace a single-track placeholder queue', () {
      expect(
        QueuePolicy.shouldApplyServerQueue(
          isRadioSnapshot: false,
          isStaleResolution: false,
          hasServerContextRef: false,
          isShuffled: false,
          localQueueLength: 1,
        ),
        isTrue,
      );
    });

    test('does NOT apply when a rich local queue exists and no context ref', () {
      expect(
        QueuePolicy.shouldApplyServerQueue(
          isRadioSnapshot: false,
          isStaleResolution: false,
          hasServerContextRef: false,
          isShuffled: false,
          localQueueLength: 20,
        ),
        isFalse,
      );
    });
  });
}