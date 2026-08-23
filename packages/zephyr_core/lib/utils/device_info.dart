import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DeviceInfo {
  static String? _cachedDeviceId;
  static String? _cachedDeviceName;

  static String _generateUuidV4() {
    final rand = Random.secure();
    final bytes = List<int>.generate(16, (_) => rand.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40; // Version 4
    bytes[8] = (bytes[8] & 0x3f) | 0x80; // Variant 1

    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20, 32)}';
  }

  static Future<String> getDeviceId() async {
    if (_cachedDeviceId != null) return _cachedDeviceId!;
    final prefs = await SharedPreferences.getInstance();
    String? id = prefs.getString('zephyr_device_id');
    if (id == null || id.isEmpty) {
      id = _generateUuidV4();
      await prefs.setString('zephyr_device_id', id);
    }
    _cachedDeviceId = id;
    return id;
  }

  static Future<String> getDeviceName() async {
    if (_cachedDeviceName != null) return _cachedDeviceName!;
    final prefs = await SharedPreferences.getInstance();
    String? name = prefs.getString('zephyr_device_name');
    if (name == null || name.isEmpty) {
      if (kIsWeb) {
        name = 'Zephyr Web';
      } else if (Platform.isLinux) {
        name = 'Zephyr Desktop (Linux)';
      } else if (Platform.isAndroid) {
        name = 'Zephyr Mobile (Android)';
      } else if (Platform.isIOS) {
        name = 'Zephyr Mobile (iOS)';
      } else if (Platform.isWindows) {
        name = 'Zephyr Desktop (Windows)';
      } else if (Platform.isMacOS) {
        name = 'Zephyr Desktop (macOS)';
      } else {
        name = 'Zephyr Device';
      }
      await prefs.setString('zephyr_device_name', name);
    }
    _cachedDeviceName = name;
    return name;
  }

  static Future<void> setDeviceName(String newName) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('zephyr_device_name', newName);
    _cachedDeviceName = newName;
  }
}
