import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/models.dart';
import '../utils/offline_storage.dart';
import 'library_provider.dart';

class OfflineDownloadsState {
  final Set<String> downloadedTrackIds;
  final Map<String, double> progressMap;
  final Set<String> activeDownloadingIds;

  const OfflineDownloadsState({
    this.downloadedTrackIds = const {},
    this.progressMap = const {},
    this.activeDownloadingIds = const {},
  });

  bool isDownloaded(String videoId) {
    final cleanId = videoId.startsWith('dz_') ? videoId : 'dz_$videoId';
    final rawId = videoId.startsWith('dz_') ? videoId.substring(3) : videoId;
    return downloadedTrackIds.contains(videoId) ||
        downloadedTrackIds.contains(cleanId) ||
        downloadedTrackIds.contains(rawId);
  }

  bool isDownloading(String videoId) {
    return activeDownloadingIds.contains(videoId);
  }

  double? getProgress(String videoId) {
    return progressMap[videoId];
  }

  OfflineDownloadsState copyWith({
    Set<String>? downloadedTrackIds,
    Map<String, double>? progressMap,
    Set<String>? activeDownloadingIds,
  }) {
    return OfflineDownloadsState(
      downloadedTrackIds: downloadedTrackIds ?? this.downloadedTrackIds,
      progressMap: progressMap ?? this.progressMap,
      activeDownloadingIds: activeDownloadingIds ?? this.activeDownloadingIds,
    );
  }
}

class OfflineDownloadsNotifier extends Notifier<OfflineDownloadsState> {
  final OfflineStorageService _storage = OfflineStorageService();

  @override
  OfflineDownloadsState build() {
    _initStorage();
    return const OfflineDownloadsState();
  }

  Future<void> _initStorage() async {
    await _storage.init();
    final offlineTracks = _storage.getAllOfflineTracks();
    final downloadedSet = offlineTracks.map((t) => t.videoId).toSet();
    state = state.copyWith(downloadedTrackIds: downloadedSet);
  }

  Future<void> downloadTrack(Track track) async {
    if (state.isDownloaded(track.videoId) || state.isDownloading(track.videoId)) return;

    final updatedActive = Set<String>.from(state.activeDownloadingIds)..add(track.videoId);
    final updatedProgress = Map<String, double>.from(state.progressMap)..[track.videoId] = 0.0;

    state = state.copyWith(
      activeDownloadingIds: updatedActive,
      progressMap: updatedProgress,
    );

    try {
      await _storage.saveTrackLocally(
        track,
        onProgress: (received, total) {
          if (total > 0) {
            final fraction = (received / total).clamp(0.0, 1.0);
            final pMap = Map<String, double>.from(state.progressMap)..[track.videoId] = fraction;
            state = state.copyWith(progressMap: pMap);
          }
        },
      );

      final newDownloaded = Set<String>.from(state.downloadedTrackIds)..add(track.videoId);
      final newActive = Set<String>.from(state.activeDownloadingIds)..remove(track.videoId);
      final newProgress = Map<String, double>.from(state.progressMap)..remove(track.videoId);

      state = state.copyWith(
        downloadedTrackIds: newDownloaded,
        activeDownloadingIds: newActive,
        progressMap: newProgress,
      );

      ref.read(libraryProvider.notifier).loadLibrary(quiet: true);
    } catch (e) {
      debugPrint('Local track download failed: $e');
      final newActive = Set<String>.from(state.activeDownloadingIds)..remove(track.videoId);
      final newProgress = Map<String, double>.from(state.progressMap)..remove(track.videoId);
      state = state.copyWith(
        activeDownloadingIds: newActive,
        progressMap: newProgress,
      );
      rethrow;
    }
  }

  Future<void> removeDownload(String videoId) async {
    await _storage.removeTrackLocally(videoId);
    final newDownloaded = Set<String>.from(state.downloadedTrackIds)..remove(videoId);
    state = state.copyWith(downloadedTrackIds: newDownloaded);
    ref.read(libraryProvider.notifier).loadLibrary(quiet: true);
  }

  Future<void> downloadBatch(List<Track> tracks) async {
    for (final track in tracks) {
      if (!state.isDownloaded(track.videoId)) {
        try {
          await downloadTrack(track);
        } catch (_) {}
      }
    }
  }
}

final offlineDownloadsProvider =
    NotifierProvider<OfflineDownloadsNotifier, OfflineDownloadsState>(
  () => OfflineDownloadsNotifier(),
);
