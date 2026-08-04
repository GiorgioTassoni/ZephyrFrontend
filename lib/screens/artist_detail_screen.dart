import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../api/zephyr_api.dart';
import '../models/models.dart';
import '../providers/navigation_provider.dart';
import '../providers/library_provider.dart';
import '../theme/colors.dart';
import '../widgets/album_card.dart';
import '../widgets/track_tile.dart';

class ArtistDetailScreen extends ConsumerStatefulWidget {
  final String channelId;

  const ArtistDetailScreen({super.key, required this.channelId});

  @override
  ConsumerState<ArtistDetailScreen> createState() => _ArtistDetailScreenState();
}

class _ArtistDetailScreenState extends ConsumerState<ArtistDetailScreen> {
  final _api = ZephyrApi();
  Artist? _artist;
  bool _isLoading = true;
  String? _error;
  bool _showAllAlbums = false;
  bool _showAllSingles = false;

  @override
  void initState() {
    super.initState();
    _fetchArtistDetails();
  }

  Future<void> _fetchArtistDetails() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final details = await _api.getArtistDetail(widget.channelId);
      setState(() {
        _artist = details;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(libraryProvider);
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: ZephyrColors.primary));
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('Error: $_error', style: const TextStyle(color: ZephyrColors.error)),
            const SizedBox(height: 16),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: ZephyrColors.primary),
              onPressed: _fetchArtistDetails,
              child: const Text('Retry', style: TextStyle(color: Colors.black)),
            ),
          ],
        ),
      );
    }

    if (_artist == null) {
      return const Center(child: Text('Artist not found'));
    }

    final topSongs = _artist!.topSongs ?? [];
    final albums = _artist!.albums ?? [];
    final singles = _artist!.singles ?? [];
    final navNotifier = ref.read(navigationProvider.notifier);

    return Scaffold(
      backgroundColor: ZephyrColors.bgDark,
      body: RefreshIndicator(
        onRefresh: _fetchArtistDetails,
        color: ZephyrColors.primary,
        backgroundColor: ZephyrColors.bgCard,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Banner header
              Stack(
                children: [
                  Container(
                    height: 280,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      image: _artist!.coverUrl != null && _artist!.coverUrl!.isNotEmpty
                          ? DecorationImage(
                              image: NetworkImage(
                                _artist!.coverUrl!.startsWith('/')
                                    ? '${_api.baseUrl}${_artist!.coverUrl!}'
                                    : _artist!.coverUrl!,
                              ),
                              fit: BoxFit.cover,
                              colorFilter: ColorFilter.mode(
                                Colors.black.withOpacity(0.5),
                                BlendMode.multiply,
                              ),
                            )
                          : null,
                      color: ZephyrColors.bgCard,
                    ),
                  ),
                  Positioned(
                    bottom: 24,
                    left: 32,
                    right: 32,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.verified, color: Colors.blue, size: 20),
                            const SizedBox(width: 8),
                            const Text(
                              'Verified Artist',
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _artist!.name,
                          style: const TextStyle(
                            fontSize: 48,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            letterSpacing: -1.5,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            if (_artist!.fans != null) ...[
                              Text(
                                '${_artist!.fans} fans',
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                              ),
                              const SizedBox(width: 16),
                            ] else if (_artist!.monthlyListeners != null) ...[
                              Text(
                                '${_artist!.monthlyListeners} monthly listeners',
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                              ),
                              const SizedBox(width: 16),
                            ],
                            if (_artist!.albumCount != null) ...[
                              Text(
                                '${_artist!.albumCount} albums',
                                style: const TextStyle(color: ZephyrColors.textDim),
                              ),
                            ] else if (_artist!.subscribers != null) ...[
                              Text(
                                '${_artist!.subscribers} subscribers',
                                style: const TextStyle(color: ZephyrColors.textDim),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32.0, vertical: 24.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Top Songs Section
                    if (topSongs.isNotEmpty) ...[
                      const Text(
                        'Popular',
                        style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: ZephyrColors.text),
                      ),
                      const SizedBox(height: 16),
                      ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: topSongs.length.clamp(0, 5),
                        itemBuilder: (context, index) {
                          final track = topSongs[index];
                          return Row(
                            children: [
                              SizedBox(
                                width: 32,
                                child: Text(
                                  '${index + 1}',
                                  style: const TextStyle(color: ZephyrColors.textDim),
                                ),
                              ),
                              Expanded(
                                child: TrackTile(track: track, queue: topSongs),
                              ),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 40),
                    ],

                    // Albums Section
                    if (albums.isNotEmpty) ...[
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          const Text(
                            'Albums',
                            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: ZephyrColors.text),
                          ),
                          if (albums.length > 5)
                            TextButton(
                              onPressed: () => setState(() => _showAllAlbums = !_showAllAlbums),
                              child: Text(
                                _showAllAlbums ? 'Show Less' : 'Show All (${albums.length})',
                                style: const TextStyle(color: ZephyrColors.primary, fontWeight: FontWeight.w600),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _showAllAlbums ? albums.length : albums.length.clamp(0, 5),
                        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 200,
                          crossAxisSpacing: 16,
                          mainAxisSpacing: 16,
                          childAspectRatio: 0.75,
                        ),
                        itemBuilder: (context, index) {
                          final album = albums[index];
                          return AlbumCard(
                            album: album,
                            onTap: () {
                              navNotifier.navigateTo(ScreenState(type: ScreenType.album, id: album.id));
                            },
                          );
                        },
                      ),
                      const SizedBox(height: 40),
                    ],

                    // Singles Section
                    if (singles.isNotEmpty) ...[
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          const Text(
                            'Singles & EPs',
                            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: ZephyrColors.text),
                          ),
                          if (singles.length > 5)
                            TextButton(
                              onPressed: () => setState(() => _showAllSingles = !_showAllSingles),
                              child: Text(
                                _showAllSingles ? 'Show Less' : 'Show All (${singles.length})',
                                style: const TextStyle(color: ZephyrColors.primary, fontWeight: FontWeight.w600),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _showAllSingles ? singles.length : singles.length.clamp(0, 5),
                        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 200,
                          crossAxisSpacing: 16,
                          mainAxisSpacing: 16,
                          childAspectRatio: 0.75,
                        ),
                        itemBuilder: (context, index) {
                          final single = singles[index];
                          return AlbumCard(
                            album: single,
                            onTap: () {
                              navNotifier.navigateTo(ScreenState(type: ScreenType.album, id: single.id));
                            },
                          );
                        },
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
