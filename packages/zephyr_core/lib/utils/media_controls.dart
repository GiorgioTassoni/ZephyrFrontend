import 'package:flutter/foundation.dart';

import '../models/models.dart';

/// Platform media-control integration seam.
///
/// The core package never touches OS-specific APIs directly. Each app shell
/// (Android / Desktop) registers its own implementation at startup:
///   - Desktop shell -> MPRIS (DBus) integration
///   - Mobile shell  -> system notification / lock-screen controls come from
///     audio_service (via audio_handler.dart), so the no-op default is fine.
///
/// Core code (e.g. player_provider) calls [MediaControls.instance]
/// unconditionally - the no-op default keeps it safe everywhere.
abstract class MediaControlsService {
  Future<void> init({
    required VoidCallback onPlayPause,
    required VoidCallback onNext,
    required VoidCallback onPrevious,
    ValueChanged<double>? onSetVolume,
  });

  void updateState({
    required bool isPlaying,
    required Track? track,
    required String apiBaseUrl,
    double? volume,
  });
}

class NoopMediaControls implements MediaControlsService {
  @override
  Future<void> init({
    required VoidCallback onPlayPause,
    required VoidCallback onNext,
    required VoidCallback onPrevious,
    ValueChanged<double>? onSetVolume,
  }) async {}

  @override
  void updateState({
    required bool isPlaying,
    required Track? track,
    required String apiBaseUrl,
    double? volume,
  }) {}
}

class MediaControls {
  MediaControls._();

  static MediaControlsService instance = NoopMediaControls();
}
