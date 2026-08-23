import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/models.dart';
import '../providers/player_provider.dart';
import '../theme/colors.dart';
import '../widgets/cover_image.dart';
import '../widgets/artist_links.dart';

class QueueScreen extends ConsumerWidget {
  const QueueScreen({super.key});

  static const int maxVisibleNormalQueue = 50;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playerState = ref.watch(playerProvider);
    final playerNotifier = ref.read(playerProvider.notifier);

    final currentTrack = playerState.currentTrack;
    final userQueue = playerState.userQueue;

    // Remaining tracks in the base queue after the current playing track
    final baseQueueRemaining = playerState.queue.isEmpty || playerState.currentIndex < 0
        ? <Track>[]
        : playerState.queue.sublist((playerState.currentIndex + 1).clamp(0, playerState.queue.length));

    // Show only tracks the next 50 tracks coming next visually (keeps all tracks in code)
    final visibleBaseQueue = baseQueueRemaining.take(maxVisibleNormalQueue).toList();

    // Exchange 60: with a server-resolved context, the backend reports the
    // real remaining count. queue_count = len(active_order) - cursor is the
    // authoritative "next in queue" number; context_total matches it in
    // steady state and serves as the denominator when both exist.
    final bool hasServerContext =
        playerState.contextRef != null &&
        (playerState.queueCount != null ||
            playerState.contextTotal != null);
    final int? serverRemaining =
        playerState.queueCount ?? playerState.contextTotal;
    final int remainingCount = hasServerContext
        ? serverRemaining!
        : baseQueueRemaining.length;

    return Scaffold(
      backgroundColor: ZephyrColors.bgDark,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          const Padding(
            padding: EdgeInsets.only(left: 24, top: 24, right: 24, bottom: 8),
            child: Text(
              'Play Queue',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: ZephyrColors.text,
              ),
            ),
          ),
          const Divider(color: ZephyrColors.bgLight, height: 1),

