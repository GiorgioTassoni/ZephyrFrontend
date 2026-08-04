import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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

class MainLayout extends ConsumerWidget {
  const MainLayout({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final navState = ref.watch(navigationProvider);
    final navNotifier = ref.read(navigationProvider.notifier);
    final authState = ref.watch(authProvider);
    final playerState = ref.watch(playerProvider);
    final playerNotifier = ref.read(playerProvider.notifier);
    final libraryState = ref.watch(libraryProvider);

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
        currentScreenWidget = LibraryScreen(initialTabIndex: navState.currentScreen.intId ?? 1);
        break;
      case ScreenType.favorites:
        currentScreenWidget = const FavoritesScreen();
        break;
      case ScreenType.settings:
        currentScreenWidget = const SettingsScreen();
        break;
      case ScreenType.album:
        currentScreenWidget = AlbumDetailScreen(browseId: navState.currentScreen.id!);
        break;
      case ScreenType.artist:
        currentScreenWidget = ArtistDetailScreen(channelId: navState.currentScreen.id!);
        break;
      case ScreenType.playlist:
        currentScreenWidget = PlaylistDetailScreen(playlistId: navState.currentScreen.id ?? navState.currentScreen.intId!);
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

    return Scaffold(
      backgroundColor: ZephyrColors.bgDark,
      body: Column(
        children: [
          // Top navigation bar (Full width of the screen!)
          _buildTopBar(context, ref, navNotifier, navState, authState),

          // Horizontal divider below top bar
          Container(height: 1, color: ZephyrColors.bgLight),

          // Split Pane: Sidebar + Content
          Expanded(
            child: Row(
              children: [
                // Sidebar
                _buildSidebar(context, ref, navState, authState, libraryState),
                
                // Vertical divider
                Container(width: 1, color: ZephyrColors.bgLight),

                // Main content area
                Expanded(
                  child: ClipRect(
                    child: Builder(
                      builder: (context) {
                        final mediaQueryData = MediaQuery.of(context);
                        final width = mediaQueryData.size.width;
                        final scale = (0.95 + (width - 1100) * 0.00034).clamp(0.95, 1.45);
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
          
          // Horizontal divider above player
          Container(height: 1, color: ZephyrColors.bgLight),

          // Bottom Player Bar
          _buildPlayerBar(context, ref, playerState, playerNotifier),
        ],
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
            padding: const EdgeInsets.only(left: 24, top: 24, bottom: 20, right: 24),
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
                    letterSpacing: -0.5,
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
            onTap: () => navNotifier.navigateTo(const ScreenState(type: ScreenType.home)),
          ),
          _buildSidebarNavItem(
            icon: Icons.library_music,
            label: 'Library',
            isSelected: navState.currentScreen.type == ScreenType.library,
            onTap: () => navNotifier.navigateTo(const ScreenState(type: ScreenType.library, intId: 1)),
          ),
          _buildSidebarNavItem(
            icon: Icons.favorite,
            label: 'Favorite Songs',
            isSelected: navState.currentScreen.type == ScreenType.favorites,
            onTap: () => navNotifier.navigateTo(const ScreenState(type: ScreenType.favorites)),
          ),
          _buildSidebarNavItem(
            icon: Icons.analytics_outlined,
            label: 'Listening Insights',
            isSelected: navState.currentScreen.type == ScreenType.statistics,
            onTap: () => navNotifier.navigateTo(const ScreenState(type: ScreenType.statistics)),
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
                  'PLAYLISTS',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                    color: ZephyrColors.textDim,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.add, size: 18, color: ZephyrColors.textDim),
                  hoverColor: Colors.transparent,
                  onPressed: () => _showCreatePlaylistDialog(context, ref),
                ),
              ],
            ),
          ),

          // Playlists Scrollable List
          Expanded(
            child: libraryState.playlists.isEmpty
                ? const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    child: Text(
                      'No playlists yet.',
                      style: TextStyle(color: ZephyrColors.textMuted, fontSize: 13),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    itemCount: libraryState.playlists.length,
                    itemBuilder: (context, index) {
                      final playlist = libraryState.playlists[index];
                      final isSelected = navState.currentScreen.type == ScreenType.playlist &&
                          (navState.currentScreen.intId == playlist.id || navState.currentScreen.id == playlist.id.toString());
                      return Material(
                        type: MaterialType.transparency,
                        child: ListTile(
                          dense: true,
                          horizontalTitleGap: 8,
                          visualDensity: VisualDensity.compact,
                          leading: CoverImage(playlistId: playlist.id, size: 24, borderRadius: 4),
                          title: Text(
                            playlist.name,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: isSelected ? ZephyrColors.primary : ZephyrColors.textDim,
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                            ),
                          ),
                          onTap: () {
                            navNotifier.navigateTo(ScreenState(
                              type: ScreenType.playlist,
                              id: playlist.id.toString(),
                              intId: playlist.id is int ? playlist.id as int : int.tryParse(playlist.id.toString()),
                            ));
                          },
                        ),
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
    Widget buildCircleArrowButton(IconData icon, bool enabled, VoidCallback? onTap) {
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

    return Container(
      height: 60,
      color: ZephyrColors.bgDark,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Left: Back & Forward Arrows
          Align(
            alignment: Alignment.centerLeft,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                buildCircleArrowButton(
                  Icons.chevron_left,
                  navNotifier.canGoBack,
                  navNotifier.canGoBack ? () => navNotifier.navigateBack() : null,
                ),
                const SizedBox(width: 8),
                buildCircleArrowButton(
                  Icons.chevron_right,
                  navNotifier.canGoForward,
                  navNotifier.canGoForward ? () => navNotifier.navigateForward() : null,
                ),
              ],
            ),
          ),

          // Center: Search Bar (Spotify style, mathematically centered)
          const Align(
            alignment: Alignment.center,
            child: _TopSearchBar(),
          ),

          // Right: User Profile Card / Settings Link (Action Menu)
          Align(
            alignment: Alignment.centerRight,
            child: PopupMenuButton<String>(
              offset: const Offset(0, 42),
              color: ZephyrColors.bgCard,
              onSelected: (value) {
                if (value == 'settings') {
                  navNotifier.navigateTo(const ScreenState(type: ScreenType.settings));
                } else if (value == 'admin') {
                  navNotifier.navigateTo(const ScreenState(type: ScreenType.admin));
                } else if (value == 'curator') {
                  navNotifier.navigateTo(const ScreenState(type: ScreenType.curator));
                } else if (value == 'import') {
                  navNotifier.navigateTo(const ScreenState(type: ScreenType.import));
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
                        Icon(Icons.admin_panel_settings, size: 16, color: ZephyrColors.textDim),
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
                      Icon(Icons.upload_file, size: 16, color: ZephyrColors.textDim),
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
                    const Icon(Icons.person, size: 18, color: ZephyrColors.primary),
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
    if (state.currentTrack == null) {
      return Container(
        height: 90,
        color: ZephyrColors.bgCard,
        alignment: Alignment.center,
        child: const Text(
          'Select a track to start listening',
          style: TextStyle(color: ZephyrColors.textDim),
        ),
      );
    }

    final track = state.currentTrack!;
    ref.watch(libraryProvider);
    final libraryNotifier = ref.read(libraryProvider.notifier);
    final isFav = libraryNotifier.isFavorite(track.videoId, title: track.title);
    final navState = ref.watch(navigationProvider);
    final navNotifier = ref.read(navigationProvider.notifier);

    return Container(
      height: 95,
      color: ZephyrColors.bgCard,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Left: Cover + Metadata + Like Button
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 340),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                InkWell(
                  onTap: () {
                    if (navState.currentScreen.type == ScreenType.lyrics) {
                      navNotifier.navigateBack();
                    } else {
                      navNotifier.navigateTo(const ScreenState(type: ScreenType.lyrics));
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
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      InkWell(
                        onTap: () {
                          if (navState.currentScreen.type == ScreenType.lyrics) {
                            navNotifier.navigateBack();
                          } else {
                            navNotifier.navigateTo(const ScreenState(type: ScreenType.lyrics));
                          }
                        },
                        child: Text(
                          track.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: ZephyrColors.text,
                          ),
                        ),
                      ),
                      const SizedBox(height: 2),
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
                        color: state.isShuffled ? ZephyrColors.primary : ZephyrColors.textDim,
                        size: 20,
                      ),
                      onPressed: () => notifier.toggleShuffle(),
                    ),
                    IconButton(
                      icon: const Icon(Icons.skip_previous, color: ZephyrColors.text, size: 24),
                      onPressed: () => notifier.playPrevious(),
                    ),
                    const SizedBox(width: 8),
                    if (state.isLoading)
                      const SizedBox(
                        width: 32,
                        height: 32,
                        child: CircularProgressIndicator(
                          strokeWidth: 3,
                          valueColor: AlwaysStoppedAnimation<Color>(ZephyrColors.primary),
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
                      icon: const Icon(Icons.skip_next, color: ZephyrColors.text, size: 24),
                      onPressed: () => notifier.playNext(),
                    ),
                    IconButton(
                      icon: Icon(
                        state.queueMode == 'repeat_one'
                            ? Icons.repeat_one
                            : Icons.repeat,
                        color: state.queueMode != 'normal' ? ZephyrColors.primary : ZephyrColors.textDim,
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
                    duration: state.duration,
                    onChangeEnd: (duration) {
                      notifier.seek(duration);
                    },
                  ),
                ),
              ],
            ),
          ),

          // Right: Lyrics Button + Volume Control
          SizedBox(
            width: 240,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
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
                      navNotifier.navigateTo(const ScreenState(type: ScreenType.queue));
                    }
                  },
                ),
                const SizedBox(width: 12),
                IconButton(
                  padding: const EdgeInsets.all(6),
                  constraints: const BoxConstraints(),
                  icon: Icon(
                    Icons.lyrics,
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
                      navNotifier.navigateTo(const ScreenState(type: ScreenType.lyrics));
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
                        : (state.volume < 0.5 ? Icons.volume_down : Icons.volume_up),
                    color: state.volume == 0 ? ZephyrColors.error : ZephyrColors.textDim,
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
                            final result = await FilePicker.pickFiles(
                              type: FileType.image,
                              allowMultiple: false,
                            );
                            if (result != null && result.files.single.path != null) {
                              setState(() {
                                coverFile = File(result.files.single.path!);
                              });
                            }
                          } catch (e) {
                            ZephyrToast.show(context, 'Error picking cover: $e', isError: true);
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
                                    color: ZephyrColors.primary.withOpacity(0.3),
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
                                        mainAxisAlignment: MainAxisAlignment.center,
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
                                    color: Colors.black.withOpacity(0.4),
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
                  child: const Text('Cancel', style: TextStyle(color: ZephyrColors.textDim)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: ZephyrColors.primary),
                  onPressed: () async {
                    if (nameController.text.trim().isEmpty) return;
                    Navigator.of(context).pop();
                    await ref.read(libraryProvider.notifier).createPlaylist(
                          nameController.text.trim(),
                          descController.text.trim(),
                          isPublic,
                          coverImage: coverFile,
                        );
                  },
                  child: const Text('Create', style: TextStyle(color: Colors.black)),
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
    final double trackLeft = offset.dx;
    final double trackTop = offset.dy + (parentBox.size.height - trackHeight) / 2;
    final double trackWidth = parentBox.size.width;
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
          thumbShape: RoundSliderThumbShape(enabledThumbRadius: 5, pressedElevation: 0),
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
                  : (_isHovered ? ZephyrColors.bgLight.withValues(alpha: 0.4) : Colors.transparent),
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
                        : (_isHovered ? ZephyrColors.text : ZephyrColors.textDim),
                    fontSize: 14,
                    fontWeight: widget.isSelected ? FontWeight.bold : FontWeight.w500,
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
          ref.read(navigationProvider.notifier).navigateTo(const ScreenState(type: ScreenType.search));
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

    return SizedBox(
      width: 420,
      height: 38,
      child: TextField(
        controller: _controller,
        focusNode: _focusNode,
        style: const TextStyle(color: ZephyrColors.text, fontSize: 13),
        onChanged: (value) {
          ref.read(searchQueryProvider.notifier).setQuery(value);
          final navState = ref.read(navigationProvider);
          if (navState.currentScreen.type != ScreenType.search) {
            ref.read(navigationProvider.notifier).navigateTo(const ScreenState(type: ScreenType.search));
          }
        },
        decoration: InputDecoration(
          hintText: 'What do you want to listen to?',
          hintStyle: const TextStyle(color: ZephyrColors.textDim, fontSize: 13),
          prefixIcon: const Icon(Icons.search, color: ZephyrColors.textDim, size: 18),
          suffixIcon: _controller.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear, color: ZephyrColors.textDim, size: 16),
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
          contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 12),
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
    );
  }
}

