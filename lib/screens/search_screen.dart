import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../api/zephyr_api.dart';
import '../models/models.dart';
import '../providers/auth_provider.dart';
import '../providers/library_provider.dart';
import '../providers/navigation_provider.dart';
import '../providers/search_provider.dart';
import '../theme/colors.dart';
import '../theme/zephyr_theme.dart';
import '../widgets/cover_image.dart';
import '../widgets/track_tile.dart';
import '../widgets/toast.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _searchController = TextEditingController();
  final _api = ZephyrApi();
  
  Timer? _debounceTimer;
  bool _isLoading = false;
  String _remoteSource = 'none';
  String _lastQuery = '';
  
  List<Track> _tracks = [];
  List<Track> _videos = [];
  List<Album> _albums = [];
  List<Artist> _artists = [];
  List<Playlist> _playlists = [];
  String? _errorMessage;

  @override
  void dispose() {
    _searchController.dispose();
    _debounceTimer?.cancel();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    _debounceTimer?.cancel();
    final cleanQuery = query.trim();
    if (cleanQuery.length < 2) {
      setState(() {
        _tracks = [];
        _videos = [];
        _albums = [];
        _artists = [];
        _playlists = [];
        _isLoading = false;
        _remoteSource = 'none';
        _errorMessage = null;
        _lastQuery = cleanQuery;
      });
      return;
    }

    if (cleanQuery == _lastQuery) return;

    _debounceTimer = Timer(const Duration(milliseconds: 500), () {
      _performSearch(cleanQuery, forceRemote: false);
    });
  }

  Future<void> _performSearch(String query, {required bool forceRemote}) async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _lastQuery = query;
    });

    try {
      final res = await _api.search(query, remote: forceRemote);
      final results = res['results'] ?? {};
      
      final List rawTracks = results['tracks'] ?? [];
      final List rawVideos = results['video'] ?? [];
      final List rawAlbums = results['albums'] ?? [];
      final List rawArtists = results['artists'] ?? [];
      final List rawPlaylists = results['playlists'] ?? [];

      final remoteSrc = (res['remote_source'] ?? 'none').toString();
 
      setState(() {
        _tracks = rawTracks.map((e) => Track.fromJson(Map<String, dynamic>.from(e))).toList();
        _videos = rawVideos.map((e) => Track.fromJson(Map<String, dynamic>.from(e))).toList();
        _albums = rawAlbums.map((e) => Album.fromJson(Map<String, dynamic>.from(e))).toList();
        _artists = rawArtists.map((e) => Artist.fromJson(Map<String, dynamic>.from(e))).toList();
        _playlists = rawPlaylists.map((e) => Playlist.fromJson(Map<String, dynamic>.from(e))).toList();
        _remoteSource = remoteSrc;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final navNotifier = ref.read(navigationProvider.notifier);
    final query = ref.watch(searchQueryProvider);

    // Sync local query and fetch results when top bar query updates
    final cleanQuery = query.trim();
    if (cleanQuery != _lastQuery) {
      _searchController.text = query;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _onSearchChanged(query);
        }
      });
    }

    final isMobile = MediaQuery.of(context).size.width < 700;

    return Scaffold(
      backgroundColor: ZephyrColors.bgDark,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isMobile)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Container(
                height: 44,
                decoration: BoxDecoration(
                  color: ZephyrColors.bgCard,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: ZephyrColors.bgLight.withValues(alpha: 0.6)),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Row(
                  children: [
                    const Icon(Icons.search, color: ZephyrColors.textDim, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        autofocus: false,
                        style: const TextStyle(color: ZephyrColors.text, fontSize: 14),
                        onChanged: (val) {
                          ref.read(searchQueryProvider.notifier).setQuery(val);
                          _onSearchChanged(val);
                        },
                        decoration: const InputDecoration(
                          hintText: 'What do you want to listen to?',
                          hintStyle: TextStyle(color: ZephyrColors.textDim, fontSize: 14),
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    ),
                    if (_searchController.text.isNotEmpty)
                      IconButton(
                        icon: const Icon(Icons.clear, color: ZephyrColors.textDim, size: 18),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        onPressed: () {
                          _searchController.clear();
                          ref.read(searchQueryProvider.notifier).setQuery('');
                          _onSearchChanged('');
                        },
                      ),
                  ],
                ),
              ),
            ),
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: ZephyrColors.primary),
                  )
                : _errorMessage != null
                    ? Center(
                        child: Text(
                          _errorMessage!,
                          style: const TextStyle(color: ZephyrColors.error, fontSize: 16),
                        ),
                      )
                    : _searchController.text.trim().isEmpty
                        ? _buildBrowseCategories()
                        : _buildSearchResults(navNotifier),
          ),
        ],
      ),
    );
  }

  // Categories shown when search field is empty (matching unfilled search page)
  Widget _buildBrowseCategories() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            Icon(Icons.music_note, size: 64, color: ZephyrColors.textDim),
            SizedBox(height: 16),
            Text(
              'Search for songs, albums, or artists',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: ZephyrColors.text,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'Results are searched locally first, falling back to Deezer discovery.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: ZephyrColors.textDim,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchResults(NavigationNotifier navNotifier) {
    if (_tracks.isEmpty && _videos.isEmpty && _albums.isEmpty && _artists.isEmpty && _playlists.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'No results found.',
              style: TextStyle(color: ZephyrColors.textDim, fontSize: 16),
            ),
            const SizedBox(height: 16),
            if (_remoteSource == 'none')
              ElevatedButton.icon(
                icon: const Icon(Icons.cloud_download_rounded, size: 18),
                label: const Text('Search on Deezer'),
                style: ZephyrTheme.primaryPillStyle(),
                onPressed: () => _performSearch(_lastQuery, forceRemote: true),
              ),
          ],
        ),
      );
    }

    final isMobile = MediaQuery.of(context).size.width < 700;
    final showOnlinePrompt = _remoteSource == 'none';

    return ListView(
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 14 : 32,
        vertical: isMobile ? 12 : 24,
      ),
      children: [
        if (showOnlinePrompt) ...[
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: ZephyrColors.bgCard,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: ZephyrColors.primary.withValues(alpha: 0.4)),
            ),
            child: isMobile
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.library_music_rounded, color: ZephyrColors.primary, size: 18),
                          SizedBox(width: 8),
                          Text(
                            'Local Library Results',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.white),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Showing results from your local library. Click below to discover songs & artists on Deezer.',
                        style: TextStyle(fontSize: 12, color: ZephyrColors.textDim),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.public_rounded, size: 16),
                          label: const Text('Search Online on Deezer'),
                          style: ZephyrTheme.primaryPillStyle(),
                          onPressed: () => _performSearch(_lastQuery, forceRemote: true),
                        ),
                      ),
                    ],
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.library_music_rounded, color: ZephyrColors.primary, size: 18),
                                SizedBox(width: 8),
                                Text(
                                  'Local Library Results',
                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.white),
                                ),
                              ],
                            ),
                            SizedBox(height: 4),
                            Text(
                              'Showing results from your local library. Click "Search Online" to discover songs & artists on Deezer.',
                              style: TextStyle(fontSize: 12, color: ZephyrColors.textDim),
                            ),
                          ],
                        ),
                      ),
                      ElevatedButton.icon(
                        icon: const Icon(Icons.public_rounded, size: 16),
                        label: const Text('Search Online'),
                        style: ZephyrTheme.primaryPillStyle(),
                        onPressed: () => _performSearch(_lastQuery, forceRemote: true),
                      ),
                    ],
                  ),
          ),
          const SizedBox(height: 24),
        ],

        // Tracks section
        if (_tracks.isNotEmpty) ...[
          const Text(
            'Songs',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _tracks.length,
            itemBuilder: (context, index) {
              return TrackTile(
                track: _tracks[index],
                queue: [_tracks[index]],
                origin: 'search',
              );
            },
          ),
          const SizedBox(height: 24),
        ],

        // Videos section
        if (_videos.isNotEmpty) ...[
          const Text(
            'Videos',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _videos.length,
            itemBuilder: (context, index) {
              return TrackTile(
                track: _videos[index],
                queue: [_videos[index]],
                origin: 'search',
              );
            },
          ),
          const SizedBox(height: 24),
        ],

        // Albums Section
        if (_albums.isNotEmpty) ...[
          const Text(
            'Albums',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 72,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _albums.length,
              itemBuilder: (context, index) {
                final album = _albums[index];
                return _SearchAlbumCard(
                  album: album,
                  onTap: () {
                    navNotifier.navigateTo(ScreenState(type: ScreenType.album, id: album.id));
                  },
                );
              },
            ),
          ),
          const SizedBox(height: 24),
        ],

        // Artists Section
        if (_artists.isNotEmpty) ...[
          const Text(
            'Artists',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 72,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _artists.length,
              itemBuilder: (context, index) {
                final artist = _artists[index];
                return _SearchArtistCard(
                  artist: artist,
                  onTap: () {
                    navNotifier.navigateTo(ScreenState(type: ScreenType.artist, id: artist.channelId));
                  },
                );
              },
            ),
          ),
          const SizedBox(height: 24),
        ],

        // Playlists Section
        if (_playlists.isNotEmpty) ...[
          const Text(
            'Playlists',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 72,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _playlists.length,
              itemBuilder: (context, index) {
                final playlist = _playlists[index];
                return _SearchPlaylistCard(
                  playlist: playlist,
                  onTap: () {
                    navNotifier.navigateTo(ScreenState(type: ScreenType.playlist, id: playlist.id.toString()));
                  },
                );
              },
            ),
          ),
          const SizedBox(height: 16),
        ],
        const SizedBox(height: 80),
      ],
    );
  }
}

