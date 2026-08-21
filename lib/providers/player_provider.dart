import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:audioplayers/audioplayers.dart' as ap;
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../api/zephyr_api.dart';
import '../models/models.dart';
import 'package:flutter/material.dart';
import '../utils/web_media_session.dart';
import '../utils/mpris_service.dart';
import '../utils/audio_handler.dart';
import '../utils/root_navigator.dart';
import '../utils/device_info.dart';
import '../widgets/unresolved_track_modal.dart';
import '../widgets/toast.dart';
import '../theme/colors.dart';
import '../utils/offline_storage.dart';
import '../utils/app_logger.dart';
import 'auth_provider.dart';
import 'library_provider.dart';

bool _isSameTrack(String? a, String? b) {
  if (a == null || b == null) return false;
  if (a == b) return true;
  final cleanA = a.startsWith('dz_') ? a.substring(3) : a;
  final cleanB = b.startsWith('dz_') ? b.substring(3) : b;
  return cleanA == cleanB;
}

bool _hasUsableTrackTitle(String title) {
  final normalized = title.trim().toLowerCase();
  return normalized.isNotEmpty &&
      normalized != 'loading...' &&
      normalized != 'unknown track';
}

DateTime? _parseUtcTimestamp(dynamic raw) {
  if (raw == null) return null;
  String s = raw.toString().trim();
  if (s.isEmpty || s == 'null') return null;
  // If the timestamp has no timezone offset (Z, +, or -HH:MM), append 'Z' so Dart parses as UTC
  if (!s.endsWith('Z') &&
      !s.endsWith('z') &&
      !s.contains('+') &&
      !RegExp(r'-\d{2}:\d{2}$').hasMatch(s)) {
    s = '${s}Z';
  }
  return DateTime.tryParse(s)?.toUtc();
}

Track _mergeTrackMetadata(Track current, Track incoming) {
  return current.copyWith(
    ytId: incoming.ytId ?? current.ytId,
    title: _hasUsableTrackTitle(incoming.title)
        ? incoming.title
        : current.title,
    artists: incoming.artists.isNotEmpty ? incoming.artists : current.artists,
    artistsIds: incoming.artistsIds.isNotEmpty
        ? incoming.artistsIds
        : current.artistsIds,
    album: incoming.album ?? current.album,
    albumId: incoming.albumId ?? current.albumId,
    duration: incoming.duration ?? current.duration,
    downloadStatus: incoming.downloadStatus != 'not_in_db'
        ? incoming.downloadStatus
        : current.downloadStatus,
    videoType: incoming.videoType ?? current.videoType,
    localPath: incoming.localPath ?? current.localPath,
    localCoverPath: incoming.localCoverPath ?? current.localCoverPath,
    coverUrl: incoming.coverUrl ?? current.coverUrl,
    isDownloaded: incoming.isDownloaded || current.isDownloaded,
    lyricsText: incoming.lyricsText ?? current.lyricsText,
    lyricsLrc: incoming.lyricsLrc ?? current.lyricsLrc,
    reason: incoming.reason ?? current.reason,
  );
}

class ZephyrPlayerState {
  final Track? currentTrack;
  final List<Track> queue;
  final List<Track> originalQueue; // keeps the original order before shuffle
  final List<Track>
  userQueue; // Queue based on "add to queue" button with priority
  final int currentIndex;
  final bool isPlaying;
  final Duration position;
  final Duration duration;
  final double volume;
  final double lastNonMutedVolume;
  final bool isLoading;
  final String? errorMessage;
  final String queueMode; // Backend queue type: 'radio' or 'context'
  // Nullable internally for compatibility with state instances created before
  // repeatMode was introduced; the getter always exposes a safe value.
  final String? _repeatMode;
  String get repeatMode => _repeatMode ?? 'off';
  final String radioStatus; // 'idle', 'pending', 'ready', 'failed'
  final String? radioRequestId;
  final int? radioGeneration;
  final String? radioErrorCode;
  final String? radioErrorMessage;
  final bool isShuffled;
  final List<Map<String, dynamic>> connectedDevices;
  final String? activeDeviceId;
  final String? activeDeviceName;
  final String myDeviceId;
  final String myDeviceName;
  final bool isPlayerDevice;
  final int historyCount;
  final DateTime? positionUpdatedAt;
  final int? basePositionMs;

  const ZephyrPlayerState({
    this.currentTrack,
    this.queue = const [],
    this.originalQueue = const [],
    this.userQueue = const [],
    this.currentIndex = 0,
    this.isPlaying = false,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.volume = 1.0,
    this.lastNonMutedVolume = 1.0,
    this.isLoading = false,
    this.errorMessage,
    this.queueMode = 'radio',
    String? repeatMode,
    this.radioStatus = 'idle',
    this.radioRequestId,
    this.radioGeneration,
    this.radioErrorCode,
    this.radioErrorMessage,
    this.isShuffled = false,
    this.connectedDevices = const [],
    this.activeDeviceId,
    this.activeDeviceName,
    this.myDeviceId = '',
    this.myDeviceName = '',
    this.isPlayerDevice = false,
    this.historyCount = 0,
    this.positionUpdatedAt,
    this.basePositionMs,
  }) : _repeatMode = repeatMode ?? 'off';

  bool get canGoPrevious => historyCount > 0 || currentIndex > 0;

  Duration get effectiveDuration {
    if (duration > Duration.zero) return duration;
    if (currentTrack?.duration != null &&
        currentTrack!.duration! > Duration.zero) {
      return currentTrack!.duration!;
    }
    return Duration.zero;
  }

  /// Calculates the projected position using position_updated_at anchor
  Duration get projectedPosition {
    if (isPlayerDevice) return position;
    if (!isPlaying || positionUpdatedAt == null) return position;

    final nowUtc = DateTime.now().toUtc();
    final elapsedMs = nowUtc.difference(positionUpdatedAt!).inMilliseconds;
    final safeElapsedMs = elapsedMs < 0 ? 0 : elapsedMs;
    final baseMs = basePositionMs ?? position.inMilliseconds;
    final effectiveMs = baseMs + safeElapsedMs;
    final maxMs = effectiveDuration.inMilliseconds;
    if (maxMs > 0) {
      return Duration(milliseconds: effectiveMs.clamp(0, maxMs));
    }
    return Duration(milliseconds: effectiveMs < 0 ? 0 : effectiveMs);
  }

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
    String? repeatMode,
    String? radioStatus,
    String? radioRequestId,
    bool clearRadioRequestId = false,
    int? radioGeneration,
    String? radioErrorCode,
    String? radioErrorMessage,
    bool clearRadioError = false,
    bool? isShuffled,
    String? errorMessage,
    bool? isLoading,
    double? volume,
    double? lastNonMutedVolume,
    int? historyCount,
    String? activeDeviceId,
    String? activeDeviceName,
    bool? isPlayerDevice,
    String? myDeviceId,
    String? myDeviceName,
    List<Map<String, dynamic>>? connectedDevices,
    DateTime? positionUpdatedAt,
    int? basePositionMs,
  }) {
    return ZephyrPlayerState(
      currentTrack: nullTrack == true
          ? null
          : (currentTrack ?? this.currentTrack),
      queue: queue ?? this.queue,
      originalQueue: originalQueue ?? this.originalQueue,
      userQueue: userQueue ?? this.userQueue,
      currentIndex: currentIndex ?? this.currentIndex,
      isPlaying: isPlaying ?? this.isPlaying,
      position: position ?? this.position,
      duration: duration ?? this.duration,
      queueMode: queueMode ?? this.queueMode,
      repeatMode: repeatMode ?? this.repeatMode,
      radioStatus: radioStatus ?? this.radioStatus,
      radioRequestId: clearRadioRequestId
          ? null
          : (radioRequestId ?? this.radioRequestId),
      radioGeneration: radioGeneration ?? this.radioGeneration,
      radioErrorCode: clearRadioError
          ? null
          : (radioErrorCode ?? this.radioErrorCode),
      radioErrorMessage: clearRadioError
          ? null
          : (radioErrorMessage ?? this.radioErrorMessage),
      isShuffled: isShuffled ?? this.isShuffled,
      errorMessage: errorMessage ?? this.errorMessage,
      isLoading: isLoading ?? this.isLoading,
      volume: volume ?? this.volume,
      lastNonMutedVolume: lastNonMutedVolume ?? this.lastNonMutedVolume,
      historyCount: historyCount ?? this.historyCount,
      activeDeviceId: activeDeviceId ?? this.activeDeviceId,
      activeDeviceName: activeDeviceName ?? this.activeDeviceName,
      isPlayerDevice: isPlayerDevice ?? this.isPlayerDevice,
      myDeviceId: myDeviceId ?? this.myDeviceId,
      myDeviceName: myDeviceName ?? this.myDeviceName,
      connectedDevices: connectedDevices ?? this.connectedDevices,
      positionUpdatedAt: positionUpdatedAt ?? this.positionUpdatedAt,
      basePositionMs: basePositionMs ?? this.basePositionMs,
    );
  }
}

class PlayerNotifier extends Notifier<ZephyrPlayerState> {
  String _describeStartupDevices(List<Map<String, dynamic>> devices) {
    if (devices.isEmpty) return '<none>';
    return devices
        .map(
          (device) =>
              '{id:${device['device_id']}, name:${device['device_name']}, '
              'is_player:${device['is_player']}, is_alive:${device['is_alive']}}',
        )
        .join(', ');
  }

  final ap.AudioPlayer _audioPlayer = ap.AudioPlayer();
  final ZephyrApi _api = ZephyrApi();

  StreamSubscription? _positionSub;
  StreamSubscription? _durationSub;
  StreamSubscription? _stateSub;
  StreamSubscription? _completeSub;

  String? _lastTrackId;
  bool _hasRecordedCurrentTrack = false;
  bool _isInitialLoad = false;
  int _playRequestId = 0;
  int _volumeRequestId = 0;
  Future<void> _volumeApplyChain = Future<void>.value();
  int _playbackGeneration = 0;
  Timer? _skipDebounceTimer;
  Timer? _ownershipRecoveryTimer;
  bool _ownershipReleased = false;
  bool _localPlaybackSuppressed = true;
  bool _hasLocalAudioSource = false;
  String? _ownerTrackStartId;
  String? _pendingOwnerTrackId;
  Timer? _cursorTimer;
  String? _lastCompletedTrackId;
  DateTime? _lastCompletionTime;
  final Map<String, Track> _dzResolvedCache = {};
  final Map<String, Future<void>> _metadataHydrations = {};

  Future<void> _hydrateTrackMetadata(String trackId) {
    final existing = _metadataHydrations[trackId];
    if (existing != null) return existing;

    late Future<void> request;
    request = () async {
      // A takeover can arrive just before /stream creates the DB row. Retry
      // briefly so a successful stream cannot leave the UI on its temporary
      // Loading.../Unknown Track placeholder.
      const delays = [
        Duration.zero,
        Duration(milliseconds: 100),
        Duration(milliseconds: 250),
        Duration(milliseconds: 500),
      ];
      for (final delay in delays) {
        if (delay > Duration.zero) await Future<void>.delayed(delay);
        try {
          final fullMeta = await _api.getTrackMetadata(trackId);
          if (state.currentTrack == null ||
              !_isSameTrack(state.currentTrack!.videoId, trackId)) {
            return;
          }
          final merged = _mergeTrackMetadata(state.currentTrack!, fullMeta);
          state = state.copyWith(
            currentTrack: merged,
            duration:
                merged.duration != null && merged.duration! > Duration.zero
                ? merged.duration
                : state.duration,
            queue: state.queue
                .map(
                  (track) => _isSameTrack(track.videoId, trackId)
                      ? _mergeTrackMetadata(track, fullMeta)
                      : track,
                )
                .toList(),
          );

          if (state.isPlayerDevice) {
            try {
              zephyrAudioHandler?.setTrackMediaItem(merged, _api.baseUrl);
            } catch (_) {}
            try {
              LinuxMprisService().updateState(
                isPlaying: state.isPlaying,
                track: merged,
                apiBaseUrl: _api.baseUrl,
              );
            } catch (_) {}
          }

          if (_hasUsableTrackTitle(merged.title) || merged.artists.isNotEmpty) {
            _api.notifyLyricsReady(trackId);
            return;
          }
        } catch (_) {
          // The stream may still be creating the row; try the next interval.
        }
      }
    }();
    _metadataHydrations[trackId] = request;
    request.whenComplete(() {
      if (identical(_metadataHydrations[trackId], request)) {
        _metadataHydrations.remove(trackId);
      }
    });
    return request;
  }

  void clearResolvedCache([String? trackId]) {
    if (trackId != null) {
      _dzResolvedCache.remove(trackId);
      // If active playing track is being cleared/re-resolved, stop playback immediately!
      if (state.currentTrack?.videoId == trackId) {
        _audioPlayer.stop();
        state = state.copyWith(
          isPlaying: false,
          position: Duration.zero,
          isLoading: false,
        );
      }
    } else {
      _dzResolvedCache.clear();
      _audioPlayer.stop();
      state = state.copyWith(
        isPlaying: false,
        position: Duration.zero,
        isLoading: false,
      );
    }
  }

  StreamSubscription? _sseSub;
  Future<void> _snapshotChain = Future<void>.value();
  Future<void>? _trackTransitionInFlight;
  String? _trackTransitionAction;
  DateTime? _lastAppliedServerUpdateAt;
  String? _nextWaitingForRadioTrackId;

