import 'dart:async';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../api/zephyr_api.dart';
import '../models/models.dart';
import '../providers/auth_provider.dart';
import '../providers/library_provider.dart';
import '../providers/navigation_provider.dart';
import '../providers/offline_provider.dart';
import '../providers/player_provider.dart';
import '../theme/colors.dart';
import '../theme/zephyr_theme.dart';
import '../widgets/cover_image.dart';
import '../widgets/track_tile.dart';
import '../widgets/toast.dart';

class PlaylistDetailScreen extends ConsumerStatefulWidget {
  final dynamic playlistId;

  const PlaylistDetailScreen({super.key, required this.playlistId});

  @override
  ConsumerState<PlaylistDetailScreen> createState() => _PlaylistDetailScreenState();
}

class _PlaylistDetailScreenState extends ConsumerState<PlaylistDetailScreen> {
  final _api = ZephyrApi();
  Playlist? _playlist;
  bool _isLoading = true;
  String? _error;
  bool _isReorderingMode = false;
  bool _isCoverHovered = false;
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _fetchPlaylistDetails();
  }

  Future<void> _fetchPlaylistDetails() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final details = await _api.getPlaylistDetail(widget.playlistId);
      // Defensive: a degenerate response (e.g. a body carrying only
      // `updated_at`) parses to id '0' / no tracks and must never blank an
      // already-loaded screen — keep the current playlist instead.
      final idStr = details.id?.toString() ?? '';
      final looksValid = idStr.isNotEmpty && idStr != '0';
      setState(() {
        if (!looksValid && _playlist != null) {
          _isLoading = false;
        } else {
          _playlist = details;
          _isLoading = false;
        }
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Map<String, dynamic> get _contextRef => {
    'type': 'playlist',
    'id': _playlist!.id.toString(),
    'order': 'as_listed',
  };

  void _playAllTracks() {
    if (_playlist == null || _playlist!.tracks == null || _playlist!.tracks!.isEmpty) return;
    final tracks = _playlist!.tracks!;
    ref.read(playerProvider.notifier).playTrack(
      tracks.first,
      tracks,
      isNewQueue: true,
      origin: 'context',
      contextRef: _contextRef,
    );
  }

  // Shuffle on a playlist is a TOGGLE: if this context is already playing
  // shuffled, pressing turns shuffle OFF (server-owned context order flips);
  // otherwise it starts/plans the playlist in shuffled order.
  void _toggleShufflePlay(List<Track> tracks, bool thisContextShuffled) {
    if (_playlist == null || tracks.isEmpty) return;
    final notif = ref.read(playerProvider.notifier);
    if (thisContextShuffled) {
      unawaited(notif.toggleShuffle());
    } else {
      unawaited(notif.playTrack(
        tracks.first,
        tracks,
        isNewQueue: true,
        origin: 'context',
        contextRef: {..._contextRef, 'order': 'shuffled'},
      ));
    }
  }

  bool _isDownloadingPlaylist = false;

  Future<void> _downloadPlaylist() async {
    if (_playlist == null || _playlist!.tracks == null || _playlist!.tracks!.isEmpty) return;
    final tracks = _playlist!.tracks!;
    setState(() => _isDownloadingPlaylist = true);
    try {
      ZephyrToast.show(context, 'Downloading "${_playlist!.name}" to this device...');
      await ref.read(offlineDownloadsProvider.notifier).downloadBatch(tracks);
      if (mounted) {
        ZephyrToast.show(context, 'Playlist "${_playlist!.name}" downloaded to device!');
      }
    } catch (e) {
      if (mounted) {
        ZephyrToast.show(context, 'Failed to download playlist: $e', isError: true);
      }
    } finally {
      if (mounted) {
        setState(() => _isDownloadingPlaylist = false);
      }
    }
  }

  Future<void> _pickAndUploadCover() async {
    if (_playlist == null) return;
    if (_playlist!.id.toString().startsWith('dz_')) return;
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
      );
      if (result != null && result.files.single.path != null) {
        final file = File(result.files.single.path!);
        await ref.read(libraryProvider.notifier).uploadPlaylistCover(_playlist!.id, file);
        await _fetchPlaylistDetails();
        if (mounted) {
          ZephyrToast.show(context, 'Cover updated successfully');
        }
      }
    } catch (e) {
      if (mounted) {
        ZephyrToast.show(context, 'Failed to upload cover: $e', isError: true);
      }
    }
  }

  void _showEditDetailsDialog() {
    if (_playlist == null || _playlist!.id.toString().startsWith('dz_')) return;
    final nameController = TextEditingController(text: _playlist!.name);
    final descController = TextEditingController(text: _playlist!.description ?? '');
    bool isPublic = _playlist!.isPublic;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: ZephyrColors.bgCard,
              title: const Text('Edit Playlist Details'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(labelText: 'Playlist Name'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: descController,
                    decoration: const InputDecoration(labelText: 'Description'),
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    title: const Text('Public Playlist'),
                    subtitle: const Text('Allow other users on this server to see and play'),
                    value: isPublic,
                    activeColor: ZephyrColors.primary,
                    contentPadding: EdgeInsets.zero,
                    onChanged: (val) => setDialogState(() => isPublic = val),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: ZephyrColors.primary),
                  onPressed: () async {
                    Navigator.of(context).pop();
                    await ref.read(libraryProvider.notifier).updatePlaylist(
                          _playlist!.id,
                          name: nameController.text.trim(),
                          description: descController.text.trim(),
                          isPublic: isPublic,
                        );
                    await _fetchPlaylistDetails();
                  },
                  child: const Text('Save', style: TextStyle(color: Colors.black)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _toggleSavePlaylist(bool isCurrentlySaved) async {
    if (_playlist == null || _playlist!.id.toString().startsWith('dz_')) return;
    try {
      if (isCurrentlySaved) {
        await ref.read(libraryProvider.notifier).unsavePlaylist(_playlist!.id);
        setState(() {
          _playlist = _playlist!.copyWith(isSaved: false);
        });
        if (mounted) ZephyrToast.show(context, 'Playlist removed from your library');
      } else {
        await ref.read(libraryProvider.notifier).savePlaylist(_playlist!.id);
        setState(() {
          _playlist = _playlist!.copyWith(isSaved: true);
        });
        if (mounted) ZephyrToast.show(context, 'Playlist saved to your library');
      }
    } catch (e) {
      if (mounted) ZephyrToast.show(context, 'Failed: $e', isError: true);
    }
  }

  void _deletePlaylist() {
    if (_playlist == null || _playlist!.id.toString().startsWith('dz_')) return;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: ZephyrColors.bgCard,
        title: const Text('Delete Playlist'),
        content: Text('Are you sure you want to delete "${_playlist!.name}"? This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: ZephyrColors.error),
            onPressed: () async {
              Navigator.of(context).pop();
              await ref.read(libraryProvider.notifier).deletePlaylist(_playlist!.id);
              ref.read(navigationProvider.notifier).navigateTo(const ScreenState(type: ScreenType.home));
            },
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Future<void> _removeTrack(String trackId) async {
    if (_playlist == null) return;
    try {
      // Route through the library notifier: it normalizes the playlist id
      // (model ids are Strings; the old direct API call passed one into an
      // `int` parameter → "Type String is not a subtype of int") and keeps
      // the shared library state in sync after the mutation.
      await ref
          .read(libraryProvider.notifier)
          .removeTrackFromPlaylist(_playlist!.id, trackId);
      await _fetchPlaylistDetails();
      if (mounted) ZephyrToast.show(context, 'Song removed from playlist');
    } catch (e) {
      if (mounted) ZephyrToast.show(context, 'Failed to remove: $e', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: ZephyrColors.primary));
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('Error: $_error', style: const TextStyle(color: ZephyrColors.error)),
            const SizedBox(height: 16),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: ZephyrColors.primary),
              onPressed: _fetchPlaylistDetails,
              child: const Text('Retry', style: TextStyle(color: Colors.black)),
            ),
          ],
        ),
      );
    }

    if (_playlist == null) {
      return const Center(child: Text('Playlist not found'));
    }

    final authState = ref.watch(authProvider);
    final currentUsername = authState.username;
    final libraryState = ref.watch(libraryProvider);

    final bool isInLibrary = libraryState.playlists.any(
      (p) => p.id.toString() == _playlist!.id.toString(),
    );
    final bool isSaved = _playlist!.isSaved || isInLibrary;

    final bool isPlaylistOwner = _playlist!.isOwner &&
        (currentUsername == null || _playlist!.ownerName == null || _playlist!.ownerName!.isEmpty || _playlist!.ownerName == currentUsername);

    final tracks = _playlist!.tracks ?? [];
    final isRemote = _playlist!.id.toString().startsWith('dz_');
    final isMobile = MediaQuery.of(context).size.width < 700;
    final offlineState = ref.watch(offlineDownloadsProvider);
    final bool allTracksDownloaded = tracks.isNotEmpty &&
        tracks.every((t) => offlineState.isDownloaded(t.videoId));

    // Shuffle control state: highlight + toggle-off when THIS playlist is the
    // active server context and it is currently shuffled.
    final playerActiveShuffle = ref.watch(playerProvider.select(
      (s) =>
          '${s.contextRef?['type']?.toString()};${s.contextRef?['id']?.toString()};${s.isShuffled}',
    ));
    final bool thisContextShuffled =
        playerActiveShuffle == 'playlist;${_playlist!.id.toString()};true';

    return Scaffold(
      backgroundColor: ZephyrColors.bgDark,
      body: CustomScrollView(
        key: PageStorageKey('playlist_detail_scroll_view_${widget.playlistId}'),
        controller: _scrollController,
        cacheExtent: 1500,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          // Playlist Header and Action Buttons
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: isMobile ? 16 : 32,
                vertical: isMobile ? 16 : 32,
              ),
              child: Column(
                crossAxisAlignment: isMobile ? CrossAxisAlignment.center : CrossAxisAlignment.start,
                children: [
                  if (isMobile) ...[
                    Center(
                      child: GestureDetector(
                        onTap: isRemote ? null : _pickAndUploadCover,
                        child: CoverImage(
                          coverUrl: _playlist!.coverUrl,
                          playlistId: isRemote ? null : _playlist!.id,
                          updatedAt: _playlist!.updatedAt,
                          size: 180,
                          borderRadius: 12,
                        ),
                      ),
                    ),
                      const SizedBox(height: 16),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Text(
                            'PLAYLIST',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.2,
                              color: ZephyrColors.textDim,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _playlist!.name,
                            style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: ZephyrColors.text,
                              letterSpacing: -0.5,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _playlist!.description ?? (_playlist!.ownerName != null ? 'By ${_playlist!.ownerName}' : 'No description'),
                            style: const TextStyle(
                              fontSize: 14,
                              color: ZephyrColors.textDim,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: 8,
                            runSpacing: 4,
                            children: [
                              Icon(
                                _playlist!.isPublic ? Icons.public : Icons.lock_outline,
                                size: 16,
                                color: ZephyrColors.textDim,
                              ),
                              Text(
                                isRemote ? 'Deezer Browse' : (_playlist!.isPublic ? 'Public Playlist' : 'Private Playlist'),
                                style: const TextStyle(color: ZephyrColors.textDim, fontSize: 13),
                              ),
                              const Icon(Icons.circle, size: 4, color: ZephyrColors.textDim),
                              Text(
                                '${_playlist!.trackCount ?? tracks.length} songs',
                                style: const TextStyle(color: ZephyrColors.textDim, fontSize: 13),
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              ElevatedButton.icon(
                                style: ZephyrTheme.primaryPillStyle(),
                                onPressed: tracks.isEmpty ? null : _playAllTracks,
                                icon: const Icon(Icons.play_arrow_rounded, size: 22, color: Colors.black),
                                label: const Text('Play All', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                              ),
                              const SizedBox(width: 12),
                              IconButton(
                                style: IconButton.styleFrom(
                                  backgroundColor: ZephyrColors.primary.withValues(alpha: 0.15),
                                  foregroundColor: ZephyrColors.primary,
                                  padding: const EdgeInsets.all(10),
                                ),
                                icon: Icon(
                                  Icons.shuffle_rounded,
                                  size: 20,
                                  color: thisContextShuffled
                                      ? ZephyrColors.primary
                                      : ZephyrColors.textDim,
                                ),
                                onPressed: tracks.isEmpty
                                    ? null
                                    : () => _toggleShufflePlay(tracks, thisContextShuffled),
                                tooltip: thisContextShuffled
                                    ? 'Turn off shuffle'
                                    : 'Shuffle play',
                              ),
                              if (!isRemote) ...[
                                if (!isPlaylistOwner) ...[
                                  const SizedBox(width: 12),
                                  IconButton(
                                    style: IconButton.styleFrom(
                                      backgroundColor: isSaved
                                          ? ZephyrColors.primary.withValues(alpha: 0.15)
                                          : ZephyrColors.bgLight,
                                      foregroundColor: isSaved
                                          ? ZephyrColors.primary
                                          : ZephyrColors.textDim,
                                      padding: const EdgeInsets.all(10),
                                    ),
                                    icon: Icon(
                                      isSaved
                                          ? Icons.bookmark_added_rounded
                                          : Icons.bookmark_add_outlined,
                                      size: 20,
                                    ),
                                    onPressed: () => _toggleSavePlaylist(isSaved),
                                    tooltip: isSaved
                                        ? 'Remove from Your Library'
                                        : 'Save to Your Library',
                                  ),
                                ],
                                const SizedBox(width: 12),
                                IconButton(
                                  style: IconButton.styleFrom(
                                    backgroundColor: allTracksDownloaded
                                        ? ZephyrColors.success.withValues(alpha: 0.15)
                                        : ZephyrColors.primary.withValues(alpha: 0.15),
                                    foregroundColor: allTracksDownloaded
                                        ? ZephyrColors.success
                                        : ZephyrColors.primary,
                                    padding: const EdgeInsets.all(10),
                                  ),
                                  icon: _isDownloadingPlaylist
                                      ? const SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(strokeWidth: 2, color: ZephyrColors.primary),
                                        )
                                      : Icon(
                                          allTracksDownloaded ? Icons.check_circle_rounded : Icons.download_rounded,
                                          size: 20,
                                        ),
                                  onPressed: _isDownloadingPlaylist ? null : _downloadPlaylist,
                                  tooltip: allTracksDownloaded
                                      ? 'All tracks downloaded to this device'
                                      : 'Download Playlist to this device',
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ] else ...[
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          GestureDetector(
                            onTap: isRemote ? null : _pickAndUploadCover,
                            child: MouseRegion(
                              cursor: isRemote ? SystemMouseCursors.basic : SystemMouseCursors.click,
                              onEnter: (_) => setState(() => _isCoverHovered = !isRemote),
                              onExit: (_) => setState(() => _isCoverHovered = false),
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  CoverImage(
                                    coverUrl: _playlist!.coverUrl,
                                    playlistId: isRemote ? null : _playlist!.id,
                                    updatedAt: _playlist!.updatedAt,
                                    size: 200,
                                    borderRadius: 12,
                                  ),
                                  if (_isCoverHovered && !isRemote)
                                    Container(
                                      width: 200,
                                      height: 200,
                                      decoration: BoxDecoration(
                                        color: Colors.black.withValues(alpha: 0.4),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: const Icon(
                                        Icons.camera_alt,
                                        color: Colors.white,
                                        size: 40,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 24),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  isRemote ? 'DEEZER PLAYLIST' : 'PLAYLIST',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 1.2,
                                    color: ZephyrColors.textDim,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  _playlist!.name,
                                  style: const TextStyle(
                                    fontSize: 36,
                                    fontWeight: FontWeight.bold,
                                    color: ZephyrColors.text,
                                    letterSpacing: -1,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  _playlist!.description ?? (_playlist!.ownerName != null ? 'By ${_playlist!.ownerName}' : 'No description'),
                                  style: const TextStyle(
                                    fontSize: 16,
                                    color: ZephyrColors.textDim,
                                  ),
                                ),
                                const SizedBox(height: 16),
                                Row(
                                  children: [
                                    Icon(
                                      _playlist!.isPublic ? Icons.public : Icons.lock_outline,
                                      size: 16,
                                      color: ZephyrColors.textDim,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      isRemote ? 'Deezer Browse' : (_playlist!.isPublic ? 'Public Playlist' : 'Private Playlist'),
                                      style: const TextStyle(color: ZephyrColors.textDim, fontSize: 13),
                                    ),
                                    const SizedBox(width: 12),
                                    const Icon(Icons.circle, size: 4, color: ZephyrColors.textDim),
                                    const SizedBox(width: 12),
                                    Text(
                                      '${_playlist!.trackCount ?? tracks.length} songs',
                                      style: const TextStyle(color: ZephyrColors.textDim, fontSize: 13),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 20),
                                Row(
                                  children: [
                                    ElevatedButton.icon(
                                      style: ZephyrTheme.primaryPillStyle(),
                                      onPressed: tracks.isEmpty ? null : _playAllTracks,
                                      icon: const Icon(Icons.play_arrow_rounded, size: 22, color: Colors.black),
                                      label: const Text('Play All', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                                    ),
                                    const SizedBox(width: 12),
                                    IconButton(
                                      style: IconButton.styleFrom(
                                        backgroundColor: ZephyrColors.primary.withValues(alpha: 0.15),
                                        foregroundColor: ZephyrColors.primary,
                                        padding: const EdgeInsets.all(10),
                                      ),
                                      icon: Icon(
                                        Icons.shuffle_rounded,
                                        size: 20,
                                        color: thisContextShuffled
                                            ? ZephyrColors.primary
                                            : ZephyrColors.textDim,
                                      ),
                                      onPressed: tracks.isEmpty
                                          ? null
                                          : () => _toggleShufflePlay(tracks, thisContextShuffled),
                                      tooltip: thisContextShuffled
                                          ? 'Turn off shuffle'
                                          : 'Shuffle play',
                                    ),
                                    if (!isRemote) ...[
                                      if (!isPlaylistOwner) ...[
                                        const SizedBox(width: 12),
                                        IconButton(
                                          style: IconButton.styleFrom(
                                            backgroundColor: isSaved
                                                ? ZephyrColors.primary.withValues(alpha: 0.15)
                                                : ZephyrColors.bgLight,
                                            foregroundColor: isSaved
                                                ? ZephyrColors.primary
                                                : ZephyrColors.textDim,
                                            padding: const EdgeInsets.all(10),
                                          ),
                                          icon: Icon(
                                            isSaved
                                                ? Icons.bookmark_added_rounded
                                                : Icons.bookmark_add_outlined,
                                            size: 20,
                                          ),
                                          onPressed: () => _toggleSavePlaylist(isSaved),
                                          tooltip: isSaved
                                              ? 'Remove from Your Library'
                                              : 'Save to Your Library',
                                        ),
                                      ],
                                      const SizedBox(width: 12),
                                      IconButton(
                                        style: IconButton.styleFrom(
                                          backgroundColor: allTracksDownloaded
                                              ? ZephyrColors.success.withValues(alpha: 0.15)
                                              : ZephyrColors.primary.withValues(alpha: 0.15),
                                          foregroundColor: allTracksDownloaded
                                              ? ZephyrColors.success
                                              : ZephyrColors.primary,
                                          padding: const EdgeInsets.all(10),
                                        ),
                                        icon: _isDownloadingPlaylist
                                            ? const SizedBox(
                                                width: 18,
                                                height: 18,
                                                child: CircularProgressIndicator(strokeWidth: 2, color: ZephyrColors.primary),
                                              )
                                            : Icon(
                                                allTracksDownloaded ? Icons.check_circle_rounded : Icons.download_rounded,
                                                size: 20,
                                              ),
                                        onPressed: _isDownloadingPlaylist ? null : _downloadPlaylist,
                                        tooltip: allTracksDownloaded
                                            ? 'All tracks downloaded to this device'
                                            : 'Download Playlist to this device',
                                      ),
                                      const SizedBox(width: 12),
                                      PopupMenuButton<String>(
                                        icon: const Icon(Icons.more_vert_rounded, color: ZephyrColors.textDim),
                                        color: ZephyrColors.bgCard,
                                        tooltip: 'Playlist Options',
                                        onSelected: (val) {
                                          if (val == 'edit') {
                                            _showEditDetailsDialog();
                                          } else if (val == 'cover') {
                                            _pickAndUploadCover();
                                          } else if (val == 'delete') {
                                            _deletePlaylist();
                                          } else if (val == 'toggle_save') {
                                            _toggleSavePlaylist(isSaved);
                                          } else if (val == 'reorder') {
                                            setState(() => _isReorderingMode = !_isReorderingMode);
                                          }
                                        },
                                        itemBuilder: (context) => [
                                          if (isPlaylistOwner) ...[
                                            const PopupMenuItem(
                                              value: 'edit',
                                              child: Row(
                                                children: [
                                                  Icon(Icons.edit_outlined, size: 20, color: ZephyrColors.textDim),
                                                  SizedBox(width: 8),
                                                  Text('Edit Details'),
                                                ],
                                              ),
                                            ),
                                            const PopupMenuItem(
                                              value: 'cover',
                                              child: Row(
                                                children: [
                                                  Icon(Icons.image_outlined, size: 20, color: ZephyrColors.textDim),
                                                  SizedBox(width: 8),
                                                  Text('Change Cover Image'),
                                                ],
                                              ),
                                            ),
                                            PopupMenuItem(
                                              value: 'reorder',
                                              child: Row(
                                                children: [
                                                  Icon(
                                                    _isReorderingMode ? Icons.check : Icons.reorder_rounded,
                                                    size: 20,
                                                    color: ZephyrColors.textDim,
                                                  ),
                                                  SizedBox(width: 8),
                                                  Text(_isReorderingMode ? 'Done Reordering' : 'Reorder Tracks'),
                                                ],
                                              ),
                                            ),
                                            const PopupMenuItem(
                                              value: 'delete',
                                              child: Row(
                                                children: [
                                                  Icon(Icons.delete_outline_rounded, size: 20, color: ZephyrColors.error),
                                                  SizedBox(width: 8),
                                                  Text('Delete Playlist', style: TextStyle(color: ZephyrColors.error)),
                                                ],
                                              ),
                                            ),
                                          ] else ...[
                                            PopupMenuItem(
                                              value: 'toggle_save',
                                              child: Row(
                                                children: [
                                                  Icon(
                                                    isSaved
                                                        ? Icons.bookmark_remove_outlined
                                                        : Icons.bookmark_add_outlined,
                                                    size: 20,
                                                    color: isSaved ? ZephyrColors.error : ZephyrColors.textDim,
                                                  ),
                                                  const SizedBox(width: 8),
                                                  Text(
                                                    isSaved ? 'Remove from Library' : 'Save to Library',
                                                    style: TextStyle(
                                                      color: isSaved ? ZephyrColors.error : ZephyrColors.text,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ],
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 28),

                    // Tracks List Header
                    if (!isMobile)
                      const Row(
                        children: [
                          SizedBox(width: 32),
                          SizedBox(width: 64, child: Text('#', style: TextStyle(color: ZephyrColors.textMuted, fontWeight: FontWeight.bold))),
                          Expanded(child: Text('TITLE', style: TextStyle(color: ZephyrColors.textMuted, fontWeight: FontWeight.bold))),
                          Text('ACTIONS', style: TextStyle(color: ZephyrColors.textMuted, fontWeight: FontWeight.bold)),
                          SizedBox(width: 100),
                        ],
                      ),
                    if (!isMobile)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8.0),
                        child: Divider(color: ZephyrColors.bgLight),
                      ),
                  ],
                ),
              ),
            ),

            // Virtualized Tracks List
            if (tracks.isEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: isMobile ? 16 : 32, vertical: 24),
                  child: const Text('No tracks in this playlist yet. Add songs using search!', style: TextStyle(color: ZephyrColors.textDim)),
                ),
              )
            else if (_isReorderingMode)
              SliverPadding(
                padding: EdgeInsets.symmetric(horizontal: isMobile ? 8 : 32),
                sliver: SliverReorderableList(
                  itemCount: tracks.length,
                  onReorder: (oldIndex, newIndex) async {
                    if (newIndex > oldIndex) {
                      newIndex -= 1;
                    }
                    final list = List<Track>.from(tracks);
                    final item = list.removeAt(oldIndex);
                    list.insert(newIndex, item);

                    final newIds = list.map((t) => t.videoId).toList();
                    await ref.read(libraryProvider.notifier).reorderPlaylistTracks(_playlist!.id, newIds);
                    await _fetchPlaylistDetails();
                  },
                  itemBuilder: (context, index) {
                    final track = tracks[index];
                    return ReorderableDragStartListener(
                      key: ValueKey(track.videoId),
                      index: index,
                      child: Row(
                        children: [
                          const Icon(Icons.drag_handle, color: ZephyrColors.textDim),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TrackTile(
                              track: track,
                              queue: tracks,
                              contextRef: _contextRef,
                              onRemoveFromPlaylist: () => _removeTrack(track.videoId),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              )
            else
              SliverPadding(
                padding: EdgeInsets.symmetric(horizontal: isMobile ? 8 : 32),
                sliver: SliverFixedExtentList(
                  itemExtent: 64.0,
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final track = tracks[index];
                      if (isMobile) {
                        return TrackTile(
                          key: ValueKey(track.videoId),
                          track: track,
                          queue: tracks,
                          contextRef: _contextRef,
                          onRemoveFromPlaylist: () => _removeTrack(track.videoId),
                        );
                      }
                      return Row(
                        key: ValueKey(track.videoId),
                        children: [
                          const SizedBox(width: 32),
                          SizedBox(
                            width: 32,
                            child: Text(
                              '${index + 1}',
                              style: const TextStyle(color: ZephyrColors.textDim, fontSize: 14),
                            ),
                          ),
                          Expanded(
                            child: TrackTile(
                              key: ValueKey('track_tile_${track.videoId}'),
                              track: track,
                              queue: tracks,
                              contextRef: _contextRef,
                              onRemoveFromPlaylist: () => _removeTrack(track.videoId),
                            ),
                          ),
                        ],
                      );
                    },
                    childCount: tracks.length,
                  ),
                ),
              ),
            const SliverPadding(padding: EdgeInsets.only(bottom: 120)),
          ],
        ),
    );
  }
}
