import 'dart:async';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../api/zephyr_api.dart';
import '../models/models.dart';
import '../providers/library_provider.dart';
import '../theme/colors.dart';
import '../widgets/resolution_candidate_modal.dart';

class ImportScreen extends ConsumerStatefulWidget {
  const ImportScreen({super.key});

  @override
  ConsumerState<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends ConsumerState<ImportScreen> {
  final _api = ZephyrApi();
  
  bool _isUploading = false;
  ImportStatus? _importStatus;
  Timer? _pollingTimer;
  String? _error;

  @override
  void dispose() {
    _pollingTimer?.cancel();
    super.dispose();
  }

  Future<void> _pickAndImportCsv() async {
    setState(() {
      _isUploading = true;
      _error = null;
      _importStatus = null;
    });
    _pollingTimer?.cancel();

    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv'],
        allowMultiple: false,
      );

      if (result != null && result.files.single.path != null) {
        final file = File(result.files.single.path!);
        final initialStatus = await _api.importCsv(file);
        
        setState(() {
          _importStatus = initialStatus;
          _isUploading = false;
        });

        // Start polling the job status
        _startPolling(initialStatus.jobId);
      } else {
        setState(() {
          _isUploading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isUploading = false;
      });
    }
  }

  void _startPolling(String jobId) {
    _pollingTimer?.cancel();
    _pollingTimer = Timer.periodic(const Duration(seconds: 3), (timer) async {
      try {
        final currentStatus = await _api.getImportStatus(jobId);
        setState(() {
          _importStatus = currentStatus;
        });

        if (currentStatus.status == 'completed' || currentStatus.status == 'failed') {
          _pollingTimer?.cancel();
          // Reload library as new tracks are imported
          ref.read(libraryProvider.notifier).loadLibrary();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Import job completed! Match success: ${currentStatus.processed - currentStatus.failed}/${currentStatus.total}'),
              backgroundColor: ZephyrColors.success,
            ),
          );
        }
      } catch (e) {
        _pollingTimer?.cancel();
        setState(() {
          _error = 'Polling failed: $e';
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final status = _importStatus;
    final progress = status != null && status.total > 0
        ? status.processed / status.total
        : 0.0;

    return Scaffold(
      backgroundColor: ZephyrColors.bgDark,
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Spotify CSV Import',
              style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Import your Spotify playlists by uploading a CSV file (exported from Exportify or standard CSV). Tracks will be matched with YouTube Music and added to your library.',
              style: TextStyle(color: ZephyrColors.textDim, fontSize: 14),
            ),
            const SizedBox(height: 32),

            // Select File Card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: ZephyrColors.bgCard,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: ZephyrColors.bgLight.withOpacity(0.5)),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.cloud_upload_outlined,
                    size: 64,
                    color: ZephyrColors.primary,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Select a Spotify CSV export file',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Columns expected: Track Name, Artist Name(s), Duration (ms)',
                    style: TextStyle(fontSize: 12, color: ZephyrColors.textMuted),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: ZephyrColors.primary,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                    ),
                    onPressed: _isUploading || (status != null && status.status == 'processing')
                        ? null
                        : _pickAndImportCsv,
                    icon: const Icon(Icons.file_open),
                    label: const Text('Choose CSV File', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),

            if (_error != null) ...[
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: ZephyrColors.error.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: ZephyrColors.error.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline, color: ZephyrColors.error),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _error!,
                        style: const TextStyle(color: ZephyrColors.error),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // Progress tracking panel
            if (status != null) ...[
              const SizedBox(height: 32),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: ZephyrColors.bgCard,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: ZephyrColors.bgLight.withOpacity(0.5)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Job Status: ${status.status.toUpperCase()}',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: status.status == 'completed'
                                ? ZephyrColors.success
                                : ZephyrColors.warning,
                          ),
                        ),
                        Text(
                          '${status.processed} / ${status.total} tracks',
                          style: const TextStyle(fontSize: 14, color: ZephyrColors.textDim),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    // Progress Bar
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 8,
                        backgroundColor: ZephyrColors.bgLight,
                        valueColor: const AlwaysStoppedAnimation<Color>(ZephyrColors.primary),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Review Items (Needs Resolution) list
                    if (status.reviewItems.isNotEmpty) ...[
                      const SizedBox(height: 20),
                      Text(
                        'Needs Resolution (${status.reviewItems.length})',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.amberAccent,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'The following tracks require candidate selection to ensure the exact match.',
                        style: TextStyle(color: ZephyrColors.textDim, fontSize: 12),
                      ),
                      const SizedBox(height: 12),
                      ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: status.reviewItems.length,
                        separatorBuilder: (context, index) => const Divider(color: ZephyrColors.bgLight, height: 1),
                        itemBuilder: (context, index) {
                          final item = status.reviewItems[index];
                          final resId = (item['id'] ?? '').toString();
                          final trackId = (item['track_id'] ?? '').toString();
                          final title = (item['source_title'] ?? 'Unknown Track').toString();
                          final artistsList = item['source_artists'] is List
                              ? (item['source_artists'] as List).map((e) => e.toString()).toList()
                              : <String>[];
                          final candidatesList = item['candidates'] is List
                              ? (item['candidates'] as List)
                                  .map((c) => ResolutionCandidate.fromJson(Map<String, dynamic>.from(c)))
                                  .toList()
                              : <ResolutionCandidate>[];

                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8.0),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        title,
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      if (artistsList.isNotEmpty)
                                        Text(
                                          artistsList.join(', '),
                                          style: const TextStyle(color: ZephyrColors.textDim, fontSize: 12),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                    ],
                                  ),
                                ),
                                ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.amberAccent,
                                    foregroundColor: Colors.black,
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  ),
                                  onPressed: () async {
                                    final exc = ResolutionRequiredException(
                                      resolutionId: resId.isNotEmpty ? resId : null,
                                      trackId: trackId,
                                      title: title,
                                      artists: artistsList,
                                      candidates: candidatesList,
                                    );
                                    final selected = await ResolutionCandidateModal.show(context, exc);
                                    if (selected == true && mounted) {
                                      // Refresh job status
                                      final updated = await _api.getImportStatus(status.jobId);
                                      setState(() {
                                        _importStatus = updated;
                                      });
                                    }
                                  },
                                  icon: const Icon(Icons.find_in_page_rounded, size: 16),
                                  label: const Text('Select Match', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ],

                    // Failed Tracks list
                    if (status.failedTracks.isNotEmpty) ...[
                      const SizedBox(height: 20),
                      const Text(
                        'Failed Tracks',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: ZephyrColors.error,
                        ),
                      ),
                      const SizedBox(height: 12),
                      ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: status.failedTracks.length,
                        separatorBuilder: (context, index) => const Divider(color: ZephyrColors.bgLight, height: 1),
                        itemBuilder: (context, index) {
                          final failed = status.failedTracks[index];
                          final title = failed['title'] ?? 'Unknown Title';
                          final artist = failed['artist'] ?? 'Unknown Artist';
                          final reason = failed['reason'] ?? 'Match score too low';

                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8.0),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        title,
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      Text(
                                        artist,
                                        style: const TextStyle(color: ZephyrColors.textDim, fontSize: 12),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: ZephyrColors.error.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    reason,
                                    style: const TextStyle(color: ZephyrColors.error, fontSize: 11),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
