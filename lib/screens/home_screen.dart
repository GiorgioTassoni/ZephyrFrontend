import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/auth_provider.dart';
import '../providers/library_provider.dart';
import '../providers/navigation_provider.dart';
import '../providers/player_provider.dart';
import '../models/models.dart';
import '../theme/colors.dart';
import '../widgets/cover_image.dart';
import '../widgets/track_tile.dart';
import '../widgets/toast.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) {
      return 'Good morning';
    } else if (hour < 18) {
      return 'Good afternoon';
    } else {
      return 'Good evening';
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final libraryState = ref.watch(libraryProvider);
    final libraryNotifier = ref.read(libraryProvider.notifier);
    final navNotifier = ref.read(navigationProvider.notifier);
    final playerNotifier = ref.read(playerProvider.notifier);

    // Limit history entries to unique tracks to avoid repeating tiles
    final uniqueHistory = <String, HistoryEntry>{};
    for (final entry in libraryState.history) {
      if (entry.track != null &&
          entry.track!.title != 'Unknown Track' &&
          entry.track!.title.isNotEmpty) {
        uniqueHistory.putIfAbsent(entry.trackId, () => entry);
      }
    }
    final historyTracks = uniqueHistory.values.map((e) => e.track!).toList();

    return Scaffold(
      backgroundColor: ZephyrColors.bgDark,
      body: Stack(
        children: [
          // Fixed Spotify-style top ambient glow (stays at the top 350px of the viewport, matching Amber Zephyr branding)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 350,
            child: IgnorePointer(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      ZephyrColors.primary.withValues(alpha: 0.18),
                      ZephyrColors.primary.withValues(alpha: 0.04),
                      Colors.transparent,
                    ],
                    stops: const [0.0, 0.4, 1.0],
                  ),
                ),
              ),
            ),
          ),
          
          // Scrollable Content
          Positioned.fill(
            child: RefreshIndicator(
              onRefresh: () => libraryNotifier.refreshLibrary(),
              color: ZephyrColors.primary,
              backgroundColor: ZephyrColors.bgCard,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Greeting Header
                    Text(
                      _getGreeting(),
                      style: const TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        color: ZephyrColors.text,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Recently Played Quick Grid (6 items)
                    _buildQuickGrid(context, ref, libraryState, navNotifier),
                    const SizedBox(height: 40),

                    // Section: Continue Listening / Listening History
                    if (historyTracks.isNotEmpty) ...[
                      const Text(
                        'Recently Played',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: ZephyrColors.text,
                        ),
                      ),
                      const SizedBox(height: 16),
                      ScrollableHorizontalList(
                        itemCount: historyTracks.length.clamp(0, 10),
                        itemHeight: context.scale(190),
                        itemBuilder: (context, index) {
                          final track = historyTracks[index];
                          return _buildHorizontalTrackCard(context, track, historyTracks, playerNotifier);
                        },
                      ),
                      const SizedBox(height: 40),
                    ],

                    // Section: Your Playlists
                    if (libraryState.playlists.isNotEmpty) ...[
                      const Text(
                        'Your Playlists',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: ZephyrColors.text,
                        ),
                      ),
                      const SizedBox(height: 16),
                      ScrollableHorizontalList(
                        itemCount: libraryState.playlists.length,
                        itemHeight: context.scale(200),
                        itemBuilder: (context, index) {
                          final playlist = libraryState.playlists[index];
                          return _buildHorizontalPlaylistCard(context, playlist, navNotifier);
                        },
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickGrid(
    BuildContext context,
    WidgetRef ref,
    LibraryState state,
    NavigationNotifier navNotifier,
  ) {
    final authState = ref.watch(authProvider);
    final isAdmin = authState.isAdmin;

    // Generate quick items: favorites, history, and up to 4 playlists
    final items = <Widget>[];

    // 1. Favorites card
    items.add(
      _QuickCard(
        title: 'Favorites',
        iconWidget: Container(
          color: ZephyrColors.primary.withValues(alpha: 0.2),
          child: const Icon(Icons.favorite, color: ZephyrColors.primary, size: 28),
        ),
        onTap: () {
          navNotifier.navigateTo(const ScreenState(type: ScreenType.favorites));
        },
      ),
    );

    // 2. VPS Songs card (Only visible to admin)
    if (isAdmin) {
      items.add(
        _QuickCard(
          title: 'VPS Songs',
          iconWidget: Container(
            color: Colors.blue.withValues(alpha: 0.2),
            child: const Icon(Icons.library_music, color: Colors.blue, size: 28),
          ),
          onTap: () {
            navNotifier.navigateTo(const ScreenState(type: ScreenType.library, intId: 2));
          },
        ),
      );
    }

    // Playlists
    for (int i = 0; i < state.playlists.length && items.length < 6; i++) {
      final pl = state.playlists[i];
      items.add(
        _QuickCard(
          title: pl.name,
          iconWidget: CoverImage(playlistId: pl.id, size: 56, borderRadius: 0),
          onTap: () {
            navNotifier.navigateTo(ScreenState(type: ScreenType.playlist, intId: pl.id));
          },
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        // Compute columns based on screen width
        final crossAxisCount = constraints.maxWidth > 800 ? 3 : 2;
        return GridView.count(
          crossAxisCount: crossAxisCount,
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
          childAspectRatio: constraints.maxWidth > 800 ? 5.5 : 4.0,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: items,
        );
      },
    );
  }
  Widget _buildHorizontalTrackCard(
    BuildContext context,
    Track track,
    List<Track> queue,
    PlayerNotifier playerNotifier,
  ) {
    return _HorizontalTrackCard(
      track: track,
      queue: queue,
      playerNotifier: playerNotifier,
    );
  }

  Widget _buildHorizontalPlaylistCard(
    BuildContext context,
    Playlist playlist,
    NavigationNotifier navNotifier,
  ) {
    return _HorizontalPlaylistCard(
      playlist: playlist,
      navNotifier: navNotifier,
    );
  }
}

class _QuickCard extends StatefulWidget {
  final String title;
  final Widget iconWidget;
  final VoidCallback onTap;

  const _QuickCard({
    required this.title,
    required this.iconWidget,
    required this.onTap,
  });

  @override
  State<_QuickCard> createState() => _QuickCardState();
}

class _QuickCardState extends State<_QuickCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: InkWell(
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(6),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            color: _isHovered ? ZephyrColors.bgLight : ZephyrColors.bgCard,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: _isHovered
                  ? ZephyrColors.primary.withValues(alpha: 0.5)
                  : ZephyrColors.bgLight.withValues(alpha: 0.4),
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AspectRatio(
                aspectRatio: 1.0,
                child: widget.iconWidget,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    widget.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: ZephyrColors.text,
                    ),
                  ),
                ),
              ),
              AnimatedOpacity(
                duration: const Duration(milliseconds: 150),
                opacity: _isHovered ? 1.0 : 0.0,
                child: Padding(
                  padding: const EdgeInsets.only(right: 16.0),
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: const BoxDecoration(
                        color: ZephyrColors.primary,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.play_arrow,
                        color: Colors.black,
                        size: 20,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HorizontalTrackCard extends ConsumerStatefulWidget {
  final Track track;
  final List<Track> queue;
  final PlayerNotifier playerNotifier;

  const _HorizontalTrackCard({
    required this.track,
    required this.queue,
    required this.playerNotifier,
  });

  @override
  ConsumerState<_HorizontalTrackCard> createState() => _HorizontalTrackCardState();
}

class _HorizontalTrackCardState extends ConsumerState<_HorizontalTrackCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: context.scale(140),
      margin: const EdgeInsets.only(right: 16),
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        cursor: SystemMouseCursors.click,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            color: _isHovered ? ZephyrColors.bgLight.withValues(alpha: 0.3) : ZephyrColors.bgCard,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: _isHovered
                  ? ZephyrColors.primary.withValues(alpha: 0.5)
                  : ZephyrColors.bgLight.withValues(alpha: 0.3),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.15),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: GestureDetector(
            onSecondaryTapDown: (details) {
              _showRightClickMenu(context, details.globalPosition);
            },
            child: InkWell(
              onTap: () {
                widget.playerNotifier.playTrack(widget.track, widget.queue);
              },
              borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Stack(
                    children: [
                      CoverImage(
                        videoId: widget.track.videoId,
                        coverUrl: widget.track.coverUrl,
                        size: context.scale(116),
                        borderRadius: 6,
                      ),
                      Positioned.fill(
                        child: AnimatedOpacity(
                          duration: const Duration(milliseconds: 200),
                          opacity: _isHovered ? 1.0 : 0.0,
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.4),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Center(
                              child: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: const BoxDecoration(
                                  color: ZephyrColors.primary,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.play_arrow,
                                  color: Colors.black,
                                  size: 20,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    widget.track.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color: ZephyrColors.text,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    widget.track.artists.join(', '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      color: ZephyrColors.textDim,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

  void _showRightClickMenu(BuildContext context, Offset position) {
    final playerNotifier = widget.playerNotifier;

    final RelativeRect positionRect = RelativeRect.fromRect(
      Rect.fromPoints(position, position),
      Offset.zero & MediaQuery.of(context).size,
    );

    showMenu<String>(
      context: context,
      position: positionRect,
      color: ZephyrColors.bgCard,
      items: [
        const PopupMenuItem(
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
      ],
    ).then((value) {
      if (value == null) return;
      
      if (value == 'queue_action') {
        playerNotifier.addToQueue(widget.track);
        ZephyrToast.show(
          context,
          'Added "${widget.track.title}" to queue!',
        );
      }
    });
  }
}

class _HorizontalPlaylistCard extends StatefulWidget {
  final Playlist playlist;
  final NavigationNotifier navNotifier;

  const _HorizontalPlaylistCard({
    required this.playlist,
    required this.navNotifier,
  });

  @override
  State<_HorizontalPlaylistCard> createState() => _HorizontalPlaylistCardState();
}

class _HorizontalPlaylistCardState extends State<_HorizontalPlaylistCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: context.scale(140),
      margin: const EdgeInsets.only(right: 16),
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        cursor: SystemMouseCursors.click,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            color: _isHovered ? ZephyrColors.bgLight.withValues(alpha: 0.3) : ZephyrColors.bgCard,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: _isHovered
                  ? ZephyrColors.primary.withValues(alpha: 0.5)
                  : ZephyrColors.bgLight.withValues(alpha: 0.3),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.15),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: InkWell(
            onTap: () {
              widget.navNotifier.navigateTo(ScreenState(type: ScreenType.playlist, intId: widget.playlist.id));
            },
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Stack(
                    children: [
                      CoverImage(
                        playlistId: widget.playlist.id,
                        size: context.scale(116),
                        borderRadius: 6,
                      ),
                      Positioned.fill(
                        child: AnimatedOpacity(
                          duration: const Duration(milliseconds: 200),
                          opacity: _isHovered ? 1.0 : 0.0,
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.4),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Center(
                              child: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: const BoxDecoration(
                                  color: ZephyrColors.primary,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.play_arrow,
                                  color: Colors.black,
                                  size: 20,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    widget.playlist.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color: ZephyrColors.text,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    widget.playlist.description ?? 'Playlist',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      color: ZephyrColors.textDim,
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

class ScrollableHorizontalList extends StatefulWidget {
  final int itemCount;
  final Widget Function(BuildContext, int) itemBuilder;
  final double itemHeight;

  const ScrollableHorizontalList({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    required this.itemHeight,
  });

  @override
  State<ScrollableHorizontalList> createState() => _ScrollableHorizontalListState();
}

class _ScrollableHorizontalListState extends State<ScrollableHorizontalList> {
  final ScrollController _scrollController = ScrollController();
  bool _showLeftArrow = false;
  bool _showRightArrow = true;
  bool _isHovered = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _onScroll());
  }

  @override
  void didUpdateWidget(ScrollableHorizontalList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.itemCount != widget.itemCount) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _onScroll());
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.offset;

    setState(() {
      _showLeftArrow = currentScroll > 10;
      _showRightArrow = currentScroll < maxScroll - 10;
    });
  }

  void _scroll(double offset) {
    if (!_scrollController.hasClients) return;
    final target = (_scrollController.offset + offset).clamp(
      0.0,
      _scrollController.position.maxScrollExtent,
    );
    _scrollController.animateTo(
      target,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // The horizontal list
          SizedBox(
            height: widget.itemHeight,
            child: ListView.builder(
              controller: _scrollController,
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              itemCount: widget.itemCount,
              itemBuilder: widget.itemBuilder,
            ),
          ),
          
          // Left Arrow
          if (_showLeftArrow)
            Positioned(
              left: -12,
              top: 0,
              bottom: 0,
              child: Center(
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: () => _scroll(-400),
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: ZephyrColors.bgCard.withValues(alpha: 0.9),
                        shape: BoxShape.circle,
                        border: Border.all(color: ZephyrColors.primary.withValues(alpha: 0.3), width: 1.5),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.4),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.chevron_left,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                  ),
                ),
              ),
            ),

          // Right Arrow
          if (_showRightArrow)
            Positioned(
              right: -12,
              top: 0,
              bottom: 0,
              child: Center(
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: () => _scroll(400),
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: ZephyrColors.bgCard.withValues(alpha: 0.9),
                        shape: BoxShape.circle,
                        border: Border.all(color: ZephyrColors.primary.withValues(alpha: 0.3), width: 1.5),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.4),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.chevron_right,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