class _SearchAlbumCard extends StatefulWidget {
  final Album album;
  final VoidCallback onTap;

  const _SearchAlbumCard({required this.album, required this.onTap});

  @override
  State<_SearchAlbumCard> createState() => _SearchAlbumCardState();
}

class _SearchAlbumCardState extends State<_SearchAlbumCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 280,
        margin: const EdgeInsets.only(right: 16),
        decoration: BoxDecoration(
          color: _isHovered ? ZephyrColors.bgLight.withValues(alpha: 0.5) : ZephyrColors.bgCard,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: ZephyrColors.bgLight.withValues(alpha: 0.3),
            width: 1.0,
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: widget.onTap,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                CoverImage(coverUrl: widget.album.coverUrl, size: 56, borderRadius: 6),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.album.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        widget.album.artists.join(', '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12, color: ZephyrColors.textDim),
                      ),
                    ],
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

class _SearchArtistCard extends StatefulWidget {
  final Artist artist;
  final VoidCallback onTap;

  const _SearchArtistCard({required this.artist, required this.onTap});

  @override
  State<_SearchArtistCard> createState() => _SearchArtistCardState();
}

class _SearchArtistCardState extends State<_SearchArtistCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 220,
        margin: const EdgeInsets.only(right: 16),
        decoration: BoxDecoration(
          color: _isHovered ? ZephyrColors.bgLight.withValues(alpha: 0.5) : ZephyrColors.bgCard,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: ZephyrColors.bgLight.withValues(alpha: 0.3),
            width: 1.0,
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: widget.onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                CoverImage(
                  coverUrl: widget.artist.coverUrl,
                  size: 48,
                  borderRadius: 24,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    widget.artist.name,
                    overflow: TextOverflow.ellipsis,
                    maxLines: 2,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: ZephyrColors.text,
                    ),
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

class _SearchPlaylistCard extends ConsumerStatefulWidget {
  final Playlist playlist;
  final VoidCallback onTap;

  const _SearchPlaylistCard({required this.playlist, required this.onTap});

  @override
  ConsumerState<_SearchPlaylistCard> createState() => _SearchPlaylistCardState();
}

class _SearchPlaylistCardState extends ConsumerState<_SearchPlaylistCard> {
  bool _isHovered = false;

  Future<void> _toggleSave(bool isCurrentlySaved) async {
    final libNotifier = ref.read(libraryProvider.notifier);
    try {
      if (isCurrentlySaved) {
        await libNotifier.unsavePlaylist(widget.playlist.id);
        if (mounted) ZephyrToast.show(context, 'Playlist removed from your library');
      } else {
        await libNotifier.savePlaylist(widget.playlist.id);
        if (mounted) ZephyrToast.show(context, 'Playlist saved to your library');
      }
    } catch (e) {
      if (mounted) ZephyrToast.show(context, 'Failed: $e', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    final currentUsername = authState.username;
    final libraryState = ref.watch(libraryProvider);

    final bool isInUserLibrary = libraryState.playlists.any(
      (p) => p.id.toString() == widget.playlist.id.toString(),
    );
    final bool isSaved = widget.playlist.isSaved || isInUserLibrary;

    final bool isOwner = widget.playlist.isOwner &&
        (currentUsername == null || widget.playlist.ownerName == null || widget.playlist.ownerName!.isEmpty || widget.playlist.ownerName == currentUsername);
    final bool isLocalZephyrPlaylist = !widget.playlist.id.toString().startsWith('dz_');

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 280,
        margin: const EdgeInsets.only(right: 16),
        decoration: BoxDecoration(
          color: _isHovered ? ZephyrColors.bgLight.withValues(alpha: 0.5) : ZephyrColors.bgCard,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: ZephyrColors.bgLight.withValues(alpha: 0.3),
            width: 1.0,
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: widget.onTap,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                CoverImage(
                  coverUrl: widget.playlist.coverUrl,
                  playlistId: widget.playlist.id,
                  size: 56,
                  borderRadius: 6,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.playlist.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        !isOwner && widget.playlist.ownerName != null && widget.playlist.ownerName!.isNotEmpty
                            ? 'by ${widget.playlist.ownerName}'
                            : (widget.playlist.ownerName ?? 'Deezer'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12, color: ZephyrColors.textDim),
                      ),
                    ],
                  ),
                ),
                if (isLocalZephyrPlaylist && !isOwner) ...[
                  IconButton(
                    icon: Icon(
                      isSaved ? Icons.bookmark_added_rounded : Icons.bookmark_add_outlined,
                      size: 20,
                      color: isSaved ? ZephyrColors.primary : ZephyrColors.textDim,
                    ),
                    onPressed: () => _toggleSave(isSaved),
                    tooltip: isSaved ? 'Remove from Library' : 'Save to Library',
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
