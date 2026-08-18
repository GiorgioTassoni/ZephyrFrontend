import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import '../api/zephyr_api.dart';
import '../models/models.dart';

class OfflineTrackData {
  final Track track;
  final String audioPath;
  final String? coverPath;
  final String? lyricsPath;
  final DateTime downloadedAt;

  OfflineTrackData({
    required this.track,
    required this.audioPath,
    this.coverPath,
    this.lyricsPath,
    required this.downloadedAt,
  });

  Map<String, dynamic> toJson() => {
        'track': track.toJson(),
        'audio_path': audioPath,
        'cover_path': coverPath,
        'lyrics_path': lyricsPath,
        'downloaded_at': downloadedAt.toIso8601String(),
      };

  factory OfflineTrackData.fromJson(Map<String, dynamic> json) {
    return OfflineTrackData(
      track: Track.fromJson(Map<String, dynamic>.from(json['track'] ?? {})),
      audioPath: json['audio_path']?.toString() ?? '',
      coverPath: json['cover_path']?.toString(),
      lyricsPath: json['lyrics_path']?.toString(),
      downloadedAt: json['downloaded_at'] != null
          ? DateTime.tryParse(json['downloaded_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }
}

class OfflineStorageService {
  static final OfflineStorageService _instance = OfflineStorageService._internal();
  factory OfflineStorageService() => _instance;
  OfflineStorageService._internal();

  final ZephyrApi _api = ZephyrApi();
  Directory? _baseDir;
  final Map<String, OfflineTrackData> _registry = {};
  bool _isInitialized = false;

  Future<void> init() async {
    if (_isInitialized) return;
    try {
      final appDir = await getApplicationDocumentsDirectory();
      _baseDir = Directory('${appDir.path}/zephyr_offline');
      if (!await _baseDir!.exists()) {
        await _baseDir!.create(recursive: true);
      }

      await Directory('${_baseDir!.path}/tracks').create(recursive: true);
      await Directory('${_baseDir!.path}/covers').create(recursive: true);
      await Directory('${_baseDir!.path}/lyrics').create(recursive: true);

      await _loadRegistry();
      _isInitialized = true;
    } catch (e) {
      debugPrint('OfflineStorageService init error: $e');
    }
  }

  Future<void> _loadRegistry() async {
    try {
      if (_baseDir == null) return;
      final file = File('${_baseDir!.path}/registry.json');
      if (!await file.exists()) return;

      final content = await file.readAsString();
      if (content.trim().isEmpty) return;

      final Map<String, dynamic> data = jsonDecode(content);
      _registry.clear();
      data.forEach((key, value) {
        if (value is Map) {
          final item = OfflineTrackData.fromJson(Map<String, dynamic>.from(value));
          // Verify audio file actually exists on disk
          if (File(item.audioPath).existsSync()) {
            _registry[key] = item;
          }
        }
      });
    } catch (e) {
      debugPrint('Error loading offline registry: $e');
    }
  }

  Future<void> _saveRegistry() async {
    try {
      if (_baseDir == null) return;
      final file = File('${_baseDir!.path}/registry.json');
      final data = _registry.map((k, v) => MapEntry(k, v.toJson()));
      await file.writeAsString(jsonEncode(data));
    } catch (e) {
      debugPrint('Error saving offline registry: $e');
    }
  }

  bool isLocallyDownloaded(String trackId) {
    final cleanId = trackId.startsWith('dz_') ? trackId : 'dz_$trackId';
    final altId = trackId.startsWith('dz_') ? trackId.substring(3) : trackId;
    final item = _registry[cleanId] ?? _registry[altId] ?? _registry[trackId];
    if (item == null) return false;
    return File(item.audioPath).existsSync();
  }

  String? getAudioFilePath(String trackId) {
    final cleanId = trackId.startsWith('dz_') ? trackId : 'dz_$trackId';
    final altId = trackId.startsWith('dz_') ? trackId.substring(3) : trackId;
    final item = _registry[cleanId] ?? _registry[altId] ?? _registry[trackId];
    if (item == null) return null;
    final file = File(item.audioPath);
    return file.existsSync() ? file.path : null;
  }

  String? getCoverFilePath(String trackId) {
    final cleanId = trackId.startsWith('dz_') ? trackId : 'dz_$trackId';
    final altId = trackId.startsWith('dz_') ? trackId.substring(3) : trackId;
    final item = _registry[cleanId] ?? _registry[altId] ?? _registry[trackId];
    if (item == null || item.coverPath == null) return null;
    final file = File(item.coverPath!);
    return file.existsSync() ? file.path : null;
  }

  String? getLyricsLrc(String trackId) {
    final cleanId = trackId.startsWith('dz_') ? trackId : 'dz_$trackId';
    final altId = trackId.startsWith('dz_') ? trackId.substring(3) : trackId;
    final item = _registry[cleanId] ?? _registry[altId] ?? _registry[trackId];
    if (item == null || item.lyricsPath == null) return null;
    final file = File(item.lyricsPath!);
    return file.existsSync() ? file.readAsStringSync() : null;
  }

  List<Track> getAllOfflineTracks() {
    return _registry.values.map((e) => e.track.copyWith(
      isDownloaded: true,
      downloadStatus: 'completed',
    )).toList();
  }

  Future<void> saveTrackLocally(
    Track track, {
    ProgressCallback? onProgress,
    CancelToken? cancelToken,
  }) async {
    await init();
    if (_baseDir == null) throw Exception('Offline storage base directory unavailable');

    final safeId = track.videoId.replaceAll(RegExp(r'[^\w\-]'), '_');
    final audioFile = File('${_baseDir!.path}/tracks/$safeId.m4a');
    final coverFile = File('${_baseDir!.path}/covers/$safeId.jpg');
    final lyricsFile = File('${_baseDir!.path}/lyrics/$safeId.lrc');

    // 1. Download audio file from GET /api/tracks/download/{track_id}
    await _api.downloadTrackAudioFile(
      track.videoId,
      audioFile.path,
      onReceiveProgress: onProgress,
      cancelToken: cancelToken,
    );

    // 2. Fetch cover image & save
    String? coverSavedPath;
    try {
      final coverUrl = _api.getCoverUrl(track.videoId);
      await _api.dio.download(coverUrl, coverFile.path, cancelToken: cancelToken);
      if (await coverFile.exists() && (await coverFile.length()) > 0) {
        coverSavedPath = coverFile.path;
      }
    } catch (_) {}

    // 3. Fetch metadata & lyrics
    String? lyricsSavedPath;
    Track enrichedTrack = track;
    try {
      final meta = await _api.getTrackMetadata(track.videoId);
      enrichedTrack = meta;
      if (meta.lyricsLrc != null && meta.lyricsLrc!.isNotEmpty) {
        await lyricsFile.writeAsString(meta.lyricsLrc!);
        lyricsSavedPath = lyricsFile.path;
      }
    } catch (_) {}

    final data = OfflineTrackData(
      track: enrichedTrack.copyWith(
        isDownloaded: true,
        downloadStatus: 'completed',
      ),
      audioPath: audioFile.path,
      coverPath: coverSavedPath,
      lyricsPath: lyricsSavedPath,
      downloadedAt: DateTime.now(),
    );

    _registry[track.videoId] = data;
    await _saveRegistry();
  }

  Future<void> removeTrackLocally(String trackId) async {
    await init();
    final cleanId = trackId.startsWith('dz_') ? trackId : 'dz_$trackId';
    final altId = trackId.startsWith('dz_') ? trackId.substring(3) : trackId;

    final item = _registry.remove(cleanId) ??
        _registry.remove(altId) ??
        _registry.remove(trackId);

    if (item != null) {
      try {
        final audioFile = File(item.audioPath);
        if (await audioFile.exists()) await audioFile.delete();
      } catch (_) {}
      if (item.coverPath != null) {
        try {
          final coverFile = File(item.coverPath!);
          if (await coverFile.exists()) await coverFile.delete();
        } catch (_) {}
      }
      if (item.lyricsPath != null) {
        try {
          final lyricsFile = File(item.lyricsPath!);
          if (await lyricsFile.exists()) await lyricsFile.delete();
        } catch (_) {}
      }
      await _saveRegistry();
    }
  }
}
