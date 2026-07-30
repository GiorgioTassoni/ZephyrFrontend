import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:audioplayers/audioplayers.dart' as ap;
import 'package:shared_preferences/shared_preferences.dart';
import '../api/zephyr_api.dart';
import '../models/models.dart';
import 'auth_provider.dart';
import 'library_provider.dart';

class ZephyrPlayerState {
  final Track? currentTrack;
  final List<Track> queue;
  final List<Track> originalQueue; // keeps the original order before shuffle
  final List<Track> userQueue; // Queue based on "add to queue" button with priority
  final int currentIndex;
  final bool isPlaying;
  final Duration position;
  final Duration duration;
  final String queueMode; // 'normal', 'repeat_all', 'repeat_one'
  final bool isShuffled;
  final String? errorMessage;
  final bool isLoading;
  final double volume;
  final double lastNonMutedVolume;

  ZephyrPlayerState({
    this.currentTrack,
    this.queue = const [],
    this.originalQueue = const [],
    this.userQueue = const [],
    this.currentIndex = -1,
    this.isPlaying = false,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.queueMode = 'normal',
    this.isShuffled = false,
    this.errorMessage,
    this.isLoading = false,
    this.volume = 1.0,
    this.lastNonMutedVolume = 1.0,
  });

  ZephyrPlayerState copyWith({
    Track? currentTrack,
    bool? nullTrack,
    List<Track>? queue,
    List<Track>? originalQueue,
    List<Track>? userQueue,
    int? currentIndex,
    bool? isPlaying,
    Duration? position,
    Duration? duration,
    String? queueMode,
    bool? isShuffled,
    String? errorMessage,
    bool? isLoading,
    double? volume,
    double? lastNonMutedVolume,
  }) {
    return ZephyrPlayerState(
      currentTrack: nullTrack == true ? null : (currentTrack ?? this.currentTrack),
      queue: queue ?? this.queue,
      originalQueue: originalQueue ?? this.originalQueue,
      userQueue: userQueue ?? this.userQueue,
      currentIndex: currentIndex ?? this.currentIndex,
      isPlaying: isPlaying ?? this.isPlaying,
      position: position ?? this.position,
      duration: duration ?? this.duration,
      queueMode: queueMode ?? this.queueMode,
      isShuffled: isShuffled ?? this.isShuffled,
      errorMessage: errorMessage ?? this.errorMessage,
      isLoading: isLoading ?? this.isLoading,
      volume: volume ?? this.volume,
      lastNonMutedVolume: lastNonMutedVolume ?? this.lastNonMutedVolume,
    );
  }
}

class PlayerNotifier extends Notifier<ZephyrPlayerState> {
  final ap.AudioPlayer _audioPlayer = ap.AudioPlayer();
  final ZephyrApi _api = ZephyrApi();
  
  StreamSubscription? _positionSub;
  StreamSubscription? _durationSub;
  StreamSubscription? _stateSub;
  StreamSubscription? _completeSub;

  String? _lastTrackId;
  bool _hasRecordedCurrentTrack = false;
  bool _isInitialLoad = false;

  @override
  ZephyrPlayerState build() {
    _initStreams();
    _loadSavedVolume();
    
    ref.onDispose(() {
      _positionSub?.cancel();
      _durationSub?.cancel();
      _stateSub?.cancel();
      _completeSub?.cancel();
      _audioPlayer.dispose();
    });

    ref.listen(authProvider, (previous, next) {
      if (next.token == null) {
        _audioPlayer.stop();
        state = ZephyrPlayerState();
      }
    });

    return ZephyrPlayerState();
  }

