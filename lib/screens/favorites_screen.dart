import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/models.dart';
import '../providers/auth_provider.dart';
import '../providers/library_provider.dart';
import '../providers/navigation_provider.dart';
import '../providers/offline_provider.dart';
import '../providers/player_provider.dart';
import '../theme/colors.dart';
import '../widgets/toast.dart';
import '../widgets/track_tile.dart';
import '../widgets/track_tile_skeleton.dart';

class FavoritesScreen extends ConsumerStatefulWidget {
  const FavoritesScreen({super.key});

  @override
  ConsumerState<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _ScrollBubbleData {
  final bool show;
  final String text;
  final double top;
  final String sortBy;

  const _ScrollBubbleData({
    this.show = false,
    this.text = '',
    this.top = 120.0,
    this.sortBy = 'date_added',
  });
}

class _FavoritesScreenState extends ConsumerState<FavoritesScreen> {
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String _sortBy = 'date_added'; // 'date_added' | 'title' | 'artist' | 'duration'
  bool _isSearchVisible = false;
  bool _isDownloadingFavorites = false;
  bool _isDraggingScrollbar = false;

  final ValueNotifier<_ScrollBubbleData> _bubbleNotifier =
      ValueNotifier(const _ScrollBubbleData());
  Timer? _bubbleFadeTimer;

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];

  String _formatMonthYear(DateTime dt) {
    return '${_months[dt.month - 1]} ${dt.year}';
  }

  void _onScrollNotification(ScrollNotification notification, List<Track> processedFavorites) {
    if (processedFavorites.isEmpty || !_isDraggingScrollbar) return;

    final pixels = notification.metrics.pixels;
    const headerHeight = 280.0;
    const itemHeight = 64.0;

    final int index = ((pixels - headerHeight) / itemHeight)
        .floor()
        .clamp(0, processedFavorites.length - 1);
    final track = processedFavorites[index];

    String text;
    switch (_sortBy) {
      case 'title':
        final clean = track.title.trim();
        text = clean.isNotEmpty ? clean[0].toUpperCase() : '#';
        if (!RegExp(r'[A-Z]').hasMatch(text)) text = '#';
        break;
      case 'artist':
        final clean = track.artists.isNotEmpty ? track.artists.first.trim() : '';
        text = clean.isNotEmpty ? clean[0].toUpperCase() : '#';
        if (!RegExp(r'[A-Z]').hasMatch(text)) text = '#';
        break;
      case 'duration':
        final mins = (track.duration?.inSeconds ?? 0) ~/ 60;
        final secs = (track.duration?.inSeconds ?? 0) % 60;
        text = '$mins:${secs.toString().padLeft(2, '0')}';
        break;
      case 'date_added':
      default:
        text = track.favoritedAt != null
            ? _formatMonthYear(track.favoritedAt!)
            : 'Liked Songs';
        break;
    }

    final viewport = notification.metrics.viewportDimension;
    final maxScroll = notification.metrics.maxScrollExtent;
    double targetTop = 120.0;
    if (maxScroll > 0) {
      final progress = (pixels / maxScroll).clamp(0.0, 1.0);
      targetTop = 80.0 + progress * (viewport - 160.0);
    }

    _bubbleFadeTimer?.cancel();
    _bubbleNotifier.value = _ScrollBubbleData(
      show: true,
      text: text,
      top: targetTop,
      sortBy: _sortBy,
    );

    _bubbleFadeTimer = Timer(const Duration(milliseconds: 1000), () {
      if (mounted) {
        _bubbleNotifier.value = _ScrollBubbleData(
          show: false,
          text: _bubbleNotifier.value.text,
          top: _bubbleNotifier.value.top,
          sortBy: _bubbleNotifier.value.sortBy,
        );
      }
    });
  }