  Future<void> _enqueueServerSnapshot(
    Map<String, dynamic> snapshot, {
    bool isInitial = false,
    bool suppressOwnerPlayback = false,
    bool forceTrackTransition = false,
  }) {
    final next = _snapshotChain.then((_) async {
      final updatedAt = _parseUtcTimestamp(snapshot['updated_at']);
      final eventType = snapshot['_event_type']?.toString() ?? 'http';
      if (updatedAt != null &&
          _lastAppliedServerUpdateAt != null &&
          updatedAt.isBefore(_lastAppliedServerUpdateAt!)) {
        AppLogger.instance.logQueue(
          'snapshot_ignored_stale',
          data: {
            'event': eventType,
            'snapshotUpdatedAt': updatedAt.toIso8601String(),
            'lastAppliedUpdatedAt': _lastAppliedServerUpdateAt!
                .toIso8601String(),
            'currentTrackId': snapshot['current_track_id'],
          },
        );
        return;
      }

      if (updatedAt != null &&
          (_lastAppliedServerUpdateAt == null ||
              updatedAt.isAfter(_lastAppliedServerUpdateAt!))) {
        _lastAppliedServerUpdateAt = updatedAt;
      }

      AppLogger.instance.logQueue(
        'snapshot_applying',
        data: {
          'event': eventType,
          'isInitial': isInitial,
          'suppressOwnerPlayback': suppressOwnerPlayback,
          'forceTrackTransition': forceTrackTransition,
          'currentTrackId': snapshot['current_track_id'],
          'isPlaying': snapshot['is_playing'],
          'updatedAt': snapshot['updated_at'],
          'queueLength': snapshot['queue'] is List
              ? (snapshot['queue'] as List).length
              : null,
          'historyCount': snapshot['history_count'],
        },
      );

      try {
        await _applyServerStateSnapshot(
          snapshot,
          isInitial: isInitial,
          suppressOwnerPlayback: suppressOwnerPlayback,
          forceTrackTransition: forceTrackTransition,
        );
      } catch (e, stackTrace) {
        AppLogger.instance.logQueue(
          'snapshot_apply_failed',
          data: {
            'event': eventType,
            'currentTrackId': snapshot['current_track_id'],
            'error': e.toString(),
          },
        );
        debugPrint('Player state snapshot notice: $e\n$stackTrace');
      }

      // If playback reached the end while radio was pending, /next returned
      // 202 instead of advancing. Retry exactly once when the matching ready
      // snapshot has installed a usable queue.
      final waitingTrackId = _nextWaitingForRadioTrackId;
      final readyRequestId = snapshot['radio_request_id']?.toString();
      final requestMatches =
          readyRequestId == null ||
          state.radioRequestId == null ||
          readyRequestId == state.radioRequestId;
      if (waitingTrackId != null &&
          state.radioStatus == 'ready' &&
          state.queue.length > 1 &&
          requestMatches &&
          _isSameTrack(state.currentTrack?.videoId, waitingTrackId)) {
        _nextWaitingForRadioTrackId = null;
        AppLogger.instance.logQueue(
          'radio_ready_retrying_next',
          data: {
            'trackId': waitingTrackId,
            'queueLength': state.queue.length,
            'radioRequestId': state.radioRequestId,
          },
        );
        unawaited(playNext());
      }
    });
    _snapshotChain = next;
    return next;
  }

  void _cancelOwnershipRecovery() {
    _ownershipRecoveryTimer?.cancel();
    _ownershipRecoveryTimer = null;
  }

  bool _hasLiveOwner(List<Map<String, dynamic>> devices) {
    return devices.any(
      (device) => device['is_player'] == true && device['is_alive'] == true,
    );
  }

  Future<void> _recoverOwnershipAfterRelease(
    List<Map<String, dynamic>> devices,
  ) async {
    if (!_ownershipReleased ||
        _ownershipRecoveryTimer != null ||
        _startupSoloClaimInProgress ||
        state.isPlayerDevice ||
        state.myDeviceId.isEmpty ||
        _hasLiveOwner(devices)) {
      return;
    }

    // Never automatically snatch ownership in the background between multiple live devices.
    // Ownership changes must only occur when explicitly initiated by the user.
    _ownershipReleased = false;
    _cancelOwnershipRecovery();
  }

  Future<void> _handleDevicesUpdate(List<Map<String, dynamic>> devices) async {
    if (_ownershipReleased) {
      await _recoverOwnershipAfterRelease(devices);
    } else {
      await _claimStartupSoloDevice(devices);
    }
  }

  Future<void> _claimStartupSoloDevice(
    List<Map<String, dynamic>> devices,
  ) async {
    if (_startupSoloClaimCompleted || _startupSoloClaimInProgress) return;
    if (state.myDeviceId.isEmpty || state.isPlayerDevice) return;

    // `is_alive` is the backend's live-device contract. Ignore a persisted
    // owner entry that is no longer alive: the current device is the only
    // connected device in that case and must explicitly claim ownership.
    final liveDevices = devices
        .where((device) => device['is_alive'] == true)
        .toList();
    final isSoloCurrentDevice =
        liveDevices.length == 1 &&
        liveDevices.first['device_id']?.toString() == state.myDeviceId;
    debugPrint(
      '[Playback startup] ownership check: myDeviceId=${state.myDeviceId}, '
      'isPlayerDevice=${state.isPlayerDevice}, '
      'activeDeviceId=${state.activeDeviceId}, '
      'devices=${_describeStartupDevices(devices)}, '
      'liveDevices=${_describeStartupDevices(liveDevices)}, '
      'soloCurrentDevice=$isSoloCurrentDevice',
    );
    if (!isSoloCurrentDevice) {
      debugPrint(
        '[Playback startup] not claiming ownership because the current '
        'device is not the only live device.',
      );
      return;
    }

    _startupSoloClaimInProgress = true;
    _suppressPersistedStartupPlayback = true;
    try {
      // Startup ownership must not auto-resume persisted playback. The user
      // can press Play explicitly after the app is ready.
      final claimed = await takeoverPlayback(force: true, startPlayback: false);
      if (claimed) _startupSoloClaimCompleted = true;
      if (!claimed) _suppressPersistedStartupPlayback = false;
    } finally {
      _startupSoloClaimInProgress = false;
    }
  }

  Future<bool> _claimLocalPlaybackIfUnowned() async {
    if (state.isPlayerDevice) return true;
    if (state.activeDeviceId != null && state.activeDeviceId!.isNotEmpty) {
      return false;
    }

    try {
      final deviceId = state.myDeviceId.isNotEmpty
          ? state.myDeviceId
          : await DeviceInfo.getDeviceId();
      final deviceName = state.myDeviceName.isNotEmpty
          ? state.myDeviceName
          : await DeviceInfo.getDeviceName();
      final snapshot = await _api.takeoverPlayer(
        deviceId: deviceId,
        deviceName: deviceName,
      );
      await _enqueueServerSnapshot(snapshot, suppressOwnerPlayback: true);
      state = state.copyWith(
        isPlayerDevice: true,
        activeDeviceId: deviceId,
        activeDeviceName: deviceName,
      );
      return true;
    } catch (e) {
      debugPrint('Claim unowned playback notice: $e');
      return false;
    }
  }

  bool _canContinuePlayback(int requestId, int playbackGeneration) {
    return _playRequestId == requestId &&
        _playbackGeneration == playbackGeneration &&
        state.isPlayerDevice &&
        !_localPlaybackSuppressed;
  }

  Future<void> _pauseLocalPlayback() async {
    _localPlaybackSuppressed = true;
    // Invalidate delayed/in-flight play requests before pausing. Otherwise an
    // old executePlay() may finish after a pause and start the stream again.
    _playRequestId++;
    _skipDebounceTimer?.cancel();

    try {
      await zephyrAudioHandler?.pause();
    } catch (_) {}
    try {
      await _audioPlayer.pause();
    } catch (_) {}
  }

  Future<void> _stopLocalPlayback() async {
    _localPlaybackSuppressed = true;
    _playbackGeneration++;
    _hasLocalAudioSource = false;
    await _pauseLocalPlayback();
    try {
      await zephyrAudioHandler?.stop();
    } catch (_) {}
    try {
      await _audioPlayer.stop();
    } catch (_) {}
  }

  void _initDeviceAndSse() async {
    final devId = await DeviceInfo.getDeviceId();
    final devName = await DeviceInfo.getDeviceName();
    state = state.copyWith(
      myDeviceId: devId,
      myDeviceName: devName,
      // Do not assume ownership before the authoritative HTTP/SSE snapshot.
      // The previous session owner may be a different device.
      isPlayerDevice: false,
      activeDeviceId: null,
      activeDeviceName: null,
    );

    if (_api.token == null) return;

    try {
      final s = await _api.getPlayerState(reason: 'startup', deviceId: devId);
      debugPrint(
        '[Playback startup] GET /api/player/state: '
        'device_id=${s['device_id']}, is_player=${s['is_player']}, '
        'is_playing=${s['is_playing']}, current_track_id=${s['current_track_id']}',
      );
      await _enqueueServerSnapshot(s, isInitial: true);
    } catch (e) {
      debugPrint('[Playback startup] state request failed: $e');
    }

    _sseSub?.cancel();
    _sseSub = _api.subscribeToPlayerEvents(devId, deviceName: devName).listen((
      snapshot,
    ) {
      // The first SSE state is another copy of the current server snapshot,
      // not a new play command. Startup protection must not call play/resume
      // against a paused local engine with no loaded source.
      final isStateEvent = snapshot['_event_type'] == 'state';
      final isSseInitialSnapshot =
          isStateEvent && snapshot['_sse_initial'] == true;
      final suppressOwnerPlayback = isSseInitialSnapshot;
      final firstSseInitialSnapshot =
          isSseInitialSnapshot && _startupPlaybackBlocked;
      if (isStateEvent && !isSseInitialSnapshot) {
        // A real mutation after startup is allowed to start the OWNER.
        _startupPlaybackBlocked = false;
      }

      // SSE snapshots can contain awaits (pause, seek, stream startup, or
      // metadata enrichment). Serialize them so an older event cannot finish
      // after a newer takeover/heartbeat event and overwrite it.
      _enqueueServerSnapshot(
        snapshot,
        isInitial: firstSseInitialSnapshot,
        suppressOwnerPlayback: suppressOwnerPlayback,
      );
    }, onError: (_) {});

    // Refresh after opening this device's SSE connection so the device list
    // includes the current device. If it is the only live device, explicitly
    // claim ownership and resume the persisted track locally.
    unawaited(_refreshStartupDevicesAndClaim());
    debugPrint(
      '[Playback startup] initialized SSE for device '
      'id=$devId, name=$devName',
    );
  }

  Future<void> _refreshStartupDevicesAndClaim() async {
    try {
      final devices = await _api.getConnectedDevices();
      debugPrint(
        '[Playback startup] GET /api/player/devices: '
        '${_describeStartupDevices(devices)}',
      );
      state = state.copyWith(connectedDevices: devices);
      await _handleDevicesUpdate(devices);
    } catch (e) {
      debugPrint('Startup device refresh notice: $e');
    }
  }

  bool _startupPlaybackBlocked = true;
  bool _suppressPersistedStartupPlayback = false;
  bool _startupSoloClaimInProgress = false;
  bool _startupSoloClaimCompleted = false;
  bool? _lastKnownServerPlaying;

  Future<void> _applyOwnerSeekPosition(Duration position) async {
    state = state.copyWith(position: position);

    try {
      if (zephyrAudioHandler != null) {
        await zephyrAudioHandler!.seek(position);
      } else {
        await _audioPlayer.seek(position).timeout(const Duration(seconds: 1));
      }
    } catch (e) {
      AppLogger.instance.logPlayer(
        'owner_seek_apply_failed',
        data: {'positionMs': position.inMilliseconds, 'error': e.toString()},
      );
      debugPrint('Owner authoritative seek notice: $e');
    }

    try {
      LinuxMprisService().updateState(
        isPlaying: state.isPlaying,
        track: state.currentTrack,
        apiBaseUrl: _api.baseUrl,
      );
    } catch (_) {}
  }

