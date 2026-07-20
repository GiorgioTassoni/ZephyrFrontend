import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../api/zephyr_api.dart';
import '../models/models.dart';
import '../providers/library_provider.dart';
import '../providers/navigation_provider.dart';
import '../providers/player_provider.dart';
import '../theme/colors.dart';
import '../widgets/cover_image.dart';
import '../widgets/track_tile.dart';

class PlaylistDetailScreen extends ConsumerStatefulWidget {
  final int playlistId;

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
      setState(() {
        _playlist = details;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _pickAndUploadCover() async {
    if (_playlist == null) return;
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.image,
        allowMultiple: false,
      );

      if (result != null && result.files.single.path != null) {
        final file = File(result.files.single.path!);
        setState(() {
          _isLoading = true;
        });
        await ref.read(libraryProvider.notifier).uploadPlaylistCover(_playlist!.id, file);
        await _fetchPlaylistDetails();
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to upload cover: $e'), backgroundColor: ZephyrColors.error),
      );
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _showEditDetailsDialog() {
    if (_playlist == null) return;
    final nameController = TextEditingController(text: _playlist!.name);
    final descController = TextEditingController(text: _playlist!.description);
    bool isPublic = _playlist!.isPublic;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              backgroundColor: ZephyrColors.bgCard,
              title: const Text('Edit Playlist Details'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(labelText: 'Name'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: descController,
                    decoration: const InputDecoration(labelText: 'Description'),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Checkbox(
                        value: isPublic,
                        activeColor: ZephyrColors.primary,
                        onChanged: (val) {
                          setState(() {
                            isPublic = val ?? false;
                          });
                        },
                      ),
                      const Text('Public Visibility'),
                    ],
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel', style: TextStyle(color: ZephyrColors.textDim)),
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

  void _deletePlaylist() {
    if (_playlist == null) return;
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
      await ref.read(libraryProvider.notifier).removeTrackFromPlaylist(_playlist!.id, trackId);
      await _fetchPlaylistDetails();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Song removed from playlist')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to remove: $e'), backgroundColor: ZephyrColors.error),
      );
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

    final tracks = _playlist!.tracks ?? [];

    return Scaffold(
      backgroundColor: ZephyrColors.bgDark,
      body: RefreshIndicator(
        onRefresh: _fetchPlaylistDetails,
        color: ZephyrColors.primary,
        backgroundColor: ZephyrColors.bgCard,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header Details
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  GestureDetector(
                    onTap: _pickAndUploadCover,
                    child: MouseRegion(
                      cursor: SystemMouseCursors.click,
                      onEnter: (_) => setState(() => _isCoverHovered = true),
                      onExit: (_) => setState(() => _isCoverHovered = false),
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          CoverImage(
                            playlistId: _playlist!.id,
                            updatedAt: _playlist!.updatedAt,
                            size: 200,
                            borderRadius: 12,
                          ),
                          if (_isCoverHovered)
                            Container(
                              width: 200,
                              height: 200,
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.4),
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
                        const Text(
                          'PLAYLIST',
                          style: TextStyle(
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
                          _playlist!.description ?? 'No description',
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
                              _playlist!.isPublic ? 'Public Playlist' : 'Private Playlist',
                              style: const TextStyle(color: ZephyrColors.textDim, fontSize: 13),
                            ),
                            const SizedBox(width: 12),
                            const Icon(Icons.circle, size: 4, color: ZephyrColors.textDim),
                            const SizedBox(width: 12),
                            Text(
                              '${tracks.length} songs',
                              style: const TextStyle(color: ZephyrColors.textDim, fontSize: 13),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        Row(
                          children: [
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: ZephyrColors.primary,
                                foregroundColor: Colors.black,
                              ),
                              onPressed: () {
                                if (tracks.isNotEmpty) {
                                  ref.read(playerProvider.notifier).playTrack(tracks.first, tracks);
                                }
                              },
                              icon: const Icon(Icons.play_arrow),
                              label: const Text('Play'),
                            ),
                            const SizedBox(width: 12),
                            OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: ZephyrColors.text,
                                side: const BorderSide(color: ZephyrColors.bgLight),
                              ),
                              onPressed: _showEditDetailsDialog,
                              icon: const Icon(Icons.edit, size: 16),
                              label: const Text('Edit Info'),
                            ),
                            const SizedBox(width: 12),
                            OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: ZephyrColors.text,
                                side: const BorderSide(color: ZephyrColors.bgLight),
                              ),
                              onPressed: () {
                                setState(() {
                                  _isReorderingMode = !_isReorderingMode;
                                });
                              },
                              icon: Icon(
                                _isReorderingMode ? Icons.check : Icons.swap_vert,
                                size: 16,
                              ),
                              label: Text(_isReorderingMode ? 'Done Reordering' : 'Reorder Songs'),
                            ),
                            const SizedBox(width: 12),
                            IconButton(
                              icon: const Icon(Icons.delete_outline, color: ZephyrColors.error),
                              onPressed: _deletePlaylist,
                              tooltip: 'Delete Playlist',
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 40),

              // Tracks List Header
              const Row(
                children: [
                  SizedBox(width: 32),
                  SizedBox(width: 64, child: Text('#', style: TextStyle(color: ZephyrColors.textMuted, fontWeight: FontWeight.bold))),
                  Expanded(child: Text('TITLE', style: TextStyle(color: ZephyrColors.textMuted, fontWeight: FontWeight.bold))),
                  Text('ACTIONS', style: TextStyle(color: ZephyrColors.textMuted, fontWeight: FontWeight.bold)),
                  SizedBox(width: 100),
                ],
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8.0),
                child: Divider(color: ZephyrColors.bgLight),
              ),

              // Tracks List
              tracks.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(24.0),
                      child: Text('No tracks in this playlist yet. Add songs using search!', style: TextStyle(color: ZephyrColors.textDim)),
                    )
                  : _isReorderingMode
                      ? ReorderableListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: tracks.length,
                          onReorder: (oldIndex, newIndex) async {
                            if (newIndex > oldIndex) {
                              newIndex -= 1;
                            }
                            final list = List<Track>.from(tracks);
                            final item = list.removeAt(oldIndex);
                            list.insert(newIndex, item);
                            
                            // Call API to save reorder
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
                                      onRemoveFromPlaylist: () => _removeTrack(track.videoId),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        )
                      : ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: tracks.length,
                          itemBuilder: (context, index) {
                            final track = tracks[index];
                            return Row(
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
                                    track: track,
                                    queue: tracks,
                                    onRemoveFromPlaylist: () => _removeTrack(track.videoId),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
            ],
          ),
        ),
      ),
    );
  }
}
