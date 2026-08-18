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
  final String queueMode; // 'normal', 'repeat_all', 'repeat_one'
  final bool isShuffled;
  final String? errorMessage;
  final bool isLoading;
  final double volume;
  final double lastNonMutedVolume;
  final int historyCount;
  final String? activeDeviceId;
  final String? activeDeviceName;
  final bool isPlayerDevice;
  final String myDeviceId;
  final String myDeviceName;
  final List<Map<String, dynamic>> connectedDevices;

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
    this.historyCount = 0,
    this.activeDeviceId,
    this.activeDeviceName,
    this.isPlayerDevice = false,
    this.myDeviceId = '',
    this.myDeviceName = '',
    this.connectedDevices = const [],
  });

  bool get canGoPrevious => historyCount > 0 || currentIndex > 0;

  Duration get effectiveDuration {
    if (duration > Duration.zero) return duration;
    if (currentTrack?.duration != null &&
        currentTrack!.duration! > Duration.zero) {
      return currentTrack!.duration!;
    }
    return Duration.zero;
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
  int _ownershipRecoveryGeneration = 0;
  bool _ownershipReleased = false;
  bool _localPlaybackSuppressed = true;
  bool _hasLocalAudioSource = false;
  String? _pendingRemoteTrackId;
  String? _ownerTrackStartId;
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
        Duration(milliseconds: 500),
        Duration(seconds: 1),
        Duration(seconds: 2),
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
            queue: state.queue
                .map(
                  (track) => _isSameTrack(track.videoId, trackId)
                      ? _mergeTrackMetadata(track, fullMeta)
                      : track,
                )
                .toList(),
          );
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

  Future<void> _enqueueServerSnapshot(
    Map<String, dynamic> snapshot, {
    bool isInitial = false,
    bool suppressOwnerPlayback = false,
  }) {
    final next = _snapshotChain.then((_) async {
      try {
        await _applyServerStateSnapshot(
          snapshot,
          isInitial: isInitial,
          suppressOwnerPlayback: suppressOwnerPlayback,
        );
      } catch (e, stackTrace) {
        debugPrint('Player state snapshot notice: $e\n$stackTrace');
      }
    });
    _snapshotChain = next;
    return next;
  }

  void _cancelOwnershipRecovery() {
    _ownershipRecoveryGeneration++;
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

    final liveDevices = devices
        .where((device) => device['is_alive'] == true)
        .toList();
    final isCurrentDeviceLive = liveDevices.any(
      (device) => device['device_id']?.toString() == state.myDeviceId,
    );
    if (!isCurrentDeviceLive || liveDevices.isEmpty) return;

    final delayMs = liveDevices.length == 1 ? 0 : math.Random().nextInt(1501);
    final generation = ++_ownershipRecoveryGeneration;
    debugPrint(
      '[Playback recovery] ownership released; live devices='
      '${_describeStartupDevices(liveDevices)}; election delay=${delayMs}ms',
    );

    _ownershipRecoveryTimer = Timer(Duration(milliseconds: delayMs), () async {
      _ownershipRecoveryTimer = null;
      if (generation != _ownershipRecoveryGeneration ||
          !_ownershipReleased ||
          state.isPlayerDevice ||
          _hasLiveOwner(state.connectedDevices)) {
        return;
      }

      debugPrint(
        '[Playback recovery] attempting non-forced takeover as '
        '${liveDevices.length == 1 ? 'sole' : 'randomly elected'} candidate',
      );
      final claimed = await takeoverPlayback(
        force: false,
        showConflictDialog: false,
      );
      if (claimed) {
        _ownershipReleased = false;
        _cancelOwnershipRecovery();
        debugPrint('[Playback recovery] takeover succeeded');
      } else {
        debugPrint('[Playback recovery] takeover lost election or failed');
      }
    });
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

    try {
      final s = await _api.getPlayerState();
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

  Future<void> _applyServerStateSnapshot(
    Map<String, dynamic> snapshot, {
    bool isInitial = false,
    bool suppressOwnerPlayback = false,
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

          // Post-download: fetch rich metadata (lyrics, album art, local path) now that DB row exists
          if (isCompleted) {
            _api
                .getTrackMetadata(trackId)
                .then((fullMeta) {
                  if (state.currentTrack != null &&
                      _isSameTrack(state.currentTrack!.videoId, trackId)) {
                    state = state.copyWith(
                      currentTrack: state.currentTrack!.copyWith(
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
                        albumId:
                            fullMeta.albumId ?? state.currentTrack!.albumId,
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
                    _api.notifyLyricsReady(state.currentTrack!.videoId);
                    _api.notifyLyricsReady(trackId);
                  }
                })
                .catchError((e) {
                  debugPrint(
                    'Error enriching track metadata after download: $e',
                  );
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

    // Only initial HTTP hydration is startup state. The first SSE state may
    // be an explicit play command and must not be swallowed as startup.
    final bool isStartup = isInitial;
    if (isInitial) {
      // Initial HTTP/SSE hydration is applied paused below.
    }

    final String? activeId = snapshot['device_id']?.toString();
    final String? activeName = snapshot['device_name']?.toString();
    // The backend snapshot is authoritative. Do not infer ownership from
    // the number of connected devices: a device can be alone in the SSE list
    // while the backend still has a live owner session.
    final bool isPlayer =
        state.myDeviceId.isNotEmpty &&
        activeId != null &&
        activeId == state.myDeviceId;
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
      if (serverQueueTracks != null && serverQueueTracks.isNotEmpty) {
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
      // Do not let an older SSE snapshot roll the REMOTE back to the track
      // that was playing before its latest click. The server will publish a
      // matching snapshot for the pending remote request shortly.
      final pendingTrackId = _pendingRemoteTrackId;
      if (pendingTrackId != null &&
          curTrackId != null &&
          _isSameTrack(curTrackId, pendingTrackId)) {
        _pendingRemoteTrackId = null;
      }

      // Demote before awaiting the local stop. Audio engines can emit final
      // callbacks during stop; they must not overwrite this server snapshot.
      final wasLocalOwner = state.isPlayerDevice;
      if (wasLocalOwner) {
        _playRequestId++;
        _playbackGeneration++;
        _ownerTrackStartId = null;
      }
      state = state.copyWith(
        activeDeviceId: activeId,
        activeDeviceName: activeName,
        isPlayerDevice: false,
        isPlaying: false,
        position: Duration(milliseconds: posMs),
      );

      if (wasLocalOwner) {
        await _stopLocalPlayback();
      }

      if (_ownershipReleased) {
        unawaited(_recoverOwnershipAfterRelease(state.connectedDevices));
      }

      // A stale remote-click guard must not suppress ownership demotion or
      // stopping local audio. It only controls whether the mirrored track is
      // updated below.
      if (pendingTrackId != null &&
          (curTrackId == null || !_isSameTrack(curTrackId, pendingTrackId))) {
        return;
      }

      Track? currentTrack = state.currentTrack;
      if (curTrackId != null &&
          curTrackId.isNotEmpty &&
          (currentTrack == null ||
              !_isSameTrack(currentTrack.videoId, curTrackId))) {
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
      if (serverQueueTracks != null && serverQueueTracks.isNotEmpty) {
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
      state = state.copyWith(
        activeDeviceId: activeId,
        activeDeviceName: activeName,
        isPlayerDevice: false,
        historyCount: hCount,
        currentTrack: currentTrack,
        queue: queueToUse,
        originalQueue: state.isShuffled ? state.originalQueue : queueToUse,
        isPlaying: serverPlaying,
        isLoading: false,
        position: Duration(milliseconds: posMs),
        duration: remoteTrackChanged ? Duration.zero : null,
      );

      // Always hydrate a remote track change. The owner may have created the
      // DB row moments earlier through /stream.
      if (remoteTrackChanged) {
        unawaited(_hydrateTrackMetadata(currentTrack.videoId));
      }
      return;
    }

    // Update queue if new server queue tracks are available
    if (serverQueueTracks != null && serverQueueTracks.isNotEmpty) {
      final curTrack = state.currentTrack;
      final fullQueue =
          (curTrack != null &&
              !serverQueueTracks.any(
                (t) => _isSameTrack(t.videoId, curTrack.videoId),
              ))
          ? [curTrack, ...serverQueueTracks]
          : serverQueueTracks;
      state = state.copyWith(
        queue: fullQueue,
        originalQueue: state.isShuffled ? state.originalQueue : fullQueue,
      );
    }

    // 3. Owner Player Device: execute pushed remote commands on local audio player
    state = state.copyWith(
      activeDeviceId: activeId,
      activeDeviceName: activeName,
      isPlayerDevice: true,
      historyCount: hCount,
      // A marked connect/reconnect snapshot re-anchors the UI position. On
      // the first startup snapshot, keep playback paused by contract; on a
      // later reconnect, reflect the server's playing state without issuing
      // local play/pause/seek commands.
      position: suppressOwnerPlayback
          ? Duration(milliseconds: posMs)
          : state.position,
      isPlaying: suppressOwnerPlayback && !isStartup
          ? serverPlaying
          : state.isPlaying,
    );

    // A. Track changed via remote command
    if (curTrackId != null && curTrackId.isNotEmpty) {
      final bool trackMismatch = !_isSameTrack(
        state.currentTrack?.videoId,
        curTrackId,
      );

      if (trackMismatch) {
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

        // The takeover response and its SSE broadcast describe the same
        // playback intent. If takeoverPlayback already owns startup for this
        // track, let that single request finish instead of opening another
        // stream from the SSE path.
        if (_ownerTrackStartId == curTrackId) return;

        final shouldStartOwner =
            serverPlaying &&
            !isInitial &&
            !suppressPersistedStartupPlayback &&
            (!suppressOwnerPlayback || !_hasLocalAudioSource);
        if (shouldStartOwner) {
          // Do not block the SSE snapshot queue while the stream is resolving
          // or buffering. A pause/seek/takeover event must be able to cancel
          // this request immediately. A reconnect snapshot also starts the
          // stream when this OWNER has no local audio source.
          if (_ownerTrackStartId == curTrackId && state.isLoading) return;
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
        (serverPlayChanged || !_hasLocalAudioSource);
    if (!suppressOwnerPlayback && (serverPauseChanged || shouldHandlePlay)) {
      _lastKnownServerPlaying = serverPlaying;
      if (serverPlaying) {
        if (_hasLocalAudioSource) {
          _localPlaybackSuppressed = false;
          try {
            await zephyrAudioHandler?.play();
          } catch (_) {}
          await _audioPlayer.resume();
          state = state.copyWith(isPlaying: true);
        } else if (state.currentTrack != null &&
            _ownerTrackStartId != state.currentTrack!.videoId) {
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

    // C. Seek position changed via remote command. The backend's marked SSE
    // connect/reconnect snapshot is an anchor, not a seek command; update the
    // mirrored state above but never move or start a local audio engine here.
    final diffMs = (posMs - state.position.inMilliseconds).abs();
    if (!suppressOwnerPlayback && diffMs > 3000) {
      final newPos = Duration(milliseconds: posMs);
      try {
        if (zephyrAudioHandler != null) {
          await zephyrAudioHandler!.seek(newPos);
        }
      } catch (_) {}
      try {
        await _audioPlayer.seek(newPos);
      } catch (_) {}
      state = state.copyWith(position: newPos);
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
  }) async {
    try {
      if (action == 'next') {
        await _api.nextPlayerTrack();
        return;
      }
      if (action == 'previous') {
        await _api.previousPlayerTrack();
        return;
      }

      String validAction = action;
      if (action == 'resume') {
        validAction = 'toggle';
      }

      await _api.sendPlayerCommand(
        action: validAction,
        currentTrackId: trackId,
        positionMs: positionMs,
        origin: origin,
      );
    } catch (e) {
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

      final currentPos = Duration(
        milliseconds:
            (takeoverSnapshot['position_ms'] as num?)?.toInt() ??
            state.position.inMilliseconds,
      );
      final serverPlaying = takeoverSnapshot['is_playing'] == true;
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
    } catch (_) {}

    ref.onDispose(() {
      _sseSub?.cancel();
      _ownershipRecoveryTimer?.cancel();
      _skipDebounceTimer?.cancel();
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
        final volume = savedVolume.clamp(0.0, 1.0).toDouble();
        state = state.copyWith(volume: volume);
        await _applyVolumeToPlayers(volume);
      }
    } catch (_) {}
  }

  void _initStreams() {
    DateTime? lastHeartbeatTime;
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

      final now = DateTime.now();
      if (state.isPlaying &&
          state.isPlayerDevice &&
          (lastHeartbeatTime == null ||
              now.difference(lastHeartbeatTime!).inSeconds >= 2)) {
        lastHeartbeatTime = now;
        _api
            .updatePlayerState(
              deviceId: state.myDeviceId,
              deviceName: state.myDeviceName,
              positionMs: pos.inMilliseconds,
              isPlaying: true,
            )
            .catchError((error) {
              if (error is PlayerActiveException) {
                // A heartbeat conflict is an ownership loss. Changing the
                // role alone is unsafe: the local stream may continue playing.
                final wasLocalOwner = state.isPlayerDevice;
                state = state.copyWith(
                  isPlayerDevice: false,
                  activeDeviceId: error.ownerDeviceId,
                  activeDeviceName: error.ownerDeviceName,
                  isPlaying: false,
                );
                if (wasLocalOwner) {
                  _stopLocalPlayback();
                }
              }
              return <String, dynamic>{};
            });
      }

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
          ref.read(libraryProvider.notifier).recordListen(trackToRecord.videoId, trackToRecord);
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

    _positionSub = _audioPlayer.onPositionChanged.listen(
      updatePos,
      onError: (_) {},
    );
    _durationSub = _audioPlayer.onDurationChanged.listen(
      updateDur,
      onError: (_) {},
    );

    Timer.periodic(const Duration(seconds: 1), (_) {
      if (!state.isPlayerDevice &&
          state.isPlaying &&
          state.currentTrack != null) {
        final newSec = state.position.inSeconds + 1;
        final maxSec = state.effectiveDuration.inSeconds;
        if (maxSec == 0 || newSec <= maxSec) {
          state = state.copyWith(position: Duration(seconds: newSec));
        }
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
        if (ps.processingState == ProcessingState.completed) {
          _handlePlaybackComplete();
        }
        LinuxMprisService().updateState(
          isPlaying: isPlaying,
          track: state.currentTrack,
          apiBaseUrl: _api.baseUrl,
        );
      }, onError: (_) {});
    } catch (_) {}

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
      _handlePlaybackComplete();
    }, onError: (_) {});

    _audioPlayer.onLog.listen((_) {}, onError: (_) {});
  }

  Future<void> playTrack(
    Track track,
    List<Track> playQueue, {
    bool immediate = false,
    bool isNewQueue = false,
    String? origin,
    Duration? initialPosition,
  }) async {
    if (!state.isPlayerDevice &&
        (state.activeDeviceId == null || state.activeDeviceId!.isEmpty)) {
      await _claimLocalPlaybackIfUnowned();
    }

    if (!state.isPlayerDevice) {
      // Remote control mode: dispatch play command to server for active player to execute
      final List<Track> fullToSend = playQueue.isNotEmpty ? playQueue : [track];

      try {
        // Render the requested track immediately, but never inherit the
        // previous owner's position. The pending ID prevents an older SSE
        // snapshot from putting the old track/position back into this UI.
        _pendingRemoteTrackId = track.videoId;
        state = state.copyWith(
          currentTrack: track,
          queue: fullToSend,
          originalQueue: state.isShuffled ? state.originalQueue : fullToSend,
          currentIndex: 0,
          position: Duration.zero,
          duration: track.duration ?? Duration.zero,
          isPlaying: true,
          isLoading: true,
          errorMessage: null,
        );

        // A remote device sends only the control intent. The backend
        // broadcasts it to the OWNER; only the OWNER calls /tracks/stream.
        // Do not precede this with PUT /player/state: that is an ownership or
        // field write, not an audio request, and creates a contradictory
        // paused SSE event.
        final response = await _api.sendPlayerCommand(
          action: 'play_track',
          currentTrackId: track.videoId,
          origin: origin == 'queue' || origin == 'context' ? origin : null,
        );
        // The command response is authoritative for the click. Apply its
        // metadata immediately; stale queued SSE states are ignored while
        // pending.
        await _enqueueServerSnapshot(response);
      } catch (e) {
        _pendingRemoteTrackId = null;
        debugPrint('Notice: Remote play track update: $e');
      }
      return;
    }

    final requestId = ++_playRequestId;
    final playbackGeneration = ++_playbackGeneration;
    _skipDebounceTimer?.cancel();
    _localPlaybackSuppressed = false;
    _hasLocalAudioSource = false;

    final prevState = state;

    // Immediately stop previous audio so the user experiences an instant pause while waiting for new track download
    try {
      await zephyrAudioHandler?.stop();
    } catch (_) {}
    try {
      await _audioPlayer.stop();
    } catch (_) {}

    final initialDur =
        (track.duration != null && track.duration! > Duration.zero)
        ? track.duration!
        : Duration.zero;

    List<Track> queueToSet = playQueue;
    if (isNewQueue) {
      // Starting a new playlist / album / context: position clicked track at top with remaining tracks
      final foundIdx = playQueue.indexWhere((t) => t.videoId == track.videoId);
      if (foundIdx != -1) {
        final remaining = playQueue.sublist(foundIdx + 1);
        queueToSet = [track, ...remaining];
      }
    } else if (origin == 'context' && state.queue.isNotEmpty) {
      // Play-and-remove semantics for same-playlist clicks: keep playlist queue and remove clicked track from upcoming
      final remaining = List<Track>.from(state.queue)
        ..removeWhere((t) => t.videoId == track.videoId);
      queueToSet = [track, ...remaining];
    } else if (origin == 'queue' && state.queue.isNotEmpty) {
      // Skip-to semantics for queue view clicks: drop preceding tracks
      final foundIdx = state.queue.indexWhere(
        (t) => t.videoId == track.videoId,
      );
      queueToSet = foundIdx != -1 ? state.queue.sublist(foundIdx) : state.queue;
    }

    // Immediately update UI metadata so skipping responds instantly on screen in loading/paused state
    state = state.copyWith(
      isLoading: true,
      isPlaying: false,
      currentTrack: track,
      queue: queueToSet,
      originalQueue: state.isShuffled ? state.originalQueue : queueToSet,
      currentIndex: 0,
      position: initialPosition ?? Duration.zero,
      duration: initialDur,
      errorMessage: null,
    );

    Future<void> executePlay() async {
      if (!_canContinuePlayback(requestId, playbackGeneration)) return;

      Track finalTrack = track;

      bool success = false;
      Object? lastError;

      final localAudioPath = OfflineStorageService().getAudioFilePath(finalTrack.videoId);
      final bool isLocal = localAudioPath != null;

      try {
        final streamUrl = isLocal ? '' : await _api.getStreamProxyUrl(finalTrack.videoId);
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

        // Sync player state with server-side queue & radio discovery engine
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
              (remaining.isNotEmpty || playQueue.length > 1);
          final String mode = isContextQueue ? 'context' : 'radio';

          if (isContextQueue) {
            final queueMaps = remaining
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
              isPlaying: true,
              origin: origin ?? 'context',
            );
            final int hCount =
                (res['history_count'] as num?)?.toInt() ?? state.historyCount;
            if (res.containsKey('queue') && res['queue'] is List) {
              final List serverQueue = res['queue'];
              final List<Track> updatedQueue = serverQueue
                  .map((e) => Track.fromJson(e))
                  .toList();
              if (updatedQueue.isNotEmpty) {
                final fullQueue = [finalTrack, ...updatedQueue];
                state = state.copyWith(
                  queue: fullQueue,
                  originalQueue: state.isShuffled
                      ? state.originalQueue
                      : fullQueue,
                  currentIndex: 0,
                  historyCount: hCount,
                );
              } else {
                state = state.copyWith(historyCount: hCount);
              }
            } else {
              state = state.copyWith(historyCount: hCount);
            }
          } else {
            final res = await _api.updatePlayerState(
              deviceId: state.isPlayerDevice ? state.myDeviceId : null,
              deviceName: state.isPlayerDevice ? state.myDeviceName : null,
              currentTrackId: finalTrack.videoId,
              queueMode: 'radio',
              isPlaying: true,
              origin: origin == 'queue' ? 'queue' : 'context',
            );
            final int hCount =
                (res['history_count'] as num?)?.toInt() ?? state.historyCount;
            if (res.containsKey('queue') && res['queue'] is List) {
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
                  historyCount: hCount,
                );
              } else {
                state = state.copyWith(historyCount: hCount);
              }
            } else {
              state = state.copyWith(historyCount: hCount);
            }
          }
        } catch (e) {
          debugPrint('Notice: Server player state sync: $e');
        }
      }
    }

    if (immediate) {
      await executePlay();
    } else {
      await Future.delayed(const Duration(milliseconds: 200));
      if (_playRequestId == requestId) {
        await executePlay();
      }
    }
  }

  Future<void> setQueue(List<Track> playQueue, int startFromIndex) async {
    if (playQueue.isEmpty) return;
    if (startFromIndex < 0 || startFromIndex >= playQueue.length) {
      startFromIndex = 0;
    }
    await playTrack(playQueue[startFromIndex], playQueue, isNewQueue: true);
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
    try {
      await zephyrAudioHandler?.pause();
    } catch (_) {}
    await _audioPlayer.pause();
    LinuxMprisService().updateState(
      isPlaying: false,
      track: state.currentTrack,
      apiBaseUrl: _api.baseUrl,
    );
    _api
        .updatePlayerState(
          deviceId: state.isPlayerDevice ? state.myDeviceId : null,
          deviceName: state.isPlayerDevice ? state.myDeviceName : null,
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
      state = state.copyWith(isPlaying: true);
      if (_isInitialLoad) {
        _isInitialLoad = false;
        final resumePos = state.position;
        await playTrack(state.currentTrack!, state.queue);
        if (resumePos > Duration.zero) {
          await seek(resumePos);
        }
      } else {
        try {
          await zephyrAudioHandler?.play();
        } catch (_) {}
        try {
          await _audioPlayer.resume();
        } catch (_) {
          // Only retry stream startup when the device is still the OWNER.
          if (state.isPlayerDevice) {
            await playTrack(state.currentTrack!, state.queue);
          }
        }
      }
      LinuxMprisService().updateState(
        isPlaying: true,
        track: state.currentTrack,
        apiBaseUrl: _api.baseUrl,
      );
      _api
          .updatePlayerState(
            deviceId: state.isPlayerDevice ? state.myDeviceId : null,
            deviceName: state.isPlayerDevice ? state.myDeviceName : null,
            isPlaying: true,
            positionMs: state.position.inMilliseconds,
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
    }
    tasks.add(_audioPlayer.setVolume(gain));
    await Future.wait(tasks);
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
    if (!state.isPlayerDevice) {
      await sendRemoteCommand('seek', positionMs: position.inMilliseconds);
      return;
    }
    try {
      if (zephyrAudioHandler != null) {
        await zephyrAudioHandler!.seek(position);
      }
    } catch (e) {
      debugPrint('ZephyrAudioHandler seek notice: $e');
    }
    try {
      await _audioPlayer.seek(position).timeout(const Duration(seconds: 1));
    } catch (_) {}
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
    if (state.queueMode == 'repeat_one') {
      seek(Duration.zero);
      resume();
    } else {
      playNext();
    }
  }

  Future<void> playNext() async {
    if (!state.isPlayerDevice &&
        (state.activeDeviceId == null || state.activeDeviceId!.isEmpty)) {
      await _claimLocalPlaybackIfUnowned();
    }

    if (!state.isPlayerDevice) {
      await _api.nextPlayerTrack();
      return;
    }

    if (state.userQueue.isNotEmpty) {
      final nextTrack = state.userQueue.first;
      final updatedUserQueue = state.userQueue.sublist(1);
      state = state.copyWith(userQueue: updatedUserQueue);
      await playTrack(nextTrack, state.queue);
      return;
    }

    if (state.queueMode == 'repeat_one' && state.currentTrack != null) {
      seek(Duration.zero);
      resume();
      return;
    }

    try {
      final nextRes = await _api.nextPlayerTrack();
      if (nextRes != null) {
        final String? nextId = nextRes['current_track_id']?.toString();
        if (nextId != null && nextId.isNotEmpty) {
          List<Track> serverQueue = [];
          if (nextRes.containsKey('queue') && nextRes['queue'] is List) {
            serverQueue = (nextRes['queue'] as List)
                .map((e) => Track.fromJson(e))
                .toList();
          }

          Track? nextTrack;
          final foundIndex = state.queue.indexWhere(
            (t) => _isSameTrack(t.videoId, nextId),
          );
          if (foundIndex != -1) {
            nextTrack = state.queue[foundIndex];
          }

          if (nextTrack == null && serverQueue.isNotEmpty) {
            final sFound = serverQueue.indexWhere(
              (t) => _isSameTrack(t.videoId, nextId),
            );
            if (sFound != -1) {
              nextTrack = serverQueue[sFound];
            }
          }

          if (nextTrack == null) {
            nextTrack = Track(
              videoId: nextId,
              title: 'Loading...',
              artists: const [],
              downloadStatus: 'not_in_db',
              isDownloaded: false,
            );
          }

          final newQueue = serverQueue.isNotEmpty
              ? [nextTrack, ...serverQueue]
              : state.queue;
          await playTrack(nextTrack, newQueue);

          // If stub, eagerly fetch metadata — track may already be downloaded
          if (nextTrack.artists.isEmpty) {
            final trackId = nextTrack.videoId;
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
          return;
        }
      }
    } catch (e) {
      debugPrint('Notice: server player next fallback to local queue: $e');
    }

    if (state.queue.isEmpty) return;

    int nextIndex = state.currentIndex + 1;
    if (nextIndex >= state.queue.length) {
      if (state.queueMode == 'repeat_all') {
        nextIndex = 0;
      } else {
        await pause();
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
    // If song is more than 3 seconds in, restart current track
    if (state.position.inSeconds > 3) {
      seek(Duration.zero);
      return;
    }

    if (!state.isPlayerDevice &&
        (state.activeDeviceId == null || state.activeDeviceId!.isEmpty)) {
      await _claimLocalPlaybackIfUnowned();
    }

    if (!state.isPlayerDevice) {
      await _api.previousPlayerTrack();
      return;
    }

    try {
      final prevRes = await _api.previousPlayerTrack();
      if (prevRes != null) {
        final String? prevId = prevRes['current_track_id']?.toString();
        final int posMs = (prevRes['position_ms'] as num?)?.toInt() ?? 0;

        if (prevId != null && prevId.isNotEmpty) {
          List<Track> serverQueue = [];
          if (prevRes.containsKey('queue') && prevRes['queue'] is List) {
            final List rawQueue = prevRes['queue'];
            for (final item in rawQueue) {
              if (item is Map<String, dynamic>) {
                serverQueue.add(Track.fromJson(item));
              } else if (item is Map) {
                serverQueue.add(
                  Track.fromJson(Map<String, dynamic>.from(item)),
                );
              }
            }
          }

          Track? prevTrack;
          final foundIndex = state.queue.indexWhere(
            (t) => _isSameTrack(t.videoId, prevId),
          );
          if (foundIndex != -1) {
            prevTrack = state.queue[foundIndex];
          }

          if (prevTrack == null && serverQueue.isNotEmpty) {
            final sFound = serverQueue.indexWhere(
              (t) => _isSameTrack(t.videoId, prevId),
            );
            if (sFound != -1) {
              prevTrack = serverQueue[sFound];
            }
          }

          prevTrack ??= Track(
            videoId: prevId,
            title: 'Loading...',
            artists: const [],
            downloadStatus: 'not_in_db',
            isDownloaded: false,
          );

          final newQueue = serverQueue.isNotEmpty
              ? [prevTrack, ...serverQueue]
              : state.queue;
          await playTrack(prevTrack, newQueue);
          if (posMs > 0) {
            await seek(Duration(milliseconds: posMs));
          }

          // History tracks are always downloaded — eagerly enrich metadata
          final trackId = prevTrack.videoId;
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
          return;
        }
      }
    } catch (e) {
      debugPrint('Notice: Server player previous fallback to local queue: $e');
    }

    if (state.queue.isEmpty) return;

    int prevIndex = state.currentIndex - 1;
    if (prevIndex < 0) {
      if (state.queueMode == 'repeat_all') {
        prevIndex = state.queue.length - 1;
      } else {
        seek(Duration.zero);
        return;
      }
    }

    await playTrack(state.queue[prevIndex], state.queue);
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
    if (state.queue.isEmpty) return;

    if (currentlyShuffled) {
      // Revert to original order
      final currentTrack = state.currentTrack;
      final newIndex = state.originalQueue.indexWhere(
        (t) => t.videoId == currentTrack?.videoId,
      );
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