          // Scrollable Queue Content
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              children: [
                // 1. Now Playing Section
                if (currentTrack != null) ...[
                  const Text(
                    'Now playing',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: ZephyrColors.textDim,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildNowPlayingTile(context, currentTrack),
                  const SizedBox(height: 32),
                ],

                // 2. Next Up (User Queue) Section
                if (userQueue.isNotEmpty) ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Next up (${userQueue.length})',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: ZephyrColors.textDim,
                        ),
                      ),
                      TextButton(
                        onPressed: playerNotifier.clearUserQueue,
                        child: const Text(
                          'Clear all',
                          style: TextStyle(
                            color: ZephyrColors.primary,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _buildReorderableList(
                    context,
                    tracks: userQueue,
                    isUserQueue: true,
                    onReorder: playerNotifier.reorderUserQueue,
                    onDelete: playerNotifier.removeFromUserQueue,
                  ),
                  const SizedBox(height: 32),
                ],

                // 3. Next In Queue (Base Queue) Section
                // Render when EITHER the server reports real remaining tracks
                // (queue_count/context_total, may be non-zero while the local
                // window is briefly empty after a context switch) OR the local
                // window has visible items.
                if (baseQueueRemaining.isNotEmpty ||
                    (hasServerContext && remainingCount > 0)) ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        // F5: never show a count lower than the tiles rendered
                        // below it (the local window can lag the server count).
                        'Next in queue (${remainingCount < visibleBaseQueue.length ? visibleBaseQueue.length : remainingCount})',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: ZephyrColors.textDim,
                        ),
                      ),
                      if (remainingCount > visibleBaseQueue.length)
                        Text(
                          'Showing next ${visibleBaseQueue.length} of ${remainingCount}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: ZephyrColors.textDim,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _buildReorderableList(
                    context,
                    tracks: visibleBaseQueue,
                    isUserQueue: false,
                    onReorder: playerNotifier.reorderBaseQueue,
                    onDelete: playerNotifier.removeFromBaseQueue,
                  ),
                  if (remainingCount > visibleBaseQueue.length) ...[
                    const SizedBox(height: 16),
                    Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: ZephyrColors.bgCard,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: ZephyrColors.bgLight.withValues(alpha: 0.5),
                          ),
                        ),
                        child: Text(
                          '+ ${remainingCount - visibleBaseQueue.length} more tracks in queue',
                          style: const TextStyle(
                            color: ZephyrColors.textDim,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                  ],
                ] else if (userQueue.isEmpty && currentTrack == null) ...[
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.only(top: 64),
                      child: Text(
                        'Queue is empty. Play a song or add songs to queue.',
                        style: TextStyle(color: ZephyrColors.textDim),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNowPlayingTile(BuildContext context, Track track) {
    return Container(
      decoration: BoxDecoration(
        color: ZephyrColors.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: ZephyrColors.primary.withValues(alpha: 0.7),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: ZephyrColors.primary.withValues(alpha: 0.2),
            blurRadius: 16,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          const Icon(
            Icons.volume_up,
            color: ZephyrColors.primary,
            size: 20,
          ),
          const SizedBox(width: 16),
          CoverImage(
            videoId: track.videoId,
            coverUrl: track.coverUrl,
            size: 44,
            borderRadius: 6,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  track.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: ZephyrColors.primary,
                  ),
                ),
                const SizedBox(height: 4),
                ArtistLinks(
                  track: track,
                  style: const TextStyle(
                    fontSize: 12,
                    color: ZephyrColors.textDim,
                  ),
                ),
              ],
            ),
          ),
          if (track.duration != null) ...[
            Text(
              _formatDuration(track.duration!),
              style: const TextStyle(
                fontSize: 13,
                color: ZephyrColors.textDim,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildReorderableList(
    BuildContext context, {
    required List<Track> tracks,
    required bool isUserQueue,
    required void Function(int, int) onReorder,
    required void Function(int) onDelete,
  }) {
    return Theme(
      data: Theme.of(context).copyWith(
        canvasColor: Colors.transparent, // Disable default shadow background during drag
      ),
      child: ReorderableListView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: tracks.length,
        onReorderItem: onReorder,
        buildDefaultDragHandles: false, // Custom drag handle for premium control
        itemBuilder: (context, index) {
          final track = tracks[index];
          final keyString = '${track.videoId}_${isUserQueue ? "user" : "base"}_$index';

          return _QueueTrackTile(
            key: ValueKey(keyString),
            track: track,
            index: index,
            onDelete: () => onDelete(index),
          );
        },
      ),
    );
  }

  String _formatDuration(Duration duration) {
    final mins = duration.inMinutes;
    final secs = duration.inSeconds % 60;
    return '$mins:${secs.toString().padLeft(2, '0')}';
  }
}

class _QueueTrackTile extends StatefulWidget {
  final Track track;
  final int index;
  final VoidCallback onDelete;

  const _QueueTrackTile({
    super.key,
    required this.track,
    required this.index,
    required this.onDelete,
  });

  @override
  State<_QueueTrackTile> createState() => _QueueTrackTileState();
}

class _QueueTrackTileState extends State<_QueueTrackTile> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: Consumer(
        builder: (context, ref, child) {
          final playerState = ref.watch(playerProvider);
          return InkWell(
            onTap: () {
              ref.read(playerProvider.notifier).playTrack(
                    widget.track,
                    playerState.queue,
                    origin: 'queue',
                  );
            },
            borderRadius: BorderRadius.circular(6),
            child: Container(
              decoration: BoxDecoration(
                color: _isHovered ? ZephyrColors.bgLight.withValues(alpha: 0.15) : Colors.transparent,
                borderRadius: BorderRadius.circular(6),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              margin: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  // Track index number
                  SizedBox(
                    width: 32,
                    child: Center(
                      child: Text(
                        '${widget.index + 1}',
                        style: const TextStyle(
                          fontSize: 13,
                          color: ZephyrColors.textMuted,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  CoverImage(
                    videoId: widget.track.videoId,
                    coverUrl: widget.track.coverUrl,
                    size: 40,
                    borderRadius: 4,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.track.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w500,
                            fontSize: 14,
                            color: ZephyrColors.text,
                          ),
                        ),
                        const SizedBox(height: 4),
                        ArtistLinks(
                          track: widget.track,
                          linkable: false,
                          style: const TextStyle(
                            fontSize: 12,
                            color: ZephyrColors.textDim,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Actions (duration + delete on hover)
                  if (widget.track.duration != null)
                    Text(
                      _formatDuration(widget.track.duration!),
                      style: const TextStyle(
                        fontSize: 13,
                        color: ZephyrColors.textDim,
                      ),
                    ),
                  if (_isHovered) ...[
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(
                        Icons.delete_outline,
                        color: ZephyrColors.error,
                        size: 18,
                      ),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      tooltip: 'Remove from Queue',
                      onPressed: widget.onDelete,
                    ),
                  ],
                  // Drag handle — only this initiates reorder, not the whole tile
                  const SizedBox(width: 8),
                  ReorderableDragStartListener(
                    index: widget.index,
                    child: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                      child: Icon(
                        Icons.drag_handle,
                        color: ZephyrColors.textMuted,
                        size: 20,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  String _formatDuration(Duration duration) {
    final mins = duration.inMinutes;
    final secs = duration.inSeconds % 60;
    return '$mins:${secs.toString().padLeft(2, '0')}';
  }
}
