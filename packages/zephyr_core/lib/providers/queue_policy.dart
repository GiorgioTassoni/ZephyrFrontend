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