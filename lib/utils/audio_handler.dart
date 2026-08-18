import 'dart:async';
import 'dart:io';
import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import '../models/models.dart';

/// Global AudioHandler instance for Zephyr Music Player.
ZephyrAudioHandler? zephyrAudioHandler;

/// Custom AudioHandler extending BaseAudioHandler to manage background playback,
/// system notification controls, lock screen metadata, audio focus, and headphone events.
class ZephyrAudioHandler extends BaseAudioHandler with SeekHandler {
  final AudioPlayer _player = AudioPlayer();

  VoidCallback? onSkipNext;
  VoidCallback? onSkipPrevious;
  VoidCallback? onTogglePlayPause;

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
        pause();
      });

      // Handle phone calls & audio focus interruptions
      session.interruptionEventStream.listen((event) {
        if (event.begin) {
          switch (event.type) {
            case AudioInterruptionType.duck:
              _player.setVolume(0.2);
              break;
            case AudioInterruptionType.pause:
            case AudioInterruptionType.unknown:
              pause();
              break;
          }
        } else {
          switch (event.type) {
            case AudioInterruptionType.duck:
              _player.setVolume(1.0);
              break;
            case AudioInterruptionType.pause:
              play();
              break;
            case AudioInterruptionType.unknown:
              break;
          }
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

    playbackState.add(
      PlaybackState(
        controls: [
          MediaControl.skipToPrevious,
          if (playing) MediaControl.pause else MediaControl.play,
          MediaControl.skipToNext,
          MediaControl.stop,
        ],
        systemActions: const {
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
        },
        androidCompactActionIndices: const [0, 1, 2],
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
    String art = track.coverUrl ?? '';
    if (art.isNotEmpty && art.startsWith('/')) {
      art = '$apiBaseUrl$art';
    }

    final item = MediaItem(
      id: track.videoId,
      album: track.album ?? 'Zephyr',
      title: track.title,
      artist: track.artists.join(', '),
      duration: track.duration,
      artUri: art.isNotEmpty ? Uri.tryParse(art) : null,
      extras: {'videoId': track.videoId, 'artists': track.artists},
    );

    mediaItem.add(item);
  }

  /// Play audio stream URL directly
  Future<void> playUrl(
    String url,
    Track track,
    String apiBaseUrl, {
    Duration? initialPosition,
  }) async {
    try {
      setTrackMediaItem(track, apiBaseUrl);
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
    } catch (e) {
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
    try {
      setTrackMediaItem(track, apiBaseUrl);
      await _player.setVolume(_player.volume);
      await _player.setFilePath(filePath);
      if (initialPosition != null && initialPosition > Duration.zero) {
        await _player.seek(initialPosition);
      }
      await _player.play();
    } catch (e) {
      debugPrint('ZephyrAudioHandler playFilePath error: $e');
      rethrow;
    }
  }

  @override
  Future<void> play() async {
    try {
      await _player.play();
    } catch (_) {}
  }

  @override
  Future<void> pause() async {
    try {
      await _player.pause();
    } catch (_) {}
  }

  @override
  Future<void> stop() async {
    try {
      await _player.stop();
    } catch (_) {}
    playbackState.add(
      playbackState.value.copyWith(
        processingState: AudioProcessingState.idle,
        playing: false,
        controls: const [],
      ),
    );
    try {
      await super.stop();
    } catch (_) {}
  }

  @override
  Future<void> seek(Duration position) async {
    try {
      await _player.seek(position);
    } catch (_) {}
  }

  @override
  Future<void> skipToNext() async {
    onSkipNext?.call();
  }

  @override
  Future<void> skipToPrevious() async {
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
        androidNotificationChannelId: 'com.example.zephyr.channel.audio',
        androidNotificationChannelName: 'Zephyr Music Playback',
        androidNotificationOngoing: false,
        androidStopForegroundOnPause: true,
        androidNotificationIcon: 'mipmap/ic_launcher',
      ),
    );
  } catch (e) {
    debugPrint('AudioService init fallback notice: $e');
    return null;
  }
}
