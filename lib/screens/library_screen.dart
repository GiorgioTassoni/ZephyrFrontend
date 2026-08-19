import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../api/zephyr_api.dart';
import '../models/models.dart';
import '../providers/auth_provider.dart';
import '../providers/library_provider.dart';
import '../providers/navigation_provider.dart';
import '../theme/colors.dart';
import '../widgets/playlist_card.dart';
import '../widgets/track_tile.dart';
import 'favorites_screen.dart';

enum LibraryView {
  grid,
  favorites,
  vpsSongs,
}

class LibraryScreen extends ConsumerStatefulWidget {
  final int initialTabIndex;
  const LibraryScreen({super.key, this.initialTabIndex = 0});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  late LibraryView _currentView;
  final ScrollController _favoritesScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _resolveCurrentView();
    _favoritesScrollController.addListener(_onFavoritesScroll);
  }

  @override
  void dispose() {
    _favoritesScrollController
      ..removeListener(_onFavoritesScroll)
      ..dispose();
    super.dispose();
  }

  void _onFavoritesScroll() {
    final sc = _favoritesScrollController;
    if (!sc.hasClients) return;
    final remaining = sc.position.maxScrollExtent - sc.position.pixels;
    // Start fetching next page when within 300px of the bottom
    if (remaining < 300) {
      ref.read(libraryProvider.notifier).loadMoreFavorites();
    }
  }

  @override
  void didUpdateWidget(LibraryScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialTabIndex != oldWidget.initialTabIndex) {
      setState(() {
        _resolveCurrentView();
      });
    }
  }

  void _resolveCurrentView() {
    final authState = ref.read(authProvider);
    if (widget.initialTabIndex == 0) {
      _currentView = LibraryView.favorites;
      final libraryState = ref.read(libraryProvider);
      if (libraryState.favorites.isEmpty) {
        Future.microtask(() => ref.read(libraryProvider.notifier).loadFavorites());
      }
    } else if (widget.initialTabIndex == 2 && authState.isAdmin) {
      _currentView = LibraryView.vpsSongs;
    } else {
      _currentView = LibraryView.grid;
    }
  }

  @override
  Widget build(BuildContext context) {
    final libraryState = ref.watch(libraryProvider);
    final navNotifier = ref.read(navigationProvider.notifier);

    return Scaffold(
      backgroundColor: ZephyrColors.bgDark,
      body: _buildCurrentView(libraryState, navNotifier),
    );
  }

  Widget _buildCurrentView(LibraryState libraryState, NavigationNotifier navNotifier) {
    final authState = ref.watch(authProvider);
    switch (_currentView) {
      case LibraryView.favorites:
        return const FavoritesScreen();
      case LibraryView.vpsSongs:
        if (!authState.isAdmin) {
          return _buildLibraryGridView(libraryState, navNotifier);
        }
        return _buildVpsSongsDetailView(libraryState, navNotifier);
      case LibraryView.grid:
        return _buildLibraryGridView(libraryState, navNotifier);
    }
  }

  Widget _buildLibraryGridView(LibraryState libraryState, NavigationNotifier navNotifier) {
    final authState = ref.watch(authProvider);
    final isAdmin = authState.isAdmin;
    final totalItems = (isAdmin ? 2 : 1) + libraryState.playlists.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Title Header
        const Padding(
          padding: EdgeInsets.only(left: 24, top: 24, right: 24, bottom: 8),
          child: Text(
            'Your Library',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: ZephyrColors.text,
            ),
          ),
        ),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.all(24),
            itemCount: totalItems,
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 160,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
              childAspectRatio: 0.75,
            ),
            itemBuilder: (context, index) {
              if (index == 0) {
                // Favorite Card
                return _CustomLibraryCard(
                  title: 'Favorite',
                  icon: const Icon(Icons.favorite, size: 54, color: ZephyrColors.primary),
                  backgroundColor: ZephyrColors.primary.withValues(alpha: 0.15),
                  onTap: () {
                    navNotifier.navigateTo(const ScreenState(type: ScreenType.favorites));
                    ref.read(libraryProvider.notifier).loadFavorites();
                  },
                );
              }
              
              if (isAdmin) {
                if (index == 1) {
                  // VPS Songs Card
                  return _CustomLibraryCard(
                    title: 'VPS Songs',
                    icon: const Icon(Icons.library_music, size: 54, color: Colors.blue),
                    backgroundColor: Colors.blue.withValues(alpha: 0.15),
                    onTap: () => navNotifier.navigateTo(const ScreenState(type: ScreenType.library, intId: 2)),
                  );
                } else {
                  // Playlist Cards
                  final playlist = libraryState.playlists[index - 2];
                  return PlaylistCard(
                    playlist: playlist,
                    onTap: () {
                      navNotifier.navigateTo(
                        ScreenState(
                          type: ScreenType.playlist,
                          id: playlist.id.toString(),
                          intId: playlist.id is int
                              ? playlist.id as int
                              : int.tryParse(playlist.id.toString()),
                        ),
                      );
                    },
                  );
                }
              } else {
                // Playlist Cards
                final playlist = libraryState.playlists[index - 1];
                return PlaylistCard(
                  playlist: playlist,
                  onTap: () {
                    navNotifier.navigateTo(
                      ScreenState(
                        type: ScreenType.playlist,
                        id: playlist.id.toString(),
                        intId: playlist.id is int
                            ? playlist.id as int
                            : int.tryParse(playlist.id.toString()),
                      ),
                    );
                  },
                );
              }
            },
          ),
        ),
      ],
    );
  }



  bool _isSelectingVps = false;
  final Set<String> _selectedVpsTrackIds = {};
  bool _isDeletingBulk = false;

  Future<void> _bulkDeleteVpsTracks(List<Track> allTracks) async {
    if (_selectedVpsTrackIds.isEmpty) return;

    bool deleteRemoteAssets = true;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          backgroundColor: ZephyrColors.bgCard,
          title: Text(
            'Delete ${_selectedVpsTrackIds.length} Track${_selectedVpsTrackIds.length == 1 ? '' : 's'}?',
            style: const TextStyle(color: ZephyrColors.text),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'This will delete ${_selectedVpsTrackIds.length} selected track(s) and their local files from the server.',
                style: const TextStyle(color: ZephyrColors.textDim, fontSize: 13),
              ),
              const SizedBox(height: 16),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                activeColor: ZephyrColors.primary,
                title: const Text('Delete remote S3 assets', style: TextStyle(color: ZephyrColors.text, fontSize: 13)),
                subtitle: const Text('Remove remote S3 audio and unreferenced covers', style: TextStyle(color: ZephyrColors.textDim, fontSize: 11)),
                value: deleteRemoteAssets,
                onChanged: (val) {
                  setDlgState(() {
                    deleteRemoteAssets = val ?? true;
                  });
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel', style: TextStyle(color: ZephyrColors.textDim)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: ZephyrColors.error),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Delete', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _isDeletingBulk = true);

    try {
      final res = await ZephyrApi().deleteTracksBulk(
        trackIds: _selectedVpsTrackIds.toList(),
        deleteRemoteAssets: deleteRemoteAssets,
      );

      if (!mounted) return;

      final deleted = res['deleted'] ?? 0;
      final skipped = (res['skipped'] as List?) ?? [];
      final notFound = (res['not_found'] as List?) ?? [];
      final localAssets = (res['removed_local_assets'] as Map?) ?? {};
      final remoteAssets = (res['removed_remote_assets'] as Map?) ?? {};
      final cleanupErrors = (res['cleanup_errors'] as List?) ?? [];

      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: ZephyrColors.bgCard,
          title: const Row(
            children: [
              Icon(Icons.delete_sweep, color: ZephyrColors.primary),
              SizedBox(width: 10),
              Text('Bulk Deletion Results', style: TextStyle(color: ZephyrColors.text)),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('• Successfully deleted: $deleted', style: const TextStyle(color: ZephyrColors.success, fontWeight: FontWeight.bold)),
                if (skipped.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text('• Skipped tracks (${skipped.length}):', style: const TextStyle(color: ZephyrColors.warning, fontWeight: FontWeight.bold)),
                  ...skipped.map((s) {
                    final tId = s is Map ? s['track_id'] : s.toString();
                    final reason = s is Map ? s['reason'] : '';
                    return Padding(
                      padding: const EdgeInsets.only(left: 12, top: 2),
                      child: Text('  - $tId ($reason)', style: const TextStyle(color: ZephyrColors.textDim, fontSize: 12)),
                    );
                  }),
                ],
                if (notFound.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text('• Not found in database: ${notFound.length}', style: const TextStyle(color: ZephyrColors.textDim)),
                ],
                const SizedBox(height: 12),
                const Divider(color: ZephyrColors.bgLight),
                const SizedBox(height: 6),
                const Text('Cleaned Assets:', style: TextStyle(color: ZephyrColors.text, fontWeight: FontWeight.bold, fontSize: 12)),
                Text('  Local: audio: ${localAssets['audio'] ?? 0}, covers: ${localAssets['covers'] ?? 0}, lyrics: ${localAssets['lyrics'] ?? 0}', style: const TextStyle(color: ZephyrColors.textDim, fontSize: 12)),
                Text('  Remote (S3): audio: ${remoteAssets['audio'] ?? 0}, covers: ${remoteAssets['covers'] ?? 0}', style: const TextStyle(color: ZephyrColors.textDim, fontSize: 12)),
                if (cleanupErrors.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text('• Cleanup errors: ${cleanupErrors.length}', style: const TextStyle(color: ZephyrColors.error, fontWeight: FontWeight.bold)),
                  ...cleanupErrors.map((e) => Padding(
                    padding: const EdgeInsets.only(left: 12, top: 2),
                    child: Text('  - $e', style: const TextStyle(color: ZephyrColors.error, fontSize: 11)),
                  )),
                ],
              ],
            ),
          ),
          actions: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: ZephyrColors.primary),
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('OK', style: TextStyle(color: Colors.black)),
            ),
          ],
        ),
      );

      setState(() {
        _selectedVpsTrackIds.clear();
        _isSelectingVps = false;
      });

      ref.read(libraryProvider.notifier).loadLibrary();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Bulk delete failed: $e'), backgroundColor: ZephyrColors.error),
      );
    } finally {
      if (mounted) setState(() => _isDeletingBulk = false);
    }
  }

  Widget _buildVpsSongsDetailView(LibraryState libraryState, NavigationNotifier navNotifier) {
    final tracks = libraryState.downloadedTracks;
    final allSelected = tracks.isNotEmpty && _selectedVpsTrackIds.length == tracks.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Padding(
          padding: const EdgeInsets.only(left: 16, top: 16, right: 16, bottom: 8),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back, color: ZephyrColors.text),
                onPressed: () {
                  if (_isSelectingVps) {
                    setState(() {
                      _isSelectingVps = false;
                      _selectedVpsTrackIds.clear();
                    });
                  } else if (navNotifier.canGoBack) {
                    navNotifier.navigateBack();
                  } else {
                    navNotifier.navigateTo(const ScreenState(type: ScreenType.library, intId: 1));
                  }
                },
              ),
              const SizedBox(width: 8),
              const Icon(Icons.library_music, color: Colors.blue, size: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'VPS Songs',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: ZephyrColors.text,
                      ),
                    ),
                    Text(
                      '${tracks.length} downloaded tracks on server',
                      style: const TextStyle(fontSize: 12, color: ZephyrColors.textDim),
                    ),
                  ],
                ),
              ),
              if (tracks.isNotEmpty) ...[
                if (_isSelectingVps) ...[
                  TextButton.icon(
                    icon: Icon(allSelected ? Icons.deselect : Icons.select_all, size: 18),
                    label: Text(allSelected ? 'Deselect All' : 'Select All'),
                    style: TextButton.styleFrom(foregroundColor: ZephyrColors.primary),
                    onPressed: () {
                      setState(() {
                        if (allSelected) {
                          _selectedVpsTrackIds.clear();
                        } else {
                          _selectedVpsTrackIds.addAll(tracks.map((t) => t.videoId));
                        }
                      });
                    },
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: ZephyrColors.error,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    ),
                    icon: _isDeletingBulk
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                          )
                        : const Icon(Icons.delete, size: 18),
                    label: Text(_isDeletingBulk ? 'Deleting...' : 'Delete Selected (${_selectedVpsTrackIds.length})'),
                    onPressed: (_isDeletingBulk || _selectedVpsTrackIds.isEmpty)
                        ? null
                        : () => _bulkDeleteVpsTracks(tracks),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.close, color: ZephyrColors.textDim),
                    tooltip: 'Cancel Selection',
                    onPressed: () {
                      setState(() {
                        _isSelectingVps = false;
                        _selectedVpsTrackIds.clear();
                      });
                    },
                  ),
                ] else ...[
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: ZephyrColors.text,
                      side: const BorderSide(color: ZephyrColors.bgLight),
                    ),
                    icon: const Icon(Icons.checklist, size: 18),
                    label: const Text('Manage / Delete'),
                    onPressed: () {
                      setState(() {
                        _isSelectingVps = true;
                        _selectedVpsTrackIds.clear();
                      });
                    },
                  ),
                ],
              ],
            ],
          ),
        ),
        const Divider(color: ZephyrColors.bgLight, height: 1),
        // List
        Expanded(
          child: tracks.isEmpty
              ? const Center(
                  child: Text(
                    'No offline songs yet. Search and download tracks.',
                    style: TextStyle(color: ZephyrColors.textDim),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  itemCount: tracks.length,
                  itemBuilder: (context, index) {
                    final track = tracks[index];
                    final isSelected = _selectedVpsTrackIds.contains(track.videoId);

                    if (_isSelectingVps) {
                      return InkWell(
                        onTap: () {
                          setState(() {
                            if (isSelected) {
                              _selectedVpsTrackIds.remove(track.videoId);
                            } else {
                              _selectedVpsTrackIds.add(track.videoId);
                            }
                          });
                        },
                        child: Row(
                          children: [
                            Checkbox(
                              activeColor: ZephyrColors.primary,
                              value: isSelected,
                              onChanged: (val) {
                                setState(() {
                                  if (val == true) {
                                    _selectedVpsTrackIds.add(track.videoId);
                                  } else {
                                    _selectedVpsTrackIds.remove(track.videoId);
                                  }
                                });
                              },
                            ),
                            Expanded(
                              child: IgnorePointer(
                                child: TrackTile(
                                  track: track,
                                  queue: tracks,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }

                    return TrackTile(
                      track: track,
                      queue: tracks,
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _CustomLibraryCard extends StatefulWidget {
  final String title;
  final Widget icon;
  final Color backgroundColor;
  final VoidCallback onTap;

  const _CustomLibraryCard({
    required this.title,
    required this.icon,
    required this.backgroundColor,
    required this.onTap,
  });

  @override
  State<_CustomLibraryCard> createState() => _CustomLibraryCardState();
}

class _CustomLibraryCardState extends State<_CustomLibraryCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          color: ZephyrColors.bgCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: _isHovered
                ? ZephyrColors.primary.withValues(alpha: 0.8)
                : ZephyrColors.bgLight.withValues(alpha: 0.4),
            width: _isHovered ? 1.5 : 1.0,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 6,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: AspectRatio(
                    aspectRatio: 1,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      decoration: BoxDecoration(
                        color: widget.backgroundColor,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Center(
                        child: widget.icon,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  widget.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: ZephyrColors.text,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Collection',
                  style: TextStyle(
                    fontSize: 11,
                    color: ZephyrColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
