/// Pure queue/context decision helpers.
///
/// These functions carry the non-trivial logic behind the playlist-switch and
/// stale-context guards. They are intentionally side-effect-free so they can be
/// unit-tested in isolation (see test/queue_logic_test.dart) without touching
/// Dio, the audio engine, or the player provider runtime.
library;

class QueuePolicy {
  QueuePolicy._();

  /// A snapshot whose `context_request_id` differs from the resolution we are
  /// currently tracking is a STALE async context result (Exchange 60). Its
  /// queue window and context metadata must not overwrite a newer context.
  ///
  /// When either id is null there is nothing to compare, so it is not stale.
  static bool isStaleContextResolution(
    String? rawRequestId,
    String? previousRequestId,
  ) {
    return rawRequestId != null &&
        previousRequestId != null &&
        rawRequestId != previousRequestId;
  }

  /// Timestamp-ordered variant of [isStaleContextResolution].
  ///
  /// The id-only check above is direction-blind: it cannot tell a LATE
  /// snapshot of the OLD resolution (genuinely stale — the case F1 guards)
  /// apart from a snapshot of a NEWER resolution the client has not adopted
  /// yet (e.g. the PUT response was lost while its SSE broadcast arrived —
  /// routine on mobile where the SSE socket dies in background). Rejecting
  /// the newer snapshot latches the stale state forever: the preserved
  /// tracked id never matches again, so every subsequent snapshot of the
  /// new context is rejected too and the previous playlist's queue sticks
  /// while the new song plays.
  ///
  /// Ordering rule: a differing id is only stale when the snapshot is
  /// strictly OLDER than the moment the currently tracked id was observed.
  /// Newer-or-equal timestamps mean adoption. When either timestamp is
  /// unknown we keep the conservative id-only behaviour.
  static bool isStaleContextResolutionGuarded({
    required String? rawRequestId,
    required String? previousRequestId,
    required DateTime? snapshotUpdatedAt,
    required DateTime? trackedUpdatedAt,
  }) {
    if (rawRequestId == null || previousRequestId == null) return false;
    if (rawRequestId == previousRequestId) return false;
    if (snapshotUpdatedAt == null || trackedUpdatedAt == null) return true;
    return snapshotUpdatedAt.isBefore(trackedUpdatedAt);
  }

  /// Whether a track-tile tap is inside the SAME context as the currently
  /// active one, or must start a brand-new queue.
  ///
  /// The requested context (when present) is authoritative: an exact type+id
  /// match means "same context", a mismatch always means "new context" even if
  /// the tapped track also appears in the current queue (overlapping
  /// playlists previously left the old queue installed). Only context-less
  /// sources (artist top-songs, library, ad-hoc lists) fall back to the legacy
  /// "track already in the queue" heuristic.
  static bool isSameContext({
    required String? origin,
    required bool hasRequestedContext,
    required bool contextMatches,
    required bool hasTrackInQueue,
  }) {
    if (origin == 'search') return false;
    final membershipFallback = !hasRequestedContext && hasTrackInQueue;
    return contextMatches || membershipFallback;
  }

  /// Whether the active `context_ref` matches the requested one (type+id).
  static bool contextMatches(
    Map<String, dynamic>? activeContext,
    Map<String, dynamic>? requestedContext,
  ) {
    return requestedContext != null &&
        activeContext != null &&
        activeContext['type']?.toString() ==
            requestedContext['type']?.toString() &&
        activeContext['id']?.toString() ==
            requestedContext['id']?.toString();
  }

  /// Whether a server snapshot's queue window should be applied to the local
  /// state, given the role/window guards and staleness.
  ///
  /// Rejects a stale resolution's window, and otherwise applies when the
  /// snapshot is a radio snapshot (not shuffled), carries a server context ref,
  /// or the local queue is a single-track placeholder to be replaced.
  static bool shouldApplyServerQueue({
    required bool isRadioSnapshot,
    required bool isStaleResolution,
    required bool hasServerContextRef,
    required bool isShuffled,
    required int localQueueLength,
  }) {
    if (isStaleResolution) return false;
    return (isRadioSnapshot && !isShuffled) ||
        hasServerContextRef ||
        (!isShuffled && localQueueLength <= 1);
  }
}