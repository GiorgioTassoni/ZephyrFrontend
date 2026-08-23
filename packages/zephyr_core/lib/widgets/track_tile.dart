import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/models.dart';
import '../providers/library_provider.dart';
import '../providers/player_provider.dart';
import '../providers/queue_policy.dart';
import '../api/zephyr_api.dart';
import '../theme/colors.dart';
import '../providers/auth_provider.dart';
import '../providers/navigation_provider.dart';
import '../providers/offline_provider.dart';
import '../utils/app_logger.dart';
import 'track_metadata_editor_dialog.dart';
import 'share_dialog.dart';
import 'cover_image.dart';
import 'artist_links.dart';
import 'favorite_button.dart';
import 'resolution_candidate_modal.dart';
import 'unresolved_track_modal.dart';
import 'toast.dart';

class TrackTile extends ConsumerStatefulWidget {
  final Track track;
  final List<Track> queue;
  final VoidCallback? onRemoveFromPlaylist;
  final Widget? trailing;
  final bool showFavoriteButton;
  final bool showDownloadIndicator;
  final EdgeInsetsGeometry? contentPadding;
  final String? origin;
  final Map<String, dynamic>? contextRef;

  const TrackTile({
    super.key,
    required this.track,
    required this.queue,
    this.onRemoveFromPlaylist,
    this.trailing,
    this.showFavoriteButton = true,
    this.showDownloadIndicator = true,
    this.contentPadding,
    this.origin,
    this.contextRef,
  });

  @override
  ConsumerState<TrackTile> createState() => _TrackTileState();
}

