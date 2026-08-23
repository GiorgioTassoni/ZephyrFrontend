import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../api/zephyr_api.dart';
import '../models/models.dart';
import '../providers/library_provider.dart';
import '../providers/player_provider.dart';
import '../theme/colors.dart';
import '../providers/navigation_provider.dart';
import '../widgets/cover_image.dart';
import '../widgets/seek_bar.dart';
import '../widgets/artist_links.dart';
import '../widgets/toast.dart';
import '../widgets/share_dialog.dart';
import '../widgets/favorite_button.dart';
import '../widgets/visualizer.dart';
import '../widgets/player_song_context_menu.dart';
import '../widgets/devices_modal.dart';
import 'queue_screen.dart';

// Model for LRC line parsing
class LrcLine {
  final Duration timestamp;
  final String text;

  LrcLine({required this.timestamp, required this.text});
}

class PlayerScreen extends ConsumerStatefulWidget {
  final bool isInline;
  const PlayerScreen({super.key, this.isInline = false});

  @override
  ConsumerState<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends ConsumerState<PlayerScreen> with SingleTickerProviderStateMixin {
  final _api = ZephyrApi();
  final ScrollController _lyricsScrollController = ScrollController();
  late TabController _tabController;
  
  // States
  Track? _enrichedMetadata;
  List<LrcLine> _lrcLines = [];
  final List<GlobalKey> _lyricKeys = [];
  final List<GlobalKey> _modalLyricKeys = [];
  Map<String, dynamic>? _relatedData;
  bool _isLoadingMetadata = false;
  bool _isLoadingRelated = false;
  String? _lastVideoId;
  int _activeLrcIndex = -1;
  bool _isSynced = true;
  bool _hasInitialScrolled = false;
  bool _isDismissing = false;
  bool _dragStartedAtTop = false;
  double _pullDistance = 0.0;

  StreamSubscription<String>? _lyricsSub;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(_onTabChanged);
    _lyricsSub = _api.onLyricsReady.listen((videoId) {
      if (mounted && (_lastVideoId == null || videoId == _lastVideoId || videoId == 'dz_$_lastVideoId' || _lastVideoId == 'dz_$videoId')) {
        _fetchMetadataAndRelated(videoId, force: true);
      }
    });
  }