  Future<void> _applyServerStateSnapshot(
    Map<String, dynamic> snapshot, {
    bool isInitial = false,
    bool suppressOwnerPlayback = false,
    bool forceTrackTransition = false,
  }) async {
    // 0. Handle typed 'track_status' event from backend (Exchange 51)
    if (snapshot['_event_type'] == 'track_status') {
      final trackId = snapshot['track_id']?.toString();
      final downloadStatus = snapshot['download_status']?.toString();

      if (trackId != null && trackId.isNotEmpty && downloadStatus != null) {
        try {
          ref
              .read(libraryProvider.notifier)
              .handleTrackStatusEvent(
                trackId: trackId,
                downloadStatus: downloadStatus,
              );
        } catch (_) {}

        final bool isCompleted = downloadStatus == 'completed';

        // Update currentTrack if it matches
        if (state.currentTrack != null &&
            _isSameTrack(state.currentTrack!.videoId, trackId)) {
          final updatedTrack = state.currentTrack!.copyWith(
            downloadStatus: downloadStatus,
            isDownloaded: isCompleted,
          );
          state = state.copyWith(currentTrack: updatedTrack);

          // Post-download: fetch rich metadata (lyrics, album art, local path) and start stream
          if (isCompleted) {
            _api
                .getTrackMetadata(trackId)
                .then((fullMeta) async {
                  if (state.currentTrack != null &&
                      _isSameTrack(state.currentTrack!.videoId, trackId)) {
                    final enrichedTrack = state.currentTrack!.copyWith(
                      title: fullMeta.title != 'Unknown Track'
                          ? fullMeta.title
                          : state.currentTrack!.title,
                      artists: fullMeta.artists.isNotEmpty
                          ? fullMeta.artists
                          : state.currentTrack!.artists,
                      artistsIds: fullMeta.artistsIds.isNotEmpty
                          ? fullMeta.artistsIds
                          : state.currentTrack!.artistsIds,
                      album: fullMeta.album ?? state.currentTrack!.album,
                      albumId: fullMeta.albumId ?? state.currentTrack!.albumId,
                      duration:
                          (fullMeta.duration != null &&
                              fullMeta.duration! > Duration.zero)
                          ? fullMeta.duration
                          : state.currentTrack!.duration,
                      coverUrl:
                          fullMeta.coverUrl ?? state.currentTrack!.coverUrl,
                      localPath: fullMeta.localPath,
                      localCoverPath: fullMeta.localCoverPath,
                      lyricsText: fullMeta.lyricsText,
                      lyricsLrc: fullMeta.lyricsLrc,
                      downloadStatus: 'completed',
                      isDownloaded: true,
                    );
                    state = state.copyWith(currentTrack: enrichedTrack);
                    _api.notifyLyricsReady(state.currentTrack!.videoId);
                    _api.notifyLyricsReady(trackId);

                    // If waiting for stream or stalled at 0:00, initiate playback now that download is complete
                    if (state.isPlayerDevice &&
                        (state.isLoading ||
                            !_hasLocalAudioSource ||
                            (zephyrAudioHandler != null &&
                                (!zephyrAudioHandler!.player.playing ||
                                    zephyrAudioHandler!.player.position ==
                                        Duration.zero)))) {
                      debugPrint(
                        '⚡ [PlayerProvider] Track $trackId download completed on server! Requesting stream...',
                      );
                      await playTrack(
                        enrichedTrack,
                        state.queue,
                        immediate: true,
                      );
                    }
                  }
                })
                .catchError((e) async {
                  debugPrint(
                    'Error enriching track metadata after download: $e',
                  );
                  if (state.isPlayerDevice &&
                      state.currentTrack != null &&
                      _isSameTrack(state.currentTrack!.videoId, trackId) &&
                      (state.isLoading || !_hasLocalAudioSource)) {
                    await playTrack(updatedTrack, state.queue, immediate: true);
                  }
                });
          }
        }

        // Update queue tracks if present
        if (state.queue.isNotEmpty) {
          final updatedQueue = state.queue.map((t) {
            if (_isSameTrack(t.videoId, trackId)) {
              return t.copyWith(
                downloadStatus: downloadStatus,
                isDownloaded: isCompleted,
              );
            }
            return t;
          }).toList();
          state = state.copyWith(queue: updatedQueue);
        }
      }
      return;
    }

    // 0.1 Handle typed 'library' event from backend (Exchange 50)
    if (snapshot['_event_type'] == 'library') {
      final scope = snapshot['scope']?.toString();
      final action = snapshot['action']?.toString();
      final playlistId = snapshot['playlist_id'];
      final trackId = snapshot['track_id']?.toString();

      try {
        ref
            .read(libraryProvider.notifier)
            .handleLibraryEvent(
              scope: scope,
              action: action,
              playlistId: playlistId,
              trackId: trackId,
            );
      } catch (_) {}
      return;
    }

    // 0.1 Handle typed 'devices' event from backend
    if (snapshot['_event_type'] == 'devices' ||
        (snapshot.containsKey('devices') && snapshot['devices'] is List)) {
      if (snapshot['devices'] is List) {
        final List rawDevs = snapshot['devices'];
        final List<Map<String, dynamic>> devList = rawDevs
            .map((e) {
              if (e is Map<String, dynamic>) return e;
              if (e is Map) return Map<String, dynamic>.from(e);
              return <String, dynamic>{};
            })
            .where((m) => m.isNotEmpty)
            .toList();

        // A devices event only describes connectivity. It must never grant
        // ownership locally: the backend is the sole authority for claims and
        // takeovers, and the owner may be present in this list even when the
        // local device is the only live SSE connection.
        state = state.copyWith(connectedDevices: devList);
        debugPrint(
          '[Playback startup] SSE devices event: '
          '${_describeStartupDevices(devList)}',
        );
        unawaited(_handleDevicesUpdate(devList));
      }
      return;
    }

    final String? activeId = snapshot['device_id']?.toString();
    final String? activeName = snapshot['device_name']?.toString();
    // The backend snapshot is authoritative. Do not infer ownership from
    // the number of connected devices: a device can be alone in the SSE list
    // while the backend still has a live owner session.
    final bool isPlayer =
        state.myDeviceId.isNotEmpty &&
        (activeId == state.myDeviceId ||
            (activeId == null && state.isPlayerDevice));

    // Only initial HTTP hydration on the local owner is startup state.
    // Remote controllers should never enter isStartup and must mirror live playback immediately.
    final bool isStartup = isInitial && isPlayer;
    if (!isInitial && activeId == null) {
      _ownershipReleased = true;
      _cancelOwnershipRecovery();
      debugPrint(
        '[Playback recovery] backend released ownership; waiting for '
        'the updated devices event',
      );
    } else if (activeId != null && activeId == state.myDeviceId) {
      _ownershipReleased = false;
      _cancelOwnershipRecovery();
    }
    final int hCount =
        (snapshot['history_count'] as num?)?.toInt() ?? state.historyCount;
    final bool serverPlaying = snapshot['is_playing'] == true;
    final int posMs =
        (snapshot['position_ms'] as num?)?.toInt() ??
        state.position.inMilliseconds;
    final String? curTrackId = snapshot['current_track_id']?.toString();
    final previousPositionUpdatedAt = state.positionUpdatedAt;

    // Radio generation is asynchronous: the seed response is `pending`, and
    // a later SSE/state snapshot changes it to `ready` or `failed`.
    final rawRadioStatus = snapshot['radio_status']?.toString();
    final hasRadioStatus = snapshot.containsKey('radio_status');
    final rawQueueMode = snapshot['queue_mode']?.toString();
    final radioError = snapshot['radio_error'];
    final radioErrorMap = radioError is Map
        ? Map<String, dynamic>.from(radioError)
        : null;
    if (hasRadioStatus ||
        snapshot.containsKey('radio_request_id') ||
        rawQueueMode == 'radio' ||
        rawQueueMode == 'context') {
      state = state.copyWith(
        queueMode: rawQueueMode == 'radio' || rawQueueMode == 'context'
            ? rawQueueMode
            : null,
        radioStatus:
            hasRadioStatus &&
                {'idle', 'pending', 'ready', 'failed'}.contains(rawRadioStatus)
            ? rawRadioStatus
            : null,
        radioRequestId: snapshot['radio_request_id']?.toString(),
        clearRadioRequestId:
            snapshot.containsKey('radio_request_id') &&
            snapshot['radio_request_id'] == null,
        radioGeneration: (snapshot['radio_generation'] as num?)?.toInt(),
        radioErrorCode: radioErrorMap?['code']?.toString(),
        radioErrorMessage: radioErrorMap?['message']?.toString(),
        clearRadioError: hasRadioStatus && rawRadioStatus != 'failed',
      );
      AppLogger.instance.logQueue(
        'radio_status_updated',
        data: {
          'status': state.radioStatus,
          'requestId': state.radioRequestId,
          'generation': state.radioGeneration,
          'errorCode': state.radioErrorCode,
          'queueLength': snapshot['queue'] is List
              ? (snapshot['queue'] as List).length
              : null,
        },
      );
    }

    DateTime? posUpdatedAt = _parseUtcTimestamp(
      snapshot['position_updated_at'],
    );

    final bool suppressPersistedStartupPlayback =
        _suppressPersistedStartupPlayback;
    if (suppressPersistedStartupPlayback &&
        !isInitial &&
        !suppressOwnerPlayback) {
      // Consume the first post-takeover broadcast. It echoes the persisted
      // is_playing=true state and is not a user play action.
      _suppressPersistedStartupPlayback = false;
    }

    List<Track>? serverQueueTracks;
    if (snapshot.containsKey('queue') && snapshot['queue'] is List) {
      final List rawQueue = snapshot['queue'];
      serverQueueTracks = rawQueue
          .map((e) {
            if (e is Map<String, dynamic>) return Track.fromJson(e);
            if (e is Map) return Track.fromJson(Map<String, dynamic>.from(e));
            return null;
          })
          .whereType<Track>()
          .toList();
    }

    List<Track>? serverUserQueueTracks;
    if (snapshot.containsKey('user_queue') && snapshot['user_queue'] is List) {
      final List rawUserQueue = snapshot['user_queue'];
      serverUserQueueTracks = rawUserQueue
          .map((e) {
            if (e is Map<String, dynamic>) return Track.fromJson(e);
            if (e is Map) return Track.fromJson(Map<String, dynamic>.from(e));
            return null;
          })
          .whereType<Track>()
          .toList();
    }

    // 1. Initial app launch: hydrate track metadata in strictly PAUSED state without starting playback
    if (isStartup) {
      // Startup is intentionally paused even if the backend snapshot says it
      // was playing. Keep a paused baseline until an explicit later command.
      _lastKnownServerPlaying = false;

      Track? initialTrack = state.currentTrack;
      if (curTrackId != null && curTrackId.isNotEmpty) {
        final found = state.queue.cast<Track?>().firstWhere(
          (t) => _isSameTrack(t?.videoId, curTrackId),
          orElse: () => null,
        );
        if (found != null) {
          initialTrack = found;
        } else if (serverQueueTracks != null) {
          initialTrack = serverQueueTracks.cast<Track?>().firstWhere(
            (t) => _isSameTrack(t?.videoId, curTrackId),
            orElse: () => null,
          );
        }
        initialTrack ??= Track(
          videoId: curTrackId,
          title: 'Unknown Track',
          artists: const [],
          downloadStatus: 'not_in_db',
          isDownloaded: false,
        );
      }

      List<Track> queueToUse = state.queue;
      if (serverQueueTracks != null) {
        if (initialTrack != null &&
            !serverQueueTracks.any(
              (t) => _isSameTrack(t.videoId, initialTrack?.videoId),
            )) {
          queueToUse = [initialTrack, ...serverQueueTracks];
        } else {
          queueToUse = serverQueueTracks;
        }
      }

      // Reset state.duration so effectiveDuration falls back to Track.duration from the queue
      final bool trackChanged =
          initialTrack != null &&
          !_isSameTrack(initialTrack.videoId, state.currentTrack?.videoId);
      state = state.copyWith(
        activeDeviceId: activeId,
        activeDeviceName: activeName,
        isPlayerDevice: isPlayer,
        historyCount: hCount,
        currentTrack: initialTrack,
        queue: queueToUse,
        originalQueue: state.isShuffled ? state.originalQueue : queueToUse,
        isPlaying: false,
        position: Duration(milliseconds: posMs),
        duration: trackChanged ? Duration.zero : null,
      );

      if (initialTrack != null) {
        loadTrackPaused(
          initialTrack,
          queueToUse,
          initialPosition: Duration(milliseconds: posMs),
        );

        // Hydrate startup/reconnect placeholders. This is deduplicated and
        // retries briefly because the owner may have just created the DB row
        // through /stream.
        if (!_hasUsableTrackTitle(initialTrack.title) ||
            initialTrack.artists.isEmpty ||
            !isPlayer) {
          unawaited(_hydrateTrackMetadata(initialTrack.videoId));
        }
      }
      return;
    }

    // 2. Non-Player Device: stop local audio and mirror the owner state.
    if (!isPlayer) {
      // Demote before awaiting the local stop. Audio engines can emit final
      // callbacks during stop; they must not overwrite this server snapshot.
      final wasLocalOwner = state.isPlayerDevice;
      if (wasLocalOwner) {
        _playRequestId++;
        _playbackGeneration++;
        _ownerTrackStartId = null;
        await _stopLocalPlayback();
      }

      if (_ownershipReleased) {
        unawaited(_recoverOwnershipAfterRelease(state.connectedDevices));
      }

      Track? currentTrack;
      if (curTrackId != null && curTrackId.isNotEmpty) {
        final found = state.queue.cast<Track?>().firstWhere(
          (t) => _isSameTrack(t?.videoId, curTrackId),
          orElse: () => null,
        );
        if (found != null) {
          currentTrack = found;
        } else if (serverQueueTracks != null) {
          currentTrack = serverQueueTracks.cast<Track?>().firstWhere(
            (t) => _isSameTrack(t?.videoId, curTrackId),
            orElse: () => null,
          );
        } else if (state.currentTrack != null &&
            _isSameTrack(state.currentTrack!.videoId, curTrackId)) {
          currentTrack = state.currentTrack;
        }
        currentTrack ??= Track(
          videoId: curTrackId,
          title: 'Unknown Track',
          artists: const [],
          downloadStatus: 'not_in_db',
          isDownloaded: false,
        );
      }

      List<Track> queueToUse = state.queue;
      if (serverQueueTracks != null) {
        if (currentTrack != null &&
            !serverQueueTracks.any(
              (t) => _isSameTrack(t.videoId, currentTrack?.videoId),
            )) {
          queueToUse = [currentTrack, ...serverQueueTracks];
        } else {
          queueToUse = serverQueueTracks;
        }
      }

      // Reset duration when track changes so effectiveDuration uses Track.duration from the queue
      final bool remoteTrackChanged =
          currentTrack != null &&
          !_isSameTrack(currentTrack.videoId, state.currentTrack?.videoId);

      // Compute initial projected position for the non-player device
      int projectedMs = posMs;
      final maxDurMs =
          (snapshot['duration_ms'] as num?)?.toInt() ??
          currentTrack?.duration?.inMilliseconds ??
          0;
      if (serverPlaying && posUpdatedAt != null) {
        final nowUtc = DateTime.now().toUtc();
        final elapsedMs = nowUtc.difference(posUpdatedAt).inMilliseconds;
        final safeElapsedMs = elapsedMs < 0 ? 0 : elapsedMs;
        final rawProjected = posMs + safeElapsedMs;
        projectedMs = maxDurMs > 0
            ? rawProjected.clamp(0, maxDurMs)
            : (rawProjected < 0 ? 0 : rawProjected);
      }

      final resolvedDuration =
          currentTrack?.duration != null &&
              currentTrack!.duration! > Duration.zero
          ? currentTrack.duration
          : (maxDurMs > 0 ? Duration(milliseconds: maxDurMs) : null);

      state = state.copyWith(
        activeDeviceId: activeId,
        activeDeviceName: activeName,
        isPlayerDevice: false,
        historyCount: hCount,
        currentTrack: currentTrack,
        queue: queueToUse,
        originalQueue: state.isShuffled ? state.originalQueue : queueToUse,
        userQueue: serverUserQueueTracks ?? state.userQueue,
        isPlaying: serverPlaying,
        isLoading: false,
        position: Duration(milliseconds: projectedMs),
        duration: resolvedDuration,
        positionUpdatedAt: posUpdatedAt,
        basePositionMs: posMs,
      );

      // Hydrate metadata whenever track changes or duration/title is missing
      if (currentTrack != null &&
          (remoteTrackChanged ||
              currentTrack.duration == null ||
              currentTrack.duration == Duration.zero ||
              !_hasUsableTrackTitle(currentTrack.title))) {
        unawaited(_hydrateTrackMetadata(currentTrack.videoId));
      }
      return;
    }

    // A pending radio snapshot deliberately contains an empty queue. Replace
    // the old context/favorites queue even in that case, then replace the
    // temporary current-only queue when the ready snapshot arrives.
    final isRadioSnapshot =
        rawQueueMode == 'radio' || state.queueMode == 'radio';
    final shouldApplyServerQueue =
        serverQueueTracks != null &&
        ((isRadioSnapshot && !state.isShuffled) ||
            (!state.isShuffled && state.queue.length <= 1));
    if (shouldApplyServerQueue) {
      final curTrack = state.currentTrack;
      final fullQueue =
          (curTrack != null &&
              !serverQueueTracks.any(
                (t) => _isSameTrack(t.videoId, curTrack.videoId),
              ))
          ? [curTrack, ...serverQueueTracks]
          : (serverQueueTracks.isEmpty && curTrack != null
                ? [curTrack]
                : serverQueueTracks);
      state = state.copyWith(queue: fullQueue, originalQueue: fullQueue);
    }

    // 3. Owner Player Device: execute pushed remote commands on local audio player
    final sameCurrentTrack =
        curTrackId != null &&
        state.currentTrack != null &&
        _isSameTrack(state.currentTrack!.videoId, curTrackId);
    final hasNewPositionAnchor =
        posUpdatedAt != null &&
        (previousPositionUpdatedAt == null ||
            posUpdatedAt.isAfter(previousPositionUpdatedAt));
    final shouldApplyOwnerSeek =
        !isInitial &&
        !suppressOwnerPlayback &&
        sameCurrentTrack &&
        hasNewPositionAnchor;

    state = state.copyWith(
      activeDeviceId: activeId,
      activeDeviceName: activeName,
      isPlayerDevice: true,
      historyCount: hCount,
      userQueue: (isStartup || isInitial)
          ? (serverUserQueueTracks ?? state.userQueue)
          : state.userQueue,
      // A marked connect/reconnect snapshot re-anchors the UI position. On
      // the first startup snapshot, keep playback paused by contract; on a
      // later reconnect, reflect the server's playing state without issuing
      // local play/pause/seek commands.
      position: (suppressOwnerPlayback && !_hasLocalAudioSource)
          ? Duration(milliseconds: posMs)
          : state.position,
      positionUpdatedAt: posUpdatedAt ?? state.positionUpdatedAt,
      basePositionMs: posMs,
      isPlaying: suppressOwnerPlayback && !isStartup
          ? serverPlaying
          : state.isPlaying,
    );

    // A remote seek keeps the same track, so it does not enter the track
    // transition branch below. Apply the newer server anchor to the owner's
    // native player directly and do not send another command back to the API.
    if (shouldApplyOwnerSeek) {
      AppLogger.instance.logPlayer(
        'owner_seek_applied_from_server',
        data: {
          'trackId': curTrackId,
          'positionMs': posMs,
          'previousPositionMs': state.position.inMilliseconds,
          'positionUpdatedAt': posUpdatedAt.toIso8601String(),
          'event': snapshot['_event_type'] ?? 'http',
        },
      );
      await _applyOwnerSeekPosition(Duration(milliseconds: posMs));
    }

    // A. Track changed via remote command
    if (curTrackId != null && curTrackId.isNotEmpty) {
      if (_pendingOwnerTrackId != null &&
          _isSameTrack(_pendingOwnerTrackId, curTrackId)) {
        _pendingOwnerTrackId = null;
      }

      final trackMismatch =
          state.currentTrack == null ||
          !_isSameTrack(state.currentTrack!.videoId, curTrackId);

      if (trackMismatch) {
        if (state.isPlayerDevice &&
            !forceTrackTransition &&
            (_pendingOwnerTrackId != null ||
                state.isLoading ||
                _ownerTrackStartId != null)) {
          debugPrint(
            '[PlayerProvider] Ignoring conflicting SSE track snapshot $curTrackId '
            'because local owner is actively executing ${state.currentTrack?.videoId} / $_pendingOwnerTrackId',
          );
          return;
        }

        if (forceTrackTransition) {
          AppLogger.instance.logQueue(
            'authoritative_transition_overrode_local_guard',
            data: {
              'trackId': curTrackId,
              'previousTrackId': state.currentTrack?.videoId,
              'isLoading': state.isLoading,
              'pendingOwnerTrackId': _pendingOwnerTrackId,
              'ownerTrackStartId': _ownerTrackStartId,
            },
          );
        }

        _lastKnownServerPlaying = serverPlaying;

        Track? newTrack = state.queue.cast<Track?>().firstWhere(
          (t) => _isSameTrack(t?.videoId, curTrackId),
          orElse: () => null,
        );
        if (newTrack == null && serverQueueTracks != null) {
          newTrack = serverQueueTracks.cast<Track?>().firstWhere(
            (t) => _isSameTrack(t?.videoId, curTrackId),
            orElse: () => null,
          );
        }
        newTrack ??= Track(
          videoId: curTrackId,
          title: 'Loading...',
          artists: const [],
          downloadStatus: 'not_in_db',
          isDownloaded: false,
        );

        if (!_hasUsableTrackTitle(newTrack.title) ||
            newTrack.artists.isEmpty ||
            newTrack.duration == null ||
            newTrack.duration == Duration.zero) {
          unawaited(_hydrateTrackMetadata(newTrack.videoId));
        }

        // The takeover response and its SSE broadcast describe the same
        // playback intent. If takeoverPlayback already owns startup for this
        // track, let that single request finish instead of opening another
        // stream from the SSE path.
        if (_ownerTrackStartId == curTrackId) return;

        if (state.isPlayerDevice) {
          _ownerTrackStartId = curTrackId;
          state = state.copyWith(
            currentTrack: newTrack,
            position: Duration.zero,
            isPlaying: false,
            isLoading: true,
          );
          _localPlaybackSuppressed = false;
          unawaited(() async {
            try {
              await playTrack(
                newTrack!,
                state.queue,
                immediate: true,
                initialPosition: Duration(milliseconds: posMs),
                syncServerState: false,
              );
            } catch (e) {
              debugPrint('Remote track start notice: $e');
            } finally {
              if (_ownerTrackStartId == curTrackId) {
                _ownerTrackStartId = null;
              }
            }
          }());
          return;
        } else {
          loadTrackPaused(
            newTrack,
            state.queue,
            initialPosition: Duration(milliseconds: posMs),
          );
          return;
        }
      }
    }

    // B. Play/Pause state flipped via remote command. A server pause must be
    // applied even when local state.isPlaying is already false: the audio
    // engine may still be playing while a stream request is completing.
    final bool isAudioActiveLocally =
        _hasLocalAudioSource ||
        (zephyrAudioHandler != null &&
            zephyrAudioHandler!.player.playing &&
            state.currentTrack != null);

    final serverPauseChanged =
        !serverPlaying && _lastKnownServerPlaying != false;
    final serverPlayChanged =
        serverPlaying &&
        state.isPlaying != true &&
        _lastKnownServerPlaying != true;
    final shouldHandlePlay =
        !isInitial &&
        !suppressPersistedStartupPlayback &&
        serverPlaying &&
        !_localPlaybackSuppressed &&
        (serverPlayChanged || (!isAudioActiveLocally && !state.isPlaying));

    if (!suppressOwnerPlayback && (serverPauseChanged || shouldHandlePlay)) {
      _lastKnownServerPlaying = serverPlaying;
      if (serverPlaying) {
        if (isAudioActiveLocally) {
          _localPlaybackSuppressed = false;
          try {
            await zephyrAudioHandler?.play();
          } catch (_) {}
          await _audioPlayer.resume();
          state = state.copyWith(isPlaying: true);
        } else if (state.currentTrack != null &&
            _ownerTrackStartId != state.currentTrack!.videoId &&
            !state.isPlaying) {
          // The server says play, but this owner has no local source. Start
          // the stream explicitly even if a stale request left isLoading set.
          // The owner-track guard prevents duplicate requests for one SSE
          // mutation while the stream is resolving.
          final trackToStart = state.currentTrack!;
          _ownerTrackStartId = trackToStart.videoId;
          state = state.copyWith(isLoading: true, isPlaying: false);
          _localPlaybackSuppressed = false;
          unawaited(() async {
            try {
              await playTrack(trackToStart, state.queue, immediate: true);
            } catch (e) {
              debugPrint('Owner playback start notice: $e');
            } finally {
              if (_ownerTrackStartId == trackToStart.videoId) {
                _ownerTrackStartId = null;
              }
            }
          }());
        }
      } else {
        state = state.copyWith(isPlaying: false);
        await _pauseLocalPlayback();
      }
    } else {
      _lastKnownServerPlaying = serverPlaying;
    }

    // C. Re-anchor position for devices without active local audio source
    if (!_hasLocalAudioSource &&
        !suppressOwnerPlayback &&
        !state.isPlayerDevice) {
      state = state.copyWith(position: Duration(milliseconds: posMs));
    }
  }

