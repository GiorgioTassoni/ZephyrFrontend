import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../api/zephyr_api.dart';
import '../models/models.dart';
import '../providers/library_provider.dart';
import '../providers/player_provider.dart';
import '../theme/colors.dart';
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
      final response = await _api.downloadAlbum(widget.browseId);
      final queued = response['queued_for_download'] ?? 0;
      final avail = response['already_downloaded'] ?? 0;
      ZephyrToast.show(
        context,
        'Album download started: $queued queued, $avail already available.',
      );
      // Reload library to update download states
      ref.read(libraryProvider.notifier).loadLibrary();
      // Re-fetch album status
      _fetchAlbumDetails(bypassCache: false);
    } catch (e) {
      ZephyrToast.show(context, 'Failed to download album: $e', isError: true);
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

    return Scaffold(
      backgroundColor: ZephyrColors.bgDark,
      body: RefreshIndicator(
        onRefresh: () => _fetchAlbumDetails(bypassCache: true),
        color: ZephyrColors.primary,
        backgroundColor: ZephyrColors.bgCard,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header Details Pane
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  CoverImage(
                    coverUrl: _album!.coverUrl,
                    size: 200,
                    borderRadius: 12,
                  ),
                  const SizedBox(width: 24),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _album!.displayBadge,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.2,
                            color: ZephyrColors.textDim,
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
                        Row(
                          children: [
                            const Icon(Icons.person, size: 16, color: ZephyrColors.primary),
                            const SizedBox(width: 6),
                            Text(
                              _album!.artists.join(', '),
                              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                            ),
                            if (_album!.year != null) ...[
                              const SizedBox(width: 12),
                              const Icon(Icons.circle, size: 4, color: ZephyrColors.textDim),
                              const SizedBox(width: 12),
                              Text(
                                '${_album!.year}',
                                style: const TextStyle(color: ZephyrColors.textDim, fontSize: 14),
                              ),
                            ],
                            const SizedBox(width: 12),
                            const Icon(Icons.circle, size: 4, color: ZephyrColors.textDim),
                            const SizedBox(width: 12),
                            Text(
                              '${_album!.trackCount ?? tracks.length} songs',
                              style: const TextStyle(color: ZephyrColors.textDim, fontSize: 14),
                            ),
                            if (_album!.downloadedCount != null && _album!.downloadedCount! > 0) ...[
                              const SizedBox(width: 12),
                              const Icon(Icons.circle, size: 4, color: ZephyrColors.textDim),
                              const SizedBox(width: 12),
                              Text(
                                '${_album!.downloadedCount} downloaded',
                                style: const TextStyle(color: ZephyrColors.success, fontSize: 14, fontWeight: FontWeight.w600),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 20),
                        if (widget.browseId.startsWith('dz_') || widget.browseId.startsWith('MPREb_') || widget.browseId.startsWith('OLAK5uy_'))
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: ZephyrColors.primary,
                              foregroundColor: Colors.black,
                              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                            ),
                            onPressed: _downloadAllTracks,
                            icon: const Icon(Icons.download, size: 18),
                            label: const Text('Download Album', style: TextStyle(fontWeight: FontWeight.bold)),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 40),

              // Tracks List Header
              const Row(
                children: [
                  SizedBox(width: 64, child: Text('#', style: TextStyle(color: ZephyrColors.textMuted, fontWeight: FontWeight.bold))),
                  Expanded(child: Text('TITLE', style: TextStyle(color: ZephyrColors.textMuted, fontWeight: FontWeight.bold))),
                  Text('ACTIONS', style: TextStyle(color: ZephyrColors.textMuted, fontWeight: FontWeight.bold)),
                  SizedBox(width: 100),
                ],
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8.0),
                child: Divider(color: ZephyrColors.bgLight),
              ),

              // Tracks List
              tracks.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(24.0),
                      child: Text('No tracks found in this album.', style: TextStyle(color: ZephyrColors.textDim)),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: tracks.length,
                      itemBuilder: (context, index) {
                        final track = tracks[index];
                        // Enrich track with album cover if needed
                        final enrichedTrack = track.copyWith(
                          coverUrl: track.coverUrl ?? _album!.coverUrl,
                          album: track.album ?? _album!.name,
                          albumId: track.albumId ?? _album!.id,
                        );

                        return Row(
                          children: [
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
            ],
          ),
        ),
      ),
    );
  }
}