  Future<void> _downloadAllFavorites(List<Track> favorites) async {
    if (favorites.isEmpty) return;
    setState(() => _isDownloadingFavorites = true);
    try {
      ZephyrToast.show(context, 'Downloading ${favorites.length} liked songs to this device...');
      await ref.read(offlineDownloadsProvider.notifier).downloadBatch(favorites);
      if (mounted) {
        ZephyrToast.show(context, 'Liked songs downloaded to device!');
      }
    } catch (e) {
      if (mounted) {
        ZephyrToast.show(context, 'Failed to download: $e', isError: true);
      }
    } finally {
      if (mounted) {
        setState(() => _isDownloadingFavorites = false);
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    final libraryState = ref.read(libraryProvider);
    if (libraryState.favorites.isEmpty) {
      Future.microtask(() => ref.read(libraryProvider.notifier).loadFavorites());
    }
  }

  @override
  void dispose() {
    _bubbleFadeTimer?.cancel();
    _bubbleNotifier.dispose();
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
      final libraryNotifier = ref.read(libraryProvider.notifier);
      libraryNotifier.loadMoreFavorites();
    }
  }

  List<Track> _getProcessedFavorites(List<Track> rawFavorites) {
    List<Track> list = List.from(rawFavorites);

    if (_searchQuery.trim().isNotEmpty) {
      final q = _searchQuery.trim().toLowerCase();
      list = list.where((t) {
        final titleMatch = t.title.toLowerCase().contains(q);
        final artistMatch = t.artists.join(', ').toLowerCase().contains(q);
        final albumMatch = (t.album ?? '').toLowerCase().contains(q);
        return titleMatch || artistMatch || albumMatch;
      }).toList();
    }

    switch (_sortBy) {
      case 'title':
        list.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
        break;
      case 'artist':
        list.sort((a, b) => a.artists.join(', ').toLowerCase().compareTo(b.artists.join(', ').toLowerCase()));
        break;
      case 'duration':
        list.sort((a, b) => (b.duration?.inSeconds ?? 0).compareTo(a.duration?.inSeconds ?? 0));
        break;
      case 'date_added':
      default:
        list.sort((a, b) {
          if (a.favoritedAt != null && b.favoritedAt != null) {
            return b.favoritedAt!.compareTo(a.favoritedAt!);
          }
          return 0; // retain server array order
        });
        break;
    }

    return list;
  }

  @override
  Widget build(BuildContext context) {
    final libraryState = ref.watch(libraryProvider);
    final authState = ref.watch(authProvider);
    final navNotifier = ref.read(navigationProvider.notifier);
    final playerState = ref.watch(playerProvider);
    final playerNotifier = ref.read(playerProvider.notifier);

    final rawFavorites = libraryState.favorites;
    final processedFavorites = _getProcessedFavorites(rawFavorites);
    final username = authState.username ?? 'User';

    final offlineState = ref.watch(offlineDownloadsProvider);
    final bool allFavoritesDownloaded = rawFavorites.isNotEmpty &&
        rawFavorites.every((t) => offlineState.isDownloaded(t.videoId));

    return Scaffold(
      backgroundColor: ZephyrColors.bgDark,
      body: LayoutBuilder(
        builder: (context, constraints) {
          return Listener(
            onPointerDown: (event) {
              if (event.localPosition.dx >= constraints.maxWidth - 32) {
                _isDraggingScrollbar = true;
              } else {
                _isDraggingScrollbar = false;
              }
            },
            onPointerUp: (_) {
              if (_isDraggingScrollbar) {
                _isDraggingScrollbar = false;
                _bubbleFadeTimer?.cancel();
                _bubbleFadeTimer = Timer(const Duration(milliseconds: 250), () {
                  if (mounted) {
                    _bubbleNotifier.value = _ScrollBubbleData(
                      show: false,
                      text: _bubbleNotifier.value.text,
                      top: _bubbleNotifier.value.top,
                      sortBy: _bubbleNotifier.value.sortBy,
                    );
                  }
                });
              }
            },
            onPointerCancel: (_) {
              _isDraggingScrollbar = false;
              _bubbleNotifier.value = _ScrollBubbleData(
                show: false,
                text: _bubbleNotifier.value.text,
                top: _bubbleNotifier.value.top,
                sortBy: _bubbleNotifier.value.sortBy,
              );
            },
            child: NotificationListener<ScrollNotification>(
              onNotification: (notification) {
                if (_isDraggingScrollbar &&
                    (notification is ScrollUpdateNotification ||
                        notification is ScrollStartNotification)) {
                  _onScrollNotification(notification, processedFavorites);
                }
                return false;
              },
              child: Stack(
                children: [
                  Scrollbar(
                    controller: _scrollController,
                    thumbVisibility: true,
                    interactive: true,
                    child: CustomScrollView(
                      key: const PageStorageKey('favorites_custom_scroll_view'),
                      controller: _scrollController,
                      slivers: [
                  // Hero Banner Header
                  SliverToBoxAdapter(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                final isMobile = constraints.maxWidth < 600;
                return Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        const Color(0xFFF59E0B).withValues(alpha: 0.22),
                        ZephyrColors.bgDark,
                      ],
                    ),
                  ),
                  padding: EdgeInsets.symmetric(
                    horizontal: isMobile ? 16 : 32,
                    vertical: isMobile ? 16 : 24,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Top Navigation Back Button Row
                      Row(
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
                          const SizedBox(width: 4),
                          const Text(
                            'Liked Songs',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: ZephyrColors.text,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      // Hero Content
                      if (isMobile)
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            _buildArtworkCard(isMobile: true),
                            const SizedBox(width: 16),
                            Expanded(
                              child: _buildHeaderDetails(username, isMobile: true, totalCount: libraryState.effectiveFavoritesCount),
                            ),
                          ],
                        )
                      else
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            _buildArtworkCard(isMobile: false),
                            const SizedBox(width: 24),
                            Expanded(
                              child: _buildHeaderDetails(username, isMobile: false, totalCount: libraryState.effectiveFavoritesCount),
                            ),
                          ],
                        ),
                    ],
                  ),
                );
              },
            ),
          ),

          // Action Bar (Play, Shuffle, Search, Sort)
          SliverToBoxAdapter(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isMobile = constraints.maxWidth < 600;
                return Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: isMobile ? 16 : 32,
                    vertical: 12,
                  ),
                  child: Row(
                    children: [
                      // Big Amber Play Button
                      Material(
                        color: ZephyrColors.primary,
                        shape: const CircleBorder(),
                        elevation: 6,
                        shadowColor: ZephyrColors.primary.withValues(alpha: 0.4),
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: processedFavorites.isNotEmpty
                              ? () => playerNotifier.playTrack(
                                    processedFavorites.first,
                                    processedFavorites,
                                    isNewQueue: true,
                                    origin: 'context',
                                  )
                              : null,
                          child: const SizedBox(
                            width: 50,
                            height: 50,
                            child: Center(
                              child: Icon(Icons.play_arrow, color: Colors.black, size: 30),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),

                      // Shuffle Button
                      IconButton(
                        icon: Icon(
                          Icons.shuffle,
                          color: playerState.isShuffled ? ZephyrColors.primary : ZephyrColors.textDim,
                          size: 26,
                        ),
                        tooltip: 'Shuffle Play',
                        onPressed: processedFavorites.isNotEmpty
                            ? () {
                                if (!playerState.isShuffled) {
                                  playerNotifier.toggleShuffle();
                                }
                                playerNotifier.playTrack(
                                  processedFavorites.first,
                                  processedFavorites,
                                  isNewQueue: true,
                                  origin: 'context',
                                );
                              }
                            : null,
                      ),
                      const SizedBox(width: 8),

                      // Download All Liked Songs Button
                      IconButton(
                        icon: _isDownloadingFavorites
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: ZephyrColors.primary,
                                ),
                              )
                            : Icon(
                                allFavoritesDownloaded
                                    ? Icons.check_circle_rounded
                                    : Icons.download_rounded,
                                color: allFavoritesDownloaded
                                    ? ZephyrColors.success
                                    : ZephyrColors.textDim,
                                size: 26,
                              ),
                        tooltip: allFavoritesDownloaded
                            ? 'All liked songs downloaded to this device'
                            : 'Download Liked Songs to this device',
                        onPressed: _isDownloadingFavorites || rawFavorites.isEmpty
                            ? null
                            : () => _downloadAllFavorites(rawFavorites),
                      ),
                      const Spacer(),

                      // Search Filter Toggle & Input
                      if (_isSearchVisible)
                        Container(
                          width: 180,
                          height: 38,
                          margin: const EdgeInsets.only(right: 8),
                          child: TextField(
                            controller: _searchController,
                            autofocus: true,
                            style: const TextStyle(color: ZephyrColors.text, fontSize: 13),
                            decoration: InputDecoration(
                              hintText: 'Search songs',
                              hintStyle: const TextStyle(color: ZephyrColors.textDim, fontSize: 13),
                              prefixIcon: const Icon(Icons.search, size: 18, color: ZephyrColors.textDim),
                              suffixIcon: IconButton(
                                icon: const Icon(Icons.clear, size: 16, color: ZephyrColors.textDim),
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() {
                                    _searchQuery = '';
                                    _isSearchVisible = false;
                                  });
                                },
                              ),
                              contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 10),
                              filled: true,
                              fillColor: ZephyrColors.bgCard,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(20),
                                borderSide: BorderSide.none,
                              ),
                            ),
                            onChanged: (val) => setState(() => _searchQuery = val),
                          ),
                        )
                      else
                        IconButton(
                          icon: const Icon(Icons.search, color: ZephyrColors.textDim, size: 22),
                          tooltip: 'Search inside favorites',
                          onPressed: () => setState(() => _isSearchVisible = true),
                        ),

                      // Sort Menu
                      PopupMenuButton<String>(
                        icon: const Icon(Icons.sort, color: ZephyrColors.textDim, size: 22),
                        tooltip: 'Sort by',
                        color: ZephyrColors.bgCard,
                        onSelected: (val) => setState(() => _sortBy = val),
                        itemBuilder: (context) => [
                          _buildSortMenuItem('date_added', 'Recently Added'),
                          _buildSortMenuItem('title', 'Title'),
                          _buildSortMenuItem('artist', 'Artist'),
                          _buildSortMenuItem('duration', 'Duration'),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
          ),

          // Main Track List or Empty States
          if (libraryState.favoritesLoading && rawFavorites.isEmpty)
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) => const TrackTileSkeleton(),
                  childCount: 12,
                ),
              ),
            )
          else if (processedFavorites.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: const BoxDecoration(
                          color: ZephyrColors.bgCard,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.favorite_border, size: 48, color: ZephyrColors.textDim),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _searchQuery.isNotEmpty ? 'No songs match "$_searchQuery"' : 'No favorite songs yet',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: ZephyrColors.text),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _searchQuery.isNotEmpty
                            ? 'Try searching for something else.'
                            : 'Tap the heart icon on any song to add it to your Liked Songs.',
                        style: const TextStyle(color: ZephyrColors.textDim, fontSize: 13),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              sliver: SliverFixedExtentList(
                itemExtent: 64.0,
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    if (index < processedFavorites.length) {
                      final track = processedFavorites[index];
                      return TrackTile(
                        key: ValueKey(track.videoId),
                        track: track,
                        queue: processedFavorites,
                        showFavoriteButton: false,
                        showDownloadIndicator: true,
                      );
                    }

                    if (libraryState.favoritesLoading) {
                      return const TrackTileSkeleton();
                    }

                    return const SizedBox.shrink();
                  },
                  childCount: processedFavorites.length +
                      (libraryState.favoritesLoading ? 1 : 0),
                ),
              ),
            ),
        ],
      ),
    ),
    if (processedFavorites.isNotEmpty)
      ValueListenableBuilder<_ScrollBubbleData>(
        valueListenable: _bubbleNotifier,
        builder: (context, data, _) {
          return Positioned(
            right: 28,
            top: data.top,
            child: IgnorePointer(
              child: AnimatedOpacity(
                opacity: data.show ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 150),
                curve: Curves.easeOut,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F172A).withValues(alpha: 0.94),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: ZephyrColors.primary.withValues(alpha: 0.5),
                      width: 1.2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.5),
                        blurRadius: 14,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        data.sortBy == 'date_added'
                            ? Icons.calendar_today_rounded
                            : (data.sortBy == 'duration'
                                ? Icons.timer_outlined
                                : Icons.sort_by_alpha_rounded),
                        size: 13,
                        color: ZephyrColors.primary,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        data.text,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 12.5,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    ],
  ),
),
);
},
),
);
  }

  Widget _buildArtworkCard({required bool isMobile}) {
    final double cardSize = isMobile ? 110 : 140;
    final double iconSize = isMobile ? 48 : 64;

    return Container(
      width: cardSize,
      height: cardSize,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFFF59E0B), // Amber 500
            Color(0xFFB45309), // Dark Amber 700
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFF59E0B).withValues(alpha: 0.35),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Center(
        child: Icon(Icons.favorite, size: iconSize, color: Colors.white),
      ),
    );
  }

  Widget _buildHeaderDetails(String username, {required bool isMobile, required int totalCount}) {
    final countLabel = '$totalCount ${totalCount == 1 ? 'song' : 'songs'}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Text(
          'PLAYLIST',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
            color: ZephyrColors.textDim,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Liked Songs',
          style: TextStyle(
            fontSize: isMobile ? 24 : 32,
            fontWeight: FontWeight.bold,
            color: ZephyrColors.text,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            const CircleAvatar(
              radius: 10,
              backgroundColor: ZephyrColors.primary,
              child: Icon(Icons.person, size: 12, color: Colors.black),
            ),
            const SizedBox(width: 6),
            Text(
              username,
              style: const TextStyle(color: ZephyrColors.text, fontWeight: FontWeight.bold, fontSize: 13),
            ),
            Text(
              ' • $countLabel',
              style: const TextStyle(color: ZephyrColors.textDim, fontSize: 13),
            ),
          ],
        ),
      ],
    );
  }

  PopupMenuItem<String> _buildSortMenuItem(String value, String label) {
    final isSelected = _sortBy == value;
    return PopupMenuItem<String>(
      value: value,
      child: Row(
        children: [
          Icon(
            isSelected ? Icons.check : Icons.circle_outlined,
            size: 16,
            color: isSelected ? ZephyrColors.primary : Colors.transparent,
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              color: isSelected ? ZephyrColors.primary : ZephyrColors.text,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }
}
