import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../api/zephyr_api.dart';
import '../models/models.dart';
import '../providers/auth_provider.dart';
import '../providers/library_provider.dart';
import '../providers/navigation_provider.dart';
import '../providers/player_provider.dart';
import '../theme/colors.dart';
import '../widgets/cover_image.dart';
import '../widgets/artist_links.dart';
import '../widgets/toast.dart';

class FavoritesScreen extends ConsumerStatefulWidget {
  const FavoritesScreen({super.key});

  @override
  ConsumerState<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends ConsumerState<FavoritesScreen> {
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String _sortBy = 'date_added'; // 'date_added' | 'title' | 'artist' | 'duration'
  bool _isSearchVisible = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    Future.microtask(() => ref.read(libraryProvider.notifier).loadFavorites());
  }

  @override
  void dispose() {
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
        // Preserves server order (most recently favorited first)
        break;
    }

    return list;
  }

  String _formatTotalDuration(List<Track> tracks) {
    int totalSeconds = 0;
    for (final t in tracks) {
      if (t.duration != null) {
        totalSeconds += t.duration!.inSeconds;
      }
    }
    if (totalSeconds == 0) return '';
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    if (hours > 0) {
      return ' • $hours hr $minutes min';
    } else if (minutes > 0) {
      return ' • $minutes min';
    }
    return '';
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

    return Scaffold(
      backgroundColor: ZephyrColors.bgDark,
      body: CustomScrollView(
        controller: _scrollController,
        slivers: [
          // Hero Banner Header
          SliverToBoxAdapter(
            child: Container(
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
              padding: const EdgeInsets.only(left: 32, right: 32, top: 24, bottom: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Top Navigation Back Button
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
                    ],
                  ),
                  const SizedBox(height: 16),
                  // Hero Content Row
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final isMobile = constraints.maxWidth < 600;
                      return isMobile
                          ? Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _buildArtworkCard(),
                                const SizedBox(height: 20),
                                _buildHeaderDetails(username, rawFavorites),
                              ],
                            )
                          : Row(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                _buildArtworkCard(),
                                const SizedBox(width: 28),
                                Expanded(
                                  child: _buildHeaderDetails(username, rawFavorites),
                                ),
                              ],
                            );
                    },
                  ),
                ],
              ),
            ),
          ),

          // Action Bar (Play, Shuffle, Search, Sort)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
              child: Row(
                children: [
                  // Big Green Play Button
                  Material(
                    color: ZephyrColors.primary,
                    shape: const CircleBorder(),
                    elevation: 6,
                    shadowColor: ZephyrColors.primary.withValues(alpha: 0.4),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: processedFavorites.isNotEmpty
                          ? () => playerNotifier.playTrack(processedFavorites.first, processedFavorites)
                          : null,
                      child: const SizedBox(
                        width: 56,
                        height: 56,
                        child: Center(
                          child: Icon(Icons.play_arrow, color: Colors.black, size: 34),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),

                  // Shuffle Button
                  IconButton(
                    icon: Icon(
                      Icons.shuffle,
                      color: playerState.isShuffled ? ZephyrColors.primary : ZephyrColors.textDim,
                      size: 28,
                    ),
                    tooltip: 'Shuffle Play',
                    onPressed: processedFavorites.isNotEmpty
                        ? () {
                            if (!playerState.isShuffled) {
                              playerNotifier.toggleShuffle();
                            }
                            playerNotifier.playTrack(processedFavorites.first, processedFavorites);
                          }
                        : null,
                  ),
                  const Spacer(),

                  // Search Filter Toggle & Input
                  if (_isSearchVisible)
                    Container(
                      width: 220,
                      height: 38,
                      margin: const EdgeInsets.only(right: 12),
                      child: TextField(
                        controller: _searchController,
                        autofocus: true,
                        style: const TextStyle(color: ZephyrColors.text, fontSize: 13),
                        decoration: InputDecoration(
                          hintText: 'Search in Liked Songs',
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
                          contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 12),
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
            ),
          ),

          // Table Header Bar (Desktop & Wide view)
          SliverToBoxAdapter(
            child: LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxWidth < 600) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 8),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          const SizedBox(
                            width: 40,
                            child: Text(
                              '#',
                              style: TextStyle(color: ZephyrColors.textMuted, fontSize: 12, fontWeight: FontWeight.bold),
                            ),
                          ),
                          const Expanded(
                            flex: 4,
                            child: Text(
                              'TITLE',
                              style: TextStyle(color: ZephyrColors.textMuted, fontSize: 12, fontWeight: FontWeight.bold),
                            ),
                          ),
                          const Expanded(
                            flex: 3,
                            child: Text(
                              'ALBUM',
                              style: TextStyle(color: ZephyrColors.textMuted, fontSize: 12, fontWeight: FontWeight.bold),
                            ),
                          ),
                          const SizedBox(
                            width: 80,
                            child: Align(
                              alignment: Alignment.centerRight,
                              child: Icon(Icons.access_time_rounded, size: 16, color: ZephyrColors.textMuted),
                            ),
                          ),
                          const SizedBox(width: 80), // for heart + menu
                        ],
                      ),
                      const SizedBox(height: 8),
                      const Divider(color: ZephyrColors.bgLight, height: 1),
                    ],
                  ),
                );
              },
            ),
          ),

          // Main Track List or States
          if (libraryState.favoritesLoading && rawFavorites.isEmpty)
            const SliverFillRemaining(
              child: Center(
                child: CircularProgressIndicator(color: ZephyrColors.primary),
              ),
            )
          else if (processedFavorites.isEmpty)
            SliverFillRemaining(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: const BoxDecoration(
                        color: ZephyrColors.bgCard,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.favorite_border, size: 64, color: ZephyrColors.textDim),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      _searchQuery.isNotEmpty ? 'No songs match "$_searchQuery"' : 'No favorite songs yet',
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: ZephyrColors.text),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _searchQuery.isNotEmpty
                          ? 'Try searching for something else.'
                          : 'Tap the heart icon on any song to add it to your Liked Songs.',
                      style: const TextStyle(color: ZephyrColors.textDim, fontSize: 14),
                    ),
                  ],
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    if (index == processedFavorites.length) {
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
                      if (!libraryState.hasMoreFavorites && rawFavorites.length > 15) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 24),
                          child: Center(
                            child: Text(
                              '${rawFavorites.length} songs loaded',
                              style: const TextStyle(color: ZephyrColors.textMuted, fontSize: 12),
                            ),
                          ),
                        );
                      }
                      return const SizedBox.shrink();
                    }

                    final track = processedFavorites[index];
                    final isCurrent = playerState.currentTrack?.videoId == track.videoId;

                    return _FavoriteTrackRow(
                      index: index + 1,
                      track: track,
                      queue: processedFavorites,
                      isCurrent: isCurrent,
                      isPlaying: isCurrent && playerState.isPlaying,
                    );
                  },
                  childCount: processedFavorites.length + 1,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildArtworkCard() {
    return Container(
      width: 180,
      height: 180,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
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
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: const Center(
        child: Icon(Icons.favorite, size: 80, color: Colors.white),
      ),
    );
  }

  Widget _buildHeaderDetails(String username, List<Track> favorites) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        const Text(
          'PLAYLIST',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.5,
            color: ZephyrColors.textDim,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Liked Songs',
          style: TextStyle(
            fontSize: 44,
            fontWeight: FontWeight.w800,
            color: ZephyrColors.text,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            const CircleAvatar(
              radius: 12,
              backgroundColor: ZephyrColors.primary,
              child: Icon(Icons.person, size: 14, color: Colors.black),
            ),
            const SizedBox(width: 8),
            Text(
              username,
              style: const TextStyle(color: ZephyrColors.text, fontWeight: FontWeight.bold, fontSize: 14),
            ),
            Text(
              ' • ${favorites.length} songs${_formatTotalDuration(favorites)}',
              style: const TextStyle(color: ZephyrColors.textDim, fontSize: 14),
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

class _FavoriteTrackRow extends ConsumerStatefulWidget {
  final int index;
  final Track track;
  final List<Track> queue;
  final bool isCurrent;
  final bool isPlaying;

  const _FavoriteTrackRow({
    required this.index,
    required this.track,
    required this.queue,
    required this.isCurrent,
    required this.isPlaying,
  });

  @override
  ConsumerState<_FavoriteTrackRow> createState() => _FavoriteTrackRowState();
}

class _FavoriteTrackRowState extends ConsumerState<_FavoriteTrackRow> {
  bool _isHovered = false;

  String _formatDuration(Duration? duration) {
    if (duration == null) return '--:--';
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final navNotifier = ref.read(navigationProvider.notifier);
    final playerNotifier = ref.read(playerProvider.notifier);
    final libraryNotifier = ref.read(libraryProvider.notifier);

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: Container(
        height: 56,
        margin: const EdgeInsets.symmetric(vertical: 2),
        decoration: BoxDecoration(
          color: _isHovered
              ? ZephyrColors.bgLight.withValues(alpha: 0.25)
              : (widget.isCurrent ? ZephyrColors.bgCard.withValues(alpha: 0.5) : Colors.transparent),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => playerNotifier.playTrack(widget.track, widget.queue),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final isCompact = constraints.maxWidth < 600;

                  return Row(
                    children: [
                      // Index / Play Icon
                      SizedBox(
                        width: 32,
                        child: Center(
                          child: _isHovered
                              ? Icon(
                                  widget.isPlaying ? Icons.pause : Icons.play_arrow,
                                  color: ZephyrColors.primary,
                                  size: 20,
                                )
                              : (widget.isCurrent
                                  ? const Icon(Icons.volume_up, color: ZephyrColors.primary, size: 18)
                                  : Text(
                                      '${widget.index}',
                                      style: const TextStyle(color: ZephyrColors.textDim, fontSize: 13),
                                    )),
                        ),
                      ),
                      const SizedBox(width: 8),

                      // Cover Thumbnail
                      CoverImage(
                        videoId: widget.track.videoId,
                        coverUrl: widget.track.coverUrl,
                        isDownloaded: widget.track.isDownloaded,
                        size: 40,
                        borderRadius: 6,
                      ),
                      const SizedBox(width: 12),

                      // Title & Artist
                      Expanded(
                        flex: 4,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.track.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: widget.isCurrent ? ZephyrColors.primary : ZephyrColors.text,
                              ),
                            ),
                            const SizedBox(height: 2),
                            ArtistLinks(
                              track: widget.track,
                              style: const TextStyle(
                                fontSize: 12,
                                color: ZephyrColors.textDim,
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Album Name (Wide screens only)
                      if (!isCompact)
                        Expanded(
                          flex: 3,
                          child: InkWell(
                            onTap: widget.track.albumId != null && widget.track.albumId!.isNotEmpty
                                ? () => navNotifier.navigateTo(ScreenState(type: ScreenType.album, id: widget.track.albumId!))
                                : null,
                            child: Text(
                              widget.track.album ?? '',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 13,
                                color: ZephyrColors.textDim,
                              ),
                            ),
                          ),
                        ),

                      // Duration
                      SizedBox(
                        width: 60,
                        child: Text(
                          _formatDuration(widget.track.duration),
                          textAlign: TextAlign.right,
                          style: const TextStyle(color: ZephyrColors.textDim, fontSize: 13),
                        ),
                      ),
                      const SizedBox(width: 12),

                      // Favorite Heart Toggle Button
                      IconButton(
                        icon: const Icon(
                          Icons.favorite,
                          color: ZephyrColors.primary,
                          size: 20,
                        ),
                        tooltip: 'Remove from favorites',
                        onPressed: () => libraryNotifier.toggleFavorite(widget.track),
                      ),

                      // Context Menu
                      PopupMenuButton<String>(
                        icon: const Icon(Icons.more_vert, color: ZephyrColors.textDim, size: 20),
                        color: ZephyrColors.bgCard,
                        onSelected: (val) {
                          if (val == 'download') {
                            ZephyrApi().queueDownload(widget.track.videoId);
                            ZephyrToast.show(context, 'Download queued for "${widget.track.title}"');
                          } else if (val.startsWith('artist_')) {
                            final channelId = val.substring('artist_'.length);
                            navNotifier.navigateTo(ScreenState(type: ScreenType.artist, id: channelId));
                          }
                        },
                        itemBuilder: (context) => [
                          if (!widget.track.isDownloaded)
                            const PopupMenuItem(
                              value: 'download',
                              child: Row(
                                children: [
                                  Icon(Icons.download, size: 18, color: ZephyrColors.textDim),
                                  SizedBox(width: 8),
                                  Text('Download Track'),
                                ],
                              ),
                            ),
                          for (int i = 0; i < widget.track.artists.length; i++)
                            if (widget.track.artistsIds.length > i && widget.track.artistsIds[i].isNotEmpty)
                              PopupMenuItem(
                                value: 'artist_${widget.track.artistsIds[i]}',
                                child: Row(
                                  children: [
                                    const Icon(Icons.person, size: 18, color: ZephyrColors.textDim),
                                    const SizedBox(width: 8),
                                    Text('Go to ${widget.track.artists[i]}'),
                                  ],
                                ),
                              ),
                        ],
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}