  Future<void> _loadSavedVolume() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedVolume = prefs.getDouble('player_volume');
      if (savedVolume != null) {
        await _audioPlayer.setVolume(savedVolume);
        state = state.copyWith(volume: savedVolume);
      }
    } catch (_) {}
  }

  void _initStreams() {
    _positionSub = _audioPlayer.onPositionChanged.listen((pos) {
      state = state.copyWith(position: pos, isLoading: false);

      // Check if we reached at least half of the song to record history
      if (!_hasRecordedCurrentTrack && state.currentTrack != null) {
        final trackId = state.currentTrack!.videoId;
        final isCorrectTrack = trackId == _lastTrackId;

        final trackDuration = state.currentTrack!.duration;
        final totalSec = (trackDuration != null && trackDuration.inSeconds > 0)
            ? trackDuration.inSeconds
            : state.duration.inSeconds;

        final isListenLimitReached = totalSec > 0
            ? (pos.inSeconds >= totalSec / 2)
            : (pos.inSeconds >= 15);

        if (isCorrectTrack && isListenLimitReached) {
          _hasRecordedCurrentTrack = true;
          final trackToRecord = state.currentTrack!;
          
          // Record locally
          ref.read(libraryProvider.notifier).addListeningHistory(trackToRecord);
          
          // Record in listening history on the backend
          _api.recordListen(trackToRecord.videoId);
        }
      }
    });

    _durationSub = _audioPlayer.onDurationChanged.listen((dur) {
      state = state.copyWith(duration: dur);
    });

    _stateSub = _audioPlayer.onPlayerStateChanged.listen((playerState) {
      state = state.copyWith(
        isPlaying: playerState == ap.PlayerState.playing,
      );
    });

    _completeSub = _audioPlayer.onPlayerComplete.listen((_) {
      _handlePlaybackComplete();
    });
  }

  Future<void> playTrack(Track track, List<Track> playQueue) async {
    // Set flags immediately (synchronously) to avoid any race conditions with audio player listeners
    _lastTrackId = track.videoId;
    _hasRecordedCurrentTrack = false;
    _isInitialLoad = false;

    // If track is missing artist metadata, attempt to enrich it immediately
    Track finalTrack = track;
    if (finalTrack.artists.isEmpty) {
      try {
        final meta = await _api.getTrackMetadata(track.videoId);
        if (meta.artists.isNotEmpty) {
          finalTrack = meta;
        }
      } catch (_) {}
    }

    final foundIndex = playQueue.indexWhere((t) => t.videoId == finalTrack.videoId);
    final newCurrentIndex = foundIndex != -1 ? foundIndex : state.currentIndex;

    state = state.copyWith(
      isLoading: true,
      currentTrack: finalTrack,
      queue: playQueue,
      originalQueue: state.isShuffled ? state.originalQueue : playQueue,
      currentIndex: newCurrentIndex,
      position: Duration.zero,
      duration: Duration.zero,
      errorMessage: null,
    );

    try {
      // Stream URL via local proxy (S-03): the proxy injects
      // Authorization: Bearer <token> — the URL itself has no token.
      final streamUrl = await _api.getStreamProxyUrl(finalTrack.videoId);

      await _audioPlayer.stop();
      await _audioPlayer.setVolume(state.volume);
      await _audioPlayer.play(ap.UrlSource(streamUrl));
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Playback error: $e',
      );
    }
  }

  Future<void> setQueue(List<Track> playQueue, int startFromIndex) async {
    if (playQueue.isEmpty) return;
    if (startFromIndex < 0 || startFromIndex >= playQueue.length) {
      startFromIndex = 0;
    }
    await playTrack(playQueue[startFromIndex], playQueue);
  }

  Future<void> pause() async {
    await _audioPlayer.pause();
  }

  void loadTrackPaused(Track track, List<Track> playQueue) {
    _lastTrackId = track.videoId;
    _hasRecordedCurrentTrack = false; // Let it record if they listen again
    _isInitialLoad = true;

    final foundIndex = playQueue.indexWhere((t) => t.videoId == track.videoId);
    final newCurrentIndex = foundIndex != -1 ? foundIndex : state.currentIndex;

    state = state.copyWith(
      isLoading: false,
      currentTrack: track,
      queue: playQueue,
      originalQueue: state.isShuffled ? state.originalQueue : playQueue,
      currentIndex: newCurrentIndex,
      position: Duration.zero,
      duration: track.duration ?? Duration.zero,
      errorMessage: null,
      isPlaying: false,
    );
  }

  Future<void> resume() async {
    if (state.currentTrack != null) {
      if (_isInitialLoad) {
        _isInitialLoad = false;
        await playTrack(state.currentTrack!, state.queue);
      } else {
        await _audioPlayer.resume();
      }
    }
  }

  Future<void> setVolume(double volume) async {
    await _audioPlayer.setVolume(volume);
    state = state.copyWith(
      volume: volume,
      lastNonMutedVolume: volume > 0 ? volume : state.lastNonMutedVolume,
    );
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble('player_volume', volume);
    } catch (_) {}
  }

  Future<void> toggleMute() async {
    if (state.volume > 0) {
      state = state.copyWith(lastNonMutedVolume: state.volume);
      await setVolume(0.0);
    } else {
      final restoreVol = state.lastNonMutedVolume > 0 ? state.lastNonMutedVolume : 0.8;
      await setVolume(restoreVol);
    }
  }

  Future<void> togglePlayPause() async {
    if (state.isPlaying) {
      await pause();
    } else {
      await resume();
    }
  }

  Future<void> seek(Duration position) async {
    await _audioPlayer.seek(position);
  }

  void _handlePlaybackComplete() {
    if (state.queueMode == 'repeat_one') {
      seek(Duration.zero);
      resume();
    } else {
      playNext();
    }
  }

  Future<List<Track>> _fetchSimilarTracks(String videoId) async {
    try {
      final res = await _api.getRelatedTracks(videoId);
      final List sections = res['sections'] ?? [];
      for (final section in sections) {
        final title = (section['title'] as String?)?.toLowerCase() ?? '';
        if (title.contains('you might also like') || title.contains('similar') || title.contains('recommend')) {
          final contents = section['contents'];
          if (contents is List) {
            final List<Track> tracks = [];
            for (final item in contents) {
              final String? vId = item['videoId'];
              final String? tTitle = item['title'] ?? item['name'];
              if (vId != null && tTitle != null) {
                final artistList = (item['artists'] as List?)
                    ?.map((e) => e['name'].toString())
                    .toList() ?? [];
                
                final thumbnails = item['thumbnails'] as List?;
                final String? rawArtUrl = (thumbnails != null && thumbnails.isNotEmpty) ? thumbnails.last['url'] : null;
                final String? albumArt = rawArtUrl != null ? rawArtUrl.split('=')[0] : null;

                tracks.add(Track(
                  videoId: vId,
                  title: tTitle,
                  artists: artistList,
                  coverUrl: albumArt,
                  downloadStatus: 'not_in_db',
                  isDownloaded: false,
                ));
              }
            }
            return tracks;
          }
        }
      }
    } catch (_) {}
    return [];
  }

  Future<void> playNext() async {
    if (state.userQueue.isNotEmpty) {
      final nextTrack = state.userQueue.first;
      final updatedUserQueue = state.userQueue.sublist(1);
      state = state.copyWith(userQueue: updatedUserQueue);
      await playTrack(nextTrack, state.queue);
      return;
    }

    if (state.queue.isEmpty) return;

    int nextIndex = state.currentIndex + 1;
    if (nextIndex >= state.queue.length) {
      if (state.queueMode == 'repeat_all') {
        nextIndex = 0;
      } else {
        // Queue is finished! Let's check for similar tracks fallback!
        final currentTrack = state.currentTrack;
        if (currentTrack != null) {
          state = state.copyWith(isLoading: true);
          final similarTracks = await _fetchSimilarTracks(currentTrack.videoId);
          if (similarTracks.isNotEmpty) {
            // Pick the first one!
            final nextTrack = similarTracks.first;
            // Play it, and set the new queue to just be this next track!
            await playTrack(nextTrack, [nextTrack]);
            return;
          }
        }

        // Stop playing if no similar tracks are found
        await _audioPlayer.stop();
        state = state.copyWith(
          isPlaying: false,
          position: Duration.zero,
          isLoading: false,
        );
        return;
      }
    }

    await playTrack(state.queue[nextIndex], state.queue);
  }

  Future<void> playPrevious() async {
    if (state.queue.isEmpty) return;

    // If song is more than 3 seconds in, restart the song instead of going to previous
    if (state.position.inSeconds > 3) {
      seek(Duration.zero);
      return;
    }

    int prevIndex = state.currentIndex - 1;
    if (prevIndex < 0) {
      if (state.queueMode == 'repeat_all') {
        prevIndex = state.queue.length - 1;
      } else {
        // Restart current song
        seek(Duration.zero);
        return;
      }
    }

    await playTrack(state.queue[prevIndex], state.queue);
  }

  void toggleShuffle() {
    final currentlyShuffled = state.isShuffled;
    if (state.queue.isEmpty) return;

    if (currentlyShuffled) {
      // Revert to original order
      final currentTrack = state.currentTrack;
      final newIndex = state.originalQueue.indexWhere((t) => t.videoId == currentTrack?.videoId);
      state = state.copyWith(
        isShuffled: false,
        queue: state.originalQueue,
        currentIndex: newIndex,
      );
    } else {
      // Shuffle the queue (but keep current track first or adapt index)
      final originalList = List<Track>.from(state.queue);
      final currentTrack = state.currentTrack;
      
      // Shuffle list
      originalList.shuffle();
      
      // Make sure current track is in the queue and we update its index
      if (currentTrack != null) {
        originalList.removeWhere((t) => t.videoId == currentTrack.videoId);
        originalList.insert(0, currentTrack);
      }
      
      state = state.copyWith(
        isShuffled: true,
        originalQueue: state.queue,
        queue: originalList,
        currentIndex: 0,
      );
    }
  }

  void toggleQueueMode() {
    String nextMode = 'normal';
    if (state.queueMode == 'normal') {
      nextMode = 'repeat_all';
    } else if (state.queueMode == 'repeat_all') {
      nextMode = 'repeat_one';
    } else {
      nextMode = 'normal';
    }
    state = state.copyWith(queueMode: nextMode);
  }

  void addToQueue(Track track) {
    final updatedUserQueue = List<Track>.from(state.userQueue)..add(track);
    if (state.currentTrack == null) {
      playTrack(track, [track]);
    } else {
      state = state.copyWith(userQueue: updatedUserQueue);
    }
  }

  void reorderUserQueue(int oldIndex, int newIndex) {
    if (oldIndex < newIndex) {
      newIndex -= 1;
    }
    final list = List<Track>.from(state.userQueue);
    if (oldIndex >= 0 && oldIndex < list.length && newIndex >= 0 && newIndex <= list.length) {
      final item = list.removeAt(oldIndex);
      list.insert(newIndex, item);
      state = state.copyWith(userQueue: list);
    }
  }

  void removeFromUserQueue(int index) {
    final list = List<Track>.from(state.userQueue);
    if (index >= 0 && index < list.length) {
      list.removeAt(index);
      state = state.copyWith(userQueue: list);
    }
  }

  void clearUserQueue() {
    state = state.copyWith(userQueue: const []);
  }

  void reorderBaseQueue(int oldIndex, int newIndex) {
    final baseStartIndex = state.currentIndex + 1;
    if (baseStartIndex >= state.queue.length) return;

    final actualOldIndex = baseStartIndex + oldIndex;
    int actualNewIndex = baseStartIndex + newIndex;

    if (actualOldIndex < actualNewIndex) {
      actualNewIndex -= 1;
    }

    final list = List<Track>.from(state.queue);
    if (actualOldIndex >= 0 && actualOldIndex < list.length && actualNewIndex >= 0 && actualNewIndex <= list.length) {
      final item = list.removeAt(actualOldIndex);
      list.insert(actualNewIndex, item);
      state = state.copyWith(queue: list);
    }
  }

  void removeFromBaseQueue(int index) {
    final baseStartIndex = state.currentIndex + 1;
    final actualIndex = baseStartIndex + index;
    final list = List<Track>.from(state.queue);
    if (actualIndex >= 0 && actualIndex < list.length) {
      list.removeAt(actualIndex);
      state = state.copyWith(queue: list);
    }
  }
}

final playerProvider = NotifierProvider<PlayerNotifier, ZephyrPlayerState>(PlayerNotifier.new);
