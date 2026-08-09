import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/models.dart';
import '../providers/library_provider.dart';
import '../providers/player_provider.dart';
import '../api/zephyr_api.dart';
import '../theme/colors.dart';
import '../providers/auth_provider.dart';
import '../providers/navigation_provider.dart';
import 'track_metadata_editor_dialog.dart';
import 'share_dialog.dart';
import 'cover_image.dart';
import 'artist_links.dart';
import 'favorite_button.dart';
import 'resolution_candidate_modal.dart';
import 'toast.dart';

class TrackTile extends ConsumerStatefulWidget {
  final Track track;
  final List<Track> queue;
  final VoidCallback? onRemoveFromPlaylist;
  final Widget? trailing;

  const TrackTile({
    super.key,
    required this.track,
    required this.queue,
    this.onRemoveFromPlaylist,
    this.trailing,
  });

  @override
  ConsumerState<TrackTile> createState() => _TrackTileState();
}

class _TrackTileState extends ConsumerState<TrackTile> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final playerState = ref.watch(playerProvider);
    final playerNotifier = ref.read(playerProvider.notifier);
    final libraryState = ref.watch(libraryProvider);
    final libraryNotifier = ref.read(libraryProvider.notifier);
    final isCurrent = playerState.currentTrack?.videoId == widget.track.videoId;
    final isFav = libraryNotifier.isFavorite(widget.track.videoId, title: widget.track.title);

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onSecondaryTapDown: (details) {
          _showRightClickMenu(context, ref, details.globalPosition);
        },
        child: Material(
          color: isCurrent
              ? ZephyrColors.bgLight.withValues(alpha: 0.5)
              : (_isHovered ? ZephyrColors.bgLight.withValues(alpha: 0.3) : Colors.transparent),
          borderRadius: BorderRadius.circular(8),
          clipBehavior: Clip.antiAlias,
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            leading: Stack(
              alignment: Alignment.center,
              children: [
                CoverImage(
                  videoId: widget.track.videoId,
                  coverUrl: widget.track.coverUrl,
                  size: 48,
                ),
                if (_isHovered || isCurrent)
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: IconButton(
                      icon: Icon(
                        isCurrent && playerState.isPlaying ? Icons.pause : Icons.play_arrow,
                        color: ZephyrColors.primary,
                        size: 24,
                      ),
                      onPressed: () {
                        if (isCurrent) {
                          playerNotifier.togglePlayPause();
                        } else {
                          playerNotifier.playTrack(widget.track, widget.queue);
                        }
                      },
                    ),
                  ),
              ],
            ),
            title: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.track.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: isCurrent ? ZephyrColors.primary : ZephyrColors.text,
                    ),
                  ),
                ),
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
              style: const TextStyle(
                color: ZephyrColors.textDim,
                fontSize: 12,
              ),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildDownloadIndicator(context, ref),
                FavoriteButton(
                  isFavorite: isFav,
                  size: 20,
                  onTap: () => libraryNotifier.toggleFavorite(widget.track),
                ),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert, color: ZephyrColors.textDim),
                  color: ZephyrColors.bgCard,
                  onSelected: (value) => _handleMenuSelection(context, ref, value),
                  itemBuilder: (context) {
                    return [
                      if (widget.track.videoId.startsWith('dz_') && !widget.track.downloadStatus.startsWith('downloading'))
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
                      if (widget.track.needsResolution)
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
                      if (widget.onRemoveFromPlaylist != null)
                        const PopupMenuItem(
                          value: 'remove_from_playlist',
                          child: Row(
                            children: [
                              Icon(Icons.playlist_remove, size: 20, color: ZephyrColors.error),
                              SizedBox(width: 8),
                              Text('Remove from Playlist', style: TextStyle(color: ZephyrColors.error)),
                            ],
                          ),
                        ),
                      const PopupMenuItem(
                        value: 'force_download',
                        child: Row(
                          children: [
                            Icon(Icons.download, size: 20, color: ZephyrColors.textDim),
                            SizedBox(width: 8),
                            Text('Queue Download'),
                          ],
                        ),
                      ),
                      for (int i = 0; i < widget.track.artists.length; i++)
                        if (widget.track.artistsIds.length > i && widget.track.artistsIds[i].isNotEmpty)
                          PopupMenuItem(
                            value: 'go_to_artist_${widget.track.artistsIds[i]}',
                            child: Row(
                              children: [
                                const Icon(Icons.person, size: 20, color: ZephyrColors.textDim),
                                const SizedBox(width: 8),
                                Text('Go to ${widget.track.artists[i]}'),
                              ],
                            ),
                          ),
                    ];
                  },
                ),
              ],
            ),
            onTap: () {
              playerNotifier.playTrack(widget.track, widget.queue);
            },
          ),
        ),
      ),
    );
  }

  Widget _buildDownloadIndicator(BuildContext context, WidgetRef ref) {
    switch (widget.track.downloadStatus) {
      case 'completed':
        return const Padding(
          padding: EdgeInsets.symmetric(horizontal: 8.0),
          child: Icon(Icons.check_circle, color: ZephyrColors.success, size: 18),
        );
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
            ZephyrToast.show(context, 'Download failed. Tap context menu to retry.', isError: true);
          },
        );
      default:
        return IconButton(
          icon: const Icon(Icons.download_for_offline_outlined, color: ZephyrColors.textDim, size: 18),
          onPressed: () => _startDownload(context, ref),
        );
    }
  }

  Future<void> _startDownload(BuildContext context, WidgetRef ref) async {
    try {
      await ZephyrApi().queueDownload(widget.track.videoId);
      if (context.mounted) {
        ZephyrToast.show(context, 'Download queued!');
        ref.read(libraryProvider.notifier).loadLibrary();
      }
    } on ResolutionRequiredException catch (e) {
      if (context.mounted) {
        final selected = await ResolutionCandidateModal.show(context, e);
        if (selected == true && context.mounted) {
          ZephyrToast.show(context, 'Selection saved! Download queued.');
          ref.read(libraryProvider.notifier).loadLibrary();
        }
      }
    } on TrackUnavailableException catch (e) {
      if (context.mounted) {
        ZephyrToast.show(context, e.message, isError: true);
      }
    } on ProviderUnavailableException catch (e) {
      if (context.mounted) {
        ZephyrToast.show(context, e.message, isError: true);
      }
    } catch (e) {
      if (context.mounted) {
        ZephyrToast.show(context, 'Failed to queue: $e', isError: true);
      }
    }
  }

  Future<void> _triggerResolutionFlow(BuildContext context, WidgetRef ref) async {
    try {
      final data = await ZephyrApi().getTrackResolution(widget.track.videoId);
      if (data != null && context.mounted) {
        final exc = ResolutionRequiredException.fromJson(data);
        final selected = await ResolutionCandidateModal.show(context, exc);
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

  void _handleMenuSelection(BuildContext context, WidgetRef ref, String value) {
    if (value == 'add_to_playlist') {
      _showAddToPlaylistDialog(context, ref);
    } else if (value == 'remove_from_playlist') {
      widget.onRemoveFromPlaylist?.call();
    } else if (value == 'force_download') {
      _startDownload(context, ref);
    } else if (value == 'reopen_resolution') {
      _reopenResolution(context, ref);
    } else if (value == 'resolve_track') {
      _triggerResolutionFlow(context, ref);
    } else if (value.startsWith('go_to_artist_')) {
      final id = value.substring('go_to_artist_'.length);
      ref.read(navigationProvider.notifier).navigateTo(ScreenState(type: ScreenType.artist, id: id));
    }
  }

  Future<void> _reopenResolution(BuildContext context, WidgetRef ref) async {
    try {
      await ZephyrApi().reopenTrackResolution(widget.track.videoId);
      if (context.mounted) {
        ZephyrToast.show(context, 'Track reset for re-resolution.');
        ref.read(libraryProvider.notifier).loadLibrary();
      }
    } on ResolutionRequiredException catch (e) {
      if (context.mounted) {
        final selected = await ResolutionCandidateModal.show(context, e);
        if (selected == true && context.mounted) {
          ZephyrToast.show(context, 'Selection saved!');
          ref.read(libraryProvider.notifier).loadLibrary();
        }
      }
    } catch (e) {
      if (context.mounted) {
        ZephyrToast.show(context, 'Reopen failed: $e', isError: true);
      }
    }
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
                              ZephyrToast.show(context, 'Added to "${playlist.name}"');
                            } catch (e) {
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

  void _showRightClickMenu(BuildContext context, WidgetRef ref, Offset position) {
    final playerNotifier = ref.read(playerProvider.notifier);
    final authState = ref.read(authProvider);

    final RelativeRect positionRect = RelativeRect.fromRect(
      Rect.fromPoints(position, position),
      Offset.zero & MediaQuery.of(context).size,
    );

    final List<PopupMenuEntry<String>> menuItems = [
      PopupMenuItem(
        value: 'queue_action',
        child: Row(
          children: [
            Icon(
              Icons.queue_music,
              size: 20,
              color: ZephyrColors.textDim,
            ),
            const SizedBox(width: 8),
            Text(
              'Add to Queue',
              style: TextStyle(color: ZephyrColors.text),
            ),
          ],
        ),
      ),
      PopupMenuItem(
        value: 'add_to_playlist',
        child: Row(
          children: [
            Icon(Icons.playlist_add, size: 20, color: ZephyrColors.textDim),
            const SizedBox(width: 8),
            Text('Add to Playlist', style: TextStyle(color: ZephyrColors.text)),
          ],
        ),
      ),
      PopupMenuItem(
        value: 'share_song',
        child: Row(
          children: [
            Icon(Icons.share_rounded, size: 20, color: ZephyrColors.textDim),
            const SizedBox(width: 8),
            Text('Share Song', style: TextStyle(color: ZephyrColors.text)),
          ],
        ),
      ),
      PopupMenuItem(
        value: 'go_to_album',
        child: Row(
          children: [
            Icon(Icons.album, size: 20, color: ZephyrColors.textDim),
            const SizedBox(width: 8),
            Text('Go to album', style: TextStyle(color: ZephyrColors.text)),
          ],
        ),
      ),
    ];

    if (widget.track.videoId.startsWith('dz_') && !widget.track.downloadStatus.startsWith('downloading')) {
      menuItems.add(
        PopupMenuItem(
          value: 'reopen_resolution',
          child: Row(
            children: const [
              Icon(Icons.sync_problem_rounded, size: 20, color: ZephyrColors.warning),
              SizedBox(width: 8),
              Text('Report wrong match', style: TextStyle(color: ZephyrColors.text)),
            ],
          ),
        ),
      );
    }

    if (widget.track.needsResolution) {
      menuItems.add(
        PopupMenuItem(
          value: 'resolve_track',
          child: Row(
            children: const [
              Icon(Icons.find_in_page_rounded, size: 20, color: Colors.amberAccent),
              SizedBox(width: 8),
              Text('Select match', style: TextStyle(color: ZephyrColors.text)),
            ],
          ),
        ),
      );
    }

    if (authState.isCurator) {
      menuItems.add(
        PopupMenuItem(
          value: 'edit_metadata',
          child: Row(
            children: [
              Icon(Icons.edit_note, size: 20, color: ZephyrColors.textDim),
              const SizedBox(width: 8),
              Text('Edit Track Details', style: TextStyle(color: ZephyrColors.text)),
            ],
          ),
        ),
      );
    }

    if (authState.isAdmin) {
      menuItems.add(
        PopupMenuItem(
          value: 'delete_track',
          child: Row(
            children: [
              Icon(Icons.delete_forever, size: 20, color: ZephyrColors.error.withValues(alpha: 0.8)),
              const SizedBox(width: 8),
              Text('Delete from Server', style: TextStyle(color: ZephyrColors.error)),
            ],
          ),
        ),
      );
    }

    showMenu<String>(
      context: context,
      position: positionRect,
      color: ZephyrColors.bgCard,
      items: menuItems,
    ).then((value) {
      if (value == null) return;
      
      if (value == 'queue_action') {
        playerNotifier.addToQueue(widget.track);
        ZephyrToast.show(
          context,
          'Added "${widget.track.title}" to queue!',
        );
      } else if (value == 'add_to_playlist') {
        _showAddToPlaylistDialog(context, ref);
      } else if (value == 'share_song') {
        showShareDialog(context, ref, widget.track);
      } else if (value == 'go_to_album') {
        final navNotifier = ref.read(navigationProvider.notifier);
        if (widget.track.albumId != null && widget.track.albumId!.isNotEmpty) {
          navNotifier.navigateTo(ScreenState(type: ScreenType.album, id: widget.track.albumId!));
        } else {
          final query = (widget.track.album != null && widget.track.album!.isNotEmpty)
              ? '${widget.track.album} ${widget.track.artists.isNotEmpty ? widget.track.artists.first : ''}'.trim()
              : '${widget.track.title} ${widget.track.artists.isNotEmpty ? widget.track.artists.first : ''}'.trim();
          ZephyrApi().search(query, remote: true).then((searchRes) {
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
            ZephyrToast.show(context, 'Could not find album page');
          }).catchError((_) {
            ZephyrToast.show(context, 'Could not find album page');
          });
        }
      } else if (value == 'edit_metadata') {
        showDialog<bool>(
          context: context,
          builder: (context) => TrackMetadataEditorDialog(track: widget.track),
        ).then((updated) {
          if (updated == true) {
            ref.read(libraryProvider.notifier).loadLibrary();
          }
        });
      } else if (value == 'delete_track') {
        _showDeleteConfirmationDialog(context, ref);
      }
    });
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
