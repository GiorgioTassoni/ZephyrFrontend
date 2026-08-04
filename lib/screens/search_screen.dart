import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../api/zephyr_api.dart';
import '../models/models.dart';
import '../providers/navigation_provider.dart';
import '../providers/search_provider.dart';
import '../theme/colors.dart';
import '../widgets/cover_image.dart';
import '../widgets/track_tile.dart';

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
  bool _hasRemote = false;
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
    if (cleanQuery.length < 4) {
      setState(() {
        _tracks = [];
        _videos = [];
        _albums = [];
        _artists = [];
        _playlists = [];
        _isLoading = false;
        _hasRemote = false;
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
      final hasRem = res['has_remote'] ?? false;
 
      setState(() {
        _tracks = rawTracks.map((e) => Track.fromJson(Map<String, dynamic>.from(e))).toList();
        _videos = rawVideos.map((e) => Track.fromJson(Map<String, dynamic>.from(e))).toList();
        _albums = rawAlbums.map((e) => Album.fromJson(Map<String, dynamic>.from(e))).toList();
        _artists = rawArtists.map((e) => Artist.fromJson(Map<String, dynamic>.from(e))).toList();
        _playlists = rawPlaylists.map((e) => Playlist.fromJson(Map<String, dynamic>.from(e))).toList();
        _hasRemote = hasRem;
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

    return Scaffold(
      backgroundColor: ZephyrColors.bgDark,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Search Results or Browse Categories
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
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.music_note, size: 64, color: ZephyrColors.textDim),
          SizedBox(height: 16),
          Text(
            'Search for songs, albums, or artists',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: ZephyrColors.text,
            ),
          ),
          SizedBox(height: 8),
          Text(
            'Results are searched locally first, falling back to Deezer discovery.',
            style: TextStyle(
              fontSize: 14,
              color: ZephyrColors.textDim,
            ),
          ),
        ],
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
                icon: const Icon(Icons.cloud_download, color: Colors.black),
                label: const Text('Search on Deezer', style: TextStyle(color: Colors.black)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: ZephyrColors.primary,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                ),
                onPressed: () => _performSearch(_lastQuery, forceRemote: true),
              ),
          ],
        ),
      );
    }

    // Only show prompt banner if remote discovery was NOT executed yet and local-only results exist
    final showOnlinePrompt = _remoteSource == 'none' && _hasRemote;

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      children: [
        if (showOnlinePrompt) ...[
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: ZephyrColors.bgCard,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: ZephyrColors.primary.withOpacity(0.3)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Deezer Discovery',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Matches were found in your local library. Click here to fetch additional tracks online via Deezer.',
                        style: TextStyle(fontSize: 12, color: ZephyrColors.textDim),
                      ),
                    ],
                  ),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: ZephyrColors.primary,
                    foregroundColor: Colors.black,
                  ),
                  onPressed: () => _performSearch(_lastQuery, forceRemote: true),
                  child: const Text('Search Online'),
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
              return TrackTile(track: _tracks[index], queue: [_tracks[index]]);
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
              return TrackTile(track: _videos[index], queue: [_videos[index]]);
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
            height: 140,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _albums.length,
              itemBuilder: (context, index) {
                final album = _albums[index];
                return Container(
                  width: 320,
                  margin: const EdgeInsets.only(right: 16),
                  child: Material(
                    type: MaterialType.transparency,
                    child: ListTile(
                      leading: CoverImage(coverUrl: album.coverUrl, size: 50),
                      title: Text(album.name, overflow: TextOverflow.ellipsis),
                      subtitle: Text(album.artists.join(', '), overflow: TextOverflow.ellipsis),
                      tileColor: ZephyrColors.bgCard,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      onTap: () {
                        navNotifier.navigateTo(ScreenState(type: ScreenType.album, id: album.id));
                      },
                    ),
                  ),
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
                return Container(
                  width: 220,
                  margin: const EdgeInsets.only(right: 16),
                  decoration: BoxDecoration(
                    color: ZephyrColors.bgCard,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Material(
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () {
                        navNotifier.navigateTo(ScreenState(type: ScreenType.artist, id: artist.channelId));
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            CoverImage(
                              coverUrl: artist.coverUrl,
                              size: 48,
                              borderRadius: 24,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                artist.name,
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
            height: 140,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _playlists.length,
              itemBuilder: (context, index) {
                final playlist = _playlists[index];
                return Container(
                  width: 320,
                  margin: const EdgeInsets.only(right: 16),
                  child: Material(
                    color: ZephyrColors.bgCard,
                    borderRadius: BorderRadius.circular(8),
                    clipBehavior: Clip.antiAlias,
                    child: ListTile(
                      leading: CoverImage(coverUrl: playlist.coverUrl, playlistId: playlist.id, size: 50),
                      title: Text(playlist.name, overflow: TextOverflow.ellipsis),
                      subtitle: Text(playlist.ownerName ?? 'Deezer', overflow: TextOverflow.ellipsis),
                      onTap: () {
                        navNotifier.navigateTo(ScreenState(type: ScreenType.playlist, id: playlist.id.toString()));
                      },
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 24),
        ],
      ],
    );
  }
}
