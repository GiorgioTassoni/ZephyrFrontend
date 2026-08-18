import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:dbus/dbus.dart';
import '../models/models.dart';

class ZephyrMprisPlayer extends DBusObject {
  VoidCallback? onPlayPause;
  VoidCallback? onNext;
  VoidCallback? onPrevious;
  ValueChanged<double>? onSetVolume;

  String _playbackStatus = 'Paused';
  double _volume = 1.0;
  Map<String, DBusValue> _metadata = {};

  ZephyrMprisPlayer() : super(DBusObjectPath('/org/mpris/MediaPlayer2'));

  void updateState({
    required bool isPlaying,
    required Track? track,
    required String apiBaseUrl,
    double? volume,
  }) {
    _playbackStatus = isPlaying ? 'Playing' : 'Paused';
    if (volume != null) {
      _volume = volume.clamp(0.0, 1.0);
    }
    if (track != null) {
      String art = track.coverUrl ?? '';
      if (art.isNotEmpty && art.startsWith('/')) {
        art = '$apiBaseUrl$art';
      }

      _metadata = {
        'mpris:trackid': DBusObjectPath('/org/mpris/MediaPlayer2/Track/${track.videoId}'),
        'mpris:length': DBusInt64(track.duration?.inMicroseconds ?? 0),
        'mpris:artUrl': DBusString(art),
        'xesam:title': DBusString(track.title),
        'xesam:artist': DBusArray.string(track.artists),
        'xesam:album': DBusString(track.album ?? 'Zephyr'),
      };
    } else {
      _metadata = {};
    }

    emitPropertiesChanged(
      'org.mpris.MediaPlayer2.Player',
      changedProperties: {
        'PlaybackStatus': DBusString(_playbackStatus),
        'Metadata': DBusDict.stringVariant(_metadata),
        'Volume': DBusDouble(_volume),
        'CanControl': const DBusBoolean(true),
        'CanPlay': const DBusBoolean(true),
        'CanPause': const DBusBoolean(true),
        'CanGoNext': const DBusBoolean(true),
        'CanGoPrevious': const DBusBoolean(true),
      },
    );
  }

  @override
  List<DBusIntrospectInterface> introspect() {
    return [
      DBusIntrospectInterface('org.mpris.MediaPlayer2', methods: [
        DBusIntrospectMethod('Raise'),
        DBusIntrospectMethod('Quit'),
      ], properties: [
        DBusIntrospectProperty('CanQuit', DBusSignature('b'), access: DBusPropertyAccess.read),
        DBusIntrospectProperty('CanRaise', DBusSignature('b'), access: DBusPropertyAccess.read),
        DBusIntrospectProperty('HasTrackList', DBusSignature('b'), access: DBusPropertyAccess.read),
        DBusIntrospectProperty('Identity', DBusSignature('s'), access: DBusPropertyAccess.read),
        DBusIntrospectProperty('DesktopEntry', DBusSignature('s'), access: DBusPropertyAccess.read),
      ]),
      DBusIntrospectInterface('org.mpris.MediaPlayer2.Player', methods: [
        DBusIntrospectMethod('Next'),
        DBusIntrospectMethod('Previous'),
        DBusIntrospectMethod('Pause'),
        DBusIntrospectMethod('PlayPause'),
        DBusIntrospectMethod('Stop'),
        DBusIntrospectMethod('Play'),
      ], properties: [
        DBusIntrospectProperty('PlaybackStatus', DBusSignature('s'), access: DBusPropertyAccess.read),
        DBusIntrospectProperty('Metadata', DBusSignature('a{sv}'), access: DBusPropertyAccess.read),
        DBusIntrospectProperty('CanControl', DBusSignature('b'), access: DBusPropertyAccess.read),
        DBusIntrospectProperty('CanGoNext', DBusSignature('b'), access: DBusPropertyAccess.read),
        DBusIntrospectProperty('CanGoPrevious', DBusSignature('b'), access: DBusPropertyAccess.read),
        DBusIntrospectProperty('CanPlay', DBusSignature('b'), access: DBusPropertyAccess.read),
        DBusIntrospectProperty('CanPause', DBusSignature('b'), access: DBusPropertyAccess.read),
        DBusIntrospectProperty('Volume', DBusSignature('d'), access: DBusPropertyAccess.readwrite),
      ]),
    ];
  }

  @override
  Future<DBusMethodResponse> handleMethodCall(DBusMethodCall methodCall) async {
    final name = methodCall.name;

    if (name == 'PlayPause' || name == 'Play' || name == 'Pause' || name == 'TogglePlayPause') {
      onPlayPause?.call();
      return DBusMethodSuccessResponse();
    } else if (name == 'Next') {
      onNext?.call();
      return DBusMethodSuccessResponse();
    } else if (name == 'Previous') {
      onPrevious?.call();
      return DBusMethodSuccessResponse();
    } else if (name == 'Stop') {
      onPlayPause?.call();
      return DBusMethodSuccessResponse();
    }
    return DBusMethodSuccessResponse();
  }

