import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/models.dart';
import '../providers/auth_provider.dart';
import '../providers/library_provider.dart';
import '../providers/navigation_provider.dart';
import '../providers/player_provider.dart';
import '../providers/search_provider.dart';
import '../theme/colors.dart';
import '../widgets/cover_image.dart';
import '../widgets/seek_bar.dart';
import '../widgets/artist_links.dart';
import '../widgets/favorite_button.dart';
import '../widgets/toast.dart';
import '../widgets/player_song_context_menu.dart';
import '../widgets/devices_modal.dart';

// Screens
import 'home_screen.dart';
import 'search_screen.dart';
import 'library_screen.dart';
import 'settings_screen.dart';
import 'album_detail_screen.dart';
import 'artist_detail_screen.dart';
import 'playlist_detail_screen.dart';
import 'admin_screen.dart';
import 'import_screen.dart';
import 'favorites_screen.dart';
import 'player_screen.dart';
import 'queue_screen.dart';
import 'curator_screen.dart';
import 'statistics_screen.dart';

class MainLayout extends ConsumerStatefulWidget {
  const MainLayout({super.key});

  @override
  ConsumerState<MainLayout> createState() => _MainLayoutState();
}

class _MainLayoutState extends ConsumerState<MainLayout> {
  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handleGlobalKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleGlobalKey);
    super.dispose();
  }

  bool _handleGlobalKey(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    final key = event.logicalKey;

    if (key == LogicalKeyboardKey.mediaPlayPause ||
        key == LogicalKeyboardKey.mediaPlay ||
        key == LogicalKeyboardKey.mediaPause ||
        key == LogicalKeyboardKey.headsetHook) {
      ref.read(playerProvider.notifier).togglePlayPause();
      return true;
    }
    if (key == LogicalKeyboardKey.mediaTrackNext) {
      ref.read(playerProvider.notifier).playNext();
      return true;
    }
    if (key == LogicalKeyboardKey.mediaTrackPrevious) {
      ref.read(playerProvider.notifier).playPrevious();
      return true;
    }
    if (key == LogicalKeyboardKey.mediaStop) {
      ref.read(playerProvider.notifier).pause();
      return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final navState = ref.watch(navigationProvider);
    final navNotifier = ref.read(navigationProvider.notifier);
    final authState = ref.watch(authProvider);
    final libraryState = ref.watch(libraryProvider);
    final playerNotifier = ref.read(playerProvider.notifier);

    // Resolve main screen widget
    Widget currentScreenWidget;
    switch (navState.currentScreen.type) {
      case ScreenType.home:
        currentScreenWidget = const HomeScreen();
        break;
      case ScreenType.search:
        currentScreenWidget = const SearchScreen();
        break;
      case ScreenType.library:
        currentScreenWidget = LibraryScreen(
          initialTabIndex: navState.currentScreen.intId ?? 1,
        );
        break;
      case ScreenType.favorites:
        currentScreenWidget = const FavoritesScreen();
        break;
      case ScreenType.settings:
        currentScreenWidget = const SettingsScreen();
        break;
      case ScreenType.album:
        currentScreenWidget = AlbumDetailScreen(
          key: ValueKey('album_${navState.currentScreen.id}'),
          browseId: navState.currentScreen.id!,
        );
        break;
      case ScreenType.artist:
        currentScreenWidget = ArtistDetailScreen(
          key: ValueKey('artist_${navState.currentScreen.id}'),
          channelId: navState.currentScreen.id!,
        );
        break;
      case ScreenType.playlist:
        final pId = navState.currentScreen.id ??
            (navState.currentScreen.intId != null
                ? navState.currentScreen.intId.toString()
                : '');
        currentScreenWidget = PlaylistDetailScreen(
          key: ValueKey('playlist_$pId'),
          playlistId: pId,
        );
        break;
      case ScreenType.admin:
        currentScreenWidget = const AdminScreen();
        break;
      case ScreenType.import:
        currentScreenWidget = const ImportScreen();
        break;
      case ScreenType.lyrics:
        currentScreenWidget = const PlayerScreen(isInline: true);
        break;
      case ScreenType.queue:
        currentScreenWidget = const QueueScreen();
        break;
      case ScreenType.curator:
        currentScreenWidget = const CuratorScreen();
        break;
      case ScreenType.statistics:
        currentScreenWidget = const StatisticsScreen();
        break;
      default:
        currentScreenWidget = const HomeScreen();
    }

    return Focus(
      autofocus: true,
      onKeyEvent: (FocusNode node, KeyEvent event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;

        final key = event.logicalKey;

        // 1. Safety check: Ignore standard keyboard shortcuts if typing inside any text field or input control
        final primaryFocus = FocusManager.instance.primaryFocus;
        if (primaryFocus != null && primaryFocus.context != null) {
          final ctx = primaryFocus.context!;
          final isEditingText =
              ctx.widget is EditableText ||
              ctx.widget is TextField ||
              ctx.findAncestorWidgetOfExactType<EditableText>() != null ||
              ctx.findAncestorWidgetOfExactType<TextField>() != null;

          if (isEditingText) {
            return KeyEventResult.ignored;
          }
        }

        // 3. STANDARD KEYBOARD SHORTCUTS

        // Space -> Toggle Play / Pause
        if (key == LogicalKeyboardKey.space) {
          playerNotifier.togglePlayPause();
          return KeyEventResult.handled;
        }

        // Left Arrow -> Seek -5s
        if (key == LogicalKeyboardKey.arrowLeft) {
          playerNotifier.seekRelative(-5);
          return KeyEventResult.handled;
        }

        // Right Arrow -> Seek +5s
        if (key == LogicalKeyboardKey.arrowRight) {
          playerNotifier.seekRelative(5);
          return KeyEventResult.handled;
        }

        // Up Arrow -> Volume +10%
        if (key == LogicalKeyboardKey.arrowUp) {
          playerNotifier.adjustVolume(0.1);
          return KeyEventResult.handled;
        }

        // Down Arrow -> Volume -10%
        if (key == LogicalKeyboardKey.arrowDown) {
          playerNotifier.adjustVolume(-0.1);
          return KeyEventResult.handled;
        }

        // M key -> Toggle Mute
        if (key == LogicalKeyboardKey.keyM) {
          playerNotifier.toggleMute();
          return KeyEventResult.handled;
        }

        // S key -> Toggle Shuffle Mode
        if (key == LogicalKeyboardKey.keyS) {
          playerNotifier.toggleShuffle();
          return KeyEventResult.handled;
        }

        // R key -> Toggle Repeat Mode
        if (key == LogicalKeyboardKey.keyR) {
          playerNotifier.toggleQueueMode();
          return KeyEventResult.handled;
        }

        // L key -> Toggle Like / Favorite for current track
        if (key == LogicalKeyboardKey.keyL) {
          final curTrack = ref.read(playerProvider).currentTrack;
          if (curTrack != null) {
            ref
                .read(libraryProvider.notifier)
                .toggleFavorite(curTrack);
          }
          return KeyEventResult.handled;
        }

        // F key -> Toggle Lyrics & Full Player View
        if (key == LogicalKeyboardKey.keyF) {
          if (navState.currentScreen.type == ScreenType.lyrics) {
            navNotifier.navigateBack();
          } else {
            navNotifier.navigateTo(const ScreenState(type: ScreenType.lyrics));
          }
          return KeyEventResult.handled;
        }

        return KeyEventResult.ignored;
      },
      child: Builder(
        builder: (context) {
          final isMobile = MediaQuery.of(context).size.width < 700;

          int getMobileNavIndex(ScreenType type) {
            switch (type) {
              case ScreenType.home:
                return 0;
              case ScreenType.search:
                return 1;
              case ScreenType.library:
              case ScreenType.playlist:
              case ScreenType.favorites:
                return 2;
              case ScreenType.statistics:
                return 3;
              default:
                return 0;
            }
          }

          SystemChrome.setEnabledSystemUIMode(
            SystemUiMode.manual,
            overlays: [SystemUiOverlay.top, SystemUiOverlay.bottom],
          );
          SystemChrome.setSystemUIOverlayStyle(
            const SystemUiOverlayStyle(
              statusBarColor: Colors.transparent,
              statusBarIconBrightness: Brightness.light,
            ),
          );

          return PopScope(
            canPop: false,
            onPopInvokedWithResult: (didPop, result) {
              if (didPop) return;
              if (navNotifier.canGoBack) {
                navNotifier.navigateBack();
              } else if (navState.currentScreen.type != ScreenType.home) {
                navNotifier.navigateTo(
                  const ScreenState(type: ScreenType.home),
                );
              } else {
                SystemNavigator.pop();
              }
            },
            child: Scaffold(
              backgroundColor: ZephyrColors.bgDark,
              bottomNavigationBar: isMobile
                  ? BottomNavigationBar(
                      currentIndex: getMobileNavIndex(
                        navState.currentScreen.type,
                      ),
                      backgroundColor: ZephyrColors.bgCard,
                      selectedItemColor: ZephyrColors.primary,
                      unselectedItemColor: ZephyrColors.textMuted,
                      type: BottomNavigationBarType.fixed,
                      onTap: (index) {
                        switch (index) {
                          case 0:
                            navNotifier.navigateTo(
                              const ScreenState(type: ScreenType.home),
                            );
                            break;
                          case 1:
                            navNotifier.navigateTo(
                              const ScreenState(type: ScreenType.search),
                            );
                            break;
                          case 2:
                            navNotifier.navigateTo(
                              const ScreenState(type: ScreenType.library),
                            );
                            break;
                          case 3:
                            navNotifier.navigateTo(
                              const ScreenState(type: ScreenType.statistics),
                            );
                            break;
                        }
                      },
                      items: const [
                        BottomNavigationBarItem(
                          icon: Icon(Icons.home_outlined),
                          activeIcon: Icon(Icons.home),
                          label: 'Home',
                        ),
                        BottomNavigationBarItem(
                          icon: Icon(Icons.search_outlined),
                          activeIcon: Icon(Icons.search),
                          label: 'Search',
                        ),
                        BottomNavigationBarItem(
                          icon: Icon(Icons.library_music_outlined),
                          activeIcon: Icon(Icons.library_music),
                          label: 'Library',
                        ),
                        BottomNavigationBarItem(
                          icon: Icon(Icons.insights_outlined),
                          activeIcon: Icon(Icons.insights),
                          label: 'Insight',
                        ),
                      ],
                    )
                  : null,
              body: Column(
                children: [
                  // Split Pane: Sidebar + Main Content Column
                  Expanded(
                    child: Row(
                      children: [
                        // Desktop Sidebar
                        if (!isMobile) ...[
                          _buildSidebar(
                            context,
                            ref,
                            navState,
                            authState,
                            libraryState,
                          ),
                          Container(width: 1, color: ZephyrColors.bgLight),
                        ],

                        // Main content column (TopBar + Page Content)
                        Expanded(
                          child: Column(
                            children: [
                              // Top Navigation & Search Bar
                              _buildTopBar(
                                context,
                                ref,
                                navNotifier,
                                navState,
                                authState,
                              ),

                              // Sub-header divider
                              if (!isMobile)
                                Container(
                                  height: 1,
                                  color: ZephyrColors.bgLight.withValues(
                                    alpha: 0.4,
                                  ),
                                ),

                              // Main Content View
                              Expanded(
                                child: ClipRect(
                                  child: Builder(
                                    builder: (context) {
                                      final mediaQueryData = MediaQuery.of(
                                        context,
                                      );
                                      final width = mediaQueryData.size.width;
                                      final scale = isMobile
                                          ? 1.0
                                          : (0.95 + (width - 1100) * 0.00034)
                                                .clamp(0.95, 1.45);
                                      return MediaQuery(
                                        data: mediaQueryData.copyWith(
                                          textScaler: TextScaler.linear(scale),
                                        ),
                                        child: currentScreenWidget,
                                      );
                                    },
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Horizontal divider above player
                  Container(height: 1, color: ZephyrColors.bgLight),

                  // Bottom Player Bar
                  _PlayerBarWidget(parentState: this),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSidebar(
    BuildContext context,
    WidgetRef ref,
    NavigationState navState,
    AuthState authState,
    LibraryState libraryState,
  ) {
    final navNotifier = ref.read(navigationProvider.notifier);

    return Container(
      width: 240,
      color: ZephyrColors.bgDark,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Zephyr Logo Header
          Padding(
            padding: const EdgeInsets.only(
              left: 24,
              top: 24,
              bottom: 20,
              right: 24,
            ),
            child: Row(
              children: [
                Image.asset(
                  'References/Zephyr_trasp.png',
                  width: 36,
                  height: 36,
                  errorBuilder: (context, error, stackTrace) => const Icon(
                    Icons.music_note,
                    color: ZephyrColors.primary,
                    size: 36,
                  ),
                ),
                const SizedBox(width: 12),
                const Text(
                  'Zephyr',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: ZephyrColors.text,
                  ),
                ),
              ],
            ),
          ),

          // Navigation Links
          _buildSidebarNavItem(
            icon: Icons.home_filled,
            label: 'Home',
            isSelected: navState.currentScreen.type == ScreenType.home,
            onTap: () => navNotifier.navigateTo(
              const ScreenState(type: ScreenType.home),
            ),
          ),
          _buildSidebarNavItem(
            icon: Icons.library_music,
            label: 'Library',
            isSelected: navState.currentScreen.type == ScreenType.library,
            onTap: () => navNotifier.navigateTo(
              const ScreenState(type: ScreenType.library, intId: 1),
            ),
          ),
          _buildSidebarNavItem(
            icon: Icons.favorite,
            label: 'Favorite Songs',
            isSelected: navState.currentScreen.type == ScreenType.favorites,
            onTap: () => navNotifier.navigateTo(
              const ScreenState(type: ScreenType.favorites),
            ),
          ),
          _buildSidebarNavItem(
            icon: Icons.analytics_outlined,
            label: 'Listening Insights',
            isSelected: navState.currentScreen.type == ScreenType.statistics,
            onTap: () => navNotifier.navigateTo(
              const ScreenState(type: ScreenType.statistics),
            ),
          ),

          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 24, vertical: 8),
            child: Divider(color: ZephyrColors.bgLight, height: 1),
          ),

          // Playlist Header + Create Button
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'RECENT PLAYLISTS',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                    color: ZephyrColors.textDim,
                  ),
                ),
                IconButton(
                  icon: const Icon(
                    Icons.add,
                    size: 18,
                    color: ZephyrColors.textDim,
                  ),
                  hoverColor: Colors.transparent,
                  onPressed: () => _showCreatePlaylistDialog(context, ref),
                ),
              ],
            ),
          ),

          // Playlists List (Top 4 Recent Playlists + See All Affordance)
          Expanded(
            child: libraryState.playlists.isEmpty
                ? const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    child: Text(
                      'No playlists yet.',
                      style: TextStyle(
                        color: ZephyrColors.textMuted,
                        fontSize: 13,
                      ),
                    ),
                  )
                : Builder(
                    builder: (context) {
                      final recentPlaylists = libraryState.playlists
                          .take(4)
                          .toList();
                      final hasMore = libraryState.playlists.length > 4;

                      return ListView(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        children: [
                          for (final playlist in recentPlaylists) ...[
                            Builder(
                              builder: (context) {
                                final isSelected =
                                    navState.currentScreen.type ==
                                        ScreenType.playlist &&
                                    (navState.currentScreen.intId ==
                                            playlist.id ||
                                        navState.currentScreen.id ==
                                            playlist.id.toString());
                                return _SidebarPlaylistItem(
                                  playlist: playlist,
                                  isSelected: isSelected,
                                  onTap: () {
                                    navNotifier.navigateTo(
                                      ScreenState(
                                        type: ScreenType.playlist,
                                        id: playlist.id.toString(),
                                        intId: playlist.id is int
                                            ? playlist.id as int
                                            : int.tryParse(
                                                playlist.id.toString(),
                                              ),
                                      ),
                                    );
                                  },
                                );
                              },
                            ),
                          ],
                          if (hasMore)
                            _SidebarSeeAllItem(
                              onTap: () => navNotifier.navigateTo(
                                const ScreenState(
                                  type: ScreenType.library,
                                  intId: 1,
                                ),
                              ),
                            ),
                        ],
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildSidebarNavItem({
    required IconData icon,
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return _SidebarNavItem(
      icon: icon,
      label: label,
      isSelected: isSelected,
      onTap: onTap,
    );
  }

  Widget _buildTopBar(
    BuildContext context,
    WidgetRef ref,
    NavigationNotifier navNotifier,
    NavigationState navState,
    AuthState authState,
  ) {
    Widget buildCircleArrowButton(
      IconData icon,
      bool enabled,
      VoidCallback? onTap,
    ) {
      return Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.35),
          shape: BoxShape.circle,
        ),
        child: IconButton(
          icon: Icon(icon, size: 16),
          color: enabled ? ZephyrColors.text : ZephyrColors.textMuted,
          padding: EdgeInsets.zero,
          splashRadius: 16,
          onPressed: enabled ? onTap : null,
        ),
      );
    }

    final isMobile = MediaQuery.of(context).size.width < 700;

    final topInset = MediaQuery.of(context).padding.top;

    return Container(
      height: isMobile ? (56 + topInset) : 60,
      color: ZephyrColors.bgDark,
      padding: EdgeInsets.only(
        left: isMobile ? 12 : 32,
        right: isMobile ? 12 : 32,
        top: isMobile ? topInset : 0,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (isMobile) ...[
            const Row(
              children: [
                Icon(Icons.graphic_eq, color: ZephyrColors.primary, size: 24),
                SizedBox(width: 8),
                Text(
                  'ZEPHYR',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.8,
                    color: ZephyrColors.text,
                  ),
                ),
              ],
            ),
            const Spacer(),
          ] else ...[
            buildCircleArrowButton(
              Icons.chevron_left,
              navNotifier.canGoBack,
              navNotifier.canGoBack ? () => navNotifier.navigateBack() : null,
            ),
            const SizedBox(width: 8),
            buildCircleArrowButton(
              Icons.chevron_right,
              navNotifier.canGoForward,
              navNotifier.canGoForward
                  ? () => navNotifier.navigateForward()
                  : null,
            ),
            const SizedBox(width: 16),

            // Search Bar (Desktop)
            const Expanded(child: _TopSearchBar()),
            const SizedBox(width: 8),
          ],

          // Right: User Profile Avatar dropdown menu
          PopupMenuButton<String>(
            offset: const Offset(0, 42),
            color: ZephyrColors.bgCard,
            onSelected: (value) {
              if (value == 'settings') {
                navNotifier.navigateTo(
                  const ScreenState(type: ScreenType.settings),
                );
              } else if (value == 'admin') {
                navNotifier.navigateTo(
                  const ScreenState(type: ScreenType.admin),
                );
              } else if (value == 'curator') {
                navNotifier.navigateTo(
                  const ScreenState(type: ScreenType.curator),
                );
              } else if (value == 'import') {
                navNotifier.navigateTo(
                  const ScreenState(type: ScreenType.import),
                );
              } else if (value == 'logout') {
                ref.read(authProvider.notifier).logout();
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'settings',
                child: Row(
                  children: [
                    Icon(Icons.settings, size: 16, color: ZephyrColors.textDim),
                    SizedBox(width: 8),
                    Text('Settings'),
                  ],
                ),
              ),
              if (authState.isAdmin)
                const PopupMenuItem(
                  value: 'admin',
                  child: Row(
                    children: [
                      Icon(
                        Icons.admin_panel_settings,
                        size: 16,
                        color: ZephyrColors.textDim,
                      ),
                      SizedBox(width: 8),
                      Text('Admin Panel'),
                    ],
                  ),
                ),
              if (authState.isCurator)
                const PopupMenuItem(
                  value: 'curator',
                  child: Row(
                    children: [
                      Icon(Icons.brush, size: 16, color: ZephyrColors.textDim),
                      SizedBox(width: 8),
                      Text('Curator Panel'),
                    ],
                  ),
                ),
              const PopupMenuItem(
                value: 'import',
                child: Row(
                  children: [
                    Icon(
                      Icons.upload_file,
                      size: 16,
                      color: ZephyrColors.textDim,
                    ),
                    SizedBox(width: 8),
                    Text('CSV Import'),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'logout',
                child: Row(
                  children: [
                    Icon(Icons.logout, size: 16, color: ZephyrColors.error),
                    SizedBox(width: 8),
                    Text('Logout', style: TextStyle(color: ZephyrColors.error)),
                  ],
                ),
              ),
            ],
            child: Container(
              height: 36,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.person,
                    size: 18,
                    color: ZephyrColors.primary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    authState.username ?? 'User',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: ZephyrColors.text,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlayerBar(
    BuildContext context,
    WidgetRef ref,
    ZephyrPlayerState state,
    PlayerNotifier notifier,
  ) {
    final isMobile = MediaQuery.of(context).size.width < 700;

    if (state.currentTrack == null) {
      return Container(
        height: isMobile ? 50 : 90,
        color: ZephyrColors.bgCard,
        alignment: Alignment.center,
        child: Text(
          'Select a track to start listening',
          style: TextStyle(
            color: ZephyrColors.textDim,
            fontSize: isMobile ? 12 : 14,
          ),
        ),
      );
    }

    final track = state.currentTrack!;
    final ownerName = state.activeDeviceName?.trim();
    final showRemoteOwner =
        !state.isPlayerDevice && ownerName != null && ownerName.isNotEmpty;
    ref.watch(libraryProvider);
    final libraryNotifier = ref.read(libraryProvider.notifier);
    final isFav = libraryNotifier.isFavorite(track.videoId, title: track.title, artists: track.artists);
    final navState = ref.watch(navigationProvider);
    final navNotifier = ref.read(navigationProvider.notifier);

    if (isMobile) {
      final double progress = state.effectiveDuration.inMilliseconds > 0
          ? (state.position.inMilliseconds /
                    state.effectiveDuration.inMilliseconds)
                .clamp(0.0, 1.0)
          : 0.0;

      final mobileBar = Container(
        color: ZephyrColors.bgCard,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            LayoutBuilder(
              builder: (ctx, constraints) {
                final width = constraints.maxWidth;
                final thumbX = (width * progress).clamp(0.0, width);

                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapDown: (details) {
                    if (width > 0 && state.effectiveDuration > Duration.zero) {
                      final frac = (details.localPosition.dx / width).clamp(
                        0.0,
                        1.0,
                      );
                      notifier.seek(state.effectiveDuration * frac);
                    }
                  },
                  onHorizontalDragUpdate: (details) {
                    if (width > 0 && state.effectiveDuration > Duration.zero) {
                      final frac = (details.localPosition.dx / width).clamp(
                        0.0,
                        1.0,
                      );
                      notifier.seek(state.effectiveDuration * frac);
                    }
                  },
                  child: Container(
                    height: 14,
                    color: Colors.transparent,
                    child: Stack(
                      alignment: Alignment.centerLeft,
                      children: [
                        // Background Track
                        Container(
                          height: 3,
                          width: double.infinity,
                          color: ZephyrColors.bgLight,
                        ),
                        // Active Progress Fill
                        FractionallySizedBox(
                          widthFactor: progress,
                          child: Container(
                            height: 3,
                            color: ZephyrColors.primary,
                          ),
                        ),
                        // Draggable Solid Amber Thumb Circle
                        Positioned(
                          left: (thumbX - 6).clamp(
                            0.0,
                            width > 12 ? width - 12 : 0.0,
                          ),
                          child: Container(
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(
                              color: ZephyrColors.primary,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: ZephyrColors.primary.withValues(
                                    alpha: 0.5,
                                  ),
                                  blurRadius: 4,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
            InkWell(
              onTap: () {
                if (navState.currentScreen.type == ScreenType.lyrics) {
                  navNotifier.navigateBack();
                } else {
                  navNotifier.navigateTo(
                    const ScreenState(type: ScreenType.lyrics),
                  );
                }
              },
              child: Container(
                height: 64,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    CoverImage(
                      videoId: track.videoId,
                      coverUrl: track.coverUrl,
                      size: 44,
                      borderRadius: 6,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            track.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: ZephyrColors.text,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              if (showRemoteOwner) ...[
                                const Icon(
                                  Icons.speaker_rounded,
                                  size: 12,
                                  color: ZephyrColors.primary,
                                ),
                                const SizedBox(width: 3),
                                Flexible(
                                  child: Tooltip(
                                    message: 'Playing on $ownerName',
                                    child: Text(
                                      ownerName,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: ZephyrColors.primary,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 4),
                                const Text(
                                  '•',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: ZephyrColors.textDim,
                                  ),
                                ),
                                const SizedBox(width: 4),
                              ],
                              Flexible(
                                child: Text(
                                  track.artists.join(', '),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: ZephyrColors.textDim,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    FavoriteButton(
                      isFavorite: isFav,
                      size: 20,
                      onTap: () => libraryNotifier.toggleFavorite(track),
                    ),
                    IconButton(
                      icon: Icon(
                        Icons.devices_rounded,
                        color: !state.isPlayerDevice
                            ? ZephyrColors.primary
                            : ZephyrColors.textDim,
                        size: 22,
                      ),
                      tooltip: 'Connect to a device',
                      onPressed: () => DevicesModal.show(context),
                    ),
                    if (state.isLoading)
                      const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            ZephyrColors.primary,
                          ),
                        ),
                      )
                    else
                      IconButton(
                        icon: Icon(
                          state.isPlaying ? Icons.pause : Icons.play_arrow,
                          color: ZephyrColors.text,
                          size: 28,
                        ),
                        onPressed: () => notifier.togglePlayPause(),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );

      return Dismissible(
        key: ValueKey('mobile_bar_${track.videoId}'),
        direction: DismissDirection.horizontal,
        confirmDismiss: (direction) async {
          if (direction == DismissDirection.endToStart) {
            notifier.playNext();
            HapticFeedback.lightImpact();
          } else if (direction == DismissDirection.startToEnd) {
            notifier.playPrevious();
            HapticFeedback.lightImpact();
          }
          return false;
        },
        background: Container(
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.only(left: 20),
          color: ZephyrColors.bgCard,
          child: const Icon(
            Icons.skip_previous,
            color: ZephyrColors.primary,
            size: 24,
          ),
        ),
        secondaryBackground: Container(
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 20),
          color: ZephyrColors.bgCard,
          child: const Icon(
            Icons.skip_next,
            color: ZephyrColors.primary,
            size: 24,
          ),
        ),
        child: mobileBar,
      );
    }

    return Container(
      height: 84,
      color: ZephyrColors.bgCard,
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Left: Cover + Metadata + Like Button (Anchored fixed width!)
          SizedBox(
            width: 280,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                InkWell(
                  onTap: () {
                    if (navState.currentScreen.type == ScreenType.lyrics) {
                      navNotifier.navigateBack();
                    } else {
                      navNotifier.navigateTo(
                        const ScreenState(type: ScreenType.lyrics),
                      );
                    }
                  },
                  borderRadius: BorderRadius.circular(6),
                  child: CoverImage(
                    videoId: track.videoId,
                    coverUrl: track.coverUrl,
                    size: 56,
                    borderRadius: 6,
                  ),
                ),
                const SizedBox(width: 12),
                Flexible(
                  child: GestureDetector(
                    onSecondaryTapDown: (details) {
                      showPlayerSongContextMenu(
                        context,
                        ref,
                        track,
                        details.globalPosition,
                      );
                    },
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        InkWell(
                          onTap: () {
                            if (navState.currentScreen.type ==
                                ScreenType.lyrics) {
                              navNotifier.navigateBack();
                            } else {
                              navNotifier.navigateTo(
                                const ScreenState(type: ScreenType.lyrics),
                              );
                            }
                          },
                          child: Text(
                            track.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: ZephyrColors.text,
                            ),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Flexible(
                              child: ArtistLinks(
                                track: track,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: ZephyrColors.textDim,
                                ),
                              ),
                            ),
                            if (showRemoteOwner) ...[
                              const SizedBox(width: 6),
                              Flexible(
                                child: Tooltip(
                                  message: 'Playing on $ownerName',
                                  child: Text(
                                    'Playing on $ownerName',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: ZephyrColors.primary,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                FavoriteButton(
                  isFavorite: isFav,
                  size: 20,
                  onTap: () => libraryNotifier.toggleFavorite(track),
                ),
              ],
            ),
          ),

          // Center: Player Controls + Seek Bar
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Control Buttons
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      icon: Icon(
                        Icons.shuffle,
                        color: state.isShuffled
                            ? ZephyrColors.primary
                            : ZephyrColors.textDim,
                        size: 20,
                      ),
                      onPressed: () => notifier.toggleShuffle(),
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.skip_previous,
                        color: ZephyrColors.text,
                        size: 24,
                      ),
                      onPressed: () => notifier.playPrevious(),
                    ),
                    const SizedBox(width: 8),
                    if (state.isLoading)
                      const SizedBox(
                        width: 32,
                        height: 32,
                        child: CircularProgressIndicator(
                          strokeWidth: 3,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            ZephyrColors.primary,
                          ),
                        ),
                      )
                    else
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          shape: const CircleBorder(),
                          padding: const EdgeInsets.all(12),
                          backgroundColor: ZephyrColors.text,
                          foregroundColor: ZephyrColors.bgDark,
                        ),
                        onPressed: () => notifier.togglePlayPause(),
                        child: Icon(
                          state.isPlaying ? Icons.pause : Icons.play_arrow,
                          size: 26,
                        ),
                      ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(
                        Icons.skip_next,
                        color: ZephyrColors.text,
                        size: 24,
                      ),
                      onPressed: () => notifier.playNext(),
                    ),
                    IconButton(
                      icon: Icon(
                        state.queueMode == 'repeat_one'
                            ? Icons.repeat_one
                            : Icons.repeat,
                        color: state.queueMode != 'normal'
                            ? ZephyrColors.primary
                            : ZephyrColors.textDim,
                        size: 20,
                      ),
                      onPressed: () => notifier.toggleQueueMode(),
                    ),
                  ],
                ),

                // Seek Bar Slider
                SizedBox(
                  width: 500,
                  child: SeekBar(
                    position: state.position,
                    duration: state.effectiveDuration,
                    isLoading: state.isLoading,
                    onChangeEnd: (duration) {
                      notifier.seek(duration);
                    },
                  ),
                ),
              ],
            ),
          ),

          // Right: Lyrics Button + Volume Control (Anchored fixed width to balance left pane!)
          SizedBox(
            width: 300,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                IconButton(
                  padding: const EdgeInsets.all(6),
                  constraints: const BoxConstraints(),
                  icon: Icon(
                    Icons.devices,
                    color: !state.isPlayerDevice
                        ? ZephyrColors.primary
                        : ZephyrColors.textDim,
                    size: 20,
                  ),
                  tooltip: 'Connect to a device',
                  onPressed: () => DevicesModal.show(context),
                ),
                const SizedBox(width: 8),
                IconButton(
                  padding: const EdgeInsets.all(6),
                  constraints: const BoxConstraints(),
                  icon: Icon(
                    Icons.queue_music,
                    color: navState.currentScreen.type == ScreenType.queue
                        ? ZephyrColors.primary
                        : ZephyrColors.textDim,
                    size: 20,
                  ),
                  tooltip: 'Play Queue',
                  onPressed: () {
                    if (navState.currentScreen.type == ScreenType.queue) {
                      navNotifier.navigateBack();
                    } else {
                      navNotifier.navigateTo(
                        const ScreenState(type: ScreenType.queue),
                      );
                    }
                  },
                ),
                const SizedBox(width: 12),
                IconButton(
                  padding: const EdgeInsets.all(6),
                  constraints: const BoxConstraints(),
                  icon: Icon(
                    Icons.mic,
                    color: navState.currentScreen.type == ScreenType.lyrics
                        ? ZephyrColors.primary
                        : ZephyrColors.textDim,
                    size: 20,
                  ),
                  tooltip: 'View Lyrics & Related',
                  onPressed: () {
                    if (navState.currentScreen.type == ScreenType.lyrics) {
                      navNotifier.navigateBack();
                    } else {
                      navNotifier.navigateTo(
                        const ScreenState(type: ScreenType.lyrics),
                      );
                    }
                  },
                ),
                const SizedBox(width: 12),
                IconButton(
                  padding: const EdgeInsets.all(6),
                  constraints: const BoxConstraints(),
                  icon: Icon(
                    state.volume == 0
                        ? Icons.volume_off
                        : (state.volume < 0.5
                              ? Icons.volume_down
                              : Icons.volume_up),
                    color: state.volume == 0
                        ? ZephyrColors.error
                        : ZephyrColors.textDim,
                    size: 20,
                  ),
                  tooltip: state.volume == 0 ? 'Unmute' : 'Mute',
                  onPressed: () => notifier.toggleMute(),
                ),
                const SizedBox(width: 10),
                // Volume slider
                const _VolumeSlider(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showCreatePlaylistDialog(BuildContext context, WidgetRef ref) {
    final nameController = TextEditingController();
    final descController = TextEditingController();
    bool isPublic = false;
    File? coverFile;
    bool isCoverHovered = false;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              backgroundColor: ZephyrColors.bgCard,
              title: const Text('Create Playlist'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Center(
                      child: GestureDetector(
                        onTap: () async {
                          try {
                            final result = await FilePicker.platform.pickFiles(
                              type: FileType.image,
                              allowMultiple: false,
                            );
                            if (result != null &&
                                result.files.single.path != null) {
                              setState(() {
                                coverFile = File(result.files.single.path!);
                              });
                            }
                          } catch (e) {
                            if (context.mounted)
                              ZephyrToast.show(
                                context,
                                'Error picking cover: $e',
                                isError: true,
                              );
                          }
                        },
                        child: MouseRegion(
                          cursor: SystemMouseCursors.click,
                          onEnter: (_) => setState(() => isCoverHovered = true),
                          onExit: (_) => setState(() => isCoverHovered = false),
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              Container(
                                width: 140,
                                height: 140,
                                decoration: BoxDecoration(
                                  color: ZephyrColors.bgLight,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: ZephyrColors.primary.withValues(
                                      alpha: 0.3,
                                    ),
                                    width: 1.5,
                                  ),
                                  image: coverFile != null
                                      ? DecorationImage(
                                          image: FileImage(coverFile!),
                                          fit: BoxFit.cover,
                                        )
                                      : null,
                                ),
                                child: coverFile == null
                                    ? const Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Icon(
                                            Icons.image,
                                            color: ZephyrColors.textDim,
                                            size: 36,
                                          ),
                                          SizedBox(height: 6),
                                          Text(
                                            'Upload Cover',
                                            style: TextStyle(
                                              color: ZephyrColors.textDim,
                                              fontSize: 12,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                          SizedBox(height: 2),
                                          Text(
                                            '(Optional)',
                                            style: TextStyle(
                                              color: ZephyrColors.textMuted,
                                              fontSize: 10,
                                            ),
                                          ),
                                        ],
                                      )
                                    : null,
                              ),
                              if (coverFile != null && isCoverHovered)
                                Container(
                                  width: 140,
                                  height: 140,
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.4),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Icon(
                                    Icons.camera_alt,
                                    color: Colors.white,
                                    size: 32,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: nameController,
                      decoration: const InputDecoration(
                        labelText: 'Playlist Name',
                        labelStyle: TextStyle(color: ZephyrColors.textDim),
                        focusedBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: ZephyrColors.primary),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: descController,
                      decoration: const InputDecoration(
                        labelText: 'Description (Optional)',
                        labelStyle: TextStyle(color: ZephyrColors.textDim),
                        focusedBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: ZephyrColors.primary),
                        ),
                      ),
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
                        const Text('Make Public'),
                      ],
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text(
                    'Cancel',
                    style: TextStyle(color: ZephyrColors.textDim),
                  ),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: ZephyrColors.primary,
                  ),
                  onPressed: () async {
                    if (nameController.text.trim().isEmpty) return;
                    Navigator.of(context).pop();
                    await ref
                        .read(libraryProvider.notifier)
                        .createPlaylist(
                          nameController.text.trim(),
                          descController.text.trim(),
                          isPublic,
                          coverImage: coverFile,
                        );
                  },
                  child: const Text(
                    'Create',
                    style: TextStyle(color: Colors.black),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

class CompactSliderTrackShape extends RoundedRectSliderTrackShape {
  const CompactSliderTrackShape();

  @override
  Rect getPreferredRect({
    required RenderBox parentBox,
    Offset offset = Offset.zero,
    required SliderThemeData sliderTheme,
    bool isEnabled = false,
    bool isDiscrete = false,
  }) {
    final double trackHeight = sliderTheme.trackHeight ?? 3.0;
    // Keep the painted track aligned with the thumb's actual travel range.
    // Painting from the parent-box edges makes the visual value look offset
    // near 0 and 1 even though Slider's numeric value is correct.
    final double thumbRadius =
        (sliderTheme.thumbShape
                ?.getPreferredSize(isEnabled, isDiscrete)
                .width ??
            10.0) /
        2;
    final double trackLeft = offset.dx + thumbRadius;
    final double trackTop =
        offset.dy + (parentBox.size.height - trackHeight) / 2;
    final double trackWidth = (parentBox.size.width - (thumbRadius * 2)).clamp(
      0.0,
      double.infinity,
    );
    return Rect.fromLTWH(trackLeft, trackTop, trackWidth, trackHeight);
  }
}

// Small helper widget for volume slider
class _VolumeSlider extends ConsumerWidget {
  const _VolumeSlider();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playerState = ref.watch(playerProvider);
    final playerNotifier = ref.read(playerProvider.notifier);

    return SizedBox(
      width: 100,
      child: SliderTheme(
        data: const SliderThemeData(
          trackHeight: 3,
          trackShape: CompactSliderTrackShape(),
          thumbShape: RoundSliderThumbShape(
            enabledThumbRadius: 5,
            pressedElevation: 0,
          ),
          overlayShape: RoundSliderOverlayShape(overlayRadius: 0),
          activeTrackColor: ZephyrColors.primary,
          inactiveTrackColor: ZephyrColors.bgLight,
          thumbColor: ZephyrColors.primary,
        ),
        child: Slider(
          value: playerState.volume,
          min: 0.0,
          max: 1.0,
          onChanged: (val) {
            playerNotifier.setVolume(val);
          },
        ),
      ),
    );
  }
}

class _SidebarNavItem extends StatefulWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _SidebarNavItem({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  State<_SidebarNavItem> createState() => _SidebarNavItemState();
}

class _SidebarNavItemState extends State<_SidebarNavItem> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(4),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: widget.isSelected
                  ? ZephyrColors.bgLight
                  : (_isHovered
                        ? ZephyrColors.bgLight.withValues(alpha: 0.4)
                        : Colors.transparent),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              children: [
                Icon(
                  widget.icon,
                  color: widget.isSelected
                      ? ZephyrColors.primary
                      : (_isHovered ? ZephyrColors.text : ZephyrColors.textDim),
                  size: 20,
                ),
                const SizedBox(width: 16),
                Text(
                  widget.label,
                  style: TextStyle(
                    color: widget.isSelected
                        ? ZephyrColors.text
                        : (_isHovered
                              ? ZephyrColors.text
                              : ZephyrColors.textDim),
                    fontSize: 14,
                    fontWeight: widget.isSelected
                        ? FontWeight.bold
                        : FontWeight.w500,
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

class _SidebarPlaylistItem extends ConsumerStatefulWidget {
  final Playlist playlist;
  final bool isSelected;
  final VoidCallback onTap;

  const _SidebarPlaylistItem({
    required this.playlist,
    required this.isSelected,
    required this.onTap,
  });

  @override
  ConsumerState<_SidebarPlaylistItem> createState() =>
      _SidebarPlaylistItemState();
}

class _SidebarPlaylistItemState extends ConsumerState<_SidebarPlaylistItem> {
  bool _isHovered = false;

  void _showContextMenu(BuildContext context, Offset position) async {
    final selected = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx + 1,
        position.dy + 1,
      ),
      color: ZephyrColors.bgCard,
      elevation: 8,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: ZephyrColors.bgLight.withValues(alpha: 0.5)),
      ),
      items: [
        const PopupMenuItem<String>(
          value: 'open',
          child: Row(
            children: [
              Icon(Icons.playlist_play, size: 18, color: ZephyrColors.textDim),
              SizedBox(width: 10),
              Text(
                'Open Playlist',
                style: TextStyle(color: ZephyrColors.text, fontSize: 13),
              ),
            ],
          ),
        ),
        if (widget.playlist.isOwner)
          const PopupMenuItem<String>(
            value: 'edit',
            child: Row(
              children: [
                Icon(Icons.edit_outlined, size: 18, color: ZephyrColors.textDim),
                SizedBox(width: 10),
                Text(
                  'Edit Playlist',
                  style: TextStyle(color: ZephyrColors.text, fontSize: 13),
                ),
              ],
            ),
          ),
        if (widget.playlist.isOwner)
          const PopupMenuItem<String>(
            value: 'delete',
            child: Row(
              children: [
                Icon(Icons.delete_outline, size: 18, color: ZephyrColors.error),
                SizedBox(width: 10),
                Text(
                  'Delete Playlist',
                  style: TextStyle(color: ZephyrColors.error, fontSize: 13),
                ),
              ],
            ),
          ),
      ],
    );

    if (!mounted || selected == null) return;

    if (selected == 'open') {
      widget.onTap();
    } else if (selected == 'edit') {
      _showEditDialog(context);
    } else if (selected == 'delete') {
      _confirmDelete(context);
    }
  }

  void _showEditDialog(BuildContext context) {
    final nameController = TextEditingController(text: widget.playlist.name);
    final descController = TextEditingController(text: widget.playlist.description ?? '');
    bool isPublic = widget.playlist.isPublic;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
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
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel', style: TextStyle(color: ZephyrColors.textDim)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: ZephyrColors.primary),
              onPressed: () async {
                Navigator.of(ctx).pop();
                await ref.read(libraryProvider.notifier).updatePlaylist(
                      widget.playlist.id,
                      name: nameController.text.trim(),
                      description: descController.text.trim(),
                      isPublic: isPublic,
                    );
                if (context.mounted) {
                  ZephyrToast.show(context, 'Playlist updated');
                }
              },
              child: const Text('Save', style: TextStyle(color: Colors.black)),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDelete(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ZephyrColors.bgCard,
        title: Text('Delete "${widget.playlist.name}"?'),
        content: const Text(
          'Are you sure you want to delete this playlist? This action cannot be undone.',
          style: TextStyle(color: ZephyrColors.textDim),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text(
              'Cancel',
              style: TextStyle(color: ZephyrColors.textDim),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: ZephyrColors.error,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              Navigator.of(ctx).pop();
              await ref
                  .read(libraryProvider.notifier)
                  .deletePlaylist(widget.playlist.id);
              if (context.mounted) {
                ZephyrToast.show(context, 'Deleted "${widget.playlist.name}"');
              }
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: GestureDetector(
          onSecondaryTapDown: (details) {
            _showContextMenu(context, details.globalPosition);
          },
          child: InkWell(
            onTap: widget.onTap,
            borderRadius: BorderRadius.circular(6),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              height: 42,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: widget.isSelected
                    ? ZephyrColors.bgLight
                    : (_isHovered
                          ? ZephyrColors.bgLight.withValues(alpha: 0.4)
                          : Colors.transparent),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                children: [
                  CoverImage(
                    playlistId: widget.playlist.id,
                    size: 24,
                    borderRadius: 4,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      widget.playlist.name,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: widget.isSelected
                            ? ZephyrColors.primary
                            : (_isHovered
                                  ? ZephyrColors.text
                                  : ZephyrColors.textDim),
                        fontSize: 14,
                        fontWeight: widget.isSelected
                            ? FontWeight.bold
                            : FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SidebarSeeAllItem extends StatefulWidget {
  final VoidCallback onTap;

  const _SidebarSeeAllItem({required this.onTap});

  @override
  State<_SidebarSeeAllItem> createState() => _SidebarSeeAllItemState();
}

class _SidebarSeeAllItemState extends State<_SidebarSeeAllItem> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(6),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            height: 38,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: _isHovered
                  ? ZephyrColors.bgLight.withValues(alpha: 0.4)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.more_horiz,
                  size: 20,
                  color: _isHovered ? ZephyrColors.text : ZephyrColors.textDim,
                ),
                const SizedBox(width: 14),
                Text(
                  'See all playlists',
                  style: TextStyle(
                    color: _isHovered
                        ? ZephyrColors.text
                        : ZephyrColors.textDim,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w500,
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

class _TopSearchBar extends ConsumerStatefulWidget {
  const _TopSearchBar();

  @override
  ConsumerState<_TopSearchBar> createState() => _TopSearchBarState();
}

class _TopSearchBarState extends ConsumerState<_TopSearchBar> {
  late TextEditingController _controller;
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    final initialQuery = ref.read(searchQueryProvider);
    _controller = TextEditingController(text: initialQuery);

    _focusNode.addListener(() {
      if (_focusNode.hasFocus) {
        final navState = ref.read(navigationProvider);
        if (navState.currentScreen.type != ScreenType.search) {
          ref
              .read(navigationProvider.notifier)
              .navigateTo(const ScreenState(type: ScreenType.search));
        }
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<String>(searchQueryProvider, (previous, next) {
      if (next != _controller.text) {
        _controller.text = next;
      }
    });

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: SizedBox(
        height: 38,
        child: TextField(
          controller: _controller,
          focusNode: _focusNode,
          style: const TextStyle(color: ZephyrColors.text, fontSize: 13),
          onChanged: (value) {
            ref.read(searchQueryProvider.notifier).setQuery(value);
            final navState = ref.read(navigationProvider);
            if (navState.currentScreen.type != ScreenType.search) {
              ref
                  .read(navigationProvider.notifier)
                  .navigateTo(const ScreenState(type: ScreenType.search));
            }
          },
          decoration: InputDecoration(
            hintText: 'What do you want to listen to?',
            hintStyle: const TextStyle(
              color: ZephyrColors.textDim,
              fontSize: 13,
            ),
            prefixIcon: const Icon(
              Icons.search,
              color: ZephyrColors.textDim,
              size: 18,
            ),
            suffixIcon: _controller.text.isNotEmpty
                ? IconButton(
                    icon: const Icon(
                      Icons.clear,
                      color: ZephyrColors.textDim,
                      size: 16,
                    ),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () {
                      _controller.clear();
                      ref.read(searchQueryProvider.notifier).setQuery('');
                    },
                  )
                : null,
            filled: true,
            fillColor: Colors.white.withValues(alpha: 0.08),
            contentPadding: const EdgeInsets.symmetric(
              vertical: 0,
              horizontal: 12,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(19),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(19),
              borderSide: const BorderSide(color: Colors.white24, width: 1.0),
            ),
          ),
        ),
      ),
    );
  }
}

class _PlayerBarWidget extends ConsumerWidget {
  final _MainLayoutState parentState;
  const _PlayerBarWidget({required this.parentState});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playerState = ref.watch(playerProvider);
    final playerNotifier = ref.read(playerProvider.notifier);
    return parentState._buildPlayerBar(context, ref, playerState, playerNotifier);
  }
}
