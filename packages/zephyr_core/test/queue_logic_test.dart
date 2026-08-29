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

  group('QueuePolicy.isStaleContextResolutionGuarded', () {
    final trackedAt = DateTime.utc(2026, 8, 27, 12, 0, 0);
    final newer = trackedAt.add(const Duration(seconds: 2));
    final older = trackedAt.subtract(const Duration(seconds: 2));

    test('is false when either id is null', () {
      expect(
        QueuePolicy.isStaleContextResolutionGuarded(
          rawRequestId: null,
          previousRequestId: 'A',
          snapshotUpdatedAt: newer,
          trackedUpdatedAt: trackedAt,
        ),
        isFalse,
      );
      expect(
        QueuePolicy.isStaleContextResolutionGuarded(
          rawRequestId: 'B',
          previousRequestId: null,
          snapshotUpdatedAt: newer,
          trackedUpdatedAt: trackedAt,
        ),
        isFalse,
      );
    });

    test('is false when ids match', () {
      expect(
        QueuePolicy.isStaleContextResolutionGuarded(
          rawRequestId: 'A',
          previousRequestId: 'A',
          snapshotUpdatedAt: older,
          trackedUpdatedAt: trackedAt,
        ),
        isFalse,
      );
    });

    test('is true for a differing id when timestamps are unknown (legacy)', () {
      // Without ordering information we keep the conservative id-only rule.
      expect(
        QueuePolicy.isStaleContextResolutionGuarded(
          rawRequestId: 'B',
          previousRequestId: 'A',
          snapshotUpdatedAt: null,
          trackedUpdatedAt: trackedAt,
        ),
        isTrue,
      );
      expect(
        QueuePolicy.isStaleContextResolutionGuarded(
          rawRequestId: 'B',
          previousRequestId: 'A',
          snapshotUpdatedAt: newer,
          trackedUpdatedAt: null,
        ),
        isTrue,
      );
    });

    test(
        'is FALSE for a differing id whose snapshot is newer than the '
        'tracked one (adoption — the mobile latched-stale bug)', () {
      expect(
        QueuePolicy.isStaleContextResolutionGuarded(
          rawRequestId: 'B',
          previousRequestId: 'A',
          snapshotUpdatedAt: newer,
          trackedUpdatedAt: trackedAt,
        ),
        isFalse,
      );
    });

    test('is FALSE for a differing id with an equal timestamp', () {
      // Equal timestamps mean the same server commit echoed back; adopting
      // is harmless and prevents a stuck guard.
      expect(
        QueuePolicy.isStaleContextResolutionGuarded(
          rawRequestId: 'B',
          previousRequestId: 'A',
          snapshotUpdatedAt: trackedAt,
          trackedUpdatedAt: trackedAt,
        ),
        isFalse,
      );
    });

    test('is TRUE for a late snapshot of the older resolution (F1 intact)', () {
      expect(
        QueuePolicy.isStaleContextResolutionGuarded(
          rawRequestId: 'A',
          previousRequestId: 'B',
          snapshotUpdatedAt: older,
          trackedUpdatedAt: trackedAt,
        ),
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