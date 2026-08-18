import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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



  Widget _buildVpsSongsDetailView(LibraryState libraryState, NavigationNotifier navNotifier) {
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
                  if (navNotifier.canGoBack) {
                    navNotifier.navigateBack();
                  } else {
                    navNotifier.navigateTo(const ScreenState(type: ScreenType.library, intId: 1));
                  }
                },
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
