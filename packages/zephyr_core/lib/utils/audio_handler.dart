import 'dart:async';
import 'dart:io';
import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:just_audio/just_audio.dart';
import '../models/models.dart';
import '../api/zephyr_api.dart';
import 'app_logger.dart';
import 'offline_storage.dart';

/// Global AudioHandler instance for Zephyr Music Player.
ZephyrAudioHandler? zephyrAudioHandler;

/// Custom AudioHandler extending BaseAudioHandler to manage background playback,
/// system notification controls, lock screen metadata, audio focus, and headphone events.
class ZephyrAudioHandler extends BaseAudioHandler with SeekHandler {
  final AudioPlayer _player = AudioPlayer();

  VoidCallback? onSkipNext;
  VoidCallback? onSkipPrevious;
  VoidCallback? onTogglePlayPause;
  bool Function()? isPlaybackOwner;
  bool _wasPlayingBeforeInterruption = false;

  ZephyrAudioHandler() {
    _initAudioSession();
    _initPlayerListeners();
  }

  AudioPlayer get player => _player;

  /// Initialize AudioSession to handle headphone disconnection ("becoming noisy") and audio focus
  Future<void> _initAudioSession() async {
    try {
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration.music());

      // Auto-pause when headphones/bluetooth disconnect
      session.becomingNoisyEventStream.listen((_) {
        final isOwner = isPlaybackOwner?.call() ?? true;
        if (isOwner) {
          pause();
        }
      });

      // Handle phone calls & audio focus interruptions
      session.interruptionEventStream.listen((event) {
        final isOwner = isPlaybackOwner?.call() ?? true;
        if (event.begin) {
          _wasPlayingBeforeInterruption = _player.playing && isOwner;
          switch (event.type) {
            case AudioInterruptionType.duck:
              if (isOwner) _player.setVolume(0.2);
              break;
            case AudioInterruptionType.pause:
            case AudioInterruptionType.unknown:
              if (isOwner) pause();
              break;
          }
        } else {
          switch (event.type) {
            case AudioInterruptionType.duck:
              if (isOwner) _player.setVolume(1.0);
              break;
            case AudioInterruptionType.pause:
              if (_wasPlayingBeforeInterruption && isOwner) {
                play();
              }
              break;
            case AudioInterruptionType.unknown:
              break;
          }
          _wasPlayingBeforeInterruption = false;
        }
      });
    } catch (e) {
      debugPrint('AudioSession init notice: $e');
    }
  }

  void _initPlayerListeners() {
    // Listen to player state changes and update audio_service PlaybackState
    _player.playerStateStream.listen((playerState) {
      _broadcastState();
    });

    // Listen to position stream to update system seek bar position
    _player.positionStream.listen((position) {
      _broadcastState();
    });
  }

  void _broadcastState() {
    final playing = _player.playing;
    final processingState = _player.processingState;

    AudioProcessingState state;
    switch (processingState) {
      case ProcessingState.idle:
        state = AudioProcessingState.idle;
        break;
      case ProcessingState.loading:
        state = AudioProcessingState.loading;
        break;
      case ProcessingState.buffering:
        state = AudioProcessingState.buffering;
        break;
      case ProcessingState.ready:
        state = AudioProcessingState.ready;
        break;
      case ProcessingState.completed:
        state = AudioProcessingState.completed;
        break;
    }

    final controls = [
      MediaControl.skipToPrevious,
      if (playing) MediaControl.pause else MediaControl.play,
      MediaControl.skipToNext,
    ];
    final compactIndices = controls.isEmpty
        ? const <int>[]
        : (controls.length >= 3 ? const [0, 1, 2] : List.generate(controls.length, (i) => i));

    playbackState.add(
      PlaybackState(
        controls: controls,
        systemActions: const {
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
        },
        androidCompactActionIndices: compactIndices,
        processingState: state,
        playing: playing,
        updatePosition: _player.position,
        bufferedPosition: _player.bufferedPosition,
        speed: _player.speed,
        queueIndex: 0,
      ),
    );
  }

  /// Update metadata broadcasted to Android MediaSession & iOS MPNowPlayingInfoCenter
  void setTrackMediaItem(Track track, String apiBaseUrl) {
    Uri? finalArtUri;
    String artUrl = '';

    try {
      final localCover = OfflineStorageService().getCoverFilePath(track.videoId);
      if (localCover != null && File(localCover).existsSync()) {
        finalArtUri = Uri.file(localCover);
      } else {
        String art = track.coverUrl ?? '';
        if (art.isNotEmpty && art.startsWith('/')) {
          art = '$apiBaseUrl$art';
        } else if (art.isEmpty && track.videoId.isNotEmpty) {
          art = '$apiBaseUrl/api/tracks/cover/${track.videoId}';
        }
        artUrl = art;

        if (artUrl.startsWith('file://')) {
          finalArtUri = Uri.tryParse(artUrl);
        }
      }
    } catch (_) {}

    final item = MediaItem(
      id: track.videoId,
      album: track.album ?? 'Zephyr',
      title: track.title,
      artist: track.artists.join(', '),
      duration: track.duration,
      artUri: finalArtUri,
      extras: {'videoId': track.videoId, 'artists': track.artists},
    );

    try {
      mediaItem.add(item);
    } catch (e) {
      debugPrint('ZephyrAudioHandler mediaItem notice: $e');
    }

    // Resolve cover image from cache manager or fetch to local file for Android notification
    if (artUrl.isNotEmpty && (finalArtUri == null || finalArtUri.scheme != 'file')) {
      unawaited(() async {
        try {
          final cacheKey = 'track_cover_${track.videoId}';
          final fileInfo = await DefaultCacheManager().getFileFromCache(cacheKey) ??
              await DefaultCacheManager().getFileFromCache(artUrl);
          if (fileInfo != null && fileInfo.file.existsSync()) {
            if (mediaItem.value?.id == track.videoId) {
              mediaItem.add(item.copyWith(artUri: Uri.file(fileInfo.file.path)));
            }
            return;
          }

          final token = ZephyrApi().token;
          final headers = <String, String>{};
          if (token != null && token.isNotEmpty) {
            headers['Authorization'] = 'Bearer $token';
          }

          final fetchedFile = await DefaultCacheManager().downloadFile(
            artUrl,
            key: cacheKey,
            authHeaders: headers,
          );
          if (fetchedFile.file.existsSync() && mediaItem.value?.id == track.videoId) {
            mediaItem.add(item.copyWith(artUri: Uri.file(fetchedFile.file.path)));
          }
        } catch (e) {
          debugPrint('Notice: Background cover cache for notification: $e');
        }
      }());
    }
  }

  Timer? _stallRecoveryTimer;

  /// Seamlessly prepare media notification and pause current audio in-place without destroying the Foreground Service
  Future<void> prepareForTrackTransition(Track track, String apiBaseUrl) async {
    _stallRecoveryTimer?.cancel();
    _stallRecoveryTimer = null;
    try {
      await _player.pause();
    } catch (_) {}
    setTrackMediaItem(track, apiBaseUrl);
    final controls = [
      MediaControl.skipToPrevious,
      MediaControl.play,
      MediaControl.skipToNext,
    ];
    playbackState.add(
      PlaybackState(
        controls: controls,
        systemActions: const {
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
        },
        androidCompactActionIndices: const [0, 1, 2],
        processingState: AudioProcessingState.buffering,
        playing: false,
        updatePosition: Duration.zero,
        bufferedPosition: Duration.zero,
        speed: _player.speed,
        queueIndex: 0,
      ),
    );
  }

  /// Play audio stream URL directly
  Future<void> playUrl(
    String url,
    Track track,
    String apiBaseUrl, {
    Duration? initialPosition,
  }) async {
    _stallRecoveryTimer?.cancel();
    _stallRecoveryTimer = null;
    try {
      setTrackMediaItem(track, apiBaseUrl);
      AppLogger.instance.logPlayer('audio_handler_play_url', data: {
        'title': track.title,
        'videoId': track.videoId,
        'initialPosMs': initialPosition?.inMilliseconds,
      });
      // The caller applies the current volume before this method. Reapplying
      // the player's existing value after replacing the source keeps Linux
      // stream volume from falling back to the native default on each track.
      await _player.setVolume(_player.volume);
      await _player.setUrl(url);
      // Seek before starting playback. Starting first and seeking afterward
      // creates an audible 0:00 start and can publish a transient zero
      // position to the shared player state during takeover.
      if (initialPosition != null && initialPosition > Duration.zero) {
        await _player.seek(initialPosition);
      }
      await _player.play();

      // On Linux only, if GStreamer opened an HTTP stream for a completed track but stalled at 0:00,
      // this watchdog recovers the pipeline.
      if (!kIsWeb && Platform.isLinux && (track.downloadStatus == 'completed' || track.isDownloaded)) {
        _stallRecoveryTimer = Timer(const Duration(seconds: 3), () async {
          if (_player.playing && _player.position == Duration.zero) {
            try {
              AppLogger.instance.logPlayer('linux_pipeline_stall_recovery', data: {'videoId': track.videoId});
              debugPrint('ZephyrAudioHandler: Stall detected at 0:00, recovering pipeline...');
              await _player.setUrl(url);
              if (initialPosition != null && initialPosition > Duration.zero) {
                await _player.seek(initialPosition);
              }
              await _player.play();
            } catch (_) {}
          }
        });
      }
    } catch (e) {
      AppLogger.instance.logPlayer('audio_handler_play_error', data: {'error': e.toString()});
      debugPrint('ZephyrAudioHandler playUrl error: $e');
      rethrow;
    }
  }

  /// Play local audio file directly from device storage
  Future<void> playFilePath(
    String filePath,
    Track track,
    String apiBaseUrl, {
    Duration? initialPosition,
  }) async {
    _stallRecoveryTimer?.cancel();
    _stallRecoveryTimer = null;
    try {
      setTrackMediaItem(track, apiBaseUrl);
      AppLogger.instance.logPlayer('audio_handler_play_local_file', data: {
        'title': track.title,
        'videoId': track.videoId,
        'filePath': filePath,
      });
      await _player.setVolume(_player.volume);
      await _player.setFilePath(filePath);
      if (initialPosition != null && initialPosition > Duration.zero) {
        await _player.seek(initialPosition);
      }
      await _player.play();
    } catch (e) {
      AppLogger.instance.logPlayer('audio_handler_local_file_error', data: {'error': e.toString()});
      debugPrint('ZephyrAudioHandler playFilePath error: $e');
      rethrow;
    }
  }

  @override
  Future<void> play() async {
    try {
      AppLogger.instance.logPlayer('audio_handler_play');
      await _player.play();
    } catch (_) {}
  }

  @override
  Future<void> pause() async {
    _stallRecoveryTimer?.cancel();
    _stallRecoveryTimer = null;
    try {
      AppLogger.instance.logPlayer('audio_handler_pause');
      await _player.pause();
    } catch (_) {}
  }

  @override
  Future<void> stop() async {
    _stallRecoveryTimer?.cancel();
    _stallRecoveryTimer = null;
    _wasPlayingBeforeInterruption = false;
    try {
      AppLogger.instance.logPlayer('audio_handler_stop');
      await _player.stop();
    } catch (_) {}
    playbackState.add(
      playbackState.value.copyWith(
        processingState: AudioProcessingState.idle,
        playing: false,
        controls: const [],
        androidCompactActionIndices: const [],
      ),
    );
    try {
      await super.stop();
    } catch (_) {}
  }

  @override
  Future<void> seek(Duration position) async {
    try {
      AppLogger.instance.logPlayer('audio_handler_seek', data: {'posMs': position.inMilliseconds});
      await _player.seek(position);
    } catch (_) {}
  }

  @override
  Future<void> skipToNext() async {
    AppLogger.instance.logQueue('audio_handler_skip_next');
    onSkipNext?.call();
  }

  @override
  Future<void> skipToPrevious() async {
    AppLogger.instance.logQueue('audio_handler_skip_previous');
    onSkipPrevious?.call();
  }

  @override
  Future<void> onTaskRemoved() async {
    try {
      await stop();
    } catch (_) {}
    try {
      await super.onTaskRemoved();
    } catch (_) {}
  }
}

/// Initialize AudioService background worker (Mobile Android/iOS only)
Future<ZephyrAudioHandler?> initAudioService() async {
  if (!kIsWeb && (Platform.isLinux || Platform.isWindows || Platform.isMacOS)) {
    return null;
  }
  try {
    return await AudioService.init(
      builder: () => ZephyrAudioHandler(),
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'com.giorgiotassoni.zephyr.channel.audio',
        androidNotificationChannelName: 'Zephyr Music Playback',
        androidNotificationChannelDescription: 'Zephyr background playback and media controls',
        androidNotificationOngoing: false,
        androidStopForegroundOnPause: false,
        androidNotificationIcon: 'mipmap/launcher_icon',
        androidShowNotificationBadge: true,
      ),
    );
  } catch (e) {
    debugPrint('AudioService init fallback notice: $e');
    return null;
  }
}
