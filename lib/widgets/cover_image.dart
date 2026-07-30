import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../api/zephyr_api.dart';
import '../providers/auth_provider.dart';
import '../theme/colors.dart';

import '../providers/library_provider.dart';

class CoverImage extends ConsumerWidget {
  final String? videoId;
  final String? coverUrl;
  final int? playlistId;
  final String? updatedAt;
  final bool? isDownloaded;
  final double size;
  final double borderRadius;

  const CoverImage({
    super.key,
    this.videoId,
    this.coverUrl,
    this.playlistId,
    this.updatedAt,
    this.isDownloaded,
    this.size = 48,
    this.borderRadius = 8,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final token = ref.watch(authProvider).token;
    final api = ZephyrApi();

    Widget placeholder = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: ZephyrColors.bgLight,
        borderRadius: BorderRadius.circular(borderRadius),
      ),
      child: Icon(
        playlistId != null ? Icons.playlist_play : Icons.music_note,
        color: ZephyrColors.textDim,
        size: size * 0.5,
      ),
    );

    // 1. Playlist Cover Image
    if (playlistId != null) {
      final libraryState = ref.watch(libraryProvider);
      String? cleanUpdatedAt = updatedAt;
      if (cleanUpdatedAt == null) {
        try {
          final playlist = libraryState.playlists.firstWhere(
            (p) => p.id == playlistId,
          );
          cleanUpdatedAt = playlist.updatedAt;
        } catch (_) {}
      }

      // Playlist cover: token injected via Authorization header, never in URL (S-03).
      String url = api.getPlaylistCoverUrl(playlistId!);
      if (cleanUpdatedAt != null && cleanUpdatedAt.isNotEmpty) {
        url = '$url?v=${Uri.encodeComponent(cleanUpdatedAt)}';
      }

      return ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: CachedNetworkImage(
          imageUrl: url,
          width: size,
          height: size,
          fit: BoxFit.cover,
          httpHeaders: {
            'User-Agent':
                'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36',
            if (token != null) 'Authorization': 'Bearer $token',
          },
          placeholder: (context, url) => placeholder,
          errorWidget: (context, url, error) => placeholder,
        ),
      );
    }

    // 2. Track Cover Image
    if (videoId != null) {
      // For online/non-downloaded tracks, load coverUrl directly from Google CDN for fast UX
      if (isDownloaded == false && coverUrl != null && coverUrl!.isNotEmpty) {
        return _buildNetworkImage(coverUrl!, size, placeholder, token);
      }

      String url = api.getCoverUrl(videoId!);
      return ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: CachedNetworkImage(
          imageUrl: url,
          width: size,
          height: size,
          fit: BoxFit.cover,
          httpHeaders: {
            'User-Agent':
                'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36',
            if (token != null) 'Authorization': 'Bearer $token',
          },
          placeholder: (context, url) => placeholder,
          errorWidget: (context, url, error) {
            if (coverUrl != null && coverUrl!.isNotEmpty) {
              return _buildNetworkImage(coverUrl!, size, placeholder, token);
            }
            return placeholder;
          },
        ),
      );
    }

    // 3. YouTube/Network Cover Image
    if (coverUrl != null && coverUrl!.isNotEmpty) {
      return _buildNetworkImage(coverUrl!, size, placeholder, token);
    }

    return placeholder;
  }

  Widget _buildNetworkImage(String url, double size, Widget placeholder, String? token) {
    final api = ZephyrApi();
    String fullUrl = url;
    if (fullUrl.startsWith('/')) {
      fullUrl = '${api.baseUrl}$fullUrl';
    }

    final isZephyrApi = fullUrl.contains('/api/');

    // S-03: never append token as a query parameter.
    // Authorization header is injected below via httpHeaders.
    final Map<String, String> headers = {
      'User-Agent':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36',
    };

    if (isZephyrApi && token != null) {
      headers['Authorization'] = 'Bearer $token';
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: CachedNetworkImage(
        imageUrl: fullUrl,
        width: size,
        height: size,
        fit: BoxFit.cover,
        httpHeaders: headers,
        placeholder: (context, url) => placeholder,
        errorWidget: (context, url, error) => placeholder,
      ),
    );
  }
}
