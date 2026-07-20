import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/auth_provider.dart';
import '../providers/library_provider.dart';
import '../providers/navigation_provider.dart';
import '../theme/colors.dart';
import '../widgets/playlist_card.dart';
import '../widgets/track_tile.dart';

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
      // Trigger a fresh API load so the list is always server-ordered
      Future.microtask(() => ref.read(libraryProvider.notifier).loadFavorites());
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
        return _buildFavoritesDetailView(libraryState);
      case LibraryView.vpsSongs:
        if (!authState.isAdmin) {
          return _buildLibraryGridView(libraryState, navNotifier);
        }
        return _buildVpsSongsDetailView(libraryState);
      case LibraryView.grid:
      default:
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
                  subtitle: '${libraryState.favorites.length} songs',
                  icon: const Icon(Icons.favorite, size: 54, color: ZephyrColors.primary),
                  backgroundColor: ZephyrColors.primary.withValues(alpha: 0.15),
                  onTap: () {
                    setState(() => _currentView = LibraryView.favorites);
                    // Fresh fetch every time user opens the favorites view
                    ref.read(libraryProvider.notifier).loadFavorites();
                  },
                );
              }
              
              if (isAdmin) {
                if (index == 1) {
                  // VPS Songs Card
                  return _CustomLibraryCard(
                    title: 'VPS Songs',
                    subtitle: '${libraryState.downloadedTracks.length} tracks',
                    icon: const Icon(Icons.library_music, size: 54, color: Colors.blue),
                    backgroundColor: Colors.blue.withValues(alpha: 0.15),
                    onTap: () => setState(() => _currentView = LibraryView.vpsSongs),
                  );
                } else {
                  // Playlist Cards
                  final playlist = libraryState.playlists[index - 2];
                  return PlaylistCard(
                    playlist: playlist,
                    onTap: () {
                      navNotifier.navigateTo(ScreenState(type: ScreenType.playlist, intId: playlist.id));
                    },
                  );
                }
              } else {
                // Playlist Cards
                final playlist = libraryState.playlists[index - 1];
                return PlaylistCard(
                  playlist: playlist,
                  onTap: () {
                    navNotifier.navigateTo(ScreenState(type: ScreenType.playlist, intId: playlist.id));
                  },
                );
              }
            },
          ),
        ),
      ],
    );
  }

  Widget _buildFavoritesDetailView(LibraryState libraryState) {
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
                onPressed: () => setState(() => _currentView = LibraryView.grid),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.favorite, color: ZephyrColors.primary, size: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Favorite Songs',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: ZephyrColors.text,
                      ),
                    ),
                    if (!libraryState.favoritesLoading && libraryState.favorites.isNotEmpty)
                      Text(
                        '${libraryState.favorites.length} songs',
                        style: const TextStyle(
                          fontSize: 12,
                          color: ZephyrColors.textDim,
                        ),
                      ),
                  ],
                ),
              ),
              if (libraryState.favoritesLoading)
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    color: ZephyrColors.primary,
                    strokeWidth: 2,
                  ),
                ),
            ],
          ),
        ),
        const Divider(color: ZephyrColors.bgLight, height: 1),
        // List
        Expanded(
          child: libraryState.favoritesLoading && libraryState.favorites.isEmpty
              ? const Center(
                  child: CircularProgressIndicator(color: ZephyrColors.primary),
                )
              : libraryState.favorites.isEmpty
                  ? const Center(
                      child: Text(
                        'No favorite songs yet. Tap the heart icon on any song to add it here.',
                        style: TextStyle(color: ZephyrColors.textDim),
                      ),
                    )
                  : ListView.builder(
                      controller: _favoritesScrollController,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      // +1 for the footer item (loading spinner or end-of-list label)
                      itemCount: libraryState.favorites.length + 1,
                      itemBuilder: (context, index) {
                        // Footer item
                        if (index == libraryState.favorites.length) {
                          if (libraryState.favoritesLoading) {
                            return const Padding(
                              padding: EdgeInsets.symmetric(vertical: 24),
                              child: Center(
                                child: SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                    color: ZephyrColors.primary,
                                    strokeWidth: 2,
                                  ),
                                ),
                              ),
                            );
                          }
                          if (!libraryState.hasMoreFavorites) {
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 24),
                              child: Center(
                                child: Text(
                                  '${libraryState.favorites.length} songs loaded',
                                  style: const TextStyle(
                                    color: ZephyrColors.textMuted,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            );
                          }
                          return const SizedBox.shrink();
                        }
                        final track = libraryState.favorites[index];
                        // ListView.builder only constructs visible items, so
                        // TrackTile (and its CoverImage) is only created — and
                        // the cover HTTP request only fired — when the row
                        // scrolls into view.
                        return RepaintBoundary(
                          child: TrackTile(
                            track: track,
                            queue: libraryState.favorites,
                          ),
                        );
                      },
                    ),
        ),
      ],
    );
  }

  Widget _buildVpsSongsDetailView(LibraryState libraryState) {
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
                onPressed: () => setState(() => _currentView = LibraryView.grid),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.library_music, color: Colors.blue, size: 24),
              const SizedBox(width: 12),
              const Text(
                'VPS Songs',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: ZephyrColors.text,
                ),
              ),
            ],
          ),
        ),
        const Divider(color: ZephyrColors.bgLight, height: 1),
        // List
        Expanded(
          child: libraryState.downloadedTracks.isEmpty
              ? const Center(
                  child: Text(
                    'No offline songs yet. Search and download tracks.',
                    style: TextStyle(color: ZephyrColors.textDim),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  itemCount: libraryState.downloadedTracks.length,
                  itemBuilder: (context, index) {
                    final track = libraryState.downloadedTracks[index];
                    return TrackTile(
                      track: track,
                      queue: libraryState.downloadedTracks,
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
  final String subtitle;
  final Widget icon;
  final Color backgroundColor;
  final VoidCallback onTap;

  const _CustomLibraryCard({
    required this.title,
    required this.subtitle,
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
          color: _isHovered ? ZephyrColors.bgLight.withValues(alpha: 0.3) : ZephyrColors.bgCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: _isHovered
                ? ZephyrColors.primary.withValues(alpha: 0.5)
                : ZephyrColors.bgLight.withValues(alpha: 0.5),
            width: 1,
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
                Text(
                  widget.subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    color: ZephyrColors.textDim,
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
