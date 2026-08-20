import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../api/zephyr_api.dart';
import '../providers/auth_provider.dart';
import '../theme/colors.dart';
import '../providers/library_provider.dart';

class CoverImage extends ConsumerStatefulWidget {
  final String? videoId;
  final String? coverUrl;
  final dynamic playlistId;
  final String? updatedAt;
  final bool? isDownloaded;
  final double size;
  final double borderRadius;
  final Duration debounceDuration;

  const CoverImage({
    super.key,
    this.videoId,
    this.coverUrl,
    this.playlistId,
    this.updatedAt,
    this.isDownloaded,
    this.size = 48,
    this.borderRadius = 8,
    this.debounceDuration = const Duration(milliseconds: 500),
  });

  @override
  ConsumerState<CoverImage> createState() => _CoverImageState();
}

class _CoverImageState extends ConsumerState<CoverImage> {
  bool _isReadyToLoad = false;
  Timer? _debounceTimer;

  @override
  void initState() {
    super.initState();
    if (widget.size >= 120 || widget.debounceDuration == Duration.zero) {
      _isReadyToLoad = true;
    } else {
      _startDebounce();
    }
  }

  @override
  void didUpdateWidget(CoverImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.coverUrl != widget.coverUrl ||
        oldWidget.videoId != widget.videoId ||
        oldWidget.playlistId != widget.playlistId) {
      if (widget.size >= 120 || widget.debounceDuration == Duration.zero) {
        _isReadyToLoad = true;
      } else {
        _startDebounce();
      }
    }
  }

  void _startDebounce() {
    _debounceTimer?.cancel();
    _isReadyToLoad = false;
    _debounceTimer = Timer(widget.debounceDuration, () {
      if (mounted) {
        setState(() {
          _isReadyToLoad = true;
        });
      }
    });
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final token = ref.watch(authProvider).token;
    final api = ZephyrApi();

    Widget placeholder = Container(
      width: widget.size,
      height: widget.size,
      decoration: BoxDecoration(
        color: ZephyrColors.bgLight,
        borderRadius: BorderRadius.circular(widget.borderRadius),
      ),
      child: Icon(
        widget.playlistId != null
            ? Icons.playlist_play
            : (widget.borderRadius >= widget.size * 0.4
                ? Icons.person_rounded
                : Icons.music_note_rounded),
        color: ZephyrColors.textDim,
        size: widget.size * 0.5,
      ),
    );

    // If fast-scrolling and not settled yet, return lightweight placeholder with zero network I/O
    if (!_isReadyToLoad) {
      return placeholder;
    }

    // 1. Playlist Cover Image
    if (widget.playlistId != null) {
      final libraryState = ref.watch(libraryProvider);
      String? cleanUpdatedAt = widget.updatedAt;
      if (cleanUpdatedAt == null) {
        try {
          final playlist = libraryState.playlists.firstWhere(
            (p) => p.id.toString() == widget.playlistId.toString(),
          );
          cleanUpdatedAt = playlist.updatedAt;
        } catch (_) {}
      }

      // Playlist cover: token injected via Authorization header, never in URL (S-03).
      String url = api.getPlaylistCoverUrl(widget.playlistId!);
      if (cleanUpdatedAt != null && cleanUpdatedAt.isNotEmpty) {
        url = '$url?v=${Uri.encodeComponent(cleanUpdatedAt)}';
      }

      return ClipRRect(
        borderRadius: BorderRadius.circular(widget.borderRadius),
        child: CachedNetworkImage(
          imageUrl: url,
          width: widget.size,
          height: widget.size,
          fit: BoxFit.cover,
          fadeInDuration: const Duration(milliseconds: 200),
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

    // 2. Network / Relative Cover Image URL
    if (widget.coverUrl != null &&
        widget.coverUrl!.isNotEmpty &&
        !widget.coverUrl!.contains('/var/lib/') &&
        (widget.coverUrl!.startsWith('http://') ||
            widget.coverUrl!.startsWith('https://') ||
            widget.coverUrl!.startsWith('/'))) {
      return _buildNetworkImage(widget.coverUrl!, widget.size, placeholder, token,
          fallbackVideoId: widget.videoId);
    }

    // 3. Local Track Cover Image Endpoint (using canonical track ID)
    if (widget.videoId != null && widget.videoId!.isNotEmpty) {
      String url = api.getCoverUrl(widget.videoId!);
      return _buildNetworkImage(url, widget.size, placeholder, token);
    }

    return placeholder;
  }

  Widget _buildNetworkImage(String url, double size, Widget placeholder, String? token,
      {String? fallbackVideoId}) {
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

    final activeToken = token ?? api.token;
    if (isZephyrApi && activeToken != null && activeToken.isNotEmpty) {
      headers['Authorization'] = 'Bearer $activeToken';
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(widget.borderRadius),
      child: CachedNetworkImage(
        imageUrl: fullUrl,
        width: size,
        height: size,
        fit: BoxFit.cover,
        fadeInDuration: const Duration(milliseconds: 200),
        httpHeaders: headers,
        placeholder: (context, url) => placeholder,
        errorWidget: (context, url, error) {
          if (fallbackVideoId != null && fallbackVideoId.isNotEmpty) {
            final fallbackUrl = api.getCoverUrl(fallbackVideoId);
            if (fallbackUrl != url) {
              return _buildNetworkImage(fallbackUrl, size, placeholder, token);
            }
          }
          return placeholder;
        },
      ),
    );
  }
}
