import 'dart:ffi' as ffi;
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:zephyr_core/app/zephyr_app.dart';
import 'package:zephyr_core/utils/app_logger.dart';
import 'package:zephyr_core/utils/media_controls.dart';

import 'mpris_service.dart';

String? _extractVideoIdFromDeepLink(String rawUrl) {
  try {
    final uri = Uri.parse(rawUrl);
    if (uri.scheme == 'zephyr') {
      if (uri.host == 'track' && uri.pathSegments.isNotEmpty) {
        return uri.pathSegments.first;
      } else if (uri.path.contains('/track/')) {
        final parts = uri.path.split('/track/');
        if (parts.length > 1) return parts[1].split('/')[0];
      } else if (uri.queryParameters.containsKey('v')) {
        return uri.queryParameters['v'];
      }
    } else if (uri.path.contains('/track/')) {
      final parts = uri.path.split('/track/');
      if (parts.length > 1) return parts[1].split('/')[0];
    }
  } catch (_) {}
  return null;
}

void _disableGStreamerVideoSink() {
  if (!Platform.isLinux) return;
  try {
    final nativeLib = ffi.DynamicLibrary.process();
    final setenv = nativeLib.lookupFunction<
        ffi.Int32 Function(ffi.Pointer<Utf8>, ffi.Pointer<Utf8>, ffi.Int32),
        int Function(ffi.Pointer<Utf8>, ffi.Pointer<Utf8>, int)>('setenv');
    final namePtr = 'GST_VIDEO_SINK'.toNativeUtf8();
    final valPtr = 'fakesink'.toNativeUtf8();
    setenv(namePtr, valPtr, 1);
    calloc.free(namePtr);
    calloc.free(valPtr);
  } catch (_) {}
}

Future<void> main(List<String> args) async {
  _disableGStreamerVideoSink();
  WidgetsFlutterBinding.ensureInitialized();
  await AppLogger.instance.init();

  // Register the desktop (MPRIS) media-controls implementation so core code
  // can drive the system media player without knowing about DBus.
  MediaControls.instance = MprisMediaControls();

  String? initialVideoId;
  for (final arg in args) {
    final vId = _extractVideoIdFromDeepLink(arg);
    if (vId != null && vId.isNotEmpty) {
      initialVideoId = vId;
      break;
    }
  }

  runApp(
    ProviderScope(
      child: ZephyrApp(initialVideoId: initialVideoId),
    ),
  );
}