  @override
  Future<DBusMethodResponse> getAllProperties(String interface) async {
    if (interface == 'org.mpris.MediaPlayer2') {
      return DBusGetAllPropertiesResponse({
        'CanQuit': const DBusBoolean(false),
        'CanRaise': const DBusBoolean(true),
        'HasTrackList': const DBusBoolean(false),
        'Identity': const DBusString('Zephyr Music Player'),
        'DesktopEntry': const DBusString('zephyr'),
      });
    } else if (interface == 'org.mpris.MediaPlayer2.Player') {
      return DBusGetAllPropertiesResponse({
        'PlaybackStatus': DBusString(_playbackStatus),
        'Metadata': DBusDict.stringVariant(_metadata),
        'CanControl': const DBusBoolean(true),
        'CanGoNext': const DBusBoolean(true),
        'CanGoPrevious': const DBusBoolean(true),
        'CanPlay': const DBusBoolean(true),
        'CanPause': const DBusBoolean(true),
        'CanSeek': const DBusBoolean(false),
        'Volume': DBusDouble(_volume),
        'Position': const DBusInt64(0),
        'Rate': const DBusDouble(1.0),
        'MinimumRate': const DBusDouble(1.0),
        'MaximumRate': const DBusDouble(1.0),
      });
    }
    return DBusGetAllPropertiesResponse({});
  }

  @override
  Future<DBusMethodResponse> getProperty(String interface, String property) async {
    final allResponse = await getAllProperties(interface);
    if (allResponse is DBusGetAllPropertiesResponse && allResponse.values.isNotEmpty) {
      final dict = allResponse.values.first as DBusDict;
      final val = dict.children[DBusString(property)];
      if (val != null) {
        return DBusGetPropertyResponse(val);
      }
    }
    return DBusMethodErrorResponse.unknownProperty();
  }

  @override
  Future<DBusMethodResponse> setProperty(String interface, String property, DBusValue value) async {
    if (interface == 'org.mpris.MediaPlayer2.Player' && property == 'Volume') {
      if (value is DBusDouble) {
        final vol = value.value.clamp(0.0, 1.0);
        _volume = vol;
        onSetVolume?.call(vol);
        emitPropertiesChanged(
          'org.mpris.MediaPlayer2.Player',
          changedProperties: {'Volume': DBusDouble(_volume)},
        );
        return DBusMethodSuccessResponse();
      }
    }
    return DBusMethodErrorResponse.unknownProperty();
  }
}

class LinuxMprisService {
  static final LinuxMprisService _instance = LinuxMprisService._internal();
  factory LinuxMprisService() => _instance;
  LinuxMprisService._internal();

  DBusClient? _client;
  ZephyrMprisPlayer? _player;
  bool _isInitialized = false;

  Future<void> init({
    required VoidCallback onPlayPause,
    required VoidCallback onNext,
    required VoidCallback onPrevious,
    ValueChanged<double>? onSetVolume,
  }) async {
    if (kIsWeb || _isInitialized) return;
    try {
      _client = DBusClient.session();
      _player = ZephyrMprisPlayer()
        ..onPlayPause = onPlayPause
        ..onNext = onNext
        ..onPrevious = onPrevious
        ..onSetVolume = onSetVolume;

      await _client?.registerObject(_player!);
      await _client?.requestName(
        'org.mpris.MediaPlayer2.zephyr',
        flags: {
          DBusRequestNameFlag.allowReplacement,
          DBusRequestNameFlag.replaceExisting,
        },
      );
      try {
        await _client?.requestName(
          'org.mpris.MediaPlayer2.zephyr.instance${pid}',
          flags: {
            DBusRequestNameFlag.allowReplacement,
            DBusRequestNameFlag.replaceExisting,
          },
        );
      } catch (_) {}

      _isInitialized = true;
    } catch (e) {
      debugPrint('Linux MPRIS init warning: $e');
    }
  }

  void updateState({
    required bool isPlaying,
    required Track? track,
    required String apiBaseUrl,
    double? volume,
  }) {
    if (!_isInitialized || _player == null) return;
    try {
      _player!.updateState(
        isPlaying: isPlaying,
        track: track,
        apiBaseUrl: apiBaseUrl,
        volume: volume,
      );
    } catch (_) {}
  }

  void dispose() {
    try {
      _client?.close();
      _isInitialized = false;
    } catch (_) {}
  }
}
