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
  final double size;
  final double borderRadius;

  const CoverImage({
    super.key,
    this.videoId,
    this.coverUrl,
    this.playlistId,
    this.updatedAt,
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

      String url = api.getPlaylistCoverUrl(playlistId!);
      final queryParams = <String>[];
      if (cleanUpdatedAt != null && cleanUpdatedAt.isNotEmpty) {
        queryParams.add('v=${Uri.encodeComponent(cleanUpdatedAt)}');
      }
      if (token != null) {
        queryParams.add('token=${Uri.encodeComponent(token)}');
      }
      if (queryParams.isNotEmpty) {
        url = '$url?${queryParams.join('&')}';
      }

      return ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: CachedNetworkImage(
          imageUrl: url,
          width: size,
          height: size,
          fit: BoxFit.cover,
          httpHeaders: token != null ? {'Authorization': 'Bearer $token'} : null,
          placeholder: (context, url) => placeholder,
          errorWidget: (context, url, error) => placeholder,
        ),
      );
    }

    // 2. Track Cover Image from local cover endpoint
    if (videoId != null) {
      String url = api.getCoverUrl(videoId!);
      if (token != null) {
        url = '$url?token=${Uri.encodeComponent(token)}';
      }
      return ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: CachedNetworkImage(
          imageUrl: url,
          width: size,
          height: size,
          fit: BoxFit.cover,
          httpHeaders: token != null ? {'Authorization': 'Bearer $token'} : null,
          placeholder: (context, url) => placeholder,
          errorWidget: (context, url, error) {
            // If the local cover fails, try to fall back to coverUrl if available
            if (coverUrl != null && coverUrl!.isNotEmpty) {
              return _buildNetworkImage(coverUrl!, size, placeholder);
            }
            return placeholder;
          },
        ),
      );
    }

    // 3. YouTube/Network Cover Image
    if (coverUrl != null && coverUrl!.isNotEmpty) {
      return _buildNetworkImage(coverUrl!, size, placeholder);
    }

    return placeholder;
  }

  Widget _buildNetworkImage(String url, double size, Widget placeholder) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: CachedNetworkImage(
        imageUrl: url,
        width: size,
        height: size,
        fit: BoxFit.cover,
        placeholder: (context, url) => placeholder,
        errorWidget: (context, url, error) => placeholder,
      ),
    );
  }
}
