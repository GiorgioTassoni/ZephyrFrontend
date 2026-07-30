import 'dart:async';
import 'package:flutter/material.dart';
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
  Map<String, dynamic>? _relatedData;
  bool _isLoadingMetadata = false;
  bool _isLoadingRelated = false;
  String? _lastVideoId;
  int _activeLrcIndex = -1;
  bool _isSynced = true;
  bool _hasRetriedLyricsOnPlay = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(_onTabChanged);
  }

  void _onTabChanged() {
    if (_tabController.index == 1 && _relatedData == null && !_isLoadingRelated && _lastVideoId != null) {
      _fetchRelatedTracks(_lastVideoId!);
    }
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    _lyricsScrollController.dispose();
    super.dispose();
  }

  Future<void> _fetchMetadataAndRelated(String videoId, {bool force = false}) async {
    if (_lastVideoId == videoId && !force) return;
    if (_lastVideoId != videoId) {
      _hasRetriedLyricsOnPlay = false;
    }
    _lastVideoId = videoId;

    setState(() {
      _isLoadingMetadata = true;
      _isLoadingRelated = false;
      _lrcLines = [];
      _lyricKeys.clear();
      _relatedData = null;
      _activeLrcIndex = -1;
      _isSynced = true;
    });

    // 1. Fetch Track Metadata (Lyrics)
    try {
      final metadata = await _api.getTrackMetadata(videoId);
      _enrichedMetadata = metadata;
      
      if (metadata.downloadStatus == 'completed' && metadata.localPath != null) {
        // Track is downloaded, lyrics are parsed
      }
      
      // Parse LRC if available
      final lrcText = resLyricsLrc(metadata);
      if (lrcText != null && lrcText.isNotEmpty) {
        _parseLrc(lrcText);
      }
    } catch (e) {
      // Handle error silently or show placeholder
    } finally {
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
    final regex = RegExp(r'\[(\d+):(\d{2})(?:\.(\d+))?\](.*)');

    for (final line in lines) {
      final match = regex.firstMatch(line.trim());
      if (match != null) {
        final min = int.tryParse(match.group(1) ?? '0') ?? 0;
        final sec = int.tryParse(match.group(2) ?? '0') ?? 0;
        final msStr = match.group(3) ?? '0';
        final ms = ((double.tryParse('0.$msStr') ?? 0.0) * 1000).round();
        final text = match.group(4) ?? '';
        final timestamp = Duration(minutes: min, seconds: sec, milliseconds: ms);
        parsed.add(LrcLine(timestamp: timestamp, text: text.trim()));
      }
    }
    // Sort by timestamp
    parsed.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    setState(() {
      _lrcLines = parsed;
      _lyricKeys.clear();
      _lyricKeys.addAll(List.generate(parsed.length, (_) => GlobalKey()));
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

    if (activeIndex != -1 && activeIndex != _activeLrcIndex) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() {
          _activeLrcIndex = activeIndex;
        });
 
        // Animate/scroll to active line if synced
        if (_isSynced &&
            _activeLrcIndex >= 0 &&
            _activeLrcIndex < _lyricKeys.length &&
            _lyricsScrollController.hasClients &&
            _lyricsScrollController.position.hasContentDimensions) {
          final key = _lyricKeys[_activeLrcIndex];
          final context = key.currentContext;
          if (context != null) {
            Scrollable.ensureVisible(
              context,
              alignment: 0.5,
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOutCubic,
            );
          } else {
            final estimate = _activeLrcIndex * 58.0;
            _lyricsScrollController.jumpTo(
              estimate.clamp(0.0, _lyricsScrollController.position.maxScrollExtent),
            );
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              final retryContext = key.currentContext;
              if (retryContext != null) {
                Scrollable.ensureVisible(
                  retryContext,
                  alignment: 0.5,
                  duration: const Duration(milliseconds: 150),
                  curve: Curves.easeOutCubic,
                );
              }
            });
          }
        }
      });
    }
  }

  Future<void> _handlePlayerMenuSelection(
    BuildContext context,
    WidgetRef ref,
    Track track,
    String value,
  ) async {
    final navNotifier = ref.read(navigationProvider.notifier);
    final isModal = Navigator.of(context).canPop() && !widget.isInline;

    if (value == 'go_to_album') {
      if (isModal) Navigator.of(context).pop();

      // 1. Direct albumId
      if (track.albumId != null && track.albumId!.isNotEmpty) {
        navNotifier.navigateTo(ScreenState(type: ScreenType.album, id: track.albumId!));
        return;
      }

      // 2. Search YTMusic remotely for album (remote: true)
      if (track.album != null && track.album!.isNotEmpty) {
        try {
          final query = '${track.album} ${track.artists.isNotEmpty ? track.artists.first : ''}'.trim();
          final searchRes = await _api.search(query, remote: true);
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
              navNotifier.navigateTo(ScreenState(type: ScreenType.album, id: id));
              return;
            }
          }
        } catch (_) {}

        ZephyrToast.show(context, 'Could not find album page for "${track.album}"');
      } else {
        ZephyrToast.show(context, 'No album information available for this track');
      }
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

        ZephyrToast.show(context, 'Could not find artist page for "$name"');
      }
    } else if (value == 'share') {
      showShareDialog(context, ref, track);
    } else if (value == 'download') {
      _api.queueDownload(track.videoId);
      ZephyrToast.show(context, 'Download queued for "${track.title}"');
    }
  }

  @override
  Widget build(BuildContext context) {
    final playerState = ref.watch(playerProvider);
    final playerNotifier = ref.read(playerProvider.notifier);
    final libraryNotifier = ref.read(libraryProvider.notifier);

    if (playerState.currentTrack == null) {
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

    final track = playerState.currentTrack!;
    
    // Auto fetch metadata and related when song changes
    _fetchMetadataAndRelated(track.videoId);

    // One-time retry when music starts playing if lyrics were missing on initial load
    if (playerState.isPlaying &&
        playerState.position.inMilliseconds > 0 &&
        !_hasRetriedLyricsOnPlay &&
        !_isLoadingMetadata &&
        _lrcLines.isEmpty &&
        (_enrichedMetadata?.lyricsText == null || _enrichedMetadata!.lyricsText!.trim().isEmpty)) {
      _hasRetriedLyricsOnPlay = true;
      Future.microtask(() {
        if (mounted) {
          _fetchMetadataAndRelated(track.videoId, force: true);
        }
      });
    }
    
    // Auto update lyrics highlighted line based on player position
    _updateLyricsScrolling(playerState.position);

    final isFav = libraryNotifier.isFavorite(track.videoId);

    if (widget.isInline) {
      return Container(
        color: ZephyrColors.bgDark,
        child: Row(
          children: [
            // Center Pane: Synced Lyrics (the only thing with the background should be the lyrics)
            Expanded(
              flex: 7,
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      const Color(0xFF2A1B07), // Ambient deep bronze/amber-chocolate shade
                      const Color(0xFF160E03), // Very dark bronze tint
                      ZephyrColors.bgDark,     // Smooth transition to dark theme background
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
                      child: CoverImage(
                        videoId: track.videoId,
                        coverUrl: track.coverUrl,
                        size: context.scale(320),
                        borderRadius: 12,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                track.title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
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
                        const SizedBox(width: 8),
                        IconButton(
                          icon: Icon(
                            isFav ? Icons.favorite : Icons.favorite_border,
                            color: isFav ? ZephyrColors.primary : ZephyrColors.textDim,
                            size: 24,
                          ),
                          onPressed: () => libraryNotifier.toggleFavorite(track),
                        ),
                        PopupMenuButton<String>(
                          icon: const Icon(Icons.more_vert, color: ZephyrColors.textDim, size: 24),
                          color: ZephyrColors.bgCard,
                          onSelected: (val) => _handlePlayerMenuSelection(context, ref, track, val),
                          itemBuilder: (context) {
                            final validArtists = track.artists.where((a) => a.trim().isNotEmpty).toList();
                            return [
                              if (track.album != null && track.album!.isNotEmpty)
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
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.keyboard_arrow_down, size: 32),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('NOW PLAYING'),
        centerTitle: true,
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              ZephyrColors.bgLight.withOpacity(0.5),
              ZephyrColors.bgDark,
            ],
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 24),
        child: Row(
          children: [
            // Left Pane: Album cover, titles, seekbar, player controls
            Expanded(
              flex: 5,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CoverImage(
                    videoId: track.videoId,
                    coverUrl: track.coverUrl,
                    size: 320,
                    borderRadius: 16,
                  ),
                  const SizedBox(height: 32),
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
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: ZephyrColors.text,
                              ),
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
                      IconButton(
                        icon: Icon(
                          isFav ? Icons.favorite : Icons.favorite_border,
                          color: isFav ? ZephyrColors.primary : ZephyrColors.textDim,
                          size: 28,
                        ),
                        onPressed: () => libraryNotifier.toggleFavorite(track),
                      ),
                      PopupMenuButton<String>(
                        icon: const Icon(Icons.more_vert, color: ZephyrColors.textDim, size: 28),
                        color: ZephyrColors.bgCard,
                        onSelected: (val) => _handlePlayerMenuSelection(context, ref, track, val),
                        itemBuilder: (context) {
                          final validArtists = track.artists.where((a) => a.trim().isNotEmpty).toList();
                          return [
                            if (track.album != null && track.album!.isNotEmpty)
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
                  SeekBar(
                    position: playerState.position,
                    duration: playerState.duration,
                    onChangeEnd: (duration) {
                      playerNotifier.seek(duration);
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
                          color: playerState.isShuffled ? ZephyrColors.primary : ZephyrColors.textDim,
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
                      if (playerState.isLoading)
                        const SizedBox(
                          width: 48,
                          height: 48,
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
                          ),
                          onPressed: () => playerNotifier.togglePlayPause(),
                          child: Icon(
                            playerState.isPlaying ? Icons.pause : Icons.play_arrow,
                            size: 32,
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
                          playerState.queueMode == 'repeat_one'
                              ? Icons.repeat_one
                              : Icons.repeat,
                          color: playerState.queueMode != 'normal' ? ZephyrColors.primary : ZephyrColors.textDim,
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
                            playerState.volume == 0
                                ? Icons.volume_off
                                : (playerState.volume < 0.5 ? Icons.volume_down : Icons.volume_up),
                            color: playerState.volume == 0 ? ZephyrColors.error : ZephyrColors.textDim,
                            size: 20,
                          ),
                          tooltip: playerState.volume == 0 ? 'Unmute' : 'Mute',
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
                              value: playerState.volume,
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

  Widget _buildLyricsView() {
    if (_lrcLines.isEmpty) {
      // Check if there is plain lyrics
      final plain = _enrichedMetadata != null ? (_enrichedMetadata as dynamic).lyricsText as String? : null;
      if (plain != null && plain.isNotEmpty) {
        return ScrollConfiguration(
          behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
          child: SingleChildScrollView(
            child: Padding(
              padding: EdgeInsets.only(
                left: widget.isInline ? 64.0 : 16.0,
                right: 24.0,
                top: 40.0,
                bottom: 40.0,
              ),
              child: Text(
                plain,
                style: TextStyle(
                  fontSize: widget.isInline ? 22 : 16,
                  height: 1.8,
                  color: ZephyrColors.textDim,
                ),
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
            // If the user scrolls manually, disable automatic scrolling synchronization
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
              controller: _lyricsScrollController,
              padding: EdgeInsets.only(
                left: widget.isInline ? 64.0 : 24.0,
                right: 24.0,
                top: 100.0,
                bottom: 100.0,
              ),
              itemCount: _lrcLines.length,
              itemBuilder: (context, index) {
              final line = _lrcLines[index];
              final isActive = index == _activeLrcIndex;
              return Align(
                key: _lyricKeys[index],
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
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                    width: double.infinity,
                    child: AnimatedDefaultTextStyle(
                      duration: const Duration(milliseconds: 200),
                      style: TextStyle(
                        fontSize: widget.isInline
                            ? (isActive ? 30 : 22)
                            : (isActive ? 24 : 18),
                        fontWeight: isActive ? FontWeight.bold : FontWeight.w500,
                        color: isActive
                            ? const Color(0xFFEEEEEE)
                            : Colors.white.withValues(alpha: 0.35),
                      ),
                      child: Text(line.text),
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
                  });
                  // Immediately scroll back to active line
                  if (_activeLrcIndex != -1 &&
                      _activeLrcIndex < _lyricKeys.length &&
                      _lyricsScrollController.hasClients &&
                      _lyricsScrollController.position.hasContentDimensions) {
                    final key = _lyricKeys[_activeLrcIndex];
                    final context = key.currentContext;
                    if (context != null) {
                      Scrollable.ensureVisible(
                        context,
                        alignment: 0.5,
                        duration: const Duration(milliseconds: 250),
                        curve: Curves.easeOutCubic,
                      );
                    } else {
                      final estimate = _activeLrcIndex * 58.0;
                      _lyricsScrollController.jumpTo(
                        estimate.clamp(0.0, _lyricsScrollController.position.maxScrollExtent),
                      );
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (!mounted) return;
                        final retryContext = key.currentContext;
                        if (retryContext != null) {
                          Scrollable.ensureVisible(
                            retryContext,
                            alignment: 0.5,
                            duration: const Duration(milliseconds: 150),
                            curve: Curves.easeOutCubic,
                          );
                        }
                      });
                    }
                  }
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