  void updateDeviceName(String newName) {
    state = state.copyWith(myDeviceName: newName);
  }

  void updateConnectedDevices(List<Map<String, dynamic>> devices) {
    state = state.copyWith(connectedDevices: devices);
  }

  Future<void> sendRemoteCommand(
    String action, {
    String? trackId,
    int? positionMs,
    String? origin,
    bool? seedRadio,
  }) async {
    try {
      Map<String, dynamic>? response;
      if (action == 'next') {
        // The async-radio contract explicitly supports remote next intents;
        // the owner uses the dedicated transition endpoint.
        response = !state.isPlayerDevice
            ? await _api.sendPlayerCommand(action: action)
            : await _api.nextPlayerTrack();
      } else if (action == 'previous') {
        // Keep the established previous endpoint for both device roles.
        response = await _api.previousPlayerTrack();
      } else {
        String validAction = action;
        if (action == 'resume') {
          validAction = 'toggle';
        }
        response = await _api.sendPlayerCommand(
          action: validAction,
          currentTrackId: trackId,
          positionMs: positionMs,
          origin: origin,
          seedRadio: seedRadio,
        );
      }
      AppLogger.instance.logQueue(
        'remote_command_result',
        data: {
          'action': action,
          'currentTrackId': response?['current_track_id'],
          'isPlaying': response?['is_playing'],
          'updatedAt': response?['updated_at'],
          'queueLength': response?['queue'] is List
              ? (response!['queue'] as List).length
              : null,
        },
      );
      if (response != null && response.isNotEmpty) {
        final httpStatus = (response['_http_status'] as num?)?.toInt();
        await _enqueueServerSnapshot(
          response,
          forceTrackTransition: action == 'next' || action == 'previous',
        );
        if (action == 'next' &&
            httpStatus == 202 &&
            response['radio_status']?.toString() == 'pending') {
          _nextWaitingForRadioTrackId = state.currentTrack?.videoId;
          AppLogger.instance.logQueue(
            'next_waiting_for_radio',
            data: {
              'trackId': _nextWaitingForRadioTrackId,
              'radioRequestId': response['radio_request_id'],
              'radioGeneration': response['radio_generation'],
            },
          );
        }
      }
    } catch (e) {
      AppLogger.instance.logQueue(
        'remote_command_failed',
        data: {'action': action, 'error': e.toString()},
      );
      debugPrint('Error sending player command: $e');
    }
  }

  Future<bool> takeoverPlayback({
    bool force = false,
    bool startPlayback = true,
    bool showConflictDialog = true,
  }) async {
    try {
      final devId = state.myDeviceId.isNotEmpty
          ? state.myDeviceId
          : await DeviceInfo.getDeviceId();
      final devName = state.myDeviceName.isNotEmpty
          ? state.myDeviceName
          : await DeviceInfo.getDeviceName();

      // The takeover response is the authoritative handoff snapshot. The
      // remote's locally extrapolated position may be stale by several
      // seconds, so never use state.position captured before this request.
      // Reserve this track before the request completes: the same takeover
      // snapshot is also broadcast through SSE and must not start a duplicate
      // stream on this device.
      final takeoverTrackId = state.currentTrack?.videoId;
      if (takeoverTrackId != null) {
        _ownerTrackStartId = takeoverTrackId;
      }
      final takeoverSnapshot = await _api.takeoverPlayer(
        deviceId: devId,
        deviceName: devName,
        force: force,
      );
      await _enqueueServerSnapshot(
        takeoverSnapshot,
        suppressOwnerPlayback: true,
      );

      int posMs =
          (takeoverSnapshot['position_ms'] as num?)?.toInt() ??
          state.position.inMilliseconds;
      final posUpdatedAt = _parseUtcTimestamp(
        takeoverSnapshot['position_updated_at'],
      );
      final serverPlaying = takeoverSnapshot['is_playing'] == true;

      if (serverPlaying && posUpdatedAt != null) {
        final nowUtc = DateTime.now().toUtc();
        final elapsedMs = nowUtc.difference(posUpdatedAt).inMilliseconds;
        final safeElapsedMs = elapsedMs < 0 ? 0 : elapsedMs;
        posMs += safeElapsedMs;
      }

      // Rewind ~3.5 seconds for connection/buffering debouncing, ensuring >= 0
      final totalDurMs = state.effectiveDuration.inMilliseconds;
      final maxAllowedMs = totalDurMs > 0 ? totalDurMs : posMs;
      final clampedPosMs = posMs.clamp(0, maxAllowedMs);
      final handoverMs = math.max(0, clampedPosMs - 3500);
      final currentPos = Duration(milliseconds: handoverMs);

      state = state.copyWith(
        isPlayerDevice: true,
        activeDeviceId: devId,
        activeDeviceName: devName,
        position: currentPos,
        isPlaying: serverPlaying,
      );

      if (state.currentTrack != null) {
        final trackForPlay = state.currentTrack!;
        if (serverPlaying && startPlayback) {
          try {
            await playTrack(
              trackForPlay,
              state.queue,
              initialPosition: currentPos,
            );
          } finally {
            if (_ownerTrackStartId == trackForPlay.videoId) {
              _ownerTrackStartId = null;
            }
          }
        } else {
          // Taking ownership of a paused session must not unexpectedly start
          // audio. Keep the authoritative position loaded and paused.
          // A startup solo claim establishes ownership but deliberately
          // keeps the local engine paused, even if the persisted server state
          // says is_playing=true. Explicit user Play/Resume may start it.
          loadTrackPaused(
            trackForPlay,
            state.queue,
            initialPosition: currentPos,
          );
          if (_ownerTrackStartId == trackForPlay.videoId) {
            _ownerTrackStartId = null;
          }
        }

        // The takeover may receive a queue placeholder while /stream creates
        // or exposes the canonical DB metadata. Hydrate with retry.
        unawaited(_hydrateTrackMetadata(trackForPlay.videoId));
      }
      return true;
    } on PlayerActiveException catch (e) {
      _ownerTrackStartId = null;
      if (!showConflictDialog) return false;
      final context = rootNavigatorKey.currentContext;
      if (context != null && context.mounted) {
        final confirm = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: ZephyrColors.bgCard,
            title: const Text('Playback Active on Another Device'),
            content: Text(
              'Audio is currently playing on "${e.ownerDeviceName}". Switch playback to this device?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text(
                  'Cancel',
                  style: TextStyle(color: ZephyrColors.textDim),
                ),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: ZephyrColors.primary,
                ),
                child: const Text(
                  'Switch Here',
                  style: TextStyle(
                    color: Colors.black,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        );

        if (confirm == true) {
          return await takeoverPlayback(force: true);
        }
      }
      return false;
    } catch (e) {
      _ownerTrackStartId = null;
      debugPrint('Takeover error: $e');
      return false;
    }
  }

