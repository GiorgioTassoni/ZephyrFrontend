import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../api/zephyr_api.dart';
import '../models/models.dart';
import '../providers/library_provider.dart';
import '../providers/navigation_provider.dart';
import '../providers/offline_provider.dart';
import '../providers/player_provider.dart';
import '../theme/colors.dart';
import 'cover_image.dart';
import 'share_dialog.dart';
import 'toast.dart';
import 'unresolved_track_modal.dart';

Future<void> showPlayerSongContextMenu(
  BuildContext context,
  WidgetRef ref,
  Track track,
  Offset position,
) async {
  final navNotifier = ref.read(navigationProvider.notifier);
  final libraryNotifier = ref.read(libraryProvider.notifier);
  final offlineState = ref.read(offlineDownloadsProvider);
  final isFav = libraryNotifier.isFavorite(track.videoId, title: track.title, artists: track.artists);
  final isLocal = offlineState.isDownloaded(track.videoId);

  final RelativeRect positionRect = RelativeRect.fromRect(
    Rect.fromPoints(position, position),
    Offset.zero & MediaQuery.of(context).size,
  );

  final List<PopupMenuEntry<String>> menuItems = [
    // 1. Go to Album
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

    // 2. Go to Artist
    if (track.artists.isNotEmpty)
      for (int i = 0; i < track.artists.length; i++)
        PopupMenuItem(
          value: 'go_to_artist_${i < track.artistsIds.length ? track.artistsIds[i] : track.artists[i]}',
          child: Row(
            children: [
              const Icon(Icons.person_outline, size: 20, color: ZephyrColors.textDim),
              const SizedBox(width: 8),
              Text('Go to ${track.artists[i]}'),
            ],
          ),
        ),

    // 3. Add to Playlist
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

    // 4. Favorite / Unfavorite
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
          Text(isFav ? 'Remove from Favorites' : 'Add to Favorites'),
        ],
      ),
    ),

    // 5. Download / Remove from device
    PopupMenuItem(
      value: isLocal ? 'remove_from_device' : 'download_to_device',
      child: Row(
        children: [
          Icon(
            isLocal ? Icons.delete_outline_rounded : Icons.download_rounded,
            size: 20,
            color: isLocal ? ZephyrColors.error : ZephyrColors.textDim,
          ),
          const SizedBox(width: 8),
          Text(isLocal ? 'Remove from Device' : 'Download to Device'),
        ],
      ),
    ),

    // 6. Share Song
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

    // 7. Report wrong match (for Deezer tracks)
    if (track.videoId.startsWith('dz_') && !track.downloadStatus.startsWith('downloading'))
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
  ];

  final selectedValue = await showMenu<String>(
    context: context,
    position: positionRect,
    color: ZephyrColors.bgCard,
    items: menuItems,
  );

  if (selectedValue == null || !context.mounted) return;

  if (selectedValue == 'toggle_favorite') {
    libraryNotifier.toggleFavorite(track);
  } else if (selectedValue == 'download_to_device') {
    try {
      ZephyrToast.show(context, 'Downloading "${track.title}" to device...');
      await ref.read(offlineDownloadsProvider.notifier).downloadTrack(track);
      if (context.mounted) {
        ZephyrToast.show(context, 'Downloaded to this device!');
      }
    } catch (e) {
      if (context.mounted) {
        ZephyrToast.show(context, 'Download failed: $e', isError: true);
      }
    }
  } else if (selectedValue == 'remove_from_device') {
    await ref.read(offlineDownloadsProvider.notifier).removeDownload(track.videoId);
    if (context.mounted) {
      ZephyrToast.show(context, 'Removed from this device');
    }
  } else if (selectedValue == 'add_to_playlist') {
    _showAddToPlaylistDialog(context, ref, track);
  } else if (selectedValue == 'share_song') {
    showShareDialog(context, ref, track);
  } else if (selectedValue == 'go_to_album') {
    _navigateToAlbum(context, ref, track);
  } else if (selectedValue == 'reopen_resolution') {
    _reopenTrackResolution(context, ref, track);
  } else if (selectedValue.startsWith('go_to_artist_')) {
    final id = selectedValue.substring('go_to_artist_'.length);
    navNotifier.navigateTo(ScreenState(type: ScreenType.artist, id: id));
  }
}

Future<void> _navigateToAlbum(BuildContext context, WidgetRef ref, Track track) async {
  final navNotifier = ref.read(navigationProvider.notifier);
  if (track.albumId != null && track.albumId!.isNotEmpty) {
    navNotifier.navigateTo(ScreenState(type: ScreenType.album, id: track.albumId!));
  } else {
    final query = (track.album != null && track.album!.isNotEmpty)
        ? '${track.album} ${track.artists.isNotEmpty ? track.artists.first : ''}'.trim()
        : '${track.title} ${track.artists.isNotEmpty ? track.artists.first : ''}'.trim();
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

void _showAddToPlaylistDialog(BuildContext context, WidgetRef ref, Track track) {
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
                            await ref.read(libraryProvider.notifier).addTrackToPlaylist(playlist.id, track);
                            if (context.mounted) ZephyrToast.show(context, 'Added to "${playlist.name}"');
                          } catch (e) {
                            if (!context.mounted) return;
                            final errStr = e.toString().toLowerCase();
                            final isDup = errStr.contains('duplicate') ||
                                errStr.contains('already') ||
                                errStr.contains('400') ||
                                errStr.contains('409');
                            ZephyrToast.show(
                              context,
                              isDup ? 'Track is already in "${playlist.name}"' : 'Failed to add to playlist: $e',
                              isError: true,
                            );
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

Future<void> _reopenTrackResolution(BuildContext context, WidgetRef ref, Track track) async {
  try {
    final playerState = ref.read(playerProvider);
    final playerNotifier = ref.read(playerProvider.notifier);
    final isCurrentActiveTrack = playerState.currentTrack?.videoId == track.videoId;

    playerNotifier.clearResolvedCache(track.videoId);
    await ZephyrApi().reopenTrackResolution(track.videoId);

    if (context.mounted) {
      ZephyrToast.show(context, 'Track reset for re-resolution. Choose new match:');
      ref.read(libraryProvider.notifier).loadLibrary();
      final selected = await UnresolvedTrackModal.show(
        context,
        trackId: track.videoId,
        title: track.title,
        artists: track.artists,
      );
      if (selected == true && context.mounted) {
        ZephyrToast.show(context, 'Selection saved! Re-streaming correct track...');
        ref.read(libraryProvider.notifier).loadLibrary();
        if (isCurrentActiveTrack) {
          playerNotifier.playTrack(track, playerState.queue.isNotEmpty ? playerState.queue : [track]);
        }
      }
    }
  } catch (e) {
    if (context.mounted) {
      ZephyrToast.show(context, 'Reopen failed: $e', isError: true);
    }
  }
}