  void _onTabChanged() {
    if (_tabController.index == 0) {
      _hasInitialScrolled = false;
      _isSynced = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          final pos = ref.read(playerProvider).position;
          _updateLyricsScrolling(pos);
        }
      });
    } else if (_tabController.index == 1 && _relatedData == null && !_isLoadingRelated && _lastVideoId != null) {
      _fetchRelatedTracks(_lastVideoId!);
    }
  }

  @override
  void dispose() {
    _lyricsSub?.cancel();
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    _lyricsScrollController.dispose();
    super.dispose();
  }

  Future<void> _fetchMetadataAndRelated(String videoId, {bool force = false}) async {
    _lastVideoId = videoId;

    final currentTrack = ref.read(playerProvider).currentTrack;
    final hasLrc = (currentTrack != null &&
        (currentTrack.videoId == videoId || currentTrack.videoId == 'dz_$videoId' || videoId == 'dz_${currentTrack.videoId}') &&
        currentTrack.lyricsLrc != null &&
        currentTrack.lyricsLrc!.isNotEmpty);

    setState(() {
      _isLoadingMetadata = !hasLrc;
      _isLoadingRelated = false;
      _enrichedMetadata = currentTrack;
      if (!hasLrc) {
        _lrcLines = [];
        _lyricKeys.clear();
        _modalLyricKeys.clear();
        _activeLrcIndex = -1;
      }
      _relatedData = null;
      _isSynced = true;
      _hasInitialScrolled = false;
    });

    if (hasLrc) {
      _parseLrc(currentTrack.lyricsLrc!);
      _isLoadingMetadata = false;
    } else if (force || (currentTrack != null && (currentTrack.isDownloaded || currentTrack.downloadStatus == 'completed'))) {
      // 1. Fetch Track Metadata (Lyrics) only if track is already downloaded or force requested
      try {
        final metadata = await _api.getTrackMetadata(videoId);
        _enrichedMetadata = metadata;
        
        final lrcText = resLyricsLrc(metadata) ?? metadata.lyricsText;
        if (lrcText != null && lrcText.isNotEmpty) {
          _parseLrc(lrcText);
        }
      } catch (e) {
        // Handle 404 silently (not in library yet)
      } finally {
        if (mounted) {
          setState(() {
            _isLoadingMetadata = false;
          });
        }
      }
    } else {
      if (mounted) {
        setState(() {
          _isLoadingMetadata = false;
        });
      }
    }

    // Only fetch related tracks if user is currently viewing the Related tab
    if (_tabController.index == 1) {
      _fetchRelatedTracks(videoId);
    }
  }

  Future<void> _fetchRelatedTracks(String videoId) async {
    if (_isLoadingRelated) return;
    setState(() {
      _isLoadingRelated = true;
    });
    try {
      final related = await _api.getRelatedTracks(videoId);
      if (mounted) {
        setState(() {
          _relatedData = related;
          _isLoadingRelated = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingRelated = false;
        });
      }
    }
  }

  String? resLyricsLrc(Track track) {
    return track.lyricsLrc;
  }

  void _parseLrc(String lrcContent) {
    final lines = lrcContent.split('\n');
    final List<LrcLine> parsed = [];
    final timeTagRegex = RegExp(r'\[(\d+):(\d{2})(?:[:\.](\d{1,3}))?\]');

    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;

      final matches = timeTagRegex.allMatches(trimmed).toList();
      if (matches.isEmpty) continue;

      final text = trimmed.replaceAll(timeTagRegex, '').trim();

      for (final match in matches) {
        final min = int.tryParse(match.group(1) ?? '0') ?? 0;
        final sec = int.tryParse(match.group(2) ?? '0') ?? 0;
        final fracStr = match.group(3) ?? '0';
        int ms = 0;
        if (fracStr.length == 1) {
          ms = (int.tryParse(fracStr) ?? 0) * 100;
        } else if (fracStr.length == 2) {
          ms = (int.tryParse(fracStr) ?? 0) * 10;
        } else {
          ms = int.tryParse(fracStr) ?? 0;
        }
        final timestamp = Duration(minutes: min, seconds: sec, milliseconds: ms);
        parsed.add(LrcLine(timestamp: timestamp, text: text));
      }
    }
    // Sort by timestamp
    parsed.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    setState(() {
      _lrcLines = parsed;
      _lyricKeys.clear();
      _modalLyricKeys.clear();
      _lyricKeys.addAll(List.generate(parsed.length, (_) => GlobalKey()));
      _modalLyricKeys.addAll(List.generate(parsed.length, (_) => GlobalKey()));
    });
  }

  void _updateLyricsScrolling(Duration position) {
    if (_lrcLines.isEmpty) return;

    int activeIndex = -1;
    for (int i = 0; i < _lrcLines.length; i++) {
      if (_lrcLines[i].timestamp <= position) {
        activeIndex = i;
      } else {
        break;
      }
    }

    if (activeIndex != -1 && (activeIndex != _activeLrcIndex || !_hasInitialScrolled)) {
      final isFirstScroll = !_hasInitialScrolled;
      _hasInitialScrolled = true;

      if (mounted) {
        setState(() {
          _activeLrcIndex = activeIndex;
        });
      }

      if (_isSynced &&
          _activeLrcIndex >= 0 &&
          _activeLrcIndex < _lyricKeys.length &&
          _lyricsScrollController.hasClients) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || !_isSynced || !_lyricsScrollController.hasClients) return;
          final key = _lyricKeys[_activeLrcIndex];
          final currentContext = key.currentContext;

          if (currentContext != null && currentContext.findRenderObject() is RenderBox) {
            final box = currentContext.findRenderObject() as RenderBox;
            if (box.hasSize) {
              final scrollableContext = _lyricsScrollController.position.context.storageContext;
              final positionInViewport = box.localToGlobal(Offset.zero, ancestor: scrollableContext.findRenderObject());
              final currentOffset = _lyricsScrollController.offset;
              final itemTop = currentOffset + positionInViewport.dy;
              final itemHeight = box.size.height;
              final viewportHeight = _lyricsScrollController.position.viewportDimension;
              final targetOffset = (itemTop + (itemHeight / 2) - (viewportHeight / 2)).clamp(
                0.0,
                _lyricsScrollController.position.maxScrollExtent,
              );

              if (isFirstScroll) {
                _lyricsScrollController.jumpTo(targetOffset);
              } else if ((_lyricsScrollController.offset - targetOffset).abs() > 8) {
                _lyricsScrollController.animateTo(
                  targetOffset,
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOut,
                );
              }
              return;
            }
          }

          if (_lyricsScrollController.position.hasContentDimensions) {
            final viewportHeight = _lyricsScrollController.position.viewportDimension;
            final targetOffset = (_activeLrcIndex * 54.0 + 27.0 - (viewportHeight / 2)).clamp(
              0.0,
              _lyricsScrollController.position.maxScrollExtent,
            );
            if (isFirstScroll) {
              _lyricsScrollController.jumpTo(targetOffset);
            } else if ((_lyricsScrollController.offset - targetOffset).abs() > 15) {
              _lyricsScrollController.animateTo(
                targetOffset,
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
              );
            }
          }
        });
      }
    }
  }

  void _dismissPlayer(BuildContext context, WidgetRef ref) {
    final navNotifier = ref.read(navigationProvider.notifier);
    if (navNotifier.canGoBack) {
      navNotifier.navigateBack();
    } else {
      navNotifier.navigateTo(const ScreenState(type: ScreenType.home));
    }
  }

  void _showQueueBottomSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.85,
        decoration: const BoxDecoration(
          color: ZephyrColors.bgDark,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: ZephyrColors.textDim.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const Expanded(child: QueueScreen()),
          ],
        ),
      ),
    );
  }

  Future<void> _handlePlayerMenuSelection(
    BuildContext context,
    WidgetRef ref,
    Track track,
    String value,
  ) async {
    final navNotifier = ref.read(navigationProvider.notifier);
    final isModal = Navigator.of(context).canPop() && !widget.isInline;

    if (value == 'show_queue') {
      _showQueueBottomSheet(context, ref);
      return;
    }

    if (value == 'go_to_album') {
      if (isModal) Navigator.of(context).pop();

      // 1. Direct albumId
      if (track.albumId != null && track.albumId!.isNotEmpty) {
        navNotifier.navigateTo(ScreenState(type: ScreenType.album, id: track.albumId!));
        return;
      }

      // 2. Search Deezer remotely for album
      final albumQuery = (track.album != null && track.album!.isNotEmpty)
          ? '${track.album} ${track.artists.isNotEmpty ? track.artists.first : ''}'.trim()
          : '${track.title} ${track.artists.isNotEmpty ? track.artists.first : ''}'.trim();

      try {
        final searchRes = await _api.search(albumQuery, remote: true);
        final results = searchRes['results'];
        List<dynamic> albums = [];
        if (results is Map && results.containsKey('albums')) {
          albums = (results['albums'] as List?) ?? [];
        } else if (searchRes['albums'] is List) {
          albums = searchRes['albums'] as List;
        }

        if (albums.isNotEmpty) {
          final firstAlbum = albums.first;
          final id = (firstAlbum['id'] ?? firstAlbum['browse_id'] ?? firstAlbum['browseId'])?.toString();
          if (id != null && id.isNotEmpty) {
            final formattedId = id.startsWith('dz_') ? id : 'dz_$id';
            navNotifier.navigateTo(ScreenState(type: ScreenType.album, id: formattedId));
            return;
          }
        }
      } catch (_) {}

      if (context.mounted) ZephyrToast.show(context, 'Could not find album page');
    } else if (value.startsWith('go_to_artist_')) {
      final indexStr = value.substring('go_to_artist_'.length);
      final index = int.tryParse(indexStr) ?? 0;
      if (index < track.artists.length) {
        if (isModal) Navigator.of(context).pop();
        final name = track.artists[index];
        final channelId = (index < track.artistsIds.length && track.artistsIds[index].isNotEmpty)
            ? track.artistsIds[index]
            : null;

        if (channelId != null && channelId.isNotEmpty) {
          navNotifier.navigateTo(ScreenState(type: ScreenType.artist, id: channelId));
          return;
        }

        try {
          final res = await _api.getArtistByName(name);
          final id = (res['id'] ?? res['channel_id'] ?? res['browse_id'])?.toString();
          if (id != null && id.isNotEmpty) {
            navNotifier.navigateTo(ScreenState(type: ScreenType.artist, id: id));
            return;
          }
        } catch (_) {}

        // Remote search fallback for artist
        try {
          final searchRes = await _api.search(name, remote: true);
          final results = searchRes['results'];
          List<dynamic> artists = [];
          if (results is Map && results.containsKey('artists')) {
            artists = (results['artists'] as List?) ?? [];
          } else if (searchRes['artists'] is List) {
            artists = searchRes['artists'] as List;
          }

          if (artists.isNotEmpty) {
            final firstArtist = artists.first;
            final id = (firstArtist['id'] ?? firstArtist['channel_id'] ?? firstArtist['browse_id'] ?? firstArtist['channelId'])?.toString();
            if (id != null && id.isNotEmpty) {
              navNotifier.navigateTo(ScreenState(type: ScreenType.artist, id: id));
              return;
            }
          }
        } catch (_) {}

        if (context.mounted) ZephyrToast.show(context, 'Could not find artist page for "$name"');
      }
    } else if (value == 'share') {
      showShareDialog(context, ref, track);
    } else if (value == 'download') {
      _api.queueDownload(track.videoId);
      ZephyrToast.show(context, 'Download queued for "${track.title}"');
    }
  }

  void _openFullscreenLyrics(BuildContext context, Track track) {
    final modalScrollController = ScrollController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: ZephyrColors.bgDark,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Consumer(
          builder: (context, ref, child) {
            final pos = ref.watch(playerProvider.select((s) => s.position));
            int modalActiveIndex = -1;
            for (int i = 0; i < _lrcLines.length; i++) {
              if (_lrcLines[i].timestamp <= pos) {
                modalActiveIndex = i;
              } else {
                break;
              }
            }

            if (_isSynced &&
                modalActiveIndex >= 0 &&
                modalActiveIndex < _modalLyricKeys.length &&
                modalScrollController.hasClients &&
                modalScrollController.position.hasContentDimensions) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (_isSynced &&
                    modalScrollController.hasClients &&
                    modalScrollController.position.hasContentDimensions) {
                  final key = _modalLyricKeys[modalActiveIndex];
                  final currentContext = key.currentContext;

                  if (currentContext != null) {
                    final box = currentContext.findRenderObject() as RenderBox?;
                    if (box != null && box.hasSize) {
                      final scrollableContext = modalScrollController.position.context.storageContext;
                      final positionInViewport = box.localToGlobal(Offset.zero, ancestor: scrollableContext.findRenderObject());
                      final currentOffset = modalScrollController.offset;
                      final itemTop = currentOffset + positionInViewport.dy;
                      final itemHeight = box.size.height;
                      final viewportHeight = modalScrollController.position.viewportDimension;
                      final targetOffset = (itemTop + (itemHeight / 2) - (viewportHeight / 2)).clamp(
                        0.0,
                        modalScrollController.position.maxScrollExtent,
                      );

                      if ((modalScrollController.offset - targetOffset).abs() > 8) {
                        modalScrollController.animateTo(
                          targetOffset,
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeInOut,
                        );
                      }
                    }
                  } else {
                    final viewportHeight = modalScrollController.position.viewportDimension;
                    final targetOffset = (modalActiveIndex * 48.0 + 24.0 - (viewportHeight / 2)).clamp(
                      0.0,
                      modalScrollController.position.maxScrollExtent,
                    );
                    if ((modalScrollController.offset - targetOffset).abs() > 15) {
                      modalScrollController.animateTo(
                        targetOffset,
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeInOut,
                      );
                    }
                  }
                }
              });
            }

            return SafeArea(
              child: SizedBox(
                height: MediaQuery.of(ctx).size.height * 0.9,
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              track.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: ZephyrColors.text,
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close, color: ZephyrColors.text),
                            onPressed: () => Navigator.pop(ctx),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1, color: ZephyrColors.bgLight),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: _buildLyricsView(
                          controller: modalScrollController,
                          isModal: true,
                          activeLineIndex: modalActiveIndex,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Color _getTrackAmbientColor(Track track) {
    final hash = track.videoId.hashCode.abs();
    final hues = [
      const Color(0xFFF59E0B), // Zephyr Amber
      const Color(0xFF06B6D4), // Cyan
      const Color(0xFF8B5CF6), // Purple
      const Color(0xFF10B981), // Emerald
      const Color(0xFFEC4899), // Pink / Rose
      const Color(0xFF3B82F6), // Royal Blue
      const Color(0xFFF97316), // Warm Orange
    ];
    return hues[hash % hues.length];
  }

  @override
  Widget build(BuildContext context) {
    final track = ref.watch(playerProvider.select((s) => s.currentTrack));
    final isPlaying = ref.watch(playerProvider.select((s) => s.isPlaying));
    final isLoading = ref.watch(playerProvider.select((s) => s.isLoading));
    final isShuffled = ref.watch(playerProvider.select((s) => s.isShuffled));
    final repeatMode = ref.watch(playerProvider.select((s) => s.repeatMode));
    final isPlayerDevice = ref.watch(playerProvider.select((s) => s.isPlayerDevice));
    final activeDeviceName = ref.watch(playerProvider.select((s) => s.activeDeviceName));
    final volume = ref.watch(playerProvider.select((s) => s.volume));

    final playerNotifier = ref.read(playerProvider.notifier);
    final libraryNotifier = ref.read(libraryProvider.notifier);

    // Listen for track changes to force lyrics reload when skipping songs
    ref.listen(playerProvider.select((s) => s.currentTrack?.videoId), (previous, next) {
      if (next != null && next != previous) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _fetchMetadataAndRelated(next, force: true);
          }
        });
      }
    });

    // Listen for live lyrics/metadata arrival after background download completes
    ref.listen(playerProvider.select((s) => s.currentTrack?.lyricsLrc ?? s.currentTrack?.lyricsText), (previous, next) {
      if (next != null && next.isNotEmpty && next != previous) {
        final currentTrack = ref.read(playerProvider).currentTrack;
        if (currentTrack != null) {
          setState(() {
            _enrichedMetadata = currentTrack;
            _isLoadingMetadata = false;
          });
          if (currentTrack.lyricsLrc != null && currentTrack.lyricsLrc!.isNotEmpty) {
            _parseLrc(currentTrack.lyricsLrc!);
          } else if (currentTrack.lyricsText != null && currentTrack.lyricsText!.contains('[')) {
            _parseLrc(currentTrack.lyricsText!);
          }
        }
      }
    });

    // Listen for playback position updates to smoothly advance lyrics without rebuilding the full screen
    ref.listen(playerProvider.select((s) => s.position), (_, pos) {
      _updateLyricsScrolling(pos);
    });

    if (track == null) {
      if (widget.isInline) {
        return const Center(
          child: Text(
            'No song loaded',
            style: TextStyle(color: ZephyrColors.textDim, fontSize: 16),
          ),
        );
      }
      return Scaffold(
        backgroundColor: ZephyrColors.bgDark,
        appBar: AppBar(),
        body: const Center(child: Text('No song loaded')),
      );
    }

    // Immediately load & parse lyrics when track changes
    if (_lastVideoId != track.videoId) {
      _lastVideoId = track.videoId;
      _enrichedMetadata = track;
      _lrcLines = [];
      _lyricKeys.clear();
      _activeLrcIndex = -1;
      _isLoadingMetadata = true;

      // Parse lyricsLrc immediately if already available on currentTrack
      if (track.lyricsLrc != null && track.lyricsLrc!.isNotEmpty) {
        _parseLrc(track.lyricsLrc!);
      }

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _fetchMetadataAndRelated(track.videoId, force: true);
        }
      });
    } else if (_lrcLines.isEmpty && track.lyricsLrc != null && track.lyricsLrc!.isNotEmpty) {
      _parseLrc(track.lyricsLrc!);
    } else if (_lrcLines.isEmpty && track.lyricsText != null && track.lyricsText!.contains('[')) {
      _parseLrc(track.lyricsText!);
    }

    final isFav = libraryNotifier.isFavorite(track.videoId, title: track.title, artists: track.artists);
    final ambientColor = _getTrackAmbientColor(track);

    final isMobile = MediaQuery.of(context).size.width < 700;

    if (widget.isInline) {
      if (isMobile) {
        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: const SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness: Brightness.light,
          ),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 800),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color.alphaBlend(ambientColor.withValues(alpha: 0.35), ZephyrColors.bgDark),
                  Color.alphaBlend(ambientColor.withValues(alpha: 0.15), ZephyrColors.bgDark),
                  ZephyrColors.bgDark,
                ],
                stops: const [0.0, 0.5, 1.0],
              ),
            ),
            child: SafeArea(
              top: true,
              bottom: true,
              child: NotificationListener<ScrollNotification>(
                onNotification: (notification) {
                  if (_isDismissing) return false;

                  if (notification is ScrollStartNotification) {
                    if (notification.metrics.pixels <= 0 && notification.dragDetails != null) {
                      _dragStartedAtTop = true;
                      _pullDistance = 0.0;
                    } else {
                      _dragStartedAtTop = false;
                      _pullDistance = 0.0;
                    }
                  } else if (notification is ScrollUpdateNotification) {
                    if (_dragStartedAtTop && notification.dragDetails != null) {
                      final delta = notification.scrollDelta ?? 0.0;
                      if (delta < 0) {
                        _pullDistance += -delta;
                      }
                      if (_pullDistance > 110 || notification.metrics.pixels < -110) {
                        _isDismissing = true;
                        _dragStartedAtTop = false;
                        _pullDistance = 0.0;
                        HapticFeedback.mediumImpact();
                        _dismissPlayer(context, ref);
                        Future.delayed(const Duration(milliseconds: 600), () {
                          if (mounted) _isDismissing = false;
                        });
                        return true;
                      }
                    }
                  } else if (notification is ScrollEndNotification) {
                    _dragStartedAtTop = false;
                    _pullDistance = 0.0;
                  }
                  return false;
                },
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  child: Column(
                    children: [
                      // Top Mobile Header Bar
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.keyboard_arrow_down_rounded, color: ZephyrColors.text, size: 32),
                            onPressed: () => _dismissPlayer(context, ref),
                          ),
                            Expanded(
                              child: Column(
                                children: [
                                  const Text(
                                    'PLAYING FROM PLAYLIST',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 1.2,
                                      color: ZephyrColors.textDim,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    track.album ?? 'Zephyr Music',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: ZephyrColors.text,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            PopupMenuButton<String>(
                              icon: const Icon(Icons.more_vert_rounded, color: ZephyrColors.text, size: 24),
                              color: ZephyrColors.bgCard,
                              onSelected: (val) => _handlePlayerMenuSelection(context, ref, track, val),
                              itemBuilder: (context) {
                                final validArtists = track.artists.where((a) => a.trim().isNotEmpty).toList();
                                return [
                                  const PopupMenuItem(
                                    value: 'show_queue',
                                    child: Row(
                                      children: [
                                        Icon(Icons.queue_music_rounded, size: 20, color: ZephyrColors.textDim),
                                        SizedBox(width: 10),
                                        Text('Play Queue'),
                                      ],
                                    ),
                                  ),
                                  const PopupMenuItem(
                                    value: 'go_to_album',
                                    child: Row(
                                      children: [
                                        Icon(Icons.album, size: 20, color: ZephyrColors.textDim),
                                        SizedBox(width: 10),
                                        Text('Go to album'),
                                      ],
                                    ),
                                  ),
                                  for (int i = 0; i < validArtists.length; i++)
                                    PopupMenuItem(
                                      value: 'go_to_artist_$i',
                                      child: Row(
                                        children: [
                                          const Icon(Icons.person, size: 20, color: ZephyrColors.textDim),
                                          SizedBox(width: 10),
                                          Text(validArtists.length == 1 ? 'Go to artist' : 'Go to ${validArtists[i]}'),
                                        ],
                                      ),
                                    ),
                                  const PopupMenuItem(
                                    value: 'share',
                                    child: Row(
                                      children: [
                                        Icon(Icons.share_rounded, size: 20, color: ZephyrColors.textDim),
                                        SizedBox(width: 10),
                                        Text('Share song'),
                                      ],
                                    ),
                                  ),
                                ];
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 44),

                    // Centered Large Album Artwork
                    Center(
                      child: GestureDetector(
                        onHorizontalDragEnd: (details) {
                          if (details.primaryVelocity != null && details.primaryVelocity! < -200) {
                            playerNotifier.playNext();
                            HapticFeedback.lightImpact();
                          } else if (details.primaryVelocity != null && details.primaryVelocity! > 200) {
                            playerNotifier.playPrevious();
                            HapticFeedback.lightImpact();
                          }
                        },
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: ambientColor.withValues(alpha: 0.6),
                                blurRadius: 40,
                                spreadRadius: 4,
                                offset: const Offset(0, 12),
                              ),
                            ],
                          ),
                          child: CoverImage(
                            videoId: track.videoId,
                            coverUrl: track.coverUrl,
                            size: (MediaQuery.of(context).size.width - 64).clamp(240.0, 360.0),
                            borderRadius: 16,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 30),

                    // Track Title, Artist & Favorite Heart
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                track.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                  color: ZephyrColors.text,
                                ),
                              ),
                              const SizedBox(height: 6),
                              ArtistLinks(
                                track: track,
                                style: const TextStyle(
                                  fontSize: 14,
                                  color: ZephyrColors.textDim,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        FavoriteButton(
                          isFavorite: isFav,
                          size: 28,
                          onTap: () => libraryNotifier.toggleFavorite(track),
                        ),
                      ],
                    ),
                    const SizedBox(height: 22),

                    // Seek Bar (isolated consumer to prevent full-screen frame invalidations)
                    Consumer(
                      builder: (context, ref, _) {
                        final pos = ref.watch(playerProvider.select((s) => s.position));
                        final dur = ref.watch(playerProvider.select((s) => s.effectiveDuration));
                        final loading = ref.watch(playerProvider.select((s) => s.isLoading));
                        return SeekBar(
                          position: pos,
                          duration: dur,
                          isLoading: loading,
                          onChangeEnd: (duration) {
                            playerNotifier.seek(duration);
                          },
                        );
                      },
                    ),
                    const SizedBox(height: 18),

                    // Playback Controls Row
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        IconButton(
                          icon: Icon(
                            Icons.shuffle_rounded,
                            color: isShuffled ? ZephyrColors.primary : ZephyrColors.textDim,
                            size: 26,
                          ),
                          onPressed: () => playerNotifier.toggleShuffle(),
                        ),
                        IconButton(
                          icon: const Icon(Icons.skip_previous_rounded, color: ZephyrColors.text, size: 38),
                          onPressed: () => playerNotifier.playPrevious(),
                        ),
                        if (isLoading)
                          const SizedBox(
                            width: 64,
                            height: 64,
                            child: CircularProgressIndicator(
                              strokeWidth: 3,
                              valueColor: AlwaysStoppedAnimation<Color>(ZephyrColors.primary),
                            ),
                          )
                        else
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              shape: const CircleBorder(),
                              padding: const EdgeInsets.all(16),
                              backgroundColor: ZephyrColors.text,
                              foregroundColor: ZephyrColors.bgDark,
                              elevation: 6,
                            ),
                            onPressed: () => playerNotifier.togglePlayPause(),
                            child: Icon(
                              isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                              size: 36,
                            ),
                          ),
                        IconButton(
                          icon: const Icon(Icons.skip_next_rounded, color: ZephyrColors.text, size: 38),
                          onPressed: () => playerNotifier.playNext(),
                        ),
                        IconButton(
                          icon: Icon(
                            repeatMode == 'one'
                                ? Icons.repeat_one_rounded
                                : Icons.repeat_rounded,
                            color: repeatMode != 'off' ? ZephyrColors.primary : ZephyrColors.textDim,
                            size: 26,
                          ),
                          onPressed: () => playerNotifier.toggleQueueMode(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),

                    // Bottom Utility Row (Spotify style: Devices on left, Share & Queue on right)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // Left: Connect to Device
                        InkWell(
                          onTap: () => DevicesModal.show(context),
                          borderRadius: BorderRadius.circular(20),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.devices_rounded,
                                  size: 22,
                                  color: !isPlayerDevice ? ZephyrColors.primary : ZephyrColors.textDim,
                                ),
                                if (!isPlayerDevice && activeDeviceName != null) ...[
                                  const SizedBox(width: 6),
                                  Text(
                                    activeDeviceName,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: ZephyrColors.primary,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),

                        // Right: Share & Queue Buttons
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.share_outlined, color: ZephyrColors.textDim, size: 22),
                              tooltip: 'Share',
                              onPressed: () => showShareDialog(context, ref, track),
                            ),
                            const SizedBox(width: 4),
                            IconButton(
                              icon: const Icon(Icons.queue_music_rounded, color: ZephyrColors.textDim, size: 24),
                              tooltip: 'Play Queue',
                              onPressed: () => _showQueueBottomSheet(context, ref),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                  // Lyrics Card ("Lyrics" / "Testi")
                  Container(
                    decoration: BoxDecoration(
                      color: Color.alphaBlend(ambientColor.withValues(alpha: 0.35), ZephyrColors.bgCard),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                    ),
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Lyrics',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: ZephyrColors.text,
                              ),
                            ),
                            Row(
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.share_outlined, color: ZephyrColors.text, size: 20),
                                  onPressed: () => showShareDialog(context, ref, track),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.fullscreen, color: ZephyrColors.text, size: 22),
                                  onPressed: () => _openFullscreenLyrics(context, track),
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          height: 220,
                          child: _isLoadingMetadata
                              ? const Center(child: CircularProgressIndicator(color: ZephyrColors.primary))
                              : _buildLyricsView(isPreview: true),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

      return Container(
        color: ZephyrColors.bgDark,
        child: Row(
          children: [
            // Center Pane: Synced Lyrics
            Expanded(
              flex: 7,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 800),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color.alphaBlend(ambientColor.withValues(alpha: 0.25), ZephyrColors.bgDark),
                      Color.alphaBlend(ambientColor.withValues(alpha: 0.10), ZephyrColors.bgDark),
                      ZephyrColors.bgDark,
                    ],
                    stops: const [0.0, 0.5, 1.0],
                  ),
                ),
                child: Material(
                  color: Colors.transparent,
                  child: _isLoadingMetadata
                      ? const Center(child: CircularProgressIndicator(color: ZephyrColors.primary))
                      : _buildLyricsView(),
                ),
              ),
            ),

            const VerticalDivider(width: 1, color: ZephyrColors.bgLight),

            // Right Pane: Song details only
            SizedBox(
              width: context.scale(380),
              child: Padding(
                padding: EdgeInsets.all(context.scale(24.0)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: ambientColor.withValues(alpha: 0.35),
                              blurRadius: 32,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: CoverImage(
                          videoId: track.videoId,
                          coverUrl: track.coverUrl,
                          size: context.scale(320),
                          borderRadius: 12,
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: GestureDetector(
                            onSecondaryTapDown: (details) {
                              showPlayerSongContextMenu(context, ref, track, details.globalPosition);
                            },
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    Flexible(
                                      child: Text(
                                        track.title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 20,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    ZephyrVisualizer(
                                      isPlaying: isPlaying,
                                      barColor: ambientColor,
                                      height: 18,
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                ArtistLinks(
                                  track: track,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    color: ZephyrColors.textDim,
                                  ),
                                  maxLines: 2,
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        FavoriteButton(
                          isFavorite: isFav,
                          size: 24,
                          onTap: () => libraryNotifier.toggleFavorite(track),
                        ),
                        const SizedBox(width: 8),
                        PopupMenuButton<String>(
                          icon: const Icon(Icons.more_vert, color: ZephyrColors.textDim, size: 24),
                          color: ZephyrColors.bgCard,
                          onSelected: (val) => _handlePlayerMenuSelection(context, ref, track, val),
                          itemBuilder: (context) {
                            final validArtists = track.artists.where((a) => a.trim().isNotEmpty).toList();
                            return [
                              const PopupMenuItem(
                                value: 'go_to_album',
                                child: Row(
                                  children: [
                                    Icon(Icons.album, size: 20, color: ZephyrColors.textDim),
                                    SizedBox(width: 10),
                                    Text('Go to album'),
                                  ],
                                ),
                              ),
                              for (int i = 0; i < validArtists.length; i++)
                                PopupMenuItem(
                                  value: 'go_to_artist_$i',
                                  child: Row(
                                    children: [
                                      const Icon(Icons.person, size: 20, color: ZephyrColors.textDim),
                                      const SizedBox(width: 10),
                                      Text(validArtists.length == 1 ? 'Go to artist' : 'Go to ${validArtists[i]}'),
                                    ],
                                  ),
                                ),
                              if (validArtists.isEmpty)
                                const PopupMenuItem(
                                  value: 'go_to_artist_0',
                                  child: Row(
                                    children: [
                                      Icon(Icons.person, size: 20, color: ZephyrColors.textDim),
                                      SizedBox(width: 10),
                                      Text('Go to artist'),
                                    ],
                                  ),
                                ),
                              const PopupMenuItem(
                                value: 'share',
                                child: Row(
                                  children: [
                                    Icon(Icons.share_rounded, size: 20, color: ZephyrColors.textDim),
                                    SizedBox(width: 10),
                                    Text('Share song'),
                                  ],
                                ),
                              ),
                            ];
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: ZephyrColors.bgDark,
      body: Container(
        padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 32),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color.alphaBlend(ambientColor.withValues(alpha: 0.35), ZephyrColors.bgDark),
              Color.alphaBlend(ambientColor.withValues(alpha: 0.15), ZephyrColors.bgDark),
              ZephyrColors.bgDark,
            ],
            stops: const [0.0, 0.4, 1.0],
          ),
        ),
        child: Row(
          children: [
            // Left Pane: Album Art and Controls
            Expanded(
              flex: 5,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: ambientColor.withValues(alpha: 0.45),
                          blurRadius: 40,
                          spreadRadius: 4,
                        ),
                      ],
                    ),
                    child: CoverImage(
                      videoId: track.videoId,
                      coverUrl: track.coverUrl,
                      size: 320,
                      borderRadius: 16,
                    ),
                  ),
                  const SizedBox(height: 32),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onSecondaryTapDown: (details) {
                            showPlayerSongContextMenu(context, ref, track, details.globalPosition);
                          },
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  Flexible(
                                    child: Text(
                                      track.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 24,
                                        fontWeight: FontWeight.w600,
                                        color: ZephyrColors.text,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  ZephyrVisualizer(
                                    isPlaying: isPlaying,
                                    barColor: ambientColor,
                                    height: 22,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              ArtistLinks(
                                track: track,
                                style: const TextStyle(
                                  fontSize: 16,
                                  color: ZephyrColors.textDim,
                                ),
                                onNavigate: () {
                                  if (Navigator.of(context).canPop()) {
                                    Navigator.of(context).pop();
                                  }
                                },
                              ),
                            ],
                          ),
                        ),
                      ),
                      FavoriteButton(
                        isFavorite: isFav,
                        size: 28,
                        onTap: () => libraryNotifier.toggleFavorite(track),
                      ),
                      PopupMenuButton<String>(
                        icon: const Icon(Icons.more_vert, color: ZephyrColors.textDim, size: 28),
                        color: ZephyrColors.bgCard,
                        onSelected: (val) => _handlePlayerMenuSelection(context, ref, track, val),
                        itemBuilder: (context) {
                          final validArtists = track.artists.where((a) => a.trim().isNotEmpty).toList();
                          return [
                            const PopupMenuItem(
                              value: 'go_to_album',
                              child: Row(
                                children: [
                                  Icon(Icons.album, size: 20, color: ZephyrColors.textDim),
                                  SizedBox(width: 10),
                                  Text('Go to album'),
                                ],
                              ),
                            ),
                            for (int i = 0; i < validArtists.length; i++)
                              PopupMenuItem(
                                value: 'go_to_artist_$i',
                                child: Row(
                                  children: [
                                    const Icon(Icons.person, size: 20, color: ZephyrColors.textDim),
                                    const SizedBox(width: 10),
                                    Text(validArtists.length == 1 ? 'Go to artist' : 'Go to ${validArtists[i]}'),
                                  ],
                                ),
                              ),
                            if (validArtists.isEmpty)
                              const PopupMenuItem(
                                value: 'go_to_artist_0',
                                child: Row(
                                  children: [
                                    Icon(Icons.person, size: 20, color: ZephyrColors.textDim),
                                    SizedBox(width: 10),
                                    Text('Go to artist'),
                                  ],
                                ),
                              ),
                            const PopupMenuItem(
                              value: 'share',
                              child: Row(
                                children: [
                                  Icon(Icons.share_rounded, size: 20, color: ZephyrColors.textDim),
                                  SizedBox(width: 10),
                                  Text('Share song'),
                                ],
                              ),
                            ),
                          ];
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // SeekBar
                  Consumer(
                    builder: (context, ref, _) {
                      final pos = ref.watch(playerProvider.select((s) => s.position));
                      final dur = ref.watch(playerProvider.select((s) => s.effectiveDuration));
                      final loading = ref.watch(playerProvider.select((s) => s.isLoading));
                      return SeekBar(
                        position: pos,
                        duration: dur,
                        isLoading: loading,
                        onChangeEnd: (duration) {
                          playerNotifier.seek(duration);
                        },
                      );
                    },
                  ),
                  const SizedBox(height: 16),

                  // Controls
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        icon: Icon(
                          Icons.shuffle,
                          color: isShuffled ? ZephyrColors.primary : ZephyrColors.textDim,
                          size: 22,
                        ),
                        onPressed: () => playerNotifier.toggleShuffle(),
                      ),
                      const SizedBox(width: 12),
                      IconButton(
                        icon: const Icon(Icons.skip_previous, color: ZephyrColors.text, size: 32),
                        onPressed: () => playerNotifier.playPrevious(),
                      ),
                      const SizedBox(width: 16),
                      if (isLoading)
                        const SizedBox(
                          width: 48,
                          height: 48,
                          child: CircularProgressIndicator(
                            strokeWidth: 3,
                            valueColor: AlwaysStoppedAnimation<Color>(ZephyrColors.primary),
                          ),
                        )
                      else
                        Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: ambientColor.withValues(alpha: 0.5),
                                blurRadius: 20,
                                spreadRadius: 2,
                              ),
                            ],
                          ),
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              shape: const CircleBorder(),
                              padding: const EdgeInsets.all(16),
                              backgroundColor: ZephyrColors.text,
                              foregroundColor: ZephyrColors.bgDark,
                              elevation: 4,
                            ),
                            onPressed: () => playerNotifier.togglePlayPause(),
                            child: Icon(
                              isPlaying ? Icons.pause : Icons.play_arrow,
                              size: 32,
                            ),
                          ),
                        ),
                      const SizedBox(width: 16),
                      IconButton(
                        icon: const Icon(Icons.skip_next, color: ZephyrColors.text, size: 32),
                        onPressed: () => playerNotifier.playNext(),
                      ),
                      const SizedBox(width: 12),
                      IconButton(
                        icon: Icon(
                          repeatMode == 'one'
                              ? Icons.repeat_one
                              : Icons.repeat,
                          color: repeatMode != 'off' ? ZephyrColors.primary : ZephyrColors.textDim,
                          size: 22,
                        ),
                        onPressed: () => playerNotifier.toggleQueueMode(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: 200,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        IconButton(
                          icon: Icon(
                            volume == 0
                                ? Icons.volume_off
                                : (volume < 0.5 ? Icons.volume_down : Icons.volume_up),
                            color: volume == 0 ? ZephyrColors.error : ZephyrColors.textDim,
                            size: 20,
                          ),
                          tooltip: volume == 0 ? 'Unmute' : 'Mute',
                          onPressed: () => playerNotifier.toggleMute(),
                        ),
                        Expanded(
                          child: SliderTheme(
                            data: const SliderThemeData(
                              trackHeight: 4,
                              thumbShape: RoundSliderThumbShape(enabledThumbRadius: 6),
                              overlayShape: RoundSliderOverlayShape(overlayRadius: 14),
                              activeTrackColor: ZephyrColors.primary,
                              inactiveTrackColor: ZephyrColors.bgLight,
                              thumbColor: ZephyrColors.primary,
                            ),
                            child: Slider(
                              min: 0.0,
                              max: 1.0,
                              value: volume,
                              onChanged: (val) {
                                playerNotifier.setVolume(val);
                              },
                            ),
                          ),
                        ),
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 8.0),
                          child: Icon(Icons.volume_up, color: ZephyrColors.textDim, size: 20),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(width: 48),
            
            // Vertical Separator
            Container(width: 1, color: ZephyrColors.bgLight),

            const SizedBox(width: 48),

            // Right Pane: Lyrics / Related Tabbed View
            Expanded(
              flex: 6,
              child: Column(
                children: [
                  TabBar(
                    controller: _tabController,
                    labelColor: ZephyrColors.text,
                    unselectedLabelColor: ZephyrColors.textDim,
                    indicatorColor: ZephyrColors.primary,
                    dividerColor: Colors.transparent,
                    tabs: const [
                      Tab(text: 'Lyrics'),
                      Tab(text: 'Related'),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: TabBarView(
                      controller: _tabController,
                      children: [
                        // Tab 1: Synced Lyrics
                        _isLoadingMetadata
                            ? const Center(child: CircularProgressIndicator(color: ZephyrColors.primary))
                            : _buildLyricsView(),

                        // Tab 2: Related Songs
                        _isLoadingRelated
                            ? const Center(child: CircularProgressIndicator(color: ZephyrColors.primary))
                            : _buildRelatedView(),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  double _getResponsiveLyricsFontSize(BuildContext context, {required bool isInline}) {
    final media = MediaQuery.of(context);
    final width = media.size.width;
    final height = media.size.height;

    if (isInline) {
      if (width < 900 || height < 600) {
        return 16.0;
      } else if (width < 1200 || height < 750) {
        return 19.0;
      } else {
        return 24.0;
      }
    } else {
      if (width < 700 || height < 550) {
        return 14.0;
      } else if (width < 950 || height < 700) {
        return 16.0;
      } else {
        return 18.0;
      }
    }
  }

  Widget _buildLyricsView({
    ScrollController? controller,
    bool isModal = false,
    bool isPreview = false,
    int? activeLineIndex,
  }) {
    final isMobile = MediaQuery.of(context).size.width < 700;
    final fontSize = isMobile ? 18.0 : _getResponsiveLyricsFontSize(context, isInline: widget.isInline);
    final isSmallWindow = MediaQuery.of(context).size.height < 650 || MediaQuery.of(context).size.width < 950;

    if (_lrcLines.isEmpty) {
      final currentTrack = ref.read(playerProvider).currentTrack;
      final plain = _enrichedMetadata?.lyricsText ??
          currentTrack?.lyricsText ??
          (_enrichedMetadata?.lyricsLrc != null && !_enrichedMetadata!.lyricsLrc!.contains('[') ? _enrichedMetadata!.lyricsLrc : null) ??
          (currentTrack?.lyricsLrc != null && !currentTrack!.lyricsLrc!.contains('[') ? currentTrack.lyricsLrc : null);

      if (plain != null && plain.trim().isNotEmpty) {
        return ScrollConfiguration(
          behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
          child: SingleChildScrollView(
            controller: controller,
            physics: isPreview ? const NeverScrollableScrollPhysics() : const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
            child: Text(
              plain,
              style: TextStyle(
                fontSize: fontSize,
                height: 1.8,
                color: ZephyrColors.textDim,
              ),
            ),
          ),
        );
      }

      return const Center(
        child: Text(
          'Lyrics not available for this track.',
          style: TextStyle(color: ZephyrColors.textDim),
        ),
      );
    }

    final playerNotifier = ref.read(playerProvider.notifier);

    return Stack(
      children: [
        // Synced Lyrics List View
        NotificationListener<ScrollNotification>(
          onNotification: (ScrollNotification notification) {
            if (notification is UserScrollNotification &&
                notification.direction != ScrollDirection.idle) {
              if (_isSynced) {
                setState(() {
                  _isSynced = false;
                });
              }
            }
            return false;
          },
          child: ScrollConfiguration(
            behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
            child: ListView.builder(
              controller: controller ?? _lyricsScrollController,
              physics: isPreview ? const NeverScrollableScrollPhysics() : const BouncingScrollPhysics(),
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 32,
                bottom: isPreview ? 24 : MediaQuery.of(context).size.height * 0.4,
              ),
              itemCount: _lrcLines.length,
              itemBuilder: (context, index) {
              final line = _lrcLines[index];
              final isActive = index == (activeLineIndex ?? _activeLrcIndex);
              return Align(
                key: isModal
                    ? (index < _modalLyricKeys.length ? _modalLyricKeys[index] : null)
                    : (index < _lyricKeys.length ? _lyricKeys[index] : null),
                alignment: Alignment.centerLeft,
                child: InkWell(
                  onTap: () {
                    // Click to seek to lyric timestamp
                    playerNotifier.seek(line.timestamp);
                    // Turn synchronization back on immediately
                    setState(() {
                      _isSynced = true;
                      _activeLrcIndex = index;
                    });
                    // Instantly scroll to active position
                    if (index >= 0 &&
                        index < _lyricKeys.length &&
                        _lyricsScrollController.hasClients &&
                        _lyricsScrollController.position.hasContentDimensions) {
                      final key = _lyricKeys[index];
                      final context = key.currentContext;
                      if (context != null) {
                        Scrollable.ensureVisible(
                          context,
                          alignment: 0.5,
                          duration: const Duration(milliseconds: 250),
                          curve: Curves.easeOutCubic,
                        );
                      }
                    }
                  },
                  borderRadius: BorderRadius.circular(8),
                  hoverColor: Colors.white.withValues(alpha: 0.05),
                  child: Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: isSmallWindow ? 8 : 12,
                    ),
                    width: double.infinity,
                    child: AnimatedScale(
                      scale: isActive ? 1.1 : 1.0,
                      duration: const Duration(milliseconds: 200),
                      alignment: Alignment.centerLeft,
                      child: AnimatedDefaultTextStyle(
                        duration: const Duration(milliseconds: 200),
                        style: TextStyle(
                          fontSize: fontSize,
                          fontWeight: FontWeight.w600,
                          color: isActive
                              ? Colors.white
                              : Colors.white.withValues(alpha: 0.35),
                        ),
                        child: Text(line.text),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),

        // Non-invasive "Sync Lyrics" pill button overlay
        AnimatedPositioned(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          bottom: _isSynced ? -60 : 24,
          left: 0,
          right: 0,
          child: Center(
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 200),
              opacity: _isSynced ? 0.0 : 1.0,
              child: ElevatedButton.icon(
                onPressed: () {
                  setState(() {
                    _isSynced = true;
                    _hasInitialScrolled = false;
                  });
                  final pos = ref.read(playerProvider).position;
                  _updateLyricsScrolling(pos);
                },
                icon: const Icon(Icons.sync, color: Colors.black, size: 16),
                label: const Text(
                  'Sync Lyrics',
                  style: TextStyle(
                    color: Colors.black,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  elevation: 6,
                  shadowColor: Colors.black.withValues(alpha: 0.4),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRelatedView() {
    if (_relatedData == null || !_relatedData!.containsKey('sections')) {
      return const Center(
        child: Text(
          'No related content found.',
          style: TextStyle(color: ZephyrColors.textDim),
        ),
      );
    }

    final List sections = _relatedData!['sections'] ?? [];
    if (sections.isEmpty) {
      return const Center(child: Text('No related songs available.'));
    }

    return ListView.builder(
      itemCount: sections.length,
      itemBuilder: (context, sectionIdx) {
        final section = sections[sectionIdx];
        final title = section['title'] ?? 'Recommendation';
        final contents = section['contents'];

        if (contents == null || (contents is List && contents.isEmpty) || (contents is String && contents.isEmpty)) {
          return const SizedBox.shrink();
        }

        // If it's a string, it's bio details
        if (contents is String) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: ZephyrColors.primary),
                ),
                const SizedBox(height: 8),
                Text(
                  contents,
                  style: const TextStyle(color: ZephyrColors.textDim, fontSize: 13, height: 1.5),
                ),
              ],
            ),
          );
        }
        final listContents = contents as List;

        return Padding(
          padding: const EdgeInsets.only(bottom: 24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: ZephyrColors.primary),
              ),
              const SizedBox(height: 12),
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: listContents.length.clamp(0, 5), // limit to top 5
                itemBuilder: (context, index) {
                  final item = listContents[index];
                  final name = item['title'] ?? item['name'] ?? '';
                  final videoId = item['videoId'];
                  final artistNames = (item['artists'] as List?)?.map((e) => e['name'].toString()).join(', ') ?? '';

                  return Material(
                    type: MaterialType.transparency,
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.music_note, color: ZephyrColors.textDim),
                      title: Text(name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                      subtitle: Text(artistNames, style: const TextStyle(fontSize: 12, color: ZephyrColors.textDim)),
                      onTap: videoId != null
                          ? () {
                              final newTrack = Track(
                                videoId: videoId,
                                title: name,
                                artists: [artistNames],
                                downloadStatus: 'not_in_db',
                                isDownloaded: false,
                              );
                              ref.read(playerProvider.notifier).playTrack(newTrack, [newTrack]);
                            }
                          : null,
                    ),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }
}