class _TrackTileState extends ConsumerState<TrackTile> {
  @override
  Widget build(BuildContext context) {
    final isCurrent = ref.watch(
      playerProvider.select(
        (s) => s.currentTrack?.videoId == widget.track.videoId,
      ),
    );
    final playerNotifier = ref.read(playerProvider.notifier);
    final libraryNotifier = ref.read(libraryProvider.notifier);
    final isFav = libraryNotifier.isFavorite(widget.track.videoId, title: widget.track.title, artists: widget.track.artists);

    final isMobile = MediaQuery.of(context).size.width < 700;

    final tile = GestureDetector(
      onSecondaryTapDown: (details) {
        _showRightClickMenu(context, ref, details.globalPosition);
      },
      onLongPress: () => _showMobileActionsBottomSheet(context, ref),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          contentPadding: widget.contentPadding ?? EdgeInsets.symmetric(horizontal: isMobile ? 8 : 16, vertical: 4),
          leading: CoverImage(
            videoId: widget.track.videoId,
            coverUrl: widget.track.coverUrl,
            size: 48,
          ),
          title: Row(
            children: [
              Expanded(
                child: Text(
                  widget.track.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w500,
                    color: isCurrent ? ZephyrColors.primary : ZephyrColors.text,
                  ),
                ),
              ),
              if (widget.track.reason != null && widget.track.reason!.isNotEmpty) ...[
                const SizedBox(width: 6),
                _buildReasonBadge(widget.track.reason!),
              ],
              if (widget.track.isVideoVersion) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.purple.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: Colors.purpleAccent.withValues(alpha: 0.4)),
                  ),
                  child: const Text(
                    'VIDEO',
                    style: TextStyle(
                      color: Colors.purpleAccent,
                      fontSize: 9.5,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ],
          ),
          subtitle: ArtistLinks(
            track: widget.track,
            linkable: false,
            style: const TextStyle(
              color: ZephyrColors.textDim,
              fontSize: 12,
            ),
          ),
          trailing: widget.trailing ??
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.showDownloadIndicator) _buildDownloadIndicator(context, ref),
                  if (widget.showFavoriteButton)
                    FavoriteButton(
                      isFavorite: isFav,
                      size: 20,
                      onTap: () => libraryNotifier.toggleFavorite(widget.track),
                    ),
                  if (isMobile)
                    IconButton(
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      icon: const Icon(Icons.more_vert, color: ZephyrColors.textDim, size: 20),
                      onPressed: () => _showMobileActionsBottomSheet(context, ref),
                    )
                  else
                    PopupMenuButton<String>(
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      icon: const Icon(Icons.more_vert, color: ZephyrColors.textDim, size: 20),
                      color: ZephyrColors.bgCard,
                      onSelected: (value) => _handleMenuSelection(context, ref, value),
                      itemBuilder: (context) => _buildTrackMenuItems(context, ref),
                    ),
                ],
              ),
          onTap: () {
            if (isCurrent) {
              playerNotifier.togglePlayPause();
            } else {
              _playTrackWithResolution(context, ref);
            }
          },
          onLongPress: () => _showMobileActionsBottomSheet(context, ref),
        ),
      ),
    );

    if (!isMobile) {
      return tile;
    }

    return Dismissible(
      key: ValueKey('swipe_queue_${widget.track.videoId}_${widget.track.hashCode}'),
      direction: DismissDirection.startToEnd,
      confirmDismiss: (direction) async {
        if (direction == DismissDirection.startToEnd) {
          playerNotifier.addToQueue(widget.track);
          HapticFeedback.mediumImpact();
          ZephyrToast.show(context, 'Added "${widget.track.title}" to queue');
        }
        return false; // Prevent removing tile from the list
      },
      background: Container(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: 20),
        decoration: BoxDecoration(
          color: ZephyrColors.primary.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Row(
          children: [
            Icon(Icons.queue_music, color: Colors.black, size: 24),
            SizedBox(width: 8),
            Text(
              'Add to Queue',
              style: TextStyle(
                color: Colors.black,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
      child: tile,
    );
  }

  Widget _buildReasonBadge(String reason) {
    String label = '';
    Color color = ZephyrColors.primary;
    if (reason == 'same_album') {
      label = 'SAME ALBUM';
      color = Colors.blueAccent;
    } else if (reason == 'same_artist') {
      label = 'SAME ARTIST';
      color = Colors.amber;
    } else if (reason == 'similar_artist') {
      label = 'RADIO';
      color = ZephyrColors.primary;
    } else {
      label = reason.toUpperCase();
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 9,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildDownloadIndicator(BuildContext context, WidgetRef ref) {
    final offlineState = ref.watch(offlineDownloadsProvider);
    final isLocal = offlineState.isDownloaded(widget.track.videoId);
    final isDownloadingLocal = offlineState.isDownloading(widget.track.videoId);
    final progress = offlineState.getProgress(widget.track.videoId);

    if (isLocal) {
      return IconButton(
        icon: const Icon(Icons.check_circle_rounded, color: ZephyrColors.success, size: 18),
        tooltip: 'Downloaded to device (Tap to remove)',
        onPressed: () => _confirmRemoveLocalDownload(context, ref),
      );
    }

    if (isDownloadingLocal) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8.0),
        child: SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(
            value: (progress != null && progress > 0) ? progress : null,
            strokeWidth: 2,
            valueColor: const AlwaysStoppedAnimation<Color>(ZephyrColors.primary),
          ),
        ),
      );
    }

    final isServerDownloaded = widget.track.downloadStatus == 'completed' || widget.track.isDownloaded;

    switch (widget.track.downloadStatus) {
      case 'pending':
      case 'downloading':
        return const Padding(
          padding: EdgeInsets.symmetric(horizontal: 8.0),
          child: SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(ZephyrColors.warning),
            ),
          ),
        );
      case 'needs_resolution':
        return IconButton(
          icon: const Icon(Icons.find_in_page_rounded, color: Colors.amberAccent, size: 18),
          tooltip: 'Selection required - Tap to choose match',
          onPressed: () => _triggerResolutionFlow(context, ref),
        );
      case 'unavailable':
        return const Padding(
          padding: EdgeInsets.symmetric(horizontal: 8.0),
          child: Tooltip(
            message: 'Track Unavailable (no safe match found)',
            child: Icon(Icons.block_rounded, color: ZephyrColors.textDim, size: 18),
          ),
        );
      case 'failed':
        return IconButton(
          icon: const Icon(Icons.error_outline, color: ZephyrColors.error, size: 18),
          onPressed: () {
            ZephyrToast.show(context, 'Download failed. Tap to retry.', isError: true);
            _startDownload(context, ref);
          },
        );
      default:
        return IconButton(
          icon: Icon(
            Icons.download_for_offline_outlined,
            color: isServerDownloaded ? ZephyrColors.textDim : ZephyrColors.textMuted,
            size: 18,
          ),
          tooltip: 'Download to this device',
          onPressed: () => _startDownload(context, ref),
        );
    }
  }

  Future<void> _confirmRemoveLocalDownload(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ZephyrColors.bgCard,
        title: const Text('Remove Download'),
        content: Text('Remove "${widget.track.title}" from this device?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel', style: TextStyle(color: ZephyrColors.textDim)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: ZephyrColors.error),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Remove', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      await ref.read(offlineDownloadsProvider.notifier).removeDownload(widget.track.videoId);
      if (context.mounted) {
        ZephyrToast.show(context, 'Removed from this device');
      }
    }
  }

  Future<void> _startDownload(BuildContext context, WidgetRef ref) async {
    try {
      ZephyrToast.show(context, 'Downloading "${widget.track.title}" to device...');
      await ref.read(offlineDownloadsProvider.notifier).downloadTrack(widget.track);
      if (context.mounted) {
        ZephyrToast.show(context, 'Downloaded to this device!');
      }
    } on ResolutionRequiredException catch (e) {
      if (context.mounted) {
        final selected = await UnresolvedTrackModal.show(
          context,
          trackId: e.trackId,
          title: e.title,
          artists: e.artists,
          initialCandidates: e.candidates,
          initialResolutionId: e.resolutionId,
        );
        if (selected == true && context.mounted) {
          await ref.read(offlineDownloadsProvider.notifier).downloadTrack(widget.track);
        }
      }
    } on TrackUnavailableException catch (e) {
      if (context.mounted) {
        ZephyrToast.show(context, '${e.message} Opening resolution options...', isError: true);
        final selected = await UnresolvedTrackModal.show(
          context,
          trackId: widget.track.videoId,
          title: widget.track.title,
          artists: widget.track.artists,
        );
        if (selected == true && context.mounted) {
          await ref.read(offlineDownloadsProvider.notifier).downloadTrack(widget.track);
        }
      }
    } on ProviderUnavailableException catch (e) {
      if (context.mounted) {
        ZephyrToast.show(context, e.message, isError: true);
      }
    } catch (e) {
      if (context.mounted) {
        ZephyrToast.show(context, 'Download failed: $e', isError: true);
      }
    }
  }

  Future<void> _triggerResolutionFlow(BuildContext context, WidgetRef ref) async {
    try {
      final data = await ZephyrApi().getTrackResolution(widget.track.videoId);
      if (data != null && context.mounted) {
        final exc = ResolutionRequiredException.fromJson(data);
        final selected = await UnresolvedTrackModal.show(
          context,
          trackId: exc.trackId,
          title: exc.title,
          artists: exc.artists,
          initialCandidates: exc.candidates,
          initialResolutionId: exc.resolutionId,
        );
        if (selected == true && context.mounted) {
          ZephyrToast.show(context, 'Selection saved!');
          ref.read(libraryProvider.notifier).loadLibrary();
        }
      } else {
        await _startDownload(context, ref);
      }
    } catch (e) {
      if (e is ResolutionRequiredException && context.mounted) {
        final selected = await ResolutionCandidateModal.show(context, e);
        if (selected == true && context.mounted) {
          ZephyrToast.show(context, 'Selection saved!');
          ref.read(libraryProvider.notifier).loadLibrary();
        }
      } else if (context.mounted) {
        ZephyrToast.show(context, 'Resolution error: $e', isError: true);
      }
    }
  }

  Future<void> _playTrackWithResolution(BuildContext context, WidgetRef ref) async {
    final playerNotifier = ref.read(playerProvider.notifier);
    final playerState = ref.read(playerProvider);

    final activeContext = playerState.contextRef;
    final requestedContext = widget.contextRef;
    // The context comparison is authoritative when the tile declares a
    // context (playlist/album/favorites). A tap in a DIFFERENT context must
    // always start a new queue even if the track also appears in the current
    // queue (overlapping playlists previously left the old queue installed).
    final bool hasRequestedContext = requestedContext != null;
    final bool contextMatches =
        QueuePolicy.contextMatches(activeContext, requestedContext);
    // Only context-less sources (artist top-songs, library, ad-hoc lists)
    // fall back to the legacy "track already in the queue" heuristic.
    final bool hasTrackInQueue =
        playerState.queue.isNotEmpty &&
        playerState.queue.any((t) => t.videoId == widget.track.videoId);
    final bool isSameContext = QueuePolicy.isSameContext(
      origin: widget.origin,
      hasRequestedContext: hasRequestedContext,
      contextMatches: contextMatches,
      hasTrackInQueue: hasTrackInQueue,
    );

    // Diagnostic: the tap's context decision. Users share AppLogger logs to
    // debug "queue did not switch when jumping playlists" (Android vs desktop).
    AppLogger.instance.logQueue(
      'tap_context_decision',
      data: {
        'trackId': widget.track.videoId,
        'title': widget.track.title,
        'origin': widget.origin ?? 'context',
        'hasRequestedContext': hasRequestedContext,
        'requestedType': requestedContext?['type'],
        'requestedId': requestedContext?['id'],
        'requestedOrder': requestedContext?['order'],
        'activeType': activeContext?['type'],
        'activeId': activeContext?['id'],
        'contextMatches': contextMatches,
        'membershipFallback':
            hasTrackInQueue && !hasRequestedContext,
        'isSameContext': isSameContext,
        'localQueueLength': playerState.queue.length,
      },
    );

    try {
      await playerNotifier.playTrack(
        widget.track,
        widget.queue,
        isNewQueue: !isSameContext,
        origin: widget.origin ?? 'context',
        contextRef: widget.contextRef,
      );
    } on ResolutionRequiredException catch (_) {
      // Handled globally by PlayerNotifier._triggerResolutionModal
    } on TrackUnavailableException catch (_) {
      // Handled globally by PlayerNotifier._triggerResolutionModal
    } on ProviderUnavailableException catch (e) {
      if (context.mounted) {
        ZephyrToast.show(context, e.message, isError: true);
      }
    } catch (e) {
      if (context.mounted) {
        ZephyrToast.show(context, 'Playback error: $e', isError: true);
      }
    }
  }

  void _handleMenuSelection(BuildContext context, WidgetRef ref, String value) {
    if (value == 'toggle_favorite') {
      ref.read(libraryProvider.notifier).toggleFavorite(widget.track);
      final isNowFav = ref.read(libraryProvider.notifier).isFavorite(widget.track.videoId, title: widget.track.title, artists: widget.track.artists);
      ZephyrToast.show(context, isNowFav ? 'Added to favorites' : 'Removed from favorites');
    } else if (value == 'add_to_queue') {
      ref.read(playerProvider.notifier).addToQueue(widget.track);
      ZephyrToast.show(context, 'Added "${widget.track.title}" to queue');
    } else if (value == 'start_radio') {
      ref.read(playerProvider.notifier).startRadio(widget.track);
      ZephyrToast.show(context, 'Starting radio for "${widget.track.title}"');
    } else if (value == 'add_to_playlist') {
      _showAddToPlaylistDialog(context, ref);
    } else if (value == 'remove_from_playlist') {
      widget.onRemoveFromPlaylist?.call();
    } else if (value == 'go_to_album') {
      _navigateToAlbum(context, ref);
    } else if (value == 'share_song') {
      showShareDialog(context, ref, widget.track);
    } else if (value == 'force_download') {
      _startDownload(context, ref);
    } else if (value == 'reopen_resolution') {
      _reopenResolution(context, ref);
    } else if (value == 'resolve_track') {
      _triggerResolutionFlow(context, ref);
    } else if (value.startsWith('go_to_artist_')) {
      final id = value.substring('go_to_artist_'.length);
      ref.read(navigationProvider.notifier).navigateTo(ScreenState(type: ScreenType.artist, id: id));
    } else if (value == 'edit_metadata') {
      _editMetadata(context, ref);
    } else if (value == 'delete_track') {
      if (context.mounted) _showDeleteConfirmationDialog(context, ref);
    }
  }

  Future<void> _navigateToAlbum(BuildContext context, WidgetRef ref) async {
    final navNotifier = ref.read(navigationProvider.notifier);
    if (widget.track.albumId != null && widget.track.albumId!.isNotEmpty) {
      navNotifier.navigateTo(ScreenState(type: ScreenType.album, id: widget.track.albumId!));
    } else {
      final query = (widget.track.album != null && widget.track.album!.isNotEmpty)
          ? '${widget.track.album} ${widget.track.artists.isNotEmpty ? widget.track.artists.first : ''}'.trim()
          : '${widget.track.title} ${widget.track.artists.isNotEmpty ? widget.track.artists.first : ''}'.trim();
      try {
        final searchRes = await ZephyrApi().search(query, remote: true);
        if (!context.mounted) return;
        final results = searchRes['results'];
        List<dynamic> albums = [];
        if (results is Map && results.containsKey('albums')) {
          albums = (results['albums'] as List?) ?? [];
        } else if (searchRes['albums'] is List) {
          albums = searchRes['albums'] as List;
        }
        if (albums.isNotEmpty) {
          final firstAlbum = albums.first;
          final id = (firstAlbum['id'] ?? firstAlbum['browse_id'] ?? firstAlbum['browseId'])?.toString();
          if (id != null && id.isNotEmpty) {
            final formattedId = id.startsWith('dz_') ? id : 'dz_$id';
            navNotifier.navigateTo(ScreenState(type: ScreenType.album, id: formattedId));
            return;
          }
        }
        ZephyrToast.show(context, 'Album not found', isError: true);
      } catch (_) {
        if (context.mounted) {
          ZephyrToast.show(context, 'Could not find album', isError: true);
        }
      }
    }
  }

  Future<void> _reopenResolution(BuildContext context, WidgetRef ref) async {
    try {
      final playerState = ref.read(playerProvider);
      final playerNotifier = ref.read(playerProvider.notifier);
      final isCurrentActiveTrack = playerState.currentTrack?.videoId == widget.track.videoId;

      playerNotifier.clearResolvedCache(widget.track.videoId);
      await ZephyrApi().reopenTrackResolution(widget.track.videoId);

      if (context.mounted) {
        ZephyrToast.show(context, 'Track reset for re-resolution. Choose new match:');
        ref.read(libraryProvider.notifier).loadLibrary();
        final selected = await UnresolvedTrackModal.show(
          context,
          trackId: widget.track.videoId,
          title: widget.track.title,
          artists: widget.track.artists,
        );
        if (selected == true && context.mounted) {
          ZephyrToast.show(context, 'Selection saved! Re-streaming correct track...');
          ref.read(libraryProvider.notifier).loadLibrary();
          if (isCurrentActiveTrack) {
            playerNotifier.playTrack(widget.track, playerState.queue.isNotEmpty ? playerState.queue : [widget.track]);
          }
        }
      }
    } on ResolutionRequiredException catch (e) {
      if (context.mounted) {
        final selected = await UnresolvedTrackModal.show(
          context,
          trackId: e.trackId,
          title: e.title,
          artists: e.artists,
          initialCandidates: e.candidates,
          initialResolutionId: e.resolutionId,
        );
        if (selected == true && context.mounted) {
          ZephyrToast.show(context, 'Selection saved!');
          ref.read(libraryProvider.notifier).loadLibrary();
          final player = ref.read(playerProvider);
          if (player.currentTrack?.videoId == widget.track.videoId) {
            ref.read(playerProvider.notifier).playTrack(widget.track, player.queue.isNotEmpty ? player.queue : [widget.track]);
          }
        }
      }
    } catch (e) {
      if (context.mounted) {
        ZephyrToast.show(context, 'Reopen failed: $e', isError: true);
      }
    }
  }

  void _showMobileActionsBottomSheet(BuildContext context, WidgetRef ref) {
    final authState = ref.read(authProvider);
    final libraryNotifier = ref.read(libraryProvider.notifier);
    final offlineState = ref.read(offlineDownloadsProvider);
    final isDownloaded = offlineState.isDownloaded(widget.track.videoId);
    final isFav = libraryNotifier.isFavorite(
      widget.track.videoId,
      title: widget.track.title,
      artists: widget.track.artists,
    );

    showModalBottomSheet(
      context: context,
      backgroundColor: ZephyrColors.bgCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      isScrollControlled: true,
      builder: (modalContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Drag handle
                  const SizedBox(height: 12),
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Header with Album Cover, Title, Artist
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      children: [
                        CoverImage(
                          videoId: widget.track.videoId,
                          coverUrl: widget.track.coverUrl,
                          size: 52,
                          borderRadius: 8,
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.track.title,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                widget.track.artists.isNotEmpty
                                    ? widget.track.artists.join(', ')
                                    : 'Unknown Artist',
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: ZephyrColors.textDim,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Divider(color: ZephyrColors.bgLight, height: 1, thickness: 0.5),
                  const SizedBox(height: 8),

                  // Action Items (matching Spotify reference)
                  // 1. Share
                  ListTile(
                    leading: const Icon(Icons.share_outlined, color: ZephyrColors.text),
                    title: const Text('Share song', style: TextStyle(color: ZephyrColors.text, fontSize: 15)),
                    onTap: () {
                      Navigator.pop(modalContext);
                      _handleMenuSelection(context, ref, 'share_song');
                    },
                  ),

                  // 2. Favorite / Liked
                  ListTile(
                    leading: Icon(
                      isFav ? Icons.favorite : Icons.favorite_border,
                      color: isFav ? ZephyrColors.primary : ZephyrColors.text,
                    ),
                    title: Text(
                      isFav ? 'Remove from Liked Songs' : 'Add to Liked Songs',
                      style: const TextStyle(color: ZephyrColors.text, fontSize: 15),
                    ),
                    onTap: () {
                      Navigator.pop(modalContext);
                      _handleMenuSelection(context, ref, 'toggle_favorite');
                    },
                  ),

                  // 3. Add to Playlist
                  ListTile(
                    leading: const Icon(Icons.add_circle_outline, color: ZephyrColors.text),
                    title: const Text('Add to playlist', style: TextStyle(color: ZephyrColors.text, fontSize: 15)),
                    onTap: () {
                      Navigator.pop(modalContext);
                      _handleMenuSelection(context, ref, 'add_to_playlist');
                    },
                  ),

                  // 4. Remove from this Playlist (if applicable)
                  if (widget.onRemoveFromPlaylist != null)
                    ListTile(
                      leading: const Icon(Icons.remove_circle_outline, color: ZephyrColors.error),
                      title: const Text(
                        'Remove from this playlist',
                        style: TextStyle(color: ZephyrColors.error, fontSize: 15),
                      ),
                      onTap: () {
                        Navigator.pop(modalContext);
                        _handleMenuSelection(context, ref, 'remove_from_playlist');
                      },
                    ),

                  // 5. Add to Queue
                  ListTile(
                    leading: const Icon(Icons.queue_music_rounded, color: ZephyrColors.text),
                    title: const Text('Add to queue', style: TextStyle(color: ZephyrColors.text, fontSize: 15)),
                    onTap: () {
                      Navigator.pop(modalContext);
                      _handleMenuSelection(context, ref, 'add_to_queue');
                    },
                  ),

                  // 5b. Start Radio
                  ListTile(
                    leading: const Icon(Icons.radio_rounded, color: ZephyrColors.text),
                    title: const Text('Start radio', style: TextStyle(color: ZephyrColors.text, fontSize: 15)),
                    onTap: () {
                      Navigator.pop(modalContext);
                      _handleMenuSelection(context, ref, 'start_radio');
                    },
                  ),

                  // 6. Go to Album
                  ListTile(
                    leading: const Icon(Icons.album_outlined, color: ZephyrColors.text),
                    title: const Text('Go to album', style: TextStyle(color: ZephyrColors.text, fontSize: 15)),
                    onTap: () {
                      Navigator.pop(modalContext);
                      _handleMenuSelection(context, ref, 'go_to_album');
                    },
                  ),

                  // 7. Go to Artist(s)
                  for (int i = 0; i < widget.track.artists.length; i++)
                    ListTile(
                      leading: const Icon(Icons.person_outline, color: ZephyrColors.text),
                      title: Text(
                        widget.track.artists.length == 1
                            ? 'Go to artist'
                            : 'Go to ${widget.track.artists[i]}',
                        style: const TextStyle(color: ZephyrColors.text, fontSize: 15),
                      ),
                      onTap: () {
                        Navigator.pop(modalContext);
                        final artistId = i < widget.track.artistsIds.length ? widget.track.artistsIds[i] : widget.track.artists[i];
                        _handleMenuSelection(context, ref, 'go_to_artist_$artistId');
                      },
                    ),

                  // 8. Download / Offline
                  ListTile(
                    leading: Icon(
                      isDownloaded ? Icons.delete_outline : Icons.download_for_offline_outlined,
                      color: isDownloaded ? ZephyrColors.error : ZephyrColors.text,
                    ),
                    title: Text(
                      isDownloaded ? 'Remove download' : 'Download track',
                      style: TextStyle(
                        color: isDownloaded ? ZephyrColors.error : ZephyrColors.text,
                        fontSize: 15,
                      ),
                    ),
                    onTap: () {
                      Navigator.pop(modalContext);
                      _handleMenuSelection(context, ref, 'force_download');
                    },
                  ),

                  // 9. Match / Reopen Resolution (if needed)
                  if (widget.track.needsResolution)
                    ListTile(
                      leading: const Icon(Icons.find_in_page_outlined, color: Colors.amberAccent),
                      title: const Text('Select match', style: TextStyle(color: Colors.amberAccent, fontSize: 15)),
                      onTap: () {
                        Navigator.pop(modalContext);
                        _handleMenuSelection(context, ref, 'resolve_track');
                      },
                    ),

                  // 10. Edit Metadata (Curator/Admin)
                  if (authState.isCurator)
                    ListTile(
                      leading: const Icon(Icons.edit_outlined, color: ZephyrColors.textDim),
                      title: const Text('Edit metadata', style: TextStyle(color: ZephyrColors.textDim, fontSize: 15)),
                      onTap: () {
                        Navigator.pop(modalContext);
                        _handleMenuSelection(context, ref, 'edit_metadata');
                      },
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _showAddToPlaylistDialog(BuildContext context, WidgetRef ref) {
    final library = ref.read(libraryProvider);
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: ZephyrColors.bgCard,
          title: const Text('Add to Playlist'),
          content: library.playlists.isEmpty
              ? const Text('No playlists found. Create one first in your Library.')
              : SizedBox(
                  width: double.maxFinite,
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: library.playlists.length,
                    itemBuilder: (context, index) {
                      final playlist = library.playlists[index];
                      return Material(
                        type: MaterialType.transparency,
                        child: ListTile(
                          leading: CoverImage(playlistId: playlist.id, size: 36),
                          title: Text(playlist.name),
                          onTap: () async {
                            Navigator.of(context).pop();
                            try {
                              await ref.read(libraryProvider.notifier).addTrackToPlaylist(playlist.id, widget.track);
                              if (context.mounted) ZephyrToast.show(context, 'Added to "${playlist.name}"');
                            } catch (e) {
                              if (!context.mounted) return;
                              final errStr = e.toString().toLowerCase();
                              final isDup = errStr.contains('duplicate') ||
                                  errStr.contains('already') ||
                                  errStr.contains('400') ||
                                  errStr.contains('409');
                              final msg = isDup
                                  ? 'Track is already in this playlist'
                                  : 'Failed to add: $e';
                              ZephyrToast.show(context, msg, isError: true);
                            }
                          },
                        ),
                      );
                    },
                  ),
                ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
          ],
        );
      },
    );
  }

  List<PopupMenuEntry<String>> _buildTrackMenuItems(BuildContext context, WidgetRef ref) {
    final authState = ref.read(authProvider);
    final isDownloadedOrLocal = widget.track.downloadStatus == 'completed' ||
        widget.track.isDownloaded ||
        widget.track.localPath != null ||
        widget.track.isLocal;

    final List<PopupMenuEntry<String>> items = [];

    final isFav = ref.read(libraryProvider.notifier).isFavorite(widget.track.videoId, title: widget.track.title, artists: widget.track.artists);
    items.add(
      PopupMenuItem(
        value: 'toggle_favorite',
        child: Row(
          children: [
            Icon(
              isFav ? Icons.favorite : Icons.favorite_border,
              size: 20,
              color: isFav ? ZephyrColors.primary : ZephyrColors.textDim,
            ),
            const SizedBox(width: 8),
            Text(isFav ? 'Remove from favorites' : 'Add to favorites'),
          ],
        ),
      ),
    );

    items.add(
      const PopupMenuItem(
        value: 'add_to_queue',
        child: Row(
          children: [
            Icon(Icons.queue_music_rounded, size: 20, color: ZephyrColors.textDim),
            SizedBox(width: 8),
            Text('Add to Queue'),
          ],
        ),
      ),
    );

    items.add(
      const PopupMenuItem(
        value: 'start_radio',
        child: Row(
          children: [
            Icon(Icons.radio_rounded, size: 20, color: ZephyrColors.textDim),
            SizedBox(width: 8),
            Text('Start Radio'),
          ],
        ),
      ),
    );

    items.add(
      const PopupMenuItem(
        value: 'add_to_playlist',
        child: Row(
          children: [
            Icon(Icons.playlist_add, size: 20, color: ZephyrColors.textDim),
            SizedBox(width: 8),
            Text('Add to Playlist'),
          ],
        ),
      ),
    );

    if (widget.onRemoveFromPlaylist != null) {
      items.add(
        const PopupMenuItem(
          value: 'remove_from_playlist',
          child: Row(
            children: [
              Icon(Icons.playlist_remove, size: 20, color: ZephyrColors.error),
              SizedBox(width: 8),
              Text('Remove from Playlist'),
            ],
          ),
        ),
      );
    }

    items.add(
      const PopupMenuItem(
        value: 'go_to_album',
        child: Row(
          children: [
            Icon(Icons.album_outlined, size: 20, color: ZephyrColors.textDim),
            SizedBox(width: 8),
            Text('Go to Album'),
          ],
        ),
      ),
    );

    if (widget.track.artists.isNotEmpty) {
      for (int i = 0; i < widget.track.artists.length; i++) {
        items.add(
          PopupMenuItem(
            value: 'go_to_artist_${i < widget.track.artistsIds.length ? widget.track.artistsIds[i] : widget.track.artists[i]}',
            child: Row(
              children: [
                const Icon(Icons.person_outline, size: 20, color: ZephyrColors.textDim),
                const SizedBox(width: 8),
                Text('Go to ${widget.track.artists[i]}'),
              ],
            ),
          ),
        );
      }
    }

    if (!isDownloadedOrLocal) {
      items.add(
        const PopupMenuItem(
          value: 'force_download',
          child: Row(
            children: [
              Icon(Icons.download_for_offline_outlined, size: 20, color: ZephyrColors.textDim),
              SizedBox(width: 8),
              Text('Download Track'),
            ],
          ),
        ),
      );
    }

    items.add(
      const PopupMenuItem(
        value: 'share_song',
        child: Row(
          children: [
            Icon(Icons.share_rounded, size: 20, color: ZephyrColors.textDim),
            SizedBox(width: 8),
            Text('Share Song'),
          ],
        ),
      ),
    );

    if (widget.track.needsResolution) {
      items.add(
        const PopupMenuItem(
          value: 'resolve_track',
          child: Row(
            children: [
              Icon(Icons.find_in_page_rounded, size: 20, color: Colors.amberAccent),
              SizedBox(width: 8),
              Text('Select match'),
            ],
          ),
        ),
      );
    }

    if (authState.isCurator) {
      items.add(
        const PopupMenuItem(
          value: 'edit_metadata',
          child: Row(
            children: [
              Icon(Icons.edit_note, size: 20, color: ZephyrColors.textDim),
              SizedBox(width: 8),
              Text('Edit Track Details'),
            ],
          ),
        ),
      );
    }

    if (authState.isAdmin) {
      items.add(
        PopupMenuItem(
          value: 'delete_track',
          child: Row(
            children: [
              Icon(Icons.delete_forever, size: 20, color: ZephyrColors.error.withValues(alpha: 0.8)),
              SizedBox(width: 8),
              const Text('Delete from Server', style: TextStyle(color: ZephyrColors.error)),
            ],
          ),
        ),
      );
    }

    if (widget.track.videoId.startsWith('dz_') && !widget.track.downloadStatus.startsWith('downloading')) {
      items.add(
        const PopupMenuItem(
          value: 'reopen_resolution',
          child: Row(
            children: [
              Icon(Icons.sync_problem_rounded, size: 20, color: ZephyrColors.warning),
              SizedBox(width: 8),
              Text('Report wrong match'),
            ],
          ),
        ),
      );
    }

    return items;
  }

  Future<void> _showRightClickMenu(BuildContext context, WidgetRef ref, Offset position) async {
    final RelativeRect positionRect = RelativeRect.fromRect(
      Rect.fromPoints(position, position),
      Offset.zero & MediaQuery.of(context).size,
    );

    final value = await showMenu<String>(
      context: context,
      position: positionRect,
      color: ZephyrColors.bgCard,
      items: _buildTrackMenuItems(context, ref),
    );
    if (value == null || !context.mounted) return;
    _handleMenuSelection(context, ref, value);
  }

  Future<void> _editMetadata(BuildContext context, WidgetRef ref) async {
    final updated = await showDialog<bool>(
      context: context,
      builder: (context) => TrackMetadataEditorDialog(track: widget.track),
    );
    if (updated == true) {
      ref.read(libraryProvider.notifier).loadLibrary();
    }
  }

  void _showDeleteConfirmationDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: ZephyrColors.bgCard,
          title: const Text('Delete Track permanently?'),
          content: Text('Are you sure you want to delete "${widget.track.title}" from the server? This will cascade to favorites, playlists, listening history, and delete files on disk.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel', style: TextStyle(color: ZephyrColors.textDim)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: ZephyrColors.error),
              onPressed: () async {
                try {
                  Navigator.pop(context); // Close dialog
                  await ZephyrApi().deleteTrack(widget.track.videoId);
                  ref.read(libraryProvider.notifier).loadLibrary();
                  if (context.mounted) {
                    ZephyrToast.show(context, 'Track "${widget.track.title}" deleted successfully.');
                  }
                } catch (e) {
                  if (context.mounted) {
                    ZephyrToast.show(context, 'Failed to delete track: $e', isError: true);
                  }
                }
              },
              child: const Text('Delete', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );
  }
}