  @override
  ZephyrPlayerState build() {
    _initStreams();
    _loadSavedVolume();
    _initDeviceAndSse();

    if (!kIsWeb && Platform.isLinux) {
      LinuxMprisService().init(
        onPlayPause: () => togglePlayPause(),
        onNext: () => playNext(),
        onPrevious: () => playPrevious(),
        onSetVolume: (vol) => setVolume(vol),
      );
    }

    try {
      zephyrAudioHandler?.onSkipNext = () => playNext();
      zephyrAudioHandler?.onSkipPrevious = () => playPrevious();
      zephyrAudioHandler?.isPlaybackOwner = () => state.isPlayerDevice;
    } catch (_) {}

    ref.onDispose(() {
      _sseSub?.cancel();
      _ownershipRecoveryTimer?.cancel();
      _skipDebounceTimer?.cancel();
      _positionSub?.cancel();
      _durationSub?.cancel();
      _stateSub?.cancel();
      _completeSub?.cancel();
      _cursorTimer?.cancel();
      _cursorTimer = null;
      _audioPlayer.dispose();
    });

    ref.listen(authProvider, (previous, next) {
      if (next.token == null) {
        _lastAppliedServerUpdateAt = null;
        _sseSub?.cancel();
        _sseSub = null;
        _audioPlayer.stop();
        state = ZephyrPlayerState();
      } else if (previous?.token == null && next.token != null) {
        _lastAppliedServerUpdateAt = null;
        _initDeviceAndSse();
      }
    });

    return ZephyrPlayerState();
  }

