import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/models.dart';
import '../providers/player_provider.dart';
import '../theme/colors.dart';
import '../widgets/cover_image.dart';
import '../widgets/artist_links.dart';

class QueueScreen extends ConsumerStatefulWidget {
  const QueueScreen({super.key});

  @override
  ConsumerState<QueueScreen> createState() => _QueueScreenState();
}

class _QueueScreenState extends ConsumerState<QueueScreen> {
  final ScrollController _scrollController = ScrollController();
  int _displayedCount = 25;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.hasClients &&
        _scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 400) {
      final playerState = ref.read(playerProvider);
      final total = playerState.userQueue.length + playerState.queue.length;
      if (_displayedCount < total) {
        setState(() {
          _displayedCount = (_displayedCount + 25).clamp(25, total);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final playerState = ref.watch(playerProvider);
    final playerNotifier = ref.read(playerProvider.notifier);

    final currentTrack = playerState.currentTrack;
    final userQueue = playerState.userQueue;

    // Remaining tracks in the base queue after the current playing track
    final baseQueueRemaining = playerState.queue.isEmpty || playerState.currentIndex < 0
        ? <Track>[]
        : playerState.queue.sublist((playerState.currentIndex + 1).clamp(0, playerState.queue.length));

    final visibleUserQueue = userQueue.take(_displayedCount).toList();
    final remainingCountForBase = (_displayedCount - visibleUserQueue.length).clamp(0, _displayedCount);
    final visibleBaseQueue = baseQueueRemaining.take(remainingCountForBase).toList();

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
              controller: _scrollController,
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
                    tracks: visibleUserQueue,
                    isUserQueue: true,
                    onReorder: playerNotifier.reorderUserQueue,
                    onDelete: playerNotifier.removeFromUserQueue,
                  ),
                  const SizedBox(height: 32),
                ],

                // 3. Next In Queue (Base Queue) Section
                if (baseQueueRemaining.isNotEmpty) ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Next in queue (${baseQueueRemaining.length})',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: ZephyrColors.textDim,
                        ),
                      ),
                      if (baseQueueRemaining.length > visibleBaseQueue.length)
                        Text(
                          'Showing ${visibleBaseQueue.length} of ${baseQueueRemaining.length}',
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
                  if (baseQueueRemaining.length > visibleBaseQueue.length) ...[
                    const SizedBox(height: 16),
                    Center(
                      child: TextButton.icon(
                        onPressed: () {
                          setState(() {
                            _displayedCount += 50;
                          });
                        },
                        icon: const Icon(Icons.expand_more, size: 18, color: ZephyrColors.primary),
                        label: Text(
                          'Load more (${baseQueueRemaining.length - visibleBaseQueue.length} remaining)',
                          style: const TextStyle(color: ZephyrColors.primary, fontSize: 13),
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

          return ReorderableDragStartListener(
            key: ValueKey(keyString),
            index: index,
            child: _QueueTrackTile(
              track: track,
              index: index,
              onDelete: () => onDelete(index),
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

class _QueueTrackTile extends StatefulWidget {
  final Track track;
  final int index;
  final VoidCallback onDelete;

  const _QueueTrackTile({
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
                  // Drag handle or Index number
                  SizedBox(
                    width: 32,
                    child: Center(
                      child: _isHovered
                          ? const Icon(
                              Icons.drag_handle,
                              color: ZephyrColors.textDim,
                              size: 20,
                            )
                          : Text(
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
                          style: const TextStyle(
                            fontSize: 12,
                            color: ZephyrColors.textDim,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Actions (Delete button on hover)
                  SizedBox(
                    width: 80,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        if (widget.track.duration != null)
                          Text(
                            _formatDuration(widget.track.duration!),
                            style: const TextStyle(
                              fontSize: 13,
                              color: ZephyrColors.textDim,
                            ),
                          ),
                        const SizedBox(width: 12),
                        if (_isHovered)
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
                          )
                        else
                          const SizedBox(width: 18),
                      ],
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
