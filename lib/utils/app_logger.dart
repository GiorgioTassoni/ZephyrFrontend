import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

class AppLogger {
  AppLogger._internal();
  static final AppLogger instance = AppLogger._internal();

  static const int _maxInMemoryEntries = 2000;
  final List<String> _inMemoryLogs = [];
  int _nextEventId = 0;
  File? _logFile;
  IOSink? _fileSink;
  bool _initialized = false;
  DateTime? _lastThrottledLogTime;

  Future<void> init() async {
    if (_initialized) return;
    try {
      final dir = await getApplicationDocumentsDirectory();
      _logFile = File('${dir.path}/zephyr_logs.txt');
      if (_logFile!.existsSync()) {
        final length = await _logFile!.length();
        if (length < 2 * 1024 * 1024) {
          final lines = await _logFile!.readAsLines();
          if (lines.length > _maxInMemoryEntries) {
            _inMemoryLogs.addAll(lines.sublist(lines.length - _maxInMemoryEntries));
          } else {
            _inMemoryLogs.addAll(lines);
          }
        }
      }
      _fileSink = _logFile!.openWrite(mode: FileMode.append);
      _initialized = true;
      logSystem('logger_initialized', data: {'persisted_path': _logFile?.path});
    } catch (e) {
      debugPrint('[AppLogger] Initialization warning: $e');
    }
  }

  void _log(String category, String action, {Map<String, dynamic>? data}) {
    final now = DateTime.now().toUtc().toIso8601String();
    final eventId = ++_nextEventId;
    final dataStr = data != null && data.isNotEmpty ? ' | data=${data.toString()}' : '';
    final entry = '[$now] [$category] [$action] [event=$eventId]$dataStr';

    // Print to console in debug mode
    debugPrint(entry);

    // In-memory ring buffer
    if (_inMemoryLogs.length >= _maxInMemoryEntries) {
      _inMemoryLogs.removeAt(0);
    }
    _inMemoryLogs.add(entry);

    // Persist to file
    try {
      _fileSink?.writeln(entry);
    } catch (_) {}
  }

  // --- Specialized Loggers ---

  void logPlayer(String action, {Map<String, dynamic>? data}) {
    _log('PLAYER', action, data: data);
  }

  void logPlayerThrottled(String action, {Map<String, dynamic>? data, Duration interval = const Duration(seconds: 5)}) {
    final now = DateTime.now();
    if (_lastThrottledLogTime == null || now.difference(_lastThrottledLogTime!) >= interval) {
      _lastThrottledLogTime = now;
      logPlayer(action, data: data);
    }
  }

  void logQueue(String action, {Map<String, dynamic>? data}) {
    _log('QUEUE', action, data: data);
  }

  void logAuth(String action, {Map<String, dynamic>? data}) {
    _log('AUTH', action, data: data);
  }

  void logApi(String action, {Map<String, dynamic>? data}) {
    _log('API', action, data: data);
  }

  void logSse(String action, {Map<String, dynamic>? data}) {
    _log('SSE', action, data: data);
  }

  void logFavorite(String action, {Map<String, dynamic>? data}) {
    _log('FAVORITE', action, data: data);
  }

  void logLifecycle(String state) {
    _log('LIFECYCLE', state);
  }

  void logSystem(String action, {Map<String, dynamic>? data}) {
    _log('SYSTEM', action, data: data);
  }

  // --- Export & Management ---

  List<String> getLogs() {
    return List<String>.unmodifiable(_inMemoryLogs);
  }

  String getLogsAsString() {
    return _inMemoryLogs.join('\n');
  }

  Future<File?> getLogFile() async {
    try {
      await _fileSink?.flush();
      return _logFile;
    } catch (_) {
      return _logFile;
    }
  }

  Future<void> clearLogs() async {
    _inMemoryLogs.clear();
    try {
      await _fileSink?.close();
      if (_logFile != null && _logFile!.existsSync()) {
        await _logFile!.writeAsString('');
      }
      if (_logFile != null) {
        _fileSink = _logFile!.openWrite(mode: FileMode.append);
      }
      logSystem('logs_cleared');
    } catch (e) {
      debugPrint('[AppLogger] Clear error: $e');
    }
  }

  Future<void> dispose() async {
    try {
      await _fileSink?.flush();
      await _fileSink?.close();
      _fileSink = null;
    } catch (_) {}
  }
}
