import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../api/zephyr_api.dart';
import '../models/models.dart';
import '../providers/library_provider.dart';
import '../providers/player_provider.dart';
import '../theme/colors.dart';
import '../theme/zephyr_theme.dart';
import '../widgets/cover_image.dart';
import '../widgets/track_tile.dart';
import '../widgets/toast.dart';

class AlbumDetailScreen extends ConsumerStatefulWidget {
  final String browseId;

  const AlbumDetailScreen({super.key, required this.browseId});

  @override
  ConsumerState<AlbumDetailScreen> createState() => _AlbumDetailScreenState();
}

class _AlbumDetailScreenState extends ConsumerState<AlbumDetailScreen> {
  final _api = ZephyrApi();
  Album? _album;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchAlbumDetails(bypassCache: false);
  }

  Future<void> _fetchAlbumDetails({bool bypassCache = false}) async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final details = await _api.getAlbumDetail(widget.browseId);
      setState(() {
        _album = details;
        _isLoading = false;
      });
    } catch (e) {
      // If remote fetch fails, check local library as fallback
      try {
        final downloaded = await _api.getDownloadedTracks();
        final albumTracks = downloaded
            .where((t) =>
                t.albumId == widget.browseId ||
                (t.album != null && t.album!.isNotEmpty && t.album == widget.browseId))
            .toList();

        if (albumTracks.isNotEmpty) {
          final firstTrack = albumTracks.first;
          final localAlbum = Album(
            id: widget.browseId,
            name: firstTrack.album ?? widget.browseId,
            artists: firstTrack.artists,
            coverUrl: firstTrack.coverUrl,
            year: null,
            tracks: albumTracks,
          );

          setState(() {
            _album = localAlbum;
            _isLoading = false;
          });
          return;
        }
      } catch (_) {}

      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _downloadAllTracks() async {
    if (_album == null) return;
    try {
      final summary = await _api.downloadAlbum(widget.browseId);
      String msg = 'Album download status: ${summary.queuedForDownload} queued, ${summary.alreadyDownloaded} available';
      if (summary.needsResolution > 0) {
        msg += ', ${summary.needsResolution} need selection';
      }
      if (summary.unavailable > 0) {
        msg += ', ${summary.unavailable} unavailable';
      }

      if (mounted) {
        ZephyrToast.show(context, msg, isError: summary.needsResolution > 0);
        ref.read(libraryProvider.notifier).loadLibrary();
        _fetchAlbumDetails(bypassCache: false);
      }
    } catch (e) {
      if (mounted) {
        ZephyrToast.show(context, 'Failed to download album: $e', isError: true);
      }
    }
  }

  void _playAllTracks() {
    if (_album == null || _album!.tracks == null || _album!.tracks!.isEmpty) return;
    final enrichedTracks = _album!.tracks!.map((t) => t.copyWith(
      coverUrl: t.coverUrl ?? _album!.coverUrl,
      album: t.album ?? _album!.name,
      albumId: t.albumId ?? _album!.id,
    )).toList();

    ref.read(playerProvider.notifier).playTrack(
      enrichedTracks.first,
      enrichedTracks,
      isNewQueue: true,
      origin: 'context',
    );
  }

  void _shufflePlayAllTracks() {
    if (_album == null || _album!.tracks == null || _album!.tracks!.isEmpty) return;
    final enrichedTracks = _album!.tracks!.map((t) => t.copyWith(
      coverUrl: t.coverUrl ?? _album!.coverUrl,
      album: t.album ?? _album!.name,
      albumId: t.albumId ?? _album!.id,
    )).toList()..shuffle();

    ref.read(playerProvider.notifier).playTrack(
      enrichedTracks.first,
      enrichedTracks,
      isNewQueue: true,
      origin: 'context',
    );
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
              onPressed: () => _fetchAlbumDetails(bypassCache: true),
              child: const Text('Retry', style: TextStyle(color: Colors.black)),
            ),
          ],
        ),
      );
    }

    if (_album == null) {
      return const Center(child: Text('Album not found'));
    }

    final tracks = _album!.tracks ?? [];

    final isMobile = MediaQuery.of(context).size.width < 700;

    return Scaffold(
      backgroundColor: ZephyrColors.bgDark,
      body: RefreshIndicator(
        onRefresh: () => _fetchAlbumDetails(bypassCache: true),
        color: ZephyrColors.primary,
        backgroundColor: ZephyrColors.bgCard,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            // Album Header Pane & Table Headers
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: isMobile ? 16 : 32,
                  vertical: isMobile ? 16 : 32,
                ),
                child: Column(
                  crossAxisAlignment: isMobile ? CrossAxisAlignment.center : CrossAxisAlignment.start,
                  children: [
                    if (isMobile) ...[
                      // Mobile Header Layout: Centered Cover Image & Details Below
                      Center(
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: ZephyrColors.primary.withValues(alpha: 0.35),
                                blurRadius: 28,
                                spreadRadius: 2,
                              ),
                            ],
                          ),
                          child: CoverImage(
                            coverUrl: _album!.coverUrl,
                            size: 180,
                            borderRadius: 12,
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: ZephyrColors.primary.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: ZephyrColors.primary.withValues(alpha: 0.4)),
                            ),
                            child: Text(
                              _album!.displayBadge.toUpperCase(),
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: ZephyrColors.primary,
                                letterSpacing: 0.8,
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            _album!.name,
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: ZephyrColors.text,
                              letterSpacing: -0.5,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: 8,
                            runSpacing: 4,
                            children: [
                              const Icon(Icons.person, size: 16, color: ZephyrColors.primary),
                              Text(
                                _album!.artists.join(', '),
                                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: ZephyrColors.text),
                              ),
                              if (_album!.year != null) ...[
                                const Icon(Icons.circle, size: 4, color: ZephyrColors.textDim),
                                Text(
                                  '${_album!.year}',
                                  style: const TextStyle(color: ZephyrColors.textDim, fontSize: 13),
                                ),
                              ],
                              const Icon(Icons.circle, size: 4, color: ZephyrColors.textDim),
                              Text(
                                '${_album!.trackCount ?? tracks.length} songs',
                                style: const TextStyle(color: ZephyrColors.textDim, fontSize: 13),
                              ),
                              if (_album!.downloadedCount != null && _album!.downloadedCount! > 0) ...[
                                const Icon(Icons.circle, size: 4, color: ZephyrColors.textDim),
                                Text(
                                  '${_album!.downloadedCount} downloaded',
                                  style: const TextStyle(color: ZephyrTheme.accentSuccess, fontSize: 13, fontWeight: FontWeight.w600),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 16),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              ElevatedButton.icon(
                                style: ZephyrTheme.primaryPillStyle(),
                                onPressed: tracks.isEmpty ? null : _playAllTracks,
                                icon: const Icon(Icons.play_arrow_rounded, size: 22, color: Colors.black),
                                label: const Text('Play All', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                              ),
                              const SizedBox(width: 12),
                              IconButton(
                                style: IconButton.styleFrom(
                                  backgroundColor: ZephyrColors.primary.withValues(alpha: 0.15),
                                  foregroundColor: ZephyrColors.primary,
                                  padding: const EdgeInsets.all(10),
                                ),
                                icon: const Icon(Icons.shuffle_rounded, size: 20),
                                onPressed: tracks.isEmpty ? null : _shufflePlayAllTracks,
                                tooltip: 'Shuffle Play',
                              ),
                              if (widget.browseId.startsWith('dz_') || widget.browseId.startsWith('MPREb_') || widget.browseId.startsWith('OLAK5uy_')) ...[
                                const SizedBox(width: 12),
                                ElevatedButton.icon(
                                  style: ZephyrTheme.primaryPillStyle(),
                                  onPressed: _downloadAllTracks,
                                  icon: const Icon(Icons.download, size: 18),
                                  label: const Text('Download Album'),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ] else ...[
                      // Desktop Header Layout
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: [
                                BoxShadow(
                                  color: ZephyrColors.primary.withValues(alpha: 0.35),
                                  blurRadius: 28,
                                  spreadRadius: 2,
                                ),
                              ],
                            ),
                            child: CoverImage(
                              coverUrl: _album!.coverUrl,
                              size: 200,
                              borderRadius: 12,
                            ),
                          ),
                          const SizedBox(width: 24),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: ZephyrColors.primary.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(color: ZephyrColors.primary.withValues(alpha: 0.4)),
                                  ),
                                  child: Text(
                                    _album!.displayBadge.toUpperCase(),
                                    style: const TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: ZephyrColors.primary,
                                      letterSpacing: 0.8,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  _album!.name,
                                  style: const TextStyle(
                                    fontSize: 36,
                                    fontWeight: FontWeight.bold,
                                    color: ZephyrColors.text,
                                    letterSpacing: -1,
                                  ),
                                ),
                                const SizedBox(height: 16),
                                Wrap(
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  spacing: 8,
                                  runSpacing: 4,
                                  children: [
                                    const Icon(Icons.person, size: 16, color: ZephyrColors.primary),
                                    Text(
                                      _album!.artists.join(', '),
                                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                                    ),
                                    if (_album!.year != null) ...[
                                      const Icon(Icons.circle, size: 4, color: ZephyrColors.textDim),
                                      Text(
                                        '${_album!.year}',
                                        style: const TextStyle(color: ZephyrColors.textDim, fontSize: 14),
                                      ),
                                    ],
                                    const Icon(Icons.circle, size: 4, color: ZephyrColors.textDim),
                                    Text(
                                      '${_album!.trackCount ?? tracks.length} songs',
                                      style: const TextStyle(color: ZephyrColors.textDim, fontSize: 14),
                                    ),
                                    if (_album!.downloadedCount != null && _album!.downloadedCount! > 0) ...[
                                      const Icon(Icons.circle, size: 4, color: ZephyrColors.textDim),
                                      Text(
                                        '${_album!.downloadedCount} downloaded',
                                        style: const TextStyle(color: ZephyrTheme.accentSuccess, fontSize: 14, fontWeight: FontWeight.w600),
                                      ),
                                    ],
                                  ],
                                ),
                                 const SizedBox(height: 20),
                                 Row(
                                   children: [
                                     ElevatedButton.icon(
                                       style: ZephyrTheme.primaryPillStyle(),
                                       onPressed: tracks.isEmpty ? null : _playAllTracks,
                                       icon: const Icon(Icons.play_arrow_rounded, size: 22, color: Colors.black),
                                       label: const Text('Play All', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                                     ),
                                     const SizedBox(width: 12),
                                     IconButton(
                                       style: IconButton.styleFrom(
                                         backgroundColor: ZephyrColors.primary.withValues(alpha: 0.15),
                                         foregroundColor: ZephyrColors.primary,
                                         padding: const EdgeInsets.all(10),
                                       ),
                                       icon: const Icon(Icons.shuffle_rounded, size: 20),
                                       onPressed: tracks.isEmpty ? null : _shufflePlayAllTracks,
                                       tooltip: 'Shuffle Play',
                                     ),
                                     if (widget.browseId.startsWith('dz_') || widget.browseId.startsWith('MPREb_') || widget.browseId.startsWith('OLAK5uy_')) ...[
                                       const SizedBox(width: 12),
                                       ElevatedButton.icon(
                                         style: ZephyrTheme.primaryPillStyle(),
                                         onPressed: _downloadAllTracks,
                                         icon: const Icon(Icons.download, size: 18),
                                         label: const Text('Download Album'),
                                       ),
                                     ],
                                   ],
                                 ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 28),

                    // Tracks List Header
                    if (!isMobile)
                      const Row(
                        children: [
                          SizedBox(width: 64, child: Text('#', style: TextStyle(color: ZephyrColors.textMuted, fontWeight: FontWeight.bold))),
                          Expanded(child: Text('TITLE', style: TextStyle(color: ZephyrColors.textMuted, fontWeight: FontWeight.bold))),
                          Text('ACTIONS', style: TextStyle(color: ZephyrColors.textMuted, fontWeight: FontWeight.bold)),
                          SizedBox(width: 100),
                        ],
                      ),
                    if (!isMobile)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8.0),
                        child: Divider(color: ZephyrColors.bgLight),
                      ),
                  ],
                ),
              ),
            ),

            // Virtualized Album Tracks List
            if (tracks.isEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: isMobile ? 16 : 32, vertical: 24),
                  child: const Text('No tracks found in this album.', style: TextStyle(color: ZephyrColors.textDim)),
                ),
              )
            else
              SliverPadding(
                padding: EdgeInsets.symmetric(horizontal: isMobile ? 8 : 32),
                sliver: SliverList.builder(
                  itemCount: tracks.length,
                  itemBuilder: (context, index) {
                    final track = tracks[index];
                    final enrichedTrack = track.copyWith(
                      coverUrl: track.coverUrl ?? _album!.coverUrl,
                      album: track.album ?? _album!.name,
                      albumId: track.albumId ?? _album!.id,
                    );

                    return Row(
                      children: [
                        if (!isMobile)
                          SizedBox(
                            width: 32,
                            child: Text(
                              '${index + 1}',
                              style: const TextStyle(color: ZephyrColors.textDim, fontSize: 14),
                            ),
                          ),
                        Expanded(
                          child: TrackTile(
                            track: enrichedTrack,
                            queue: tracks.map((t) => t.copyWith(
                              coverUrl: t.coverUrl ?? _album!.coverUrl,
                              album: t.album ?? _album!.name,
                              albumId: t.albumId ?? _album!.id,
                            )).toList(),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            const SliverPadding(padding: EdgeInsets.only(bottom: 120)),
          ],
        ),
      ),
    );
  }
}
