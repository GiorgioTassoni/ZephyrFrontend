import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:zephyr_core/app/zephyr_app.dart';
import 'package:zephyr_core/utils/app_logger.dart';
import 'package:zephyr_core/utils/app_platform.dart';
import 'package:zephyr_core/utils/audio_handler.dart';

Future<void> main() async {
  AppPlatform.formFactor = ZephyrFormFactor.mobile;
  WidgetsFlutterBinding.ensureInitialized();
  await AppLogger.instance.init();

  SystemChrome.setEnabledSystemUIMode(
    SystemUiMode.manual,
    overlays: [SystemUiOverlay.top, SystemUiOverlay.bottom],
  );
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ),
  );

  // Initialize background AudioService (notification / lock-screen controls).
  try {
    zephyrAudioHandler = await initAudioService();
  } catch (e) {
    debugPrint('AudioService init notice: $e');
    zephyrAudioHandler ??= ZephyrAudioHandler();
  }

  runApp(
    const ProviderScope(
      child: ZephyrApp(),
    ),
  );
}