  Future<void> _loadSavedVolume() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedVolume = prefs.getDouble('player_volume');
      if (savedVolume != null) {
        final volume = savedVolume.clamp(0.0, 1.0).toDouble();
        state = state.copyWith(volume: volume);
        await _applyVolumeToPlayers(volume);
      }
    } catch (_) {}
  }

  void _initStreams() {
    void updatePos(Duration pos) {
      // Audio callbacks belong only to the local OWNER. When ownership is
      // transferred away, just_audio/audioplayers can emit a final zero
      // position while being paused; accepting it would overwrite the
      // authoritative SSE position on this REMOTE.
      if (!state.isPlayerDevice) return;

      if (_isInitialLoad &&
          !state.isPlaying &&
          pos == Duration.zero &&
          state.position > Duration.zero) {
        return;
      }
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
            : (pos.inSeconds >= 30);

        if (isCorrectTrack && isListenLimitReached) {
          _hasRecordedCurrentTrack = true;
          final trackToRecord = state.currentTrack!;

          // Record locally & send / buffer for sync
          ref
              .read(libraryProvider.notifier)
              .recordListen(trackToRecord.videoId, trackToRecord);
        }
      }
    }

    void updateDur(Duration dur) {
      // Do not let a paused local audio engine overwrite the duration of the
      // track currently being mirrored from the OWNER.
      if (!state.isPlayerDevice) return;

      if (dur > Duration.zero) {
        state = state.copyWith(duration: dur);
        if (state.currentTrack != null &&
            (state.currentTrack!.duration == null ||
                state.currentTrack!.duration == Duration.zero)) {
          state = state.copyWith(
            currentTrack: state.currentTrack!.copyWith(duration: dur),
          );
        }
      }
    }

    if (zephyrAudioHandler == null) {
      _positionSub = _audioPlayer.onPositionChanged.listen(
        updatePos,
        onError: (_) {},
      );
      _durationSub = _audioPlayer.onDurationChanged.listen(
        updateDur,
        onError: (_) {},
      );
      _stateSub = _audioPlayer.onPlayerStateChanged.listen((playerState) {
        if (!state.isPlayerDevice || _localPlaybackSuppressed) return;
        final isPlaying = playerState == ap.PlayerState.playing;
        state = state.copyWith(
          isPlaying: isPlaying,
          isLoading: isPlaying ? false : state.isLoading,
        );
        LinuxMprisService().updateState(
          isPlaying: isPlaying,
          track: state.currentTrack,
          apiBaseUrl: _api.baseUrl,
        );
      }, onError: (_) {});
      _completeSub = _audioPlayer.onPlayerComplete.listen((_) {
        if (!state.isPlaying || _localPlaybackSuppressed) return;
        _handlePlaybackComplete();
      }, onError: (_) {});
    }

    // Remote cursor projection is intentionally local. The authoritative
    // track/queue transition arrives through SSE; reaching the projected end
    // must never start a periodic GET /api/player/state loop.
    _cursorTimer ??= Timer.periodic(const Duration(seconds: 1), (_) {
      if (!state.isPlayerDevice &&
          state.isPlaying &&
          state.currentTrack != null) {
        state = state.copyWith(position: state.projectedPosition);
      }
    });

    try {
      zephyrAudioHandler?.player.positionStream.listen(
        updatePos,
        onError: (_) {},
      );
      zephyrAudioHandler?.player.durationStream.listen((dur) {
        if (dur != null) updateDur(dur);
      }, onError: (_) {});
      zephyrAudioHandler?.player.playerStateStream.listen((ps) {
        if (!state.isPlayerDevice || _localPlaybackSuppressed) return;
        final isPlaying = ps.playing;
        state = state.copyWith(
          isPlaying: isPlaying,
          isLoading:
              (ps.processingState == ProcessingState.ready ||
                  ps.processingState == ProcessingState.completed)
              ? false
              : state.isLoading,
        );
        if (ps.processingState == ProcessingState.completed &&
            !_localPlaybackSuppressed) {
          AppLogger.instance.logPlayer(
            'player_processing_completed_event',
            data: {
              'track': state.currentTrack?.title,
              'queueIndex': state.currentIndex,
              'queueLength': state.queue.length,
            },
          );
          _handlePlaybackComplete();
        }
        LinuxMprisService().updateState(
          isPlaying: isPlaying,
          track: state.currentTrack,
          apiBaseUrl: _api.baseUrl,
        );
      }, onError: (_) {});
    } catch (_) {}

    _audioPlayer.onLog.listen((_) {}, onError: (_) {});
  }

  Future<void> playTrack(
    Track track,
    List<Track> playQueue, {
    bool immediate = false,
    bool isNewQueue = false,
    String? origin,
    Duration? initialPosition,
    bool syncServerState = true,
  }) async {
    // A new explicit play invalidates any pending end-of-radio retry.
    _nextWaitingForRadioTrackId = null;

    AppLogger.instance.logPlayer(
      'play_track_requested',
      data: {
        'track': track.title,
        'videoId': track.videoId,
        'artists': track.artists,
        'isPlayerDevice': state.isPlayerDevice,
        'queueLength': playQueue.length,
        'isNewQueue': isNewQueue,
        'origin': origin,
        'initialPosMs': initialPosition?.inMilliseconds,
      },
    );

    if (!state.isPlayerDevice &&
        (state.activeDeviceId == null || state.activeDeviceId!.isEmpty)) {
      await _claimLocalPlaybackIfUnowned();
    }

    if (!state.isPlayerDevice) {
      // Remote control mode: dispatch play command to server for active player to execute
      final bool shouldSeedRadio = (origin == 'search' || origin == 'radio');
      List<Track> fullToSend = playQueue.isNotEmpty ? playQueue : [track];
      if (origin != 'queue' && state.isShuffled && playQueue.length > 1) {
        final remaining =
            playQueue.where((t) => t.videoId != track.videoId).toList()
              ..shuffle();
        fullToSend = [track, ...remaining];
      }

      try {
        state = state.copyWith(
          currentTrack: track,
          queue: shouldSeedRadio ? [track] : fullToSend,
          originalQueue: shouldSeedRadio
              ? [track]
              : (playQueue.isNotEmpty ? playQueue : [track]),
          queueMode: shouldSeedRadio ? 'radio' : null,
          radioStatus: shouldSeedRadio ? 'pending' : null,
          clearRadioError: shouldSeedRadio,
          currentIndex: 0,
          position: Duration.zero,
          duration: track.duration ?? Duration.zero,
          isPlaying: true,
          isLoading: true,
          errorMessage: null,
        );

        final response = await _api.sendPlayerCommand(
          action: 'play_track',
          currentTrackId: track.videoId,
          origin: origin == 'queue' || origin == 'context' ? origin : null,
          seedRadio: shouldSeedRadio ? true : null,
        );
        if (response != null && response.isNotEmpty) {
          await _enqueueServerSnapshot(response);
        }
      } catch (e) {
        debugPrint('Notice: Remote play track update: $e');
      }
      return;
    }

    final requestId = ++_playRequestId;
    final playbackGeneration = ++_playbackGeneration;
    _pendingOwnerTrackId = track.videoId;
    _skipDebounceTimer?.cancel();
    _localPlaybackSuppressed = false;
    _hasLocalAudioSource = false;

    final prevState = state;

    // Seamlessly prepare media notification and pause previous audio in-place
    try {
      if (zephyrAudioHandler != null) {
        await zephyrAudioHandler!.prepareForTrackTransition(
          track,
          _api.baseUrl,
        );
      } else {
        await _audioPlayer.stop();
      }
    } catch (_) {}

    final initialDur =
        (track.duration != null && track.duration! > Duration.zero)
        ? track.duration!
        : Duration.zero;

    List<Track> queueToSet;
    List<Track> originalQueueToSet;
    int targetIndex = 0;

    final bool isFromCurrentQueue =
        origin == 'queue' ||
        (origin != 'context' &&
            !isNewQueue &&
            state.queue.isNotEmpty &&
            state.queue.any((t) => _isSameTrack(t.videoId, track.videoId)));

    if (isFromCurrentQueue) {
      queueToSet = state.queue;
      originalQueueToSet = state.originalQueue.isNotEmpty
          ? state.originalQueue
          : state.queue;
      final foundIdx = queueToSet.indexWhere(
        (t) => _isSameTrack(t.videoId, track.videoId),
      );
      targetIndex = foundIdx != -1 ? foundIdx : 0;
    } else {
      // New playlist / album / context playback
      final baseList = playQueue.isNotEmpty ? playQueue : [track];
      originalQueueToSet = List<Track>.from(baseList);

      if (state.isShuffled && baseList.length > 1) {
        final remaining =
            baseList
                .where((t) => !_isSameTrack(t.videoId, track.videoId))
                .toList()
              ..shuffle();
        queueToSet = [track, ...remaining];
        targetIndex = 0;
      } else {
        queueToSet = List<Track>.from(baseList);
        final foundIdx = queueToSet.indexWhere(
          (t) => _isSameTrack(t.videoId, track.videoId),
        );
        targetIndex = foundIdx != -1 ? foundIdx : 0;
      }
    }

    // Immediately update UI metadata so skipping responds instantly on screen in loading/paused state
    state = state.copyWith(
      isLoading: true,
      isPlaying: false,
      currentTrack: track,
      queue: queueToSet,
      originalQueue: originalQueueToSet,
      currentIndex: targetIndex,
      position: initialPosition ?? Duration.zero,
      duration: initialDur,
      errorMessage: null,
    );

    if (!_hasUsableTrackTitle(track.title) ||
        track.artists.isEmpty ||
        track.duration == null ||
        track.duration == Duration.zero) {
      unawaited(_hydrateTrackMetadata(track.videoId));
    }

    final userQueueMaps = state.userQueue
        .map(
          (t) => {
            'track_id': t.videoId,
            'title': t.title,
            'artists': t.artists,
            'album': t.album,
            'duration_seconds': t.duration?.inSeconds ?? 0,
            'cover_url': t.coverUrl,
            'stream_url': '/api/tracks/stream/${t.videoId}',
          },
        )
        .toList();

    // The async radio contract makes seeding non-blocking. Clear the local
    // queue immediately, start the stream below, and let the response/SSE
    // snapshot install the generated queue when it is ready.
    bool radioSeedRequested = false;
    if (syncServerState && (origin == 'search' || origin == 'radio')) {
      radioSeedRequested = true;
      state = state.copyWith(
        queue: [track],
        originalQueue: [track],
        currentIndex: 0,
        queueMode: 'radio',
        radioStatus: 'pending',
        clearRadioError: true,
      );
      AppLogger.instance.logQueue(
        'radio_seed_started_async',
        data: {
          'trackId': track.videoId,
          'origin': origin,
          'isPlayerDevice': state.isPlayerDevice,
        },
      );
      unawaited(
        _seedRadioInBackground(
          track: track,
          userQueue: userQueueMaps,
          playbackGeneration: playbackGeneration,
        ),
      );
    }

    Future<void> executePlay() async {
      if (!_canContinuePlayback(requestId, playbackGeneration)) return;

      Track finalTrack = track;
      if (state.currentTrack != null &&
          _isSameTrack(state.currentTrack!.videoId, track.videoId) &&
          _hasUsableTrackTitle(state.currentTrack!.title)) {
        finalTrack = _mergeTrackMetadata(track, state.currentTrack!);
      }

      bool success = false;
      Object? lastError;

      final localAudioPath = OfflineStorageService().getAudioFilePath(
        finalTrack.videoId,
      );
      final bool isLocal = localAudioPath != null;

      try {
        final streamUrl = isLocal
            ? ''
            : await _api.getStreamProxyUrl(finalTrack.videoId);
        if (!_canContinuePlayback(requestId, playbackGeneration)) return;

        bool audioHandlerStarted = false;
        try {
          if (zephyrAudioHandler != null) {
            await zephyrAudioHandler!.player.setVolume(
              _volumeToGain(state.volume),
            );
            if (isLocal) {
              await zephyrAudioHandler!.playFilePath(
                localAudioPath,
                finalTrack,
                _api.baseUrl,
                initialPosition: initialPosition,
              );
            } else {
              await zephyrAudioHandler!.playUrl(
                streamUrl,
                finalTrack,
                _api.baseUrl,
                initialPosition: initialPosition,
              );
            }
            audioHandlerStarted = true;
          }
        } catch (e) {
          if (!isLocal) {
            final proxyError = _api.takeProxyStreamError(finalTrack.videoId);
            if (proxyError is ResolutionRequiredException) {
              throw proxyError;
            }
            if (proxyError is TrackUnavailableException) {
              throw proxyError;
            }
            if (proxyError is ProviderUnavailableException) {
              throw proxyError;
            }
          }
          debugPrint('zephyrAudioHandler fallback to audioplayers: $e');
        }

        if (!_canContinuePlayback(requestId, playbackGeneration)) return;
        if (!audioHandlerStarted) {
          await _audioPlayer.stop();
          if (!_canContinuePlayback(requestId, playbackGeneration)) return;
          try {
            if (isLocal) {
              await _audioPlayer.setSource(ap.DeviceFileSource(localAudioPath));
            } else {
              await _audioPlayer.setSource(ap.UrlSource(streamUrl));
            }
          } catch (e) {
            if (!isLocal) {
              final proxyError = await _api.waitForProxyStreamError(
                finalTrack.videoId,
              );
              if (proxyError is ResolutionRequiredException) {
                throw proxyError;
              }
              if (proxyError is TrackUnavailableException) {
                throw proxyError;
              }
              if (proxyError is ProviderUnavailableException) {
                throw proxyError;
              }
            }
            rethrow;
          }
          await _audioPlayer.setVolume(_volumeToGain(state.volume));
        }

        // The audio handler seeks before play. Keep the fallback path
        // consistent by seeking before its first resume as well.
        if (!_canContinuePlayback(requestId, playbackGeneration)) return;
        if (!audioHandlerStarted) {
          if (initialPosition != null && initialPosition > Duration.zero) {
            try {
              await _audioPlayer.seek(initialPosition);
            } catch (e) {
              debugPrint('Error seeking to initialPosition: $e');
            }
          }
          await _audioPlayer.resume();
        }

        // Pause/takeover can happen while the source is loading. Never allow
        // an obsolete play request to resurrect audio after that transition.
        if (!_canContinuePlayback(requestId, playbackGeneration)) {
          await _stopLocalPlayback();
          return;
        }
        _hasLocalAudioSource = true;
        success = true;
      } on ResolutionRequiredException catch (e) {
        if (_playRequestId != requestId) return;
        state = prevState.copyWith(
          isLoading: false,
          errorMessage:
              'Selection required for "${e.title}". Tap to choose match.',
        );
        _triggerResolutionModal(e, finalTrack, playQueue);
        rethrow;
      } on TrackUnavailableException catch (e) {
        if (_playRequestId != requestId) return;
        state = prevState.copyWith(isLoading: false, errorMessage: e.message);
        _triggerResolutionModal(e, finalTrack, playQueue);
        rethrow;
      } on ProviderUnavailableException catch (e) {
        if (_playRequestId != requestId) return;
        state = prevState.copyWith(isLoading: false, errorMessage: e.message);
        return;
      } on RateLimitException catch (e) {
        if (_playRequestId != requestId) return;
        state = prevState.copyWith(isLoading: false, errorMessage: e.message);
        return;
      } on PlatformException catch (e) {
        if (_playRequestId != requestId) return;
        lastError = e.message ?? e.toString();
        final errStr = e.toString().toLowerCase();
        if (errStr.contains('429') || errStr.contains('too many requests')) {
          state = prevState.copyWith(
            isLoading: false,
            errorMessage:
                'Stream rate limited by provider (HTTP 429). Please wait a few seconds.',
          );
          return;
        }
      } catch (e) {
        if (_playRequestId != requestId) return;

        // The local proxy receives backend errors on behalf of the audio
        // engine, which cannot expose Dio's JSON response to this layer.
        // Rehydrate the typed resolution/unavailable exception before the
        // generic playback error path consumes it.
        final proxyError = _api.takeProxyStreamError(finalTrack.videoId);
        if (proxyError is ResolutionRequiredException) {
          state = prevState.copyWith(
            isLoading: false,
            errorMessage:
                'Selection required for "${proxyError.title}". Tap to choose match.',
          );
          _triggerResolutionModal(proxyError, finalTrack, playQueue);
          return;
        }
        if (proxyError is TrackUnavailableException) {
          state = prevState.copyWith(
            isLoading: false,
            errorMessage: proxyError.message,
          );
          _triggerResolutionModal(proxyError, finalTrack, playQueue);
          return;
        }

        lastError = e;
      }

      if (!_canContinuePlayback(requestId, playbackGeneration)) return;

      if (!success) {
        try {
          await _audioPlayer.stop();
        } catch (_) {}
        state = prevState.copyWith(
          isLoading: false,
          errorMessage: 'Playback error: ${lastError ?? "Stream unavailable"}',
        );
      } else {
        _lastTrackId = finalTrack.videoId;
        _hasRecordedCurrentTrack = false;
        _isInitialLoad = false;

        final resolvedDuration =
            (finalTrack.duration != null &&
                finalTrack.duration! > Duration.zero)
            ? finalTrack.duration!
            : (state.duration > Duration.zero ? state.duration : Duration.zero);

        final trackWithDuration = finalTrack.copyWith(
          duration: resolvedDuration > Duration.zero
              ? resolvedDuration
              : finalTrack.duration,
        );

        state = state.copyWith(
          isLoading: false,
          currentTrack: trackWithDuration,
          position: initialPosition ?? Duration.zero,
          duration: resolvedDuration,
          errorMessage: null,
          isPlaying: true,
        );
        updateWebMediaSession(finalTrack, this);
        LinuxMprisService().updateState(
          isPlaying: true,
          track: finalTrack,
          apiBaseUrl: _api.baseUrl,
        );

        // If played track was a stub, attempt to enrich metadata from DB immediately
        if (finalTrack.artists.isEmpty || finalTrack.title == 'Loading...') {
          final trackId = finalTrack.videoId;
          _api
              .getTrackMetadata(trackId)
              .then((fullMeta) {
                if (_isSameTrack(state.currentTrack?.videoId, trackId)) {
                  state = state.copyWith(
                    currentTrack: state.currentTrack!.copyWith(
                      title: fullMeta.title != 'Unknown Track'
                          ? fullMeta.title
                          : state.currentTrack!.title,
                      artists: fullMeta.artists.isNotEmpty
                          ? fullMeta.artists
                          : state.currentTrack!.artists,
                      album: fullMeta.album ?? state.currentTrack!.album,
                      duration:
                          (fullMeta.duration != null &&
                              fullMeta.duration! > Duration.zero)
                          ? fullMeta.duration
                          : state.currentTrack!.duration,
                      coverUrl:
                          fullMeta.coverUrl ?? state.currentTrack!.coverUrl,
                      localPath: fullMeta.localPath,
                      localCoverPath: fullMeta.localCoverPath,
                      lyricsText: fullMeta.lyricsText,
                      lyricsLrc: fullMeta.lyricsLrc,
                      downloadStatus: 'completed',
                      isDownloaded: true,
                    ),
                  );
                  _api.notifyLyricsReady(trackId);
                }
              })
              .catchError((_) {});
        }

        // Sync player state with the server-owned context/radio queue.
        if (syncServerState) {
          try {
            final foundIndex = playQueue.indexWhere(
              (t) => t.videoId == finalTrack.videoId,
            );
            final remaining =
                foundIndex != -1 && foundIndex < playQueue.length - 1
                ? playQueue.sublist(foundIndex + 1)
                : (playQueue.length > 1
                      ? (List<Track>.from(playQueue)
                          ..removeWhere((t) => t.videoId == finalTrack.videoId))
                      : <Track>[]);

            final bool isContextQueue =
                (origin != 'search' && origin != 'radio') &&
                (remaining.isNotEmpty ||
                    playQueue.length > 1 ||
                    state.queue.length > 1);
            final String mode = isContextQueue ? 'context' : 'radio';

            if (isContextQueue) {
              final List<Track> baseQueue = state.isShuffled
                  ? state.queue
                        .where(
                          (t) => !_isSameTrack(t.videoId, finalTrack.videoId),
                        )
                        .toList()
                  : remaining;

              final queueMaps = baseQueue
                  .take(50)
                  .map(
                    (t) => {
                      'track_id': t.videoId,
                      'title': t.title,
                      'artists': t.artists,
                      'album': t.album,
                      'duration_seconds': t.duration?.inSeconds ?? 0,
                      'cover_url': t.coverUrl,
                      'stream_url': '/api/tracks/stream/${t.videoId}',
                    },
                  )
                  .toList();

              final res = await _api.updatePlayerState(
                deviceId: state.isPlayerDevice ? state.myDeviceId : null,
                deviceName: state.isPlayerDevice ? state.myDeviceName : null,
                currentTrackId: finalTrack.videoId,
                queueMode: mode,
                queue: queueMaps,
                userQueue: userQueueMaps,
                isPlaying: true,
                origin: origin == 'queue'
                    ? 'queue'
                    : (origin == 'context' ? 'context' : null),
              );
              final int hCount =
                  (res['history_count'] as num?)?.toInt() ?? state.historyCount;
              // In context/playlist mode, preserve the client's complete playlist queue
              state = state.copyWith(historyCount: hCount);
            } else {
              final Map<String, dynamic> res;
              if (radioSeedRequested) {
                AppLogger.instance.logQueue(
                  'radio_playback_heartbeat',
                  data: {'trackId': finalTrack.videoId, 'origin': origin},
                );
                res = await _api.updatePlayerState(
                  deviceId: state.isPlayerDevice ? state.myDeviceId : null,
                  deviceName: state.isPlayerDevice ? state.myDeviceName : null,
                  currentTrackId: finalTrack.videoId,
                  queueMode: 'radio',
                  userQueue: userQueueMaps,
                  isPlaying: true,
                );
                await _enqueueServerSnapshot(res, suppressOwnerPlayback: true);
              } else {
                AppLogger.instance.logQueue(
                  'radio_seed_requested',
                  data: {
                    'trackId': finalTrack.videoId,
                    'origin': origin,
                    'isPlayerDevice': state.isPlayerDevice,
                  },
                );
                res = await _api.updatePlayerState(
                  deviceId: state.isPlayerDevice ? state.myDeviceId : null,
                  deviceName: state.isPlayerDevice ? state.myDeviceName : null,
                  currentTrackId: finalTrack.videoId,
                  queueMode: 'radio',
                  seedRadio: true,
                  userQueue: userQueueMaps,
                  isPlaying: true,
                );
                AppLogger.instance.logQueue(
                  'radio_seed_response',
                  data: {
                    'trackId': finalTrack.videoId,
                    'responseTrackId': res['current_track_id'],
                    'queueLength': res['queue'] is List
                        ? (res['queue'] as List).length
                        : null,
                    'queueCount': res['queue_count'],
                    'updatedAt': res['updated_at'],
                  },
                );
              }
              final int hCount =
                  (res['history_count'] as num?)?.toInt() ?? state.historyCount;
              if (radioSeedRequested) {
                state = state.copyWith(
                  queueMode: 'radio',
                  historyCount: hCount,
                );
              } else if (res.containsKey('queue') && res['queue'] is List) {
                final List serverQueue = res['queue'];
                final List<Track> radioTracks = serverQueue
                    .map((e) => Track.fromJson(e))
                    .toList();
                if (radioTracks.isNotEmpty) {
                  final fullQueue = [finalTrack, ...radioTracks];
                  state = state.copyWith(
                    queue: fullQueue,
                    originalQueue: fullQueue,
                    currentIndex: 0,
                    queueMode: 'radio',
                    historyCount: hCount,
                  );
                } else {
                  // Server didn't return radio tracks inline — fetch via discovery
                  state = state.copyWith(
                    queueMode: 'radio',
                    historyCount: hCount,
                  );
                  _fetchDiscoveryQueue(finalTrack);
                }
              } else {
                // No queue key in response at all — fetch via discovery
                state = state.copyWith(
                  queueMode: 'radio',
                  historyCount: hCount,
                );
                _fetchDiscoveryQueue(finalTrack);
              }
            }
          } catch (e) {
            debugPrint('Notice: Server player state sync: $e');
          }
        }
      }
    }

    try {
      if (immediate) {
        await executePlay();
      } else {
        await Future.delayed(const Duration(milliseconds: 200));
        if (_playRequestId == requestId) {
          await executePlay();
        }
      }
    } finally {
      if (_pendingOwnerTrackId == track.videoId) {
        _pendingOwnerTrackId = null;
      }
    }
  }

  Future<void> _seedRadioInBackground({
    required Track track,
    required List<Map<String, dynamic>> userQueue,
    required int playbackGeneration,
  }) async {
    try {
      final seedResponse = await _api.updatePlayerState(
        deviceId: state.isPlayerDevice ? state.myDeviceId : null,
        deviceName: state.isPlayerDevice ? state.myDeviceName : null,
        currentTrackId: track.videoId,
        queueMode: 'radio',
        seedRadio: true,
        userQueue: userQueue,
        isPlaying: false,
      );

      AppLogger.instance.logQueue(
        'radio_seed_async_response',
        data: {
          'trackId': track.videoId,
          'queueMode': seedResponse['queue_mode'],
          'radioStatus': seedResponse['radio_status'],
          'radioRequestId': seedResponse['radio_request_id'],
          'radioGeneration': seedResponse['radio_generation'],
          'queueLength': seedResponse['queue'] is List
              ? (seedResponse['queue'] as List).length
              : null,
        },
      );

      // A newer play/skip must not have its local queue replaced by the old
      // seed response. The backend independently discards stale jobs.
      if (_playbackGeneration != playbackGeneration ||
          !_isSameTrack(state.currentTrack?.videoId, track.videoId)) {
        AppLogger.instance.logQueue(
          'radio_seed_async_response_ignored',
          data: {
            'trackId': track.videoId,
            'currentTrackId': state.currentTrack?.videoId,
            'playbackGeneration': playbackGeneration,
            'currentPlaybackGeneration': _playbackGeneration,
          },
        );
        return;
      }

      await _enqueueServerSnapshot(seedResponse, suppressOwnerPlayback: true);
    } catch (e) {
      AppLogger.instance.logQueue(
        'radio_seed_async_failed',
        data: {'trackId': track.videoId, 'error': e.toString()},
      );
      if (_playbackGeneration == playbackGeneration &&
          _isSameTrack(state.currentTrack?.videoId, track.videoId)) {
        state = state.copyWith(
          radioStatus: 'failed',
          radioErrorCode: 'provider_error',
          radioErrorMessage: e.toString(),
        );
      }
    }
  }

  /// Legacy fallback for servers that do not implement the asynchronous
  /// `radio_status` contract and return no radio tracks inline.
  void _fetchDiscoveryQueue(Track seed) {
    AppLogger.instance.logQueue(
      'radio_discovery_fallback_requested',
      data: {'trackId': seed.videoId, 'ytId': seed.ytId},
    );
    _api
        .getDiscoveryQueue(seed.videoId)
        .then((res) async {
          List<Track> discovered = [];
          if (res.containsKey('queue') && res['queue'] is List) {
            discovered = (res['queue'] as List)
                .map(
                  (e) => Track.fromJson(
                    e is Map<String, dynamic>
                        ? e
                        : Map<String, dynamic>.from(e as Map),
                  ),
                )
                .toList();
          }

          // If Deezer discovery returned no tracks (e.g. local track without Deezer ID), fallback to related tracks
          if (discovered.isEmpty) {
            try {
              final targetId = (seed.ytId != null && seed.ytId!.isNotEmpty)
                  ? seed.ytId!
                  : seed.videoId;
              final relatedRes = await _api.getRelatedTracks(targetId);
              final sections = (relatedRes['sections'] as List?) ?? [];
              for (final section in sections) {
                if (section is Map &&
                    section.containsKey('items') &&
                    section['items'] is List) {
                  for (final item in section['items']) {
                    if (item is Map) {
                      discovered.add(
                        Track.fromJson(
                          item is Map<String, dynamic>
                              ? item
                              : Map<String, dynamic>.from(item),
                        ),
                      );
                    }
                  }
                }
              }
            } catch (_) {}
          }

          // Fallback: If still empty and track has artist, query artist's tracks locally
          if (discovered.isEmpty && seed.artists.isNotEmpty) {
            try {
              final searchRes = await _api.search(
                seed.artists.first,
                remote: false,
              );
              final results = searchRes['results'];
              if (results is Map &&
                  results.containsKey('tracks') &&
                  results['tracks'] is List) {
                for (final item in results['tracks']) {
                  if (item is Map) {
                    final t = Track.fromJson(
                      item is Map<String, dynamic>
                          ? item
                          : Map<String, dynamic>.from(item),
                    );
                    if (!_isSameTrack(t.videoId, seed.videoId)) {
                      discovered.add(t);
                    }
                  }
                }
              }
            } catch (_) {}
          }

          AppLogger.instance.logQueue(
            'radio_discovery_fallback_response',
            data: {'trackId': seed.videoId, 'queueLength': discovered.length},
          );
          if (discovered.isNotEmpty &&
              _isSameTrack(state.currentTrack?.videoId, seed.videoId)) {
            final fullQueue = [seed, ...discovered];
            state = state.copyWith(
              queue: fullQueue,
              originalQueue: fullQueue,
              currentIndex: 0,
              queueMode: 'radio',
            );
          }
        })
        .catchError((e) {
          debugPrint('Notice: Discovery queue fetch failed: $e');
          // If getDiscoveryQueue errored (e.g. 404), fallback to related tracks
          _api
              .getRelatedTracks(seed.videoId)
              .then((relatedRes) {
                final sections = (relatedRes['sections'] as List?) ?? [];
                final List<Track> discovered = [];
                for (final section in sections) {
                  if (section is Map &&
                      section.containsKey('items') &&
                      section['items'] is List) {
                    for (final item in section['items']) {
                      if (item is Map) {
                        discovered.add(
                          Track.fromJson(
                            item is Map<String, dynamic>
                                ? item
                                : Map<String, dynamic>.from(item),
                          ),
                        );
                      }
                    }
                  }
                }
                if (discovered.isNotEmpty &&
                    _isSameTrack(state.currentTrack?.videoId, seed.videoId)) {
                  final fullQueue = [seed, ...discovered];
                  state = state.copyWith(
                    queue: fullQueue,
                    originalQueue: fullQueue,
                    currentIndex: 0,
                    queueMode: 'radio',
                  );
                }
              })
              .catchError((_) {});
        });
  }

  Future<void> setQueue(List<Track> playQueue, int startFromIndex) async {
    if (playQueue.isEmpty) return;
    if (startFromIndex < 0 || startFromIndex >= playQueue.length) {
      startFromIndex = 0;
    }
    await playTrack(playQueue[startFromIndex], playQueue, isNewQueue: true);
  }

  /// Start a fresh radio queue seeded by [track].
  Future<void> startRadio(Track track) async {
    await playTrack(track, [track], origin: 'radio', isNewQueue: true);
  }

  Future<void> pause() async {
    if (!state.isPlayerDevice) {
      await sendRemoteCommand('pause');
      return;
    }
    // Invalidate any delayed play request before pausing. This prevents a
    // previous takeover/play request from starting the stream after pause.
    _localPlaybackSuppressed = true;
    _playRequestId++;
    _skipDebounceTimer?.cancel();
    state = state.copyWith(isPlaying: false);
    if (zephyrAudioHandler != null) {
      try {
        await zephyrAudioHandler!.pause();
      } catch (e) {
        debugPrint('ZephyrAudioHandler pause notice: $e');
      }
    } else {
      try {
        await _audioPlayer.pause();
      } catch (e) {
        debugPrint('AudioPlayer pause notice: $e');
      }
    }
    LinuxMprisService().updateState(
      isPlaying: false,
      track: state.currentTrack,
      apiBaseUrl: _api.baseUrl,
    );
    _api
        .updatePlayerState(
          deviceId: state.isPlayerDevice ? state.myDeviceId : null,
          deviceName: state.isPlayerDevice ? state.myDeviceName : null,
          currentTrackId: state.currentTrack?.videoId,
          isPlaying: false,
          positionMs: state.position.inMilliseconds,
        )
        .catchError((_) => <String, dynamic>{});
  }

  void loadTrackPaused(
    Track track,
    List<Track> playQueue, {
    Duration? initialPosition,
  }) {
    _lastTrackId = track.videoId;
    _hasRecordedCurrentTrack = false; // Let it record if they listen again
    _isInitialLoad = true;

    final foundIndex = playQueue.indexWhere((t) => t.videoId == track.videoId);
    final newCurrentIndex = foundIndex != -1 ? foundIndex : state.currentIndex;
    final resolvedPos =
        initialPosition ??
        (state.position > Duration.zero ? state.position : Duration.zero);

    state = state.copyWith(
      isLoading: false,
      currentTrack: track,
      queue: playQueue,
      originalQueue: state.isShuffled ? state.originalQueue : playQueue,
      currentIndex: newCurrentIndex,
      position: resolvedPos,
      duration: track.duration ?? Duration.zero,
      errorMessage: null,
      isPlaying: false,
    );
    try {
      zephyrAudioHandler?.setTrackMediaItem(track, _api.baseUrl);
    } catch (_) {}
    LinuxMprisService().updateState(
      isPlaying: false,
      track: track,
      apiBaseUrl: _api.baseUrl,
    );

    if (track.isDownloaded &&
        (track.coverUrl == null || track.coverUrl!.isEmpty)) {
      _api
          .getTrackMetadata(track.videoId)
          .then((meta) {
            if (state.currentTrack?.videoId == track.videoId &&
                meta.coverUrl != null &&
                meta.coverUrl!.isNotEmpty) {
              final updated = state.currentTrack!.copyWith(
                coverUrl: meta.coverUrl,
                album: meta.album ?? state.currentTrack!.album,
              );
              state = state.copyWith(currentTrack: updated);
            }
          })
          .catchError((_) => null);
    }
  }

  Future<void> resume() async {
    if (!state.isPlayerDevice &&
        (state.activeDeviceId == null || state.activeDeviceId!.isEmpty)) {
      await _claimLocalPlaybackIfUnowned();
    }

    if (!state.isPlayerDevice) {
      await sendRemoteCommand('toggle');
      return;
    }
    if (state.currentTrack != null) {
      _suppressPersistedStartupPlayback = false;
      _localPlaybackSuppressed = false;
      final currentPos = state.position;
      state = state.copyWith(isPlaying: true);
      if (_isInitialLoad) {
        _isInitialLoad = false;
        await playTrack(
          state.currentTrack!,
          state.queue,
          initialPosition: currentPos,
        );
      } else {
        if (zephyrAudioHandler != null) {
          try {
            await zephyrAudioHandler!.play();
          } catch (_) {
            if (state.isPlayerDevice) {
              await playTrack(
                state.currentTrack!,
                state.queue,
                initialPosition: currentPos,
              );
            }
          }
        } else {
          try {
            await _audioPlayer.resume();
          } catch (_) {
            if (state.isPlayerDevice) {
              await playTrack(
                state.currentTrack!,
                state.queue,
                initialPosition: currentPos,
              );
            }
          }
        }
      }
      try {
        LinuxMprisService().updateState(
          isPlaying: true,
          track: state.currentTrack,
          apiBaseUrl: _api.baseUrl,
        );
      } catch (_) {}
      _api
          .updatePlayerState(
            deviceId: state.isPlayerDevice ? state.myDeviceId : null,
            deviceName: state.isPlayerDevice ? state.myDeviceName : null,
            currentTrackId: state.currentTrack?.videoId,
            isPlaying: true,
            positionMs: currentPos.inMilliseconds,
          )
          .catchError((_) => <String, dynamic>{});
    }
  }

  /// Converts linear UI volume slider (0.0 .. 1.0) into natural perceived loudness gain
  /// using a cubic curve. Matches PulseAudio / PipeWire / ALSA cubic attenuation and human hearing.
  static double _volumeToGain(double sliderVolume) {
    final v = sliderVolume.clamp(0.0, 1.0);
    return v * v * v;
  }

  Future<void> _applyVolumeToPlayers(double volume) async {
    final gain = _volumeToGain(volume);
    final tasks = <Future<void>>[];
    final handlerPlayer = zephyrAudioHandler?.player;
    if (handlerPlayer != null) {
      tasks.add(handlerPlayer.setVolume(gain));
    } else {
      tasks.add(_audioPlayer.setVolume(gain));
    }
    try {
      await Future.wait(tasks);
    } catch (_) {}
  }

  Future<void> setVolume(double volume) async {
    final normalized = volume.clamp(0.0, 1.0).toDouble();
    final requestId = ++_volumeRequestId;

    // Update the UI immediately, but serialize native volume writes. During a
    // drag, audioplayers/just_audio can otherwise complete older async writes
    // after the latest value and leave Linux audibly at (for example) 36%.
    state = state.copyWith(
      volume: normalized,
      lastNonMutedVolume: normalized > 0
          ? normalized
          : state.lastNonMutedVolume,
    );

    LinuxMprisService().updateState(
      isPlaying: state.isPlaying,
      track: state.currentTrack,
      apiBaseUrl: _api.baseUrl,
      volume: normalized,
    );

    _volumeApplyChain = _volumeApplyChain.then((_) async {
      if (requestId != _volumeRequestId) return;
      await _applyVolumeToPlayers(normalized);
    });
    final apply = _volumeApplyChain;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble('player_volume', normalized);
    } catch (_) {}
    await apply;
  }

  Future<void> toggleMute() async {
    if (state.volume > 0) {
      state = state.copyWith(lastNonMutedVolume: state.volume);
      await setVolume(0.0);
    } else {
      final restoreVol = state.lastNonMutedVolume > 0
          ? state.lastNonMutedVolume
          : 0.8;
      await setVolume(restoreVol);
    }
  }

  Future<void> togglePlayPause() async {
    if (!state.isPlayerDevice &&
        (state.activeDeviceId == null || state.activeDeviceId!.isEmpty)) {
      await _claimLocalPlaybackIfUnowned();
    }

    if (!state.isPlayerDevice) {
      await sendRemoteCommand('toggle');
      return;
    }
    if (state.isPlaying) {
      await pause();
    } else {
      await resume();
    }
  }

  Future<void> seek(Duration position) async {
    state = state.copyWith(position: position);

    if (!state.isPlayerDevice &&
        (state.activeDeviceId == null || state.activeDeviceId!.isEmpty)) {
      await _claimLocalPlaybackIfUnowned();
    }

    if (!state.isPlayerDevice) {
      await sendRemoteCommand('seek', positionMs: position.inMilliseconds);
      return;
    }

    try {
      LinuxMprisService().updateState(
        isPlaying: state.isPlaying,
        track: state.currentTrack,
        apiBaseUrl: _api.baseUrl,
      );
    } catch (_) {}

    if (zephyrAudioHandler != null) {
      try {
        await zephyrAudioHandler!.seek(position);
      } catch (e) {
        debugPrint('ZephyrAudioHandler seek notice: $e');
      }
    } else {
      try {
        await _audioPlayer.seek(position).timeout(const Duration(seconds: 1));
      } catch (_) {}
    }

    _api
        .updatePlayerState(
          deviceId: state.isPlayerDevice ? state.myDeviceId : null,
          deviceName: state.isPlayerDevice ? state.myDeviceName : null,
          isPlaying: state.isPlaying,
          positionMs: position.inMilliseconds,
        )
        .catchError((_) => <String, dynamic>{});
  }

  Future<void> seekRelative(int seconds) async {
    final currentPos = state.position;
    final maxDur = state.effectiveDuration;
    int newSec = currentPos.inSeconds + seconds;
    if (newSec < 0) newSec = 0;
    if (maxDur > Duration.zero && newSec > maxDur.inSeconds) {
      newSec = maxDur.inSeconds;
    }
    await seek(Duration(seconds: newSec));
  }

  Future<void> adjustVolume(double delta) async {
    double newVol = state.volume + delta;
    if (newVol < 0.0) newVol = 0.0;
    if (newVol > 1.0) newVol = 1.0;
    await setVolume(newVol);
  }

  void _handlePlaybackComplete() {
    final currentId = state.currentTrack?.videoId;
    final now = DateTime.now();
    if (currentId != null && _lastCompletedTrackId == currentId) {
      if (_lastCompletionTime != null &&
          now.difference(_lastCompletionTime!).inMilliseconds < 1500) {
        AppLogger.instance.logPlayer(
          'duplicate_completion_ignored',
          data: {'track': state.currentTrack?.title, 'trackId': currentId},
        );
        return;
      }
    }
    _lastCompletedTrackId = currentId;
    _lastCompletionTime = now;

    AppLogger.instance.logPlayer(
      'track_playback_complete',
      data: {
        'track': state.currentTrack?.title,
        'queueMode': state.queueMode,
        'repeatMode': state.repeatMode,
        'currentIndex': state.currentIndex,
        'queueLength': state.queue.length,
        'userQueueLength': state.userQueue.length,
      },
    );

    if (state.repeatMode == 'one') {
      seek(Duration.zero);
      resume();
    } else {
      playNext();
    }
  }

  Future<void> playNext() {
    return _runTrackTransition('next', _playNextInternal);
  }

  Future<void> playPrevious() {
    return _runTrackTransition('previous', _playPreviousInternal);
  }

  Future<void> _runTrackTransition(
    String action,
    Future<void> Function() operation,
  ) async {
    final inFlight = _trackTransitionInFlight;
    if (inFlight != null) {
      AppLogger.instance.logQueue(
        'transition_ignored_in_flight',
        data: {'action': action, 'activeAction': _trackTransitionAction},
      );
      await inFlight;
      return;
    }

    _trackTransitionAction = action;
    late Future<void> request;
    request = operation();
    _trackTransitionInFlight = request;
    try {
      await request;
    } finally {
      if (identical(_trackTransitionInFlight, request)) {
        _trackTransitionInFlight = null;
        _trackTransitionAction = null;
      }
    }
  }

  Future<void> _playNextInternal() async {
    AppLogger.instance.logQueue(
      'skip_next_triggered',
      data: {
        'currentTrack': state.currentTrack?.title,
        'videoId': state.currentTrack?.videoId,
        'currentIndex': state.currentIndex,
        'queueLength': state.queue.length,
        'userQueueLength': state.userQueue.length,
        'isPlayerDevice': state.isPlayerDevice,
        'queueMode': state.queueMode,
      },
    );

    if (!state.isPlayerDevice &&
        (state.activeDeviceId == null || state.activeDeviceId!.isEmpty)) {
      await _claimLocalPlaybackIfUnowned();
    }

    if (!state.isPlayerDevice) {
      await sendRemoteCommand('next');
      return;
    }

    // Single-track repeat mode restarts track locally
    if (state.repeatMode == 'one' && state.currentTrack != null) {
      AppLogger.instance.logQueue('play_next_repeat_one_restart');
      await seek(Duration.zero);
      await resume();
      return;
    }

    // Owner device: call server-side next (drains user-queue, context/radio queue, auto-refills radio)
    try {
      final beforeTrackId = state.currentTrack?.videoId;
      final nextRes = await _api.nextPlayerTrack();
      if (nextRes != null) {
        AppLogger.instance.logQueue(
          'next_snapshot_received',
          data: {
            'beforeTrackId': beforeTrackId,
            'afterTrackId': nextRes['current_track_id'],
            'updatedAt': nextRes['updated_at'],
            'isPlaying': nextRes['is_playing'],
          },
        );
        await _enqueueServerSnapshot(nextRes, forceTrackTransition: true);
        final httpStatus = (nextRes['_http_status'] as num?)?.toInt();
        if (httpStatus == 202 &&
            nextRes['radio_status']?.toString() == 'pending') {
          _nextWaitingForRadioTrackId = beforeTrackId;
          AppLogger.instance.logQueue(
            'next_waiting_for_radio',
            data: {
              'trackId': beforeTrackId,
              'radioRequestId': nextRes['radio_request_id'],
              'radioGeneration': nextRes['radio_generation'],
            },
          );
          // Do not pause or reset the current track. The ready SSE snapshot
          // will trigger next again once the radio queue exists.
        }
        return;
      }
      AppLogger.instance.logQueue(
        'next_empty_response',
        data: {
          'beforeTrackId': beforeTrackId,
          'repeatMode': state.repeatMode,
          'queueMode': state.queueMode,
        },
      );

      // Repeat-all is a frontend preference. Only an explicit user-selected
      // repeat mode may wrap a context queue; radio remains server-managed.
      if (state.repeatMode == 'all' &&
          state.queueMode == 'context' &&
          state.queue.isNotEmpty) {
        final firstTrack = state.queue.first;
        AppLogger.instance.logQueue(
          'repeat_all_wrapping_context_queue',
          data: {
            'trackId': firstTrack.videoId,
            'queueLength': state.queue.length,
          },
        );
        await playTrack(
          firstTrack,
          state.queue,
          origin: 'queue',
          immediate: true,
        );
        return;
      }
    } catch (e) {
      AppLogger.instance.logQueue(
        'next_request_failed',
        data: {'error': e.toString()},
      );
      debugPrint('Notice: Server player next notice: $e');
    }

    // End of queue reached: stop cleanly
    AppLogger.instance.logQueue('play_next_queue_ended');
    await pause();
    state = state.copyWith(
      isPlaying: false,
      position: Duration.zero,
      isLoading: false,
    );
  }

  Future<void> _playPreviousInternal() async {
    AppLogger.instance.logQueue(
      'skip_previous_triggered',
      data: {
        'currentTrack': state.currentTrack?.title,
        'positionSec': state.position.inSeconds,
        'currentIndex': state.currentIndex,
      },
    );

    // If song is more than 3 seconds in, restart current track
    if (state.position.inSeconds > 3) {
      await seek(Duration.zero);
      return;
    }

    if (!state.isPlayerDevice &&
        (state.activeDeviceId == null || state.activeDeviceId!.isEmpty)) {
      await _claimLocalPlaybackIfUnowned();
    }

    if (!state.isPlayerDevice) {
      await sendRemoteCommand('previous');
      return;
    }

    // Owner device: call server-side previous (pops history, re-inserts current track at head of queue)
    try {
      final beforeTrackId = state.currentTrack?.videoId;
      final prevRes = await _api.previousPlayerTrack();
      if (prevRes != null) {
        AppLogger.instance.logQueue(
          'previous_snapshot_received',
          data: {
            'beforeTrackId': beforeTrackId,
            'afterTrackId': prevRes['current_track_id'],
            'updatedAt': prevRes['updated_at'],
            'isPlaying': prevRes['is_playing'],
          },
        );
        await _enqueueServerSnapshot(prevRes, forceTrackTransition: true);
        return;
      }
      AppLogger.instance.logQueue(
        'previous_empty_response',
        data: {'beforeTrackId': beforeTrackId},
      );
    } catch (e) {
      AppLogger.instance.logQueue(
        'previous_request_failed',
        data: {'error': e.toString()},
      );
      debugPrint('Notice: Server player previous notice: $e');
    }

    // Fallback: If no previous track exists in history, restart current song to 0:00
    await seek(Duration.zero);
  }

  bool _isResolutionModalShowing = false;

  void _triggerResolutionModal(
    dynamic exception,
    Track targetTrack,
    List<Track> queue,
  ) async {
    if (_isResolutionModalShowing) return;

    if (exception is ResolutionRequiredException) {
      final prefs = await SharedPreferences.getInstance();
      final autoSelectEnabled =
          prefs.getBool('auto_select_high_confidence') ?? true;

      if (autoSelectEnabled && exception.candidates.isNotEmpty) {
        final candidates = List<ResolutionCandidate>.from(exception.candidates);
        candidates.sort((a, b) => b.matchScore.compareTo(a.matchScore));
        final top = candidates.first;

        if (top.matchScore >= 85 && top.videoType != 'OMV') {
          try {
            await _api.selectTrackCandidate(
              exception.trackId,
              resolutionId: exception.resolutionId,
              videoId: top.videoId,
            );
            final ctx = rootNavigatorKey.currentContext;
            if (ctx != null && ctx.mounted) {
              ZephyrToast.show(
                ctx,
                '⚡ Auto-matched "${top.title}" (${top.matchScore}% match)',
              );
            }
            clearResolvedCache(exception.trackId);
            await playTrack(targetTrack, queue, immediate: true);
            return;
          } catch (_) {}
        }
      }
    }

    final context = rootNavigatorKey.currentContext;
    if (context == null || !context.mounted) return;

    _isResolutionModalShowing = true;

    if (exception is ResolutionRequiredException) {
      UnresolvedTrackModal.show(
        context,
        trackId: exception.trackId,
        title: exception.title,
        artists: exception.artists,
        initialCandidates: exception.candidates,
        initialResolutionId: exception.resolutionId,
      ).then((selected) async {
        _isResolutionModalShowing = false;
        if (selected == true) {
          _api.clearProxyStreamError(exception.trackId);
          clearResolvedCache(exception.trackId);
          await playTrack(targetTrack, queue, immediate: true);
        }
      });
    } else if (exception is TrackUnavailableException) {
      UnresolvedTrackModal.show(
        context,
        trackId: targetTrack.videoId,
        title: targetTrack.title,
        artists: targetTrack.artists,
      ).then((selected) async {
        _isResolutionModalShowing = false;
        if (selected == true) {
          _api.clearProxyStreamError(targetTrack.videoId);
          clearResolvedCache(targetTrack.videoId);
          await playTrack(targetTrack, queue, immediate: true);
        }
      });
    } else {
      _isResolutionModalShowing = false;
    }
  }

  void toggleShuffle() {
    final currentlyShuffled = state.isShuffled;
    if (state.queue.isEmpty) {
      state = state.copyWith(isShuffled: !currentlyShuffled);
      return;
    }

    List<Track> newQueue;
    int newIndex;

    if (currentlyShuffled) {
      // Revert to original order
      final currentTrack = state.currentTrack;
      newIndex = state.originalQueue.indexWhere(
        (t) => _isSameTrack(t.videoId, currentTrack?.videoId),
      );
      if (newIndex == -1) newIndex = 0;
      newQueue = List<Track>.from(
        state.originalQueue.isNotEmpty ? state.originalQueue : state.queue,
      );
      state = state.copyWith(
        isShuffled: false,
        queue: newQueue,
        currentIndex: newIndex,
      );
    } else {
      // Shuffle the queue (but keep current track first)
      final originalList = List<Track>.from(
        state.originalQueue.isNotEmpty ? state.originalQueue : state.queue,
      );
      final currentTrack = state.currentTrack;

      if (currentTrack != null) {
        originalList.removeWhere(
          (t) => _isSameTrack(t.videoId, currentTrack.videoId),
        );
      }
      originalList.shuffle();
      if (currentTrack != null) {
        originalList.insert(0, currentTrack);
      }

      newQueue = originalList;
      newIndex = 0;
      state = state.copyWith(
        isShuffled: true,
        originalQueue: state.originalQueue.isNotEmpty
            ? state.originalQueue
            : state.queue,
        queue: newQueue,
        currentIndex: 0,
      );
    }

    _api
        .updatePlayerState(
          deviceId: state.isPlayerDevice ? state.myDeviceId : null,
          deviceName: state.isPlayerDevice ? state.myDeviceName : null,
          queue: newQueue.map((t) => t.toJson()).toList(),
        )
        .catchError((_) => <String, dynamic>{});
  }

  void toggleQueueMode() {
    final nextMode = switch (state.repeatMode) {
      'off' => 'all',
      'all' => 'one',
      _ => 'off',
    };
    state = state.copyWith(repeatMode: nextMode);
  }

  void addToQueue(Track track) {
    final updatedUserQueue = List<Track>.from(state.userQueue)..add(track);
    if (state.currentTrack == null) {
      playTrack(track, [track]);
    } else {
      state = state.copyWith(userQueue: updatedUserQueue);
      unawaited(_api.addUserQueue(track).catchError((_) {}));
    }
  }

  void reorderUserQueue(int oldIndex, int newIndex) {
    if (oldIndex < newIndex) {
      newIndex -= 1;
    }
    final list = List<Track>.from(state.userQueue);
    if (oldIndex >= 0 &&
        oldIndex < list.length &&
        newIndex >= 0 &&
        newIndex <= list.length) {
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
      if (list.isEmpty) {
        unawaited(_api.clearUserQueue().catchError((_) {}));
      }
    }
  }

  void clearUserQueue() {
    state = state.copyWith(userQueue: const []);
    unawaited(_api.clearUserQueue().catchError((_) {}));
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
    if (actualOldIndex >= 0 &&
        actualOldIndex < list.length &&
        actualNewIndex >= 0 &&
        actualNewIndex <= list.length) {
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

final playerProvider = NotifierProvider<PlayerNotifier, ZephyrPlayerState>(
  PlayerNotifier.new,
);
