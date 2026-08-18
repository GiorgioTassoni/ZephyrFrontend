import 'dart:async';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../api/zephyr_api.dart';
import '../models/models.dart';
import '../providers/library_provider.dart';
import '../theme/colors.dart';
import '../theme/zephyr_theme.dart';
import '../widgets/resolution_candidate_modal.dart';
import '../widgets/toast.dart';

class ImportScreen extends ConsumerStatefulWidget {
  const ImportScreen({super.key});

  @override
  ConsumerState<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends ConsumerState<ImportScreen> {
  final _api = ZephyrApi();

  bool _isUploading = false;
  bool _isCancelling = false;
  bool _isLoadingHistory = true;
  ImportStatus? _importStatus;
  String? _error;
  String? _selectedImportJobId;
  List<ImportStatus> _importHistory = [];
  StreamSubscription<Map<String, dynamic>>? _sseSub;

  @override
  void initState() {
    super.initState();
    _loadImportHistory();
    _subscribeToSseEvents();
  }

  @override
  void dispose() {
    _sseSub?.cancel();
    super.dispose();
  }

  void _subscribeToSseEvents() {
    _sseSub = _api.onImportProgress.listen((data) {
      if (!mounted) return;
      final jobId = data['job_id']?.toString() ?? '';
      if (jobId.isEmpty) return;

      final status = data['status']?.toString() ?? 'processing';
      final total = (data['total'] as num?)?.toInt() ?? 0;
      final processed = (data['processed'] as num?)?.toInt() ?? 0;
      final queued = (data['queued'] as num?)?.toInt() ?? 0;
      final failed = (data['failed'] as num?)?.toInt() ?? 0;
      final needsReview = (data['needs_review'] as num?)?.toInt() ?? 0;
      final unavailable = (data['unavailable'] as num?)?.toInt() ?? 0;

      // Update in-memory history list
      setState(() {
        final existingIndex = _importHistory.indexWhere((h) => h.jobId == jobId);
        if (existingIndex != -1) {
          _importHistory[existingIndex] = _importHistory[existingIndex].copyWith(
            status: status,
            total: total > 0 ? total : _importHistory[existingIndex].total,
            processed: processed,
            queued: queued,
            failed: failed,
            needsReview: needsReview,
            unavailable: unavailable,
          );
        }
      });

      // If this event matches the currently opened import
      if (_selectedImportJobId == jobId || _importStatus?.jobId == jobId) {
        final isTerminal = status == 'completed' ||
            status == 'completed_with_review' ||
            status == 'cancelled';

        if (isTerminal) {
          // Terminal snapshot: fetch full payload to load review_items and failed_tracks
          _api.getImportStatus(jobId).then((fullStatus) {
            if (!mounted) return;
            setState(() {
              _importStatus = fullStatus;
              _selectedImportJobId = jobId;
              _isCancelling = false;
            });
            if (status == 'completed' || status == 'completed_with_review') {
              ref.read(libraryProvider.notifier).loadLibrary();
            }
          }).catchError((e) {
            if (!mounted) return;
            setState(() {
              _importStatus = _importStatus?.copyWith(
                status: status,
                total: total,
                processed: processed,
                queued: queued,
                failed: failed,
                needsReview: needsReview,
                unavailable: unavailable,
              );
              _isCancelling = false;
            });
          });
        } else {
          // Live per-row incremental progress
          setState(() {
            if (_importStatus != null) {
              _importStatus = _importStatus!.copyWith(
                status: status,
                total: total > 0 ? total : _importStatus!.total,
                processed: processed,
                queued: queued,
                failed: failed,
                needsReview: needsReview,
                unavailable: unavailable,
              );
            }
          });
        }
      }
    });
  }

  Future<void> _loadImportHistory() async {
    setState(() => _isLoadingHistory = true);
    try {
      final history = await _api.getImportList();
      if (!mounted) return;
      setState(() {
        _importHistory = history;
        _isLoadingHistory = false;
      });

      // If there's an ongoing import, automatically select it to view live progress
      final activeJob = history.where((j) => j.status == 'processing').firstOrNull;
      if (activeJob != null && _selectedImportJobId == null) {
        _selectImport(activeJob.jobId);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoadingHistory = false;
      });
      debugPrint('Notice: Error loading import history: $e');
    }
  }

  Future<void> _selectImport(String jobId) async {
    setState(() {
      _selectedImportJobId = jobId;
      _error = null;
    });

    try {
      final status = await _api.getImportStatus(jobId);
      if (!mounted) return;
      setState(() {
        _importStatus = status;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Could not load import details: $e');
    }
  }

  Future<void> _pickAndImportCsv() async {
    setState(() {
      _isUploading = true;
      _error = null;
    });

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv'],
        allowMultiple: false,
      );

      if (result != null && result.files.single.path != null) {
        final file = File(result.files.single.path!);
        final initialStatus = await _api.importCsv(file);

        setState(() {
          _selectedImportJobId = initialStatus.jobId;
          _importStatus = initialStatus;
          _importHistory.removeWhere((h) => h.jobId == initialStatus.jobId);
          _importHistory.insert(0, initialStatus);
          _isUploading = false;
        });

        if (mounted) {
          ZephyrToast.show(context, 'CSV uploaded! Processing tracks via live SSE progress...');
        }
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

  Future<void> _cancelImport() async {
    if (_importStatus == null || _isCancelling) return;
    final jobId = _importStatus!.jobId;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ZephyrColors.bgCard,
        title: const Text('Cancel Import?'),
        content: const Text('Are you sure you want to cancel this running import? Already queued tracks will remain in your library.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Keep Running', style: TextStyle(color: ZephyrColors.textDim)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: ZephyrColors.error),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Cancel Import', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _isCancelling = true);
    try {
      await _api.cancelImportJob(jobId);
      if (mounted) {
        ZephyrToast.show(context, 'Import cancelled');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isCancelling = false);
        ZephyrToast.show(context, 'Failed to cancel import: $e', isError: true);
      }
    }
  }

  Widget _buildStatusChip(String status) {
    Color color;
    IconData icon;
    String label = status.replaceAll('_', ' ').toUpperCase();

    switch (status) {
      case 'processing':
        color = Colors.amber;
        icon = Icons.sync_rounded;
        break;
      case 'completed':
        color = ZephyrColors.success;
        icon = Icons.check_circle_rounded;
        break;
      case 'completed_with_review':
        color = Colors.orangeAccent;
        icon = Icons.find_in_page_rounded;
        label = 'REVIEW NEEDED';
        break;
      case 'cancelled':
        color = ZephyrColors.textDim;
        icon = Icons.cancel_outlined;
        break;
      case 'failed':
      default:
        color = ZephyrColors.error;
        icon = Icons.error_outline_rounded;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSavedImportsSelector() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: ZephyrColors.bgCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: ZephyrColors.bgLight.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          const Icon(Icons.history_rounded, color: ZephyrColors.primary),
          const SizedBox(width: 12),
          Expanded(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                isExpanded: true,
                value: _selectedImportJobId,
                hint: const Text('Recent Imports (History)'),
                items: _importHistory.map((item) {
                  final name = item.playlistName ?? (item.importMode != null ? 'Import (${item.importMode})' : 'CSV Import');
                  final dateStr = '${item.createdAt.month}/${item.createdAt.day} ${item.createdAt.hour}:${item.createdAt.minute.toString().padLeft(2, '0')}';
                  return DropdownMenuItem<String>(
                    value: item.jobId,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            '$name ($dateStr)',
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                        const SizedBox(width: 8),
                        _buildStatusChip(item.status),
                      ],
                    ),
                  );
                }).toList(),
                onChanged: (jobId) {
                  if (jobId != null) _selectImport(jobId);
                },
              ),
            ),
          ),
          IconButton(
            tooltip: 'Refresh History',
            icon: const Icon(Icons.refresh_rounded, size: 20, color: ZephyrColors.textDim),
            onPressed: _loadImportHistory,
          ),
        ],
      ),
    );
  }

  Widget _buildMetricCard({
    required String label,
    required int count,
    required Color color,
    required IconData icon,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 11,
                      color: ZephyrColors.textDim,
                      fontWeight: FontWeight.w500,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    '$count',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final status = _importStatus;
    final progress = status != null && status.total > 0
        ? (status.processed / status.total).clamp(0.0, 1.0)
        : 0.0;
    final isProcessing = status != null && status.status == 'processing';

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
              'Import your Spotify playlists by uploading a CSV file. Live progress updates in real-time without polling.',
              style: TextStyle(color: ZephyrColors.textDim, fontSize: 14),
            ),
            const SizedBox(height: 32),

            if (_importHistory.isNotEmpty || _isLoadingHistory) ...[
              _buildSavedImportsSelector(),
              const SizedBox(height: 20),
            ],

            // Select File Card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: ZephyrColors.bgCard,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: ZephyrColors.bgLight.withValues(alpha: 0.5),
                ),
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
                    style: TextStyle(
                      fontSize: 12,
                      color: ZephyrColors.textMuted,
                    ),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    style: ZephyrTheme.primaryPillStyle(),
                    onPressed: _isUploading || isProcessing ? null : _pickAndImportCsv,
                    icon: const Icon(Icons.file_open),
                    label: Text(_isUploading ? 'Uploading...' : 'Choose CSV File'),
                  ),
                ],
              ),
            ),

            if (_error != null) ...[
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: ZephyrColors.error.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: ZephyrColors.error.withValues(alpha: 0.3),
                  ),
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
                  border: Border.all(
                    color: ZephyrColors.bgLight.withValues(alpha: 0.5),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Text(
                              status.playlistName ?? 'Import Job',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 18,
                              ),
                            ),
                            const SizedBox(width: 10),
                            _buildStatusChip(status.status),
                          ],
                        ),
                        Row(
                          children: [
                            Text(
                              '${status.processed} / ${status.total} tracks',
                              style: const TextStyle(
                                fontSize: 14,
                                color: ZephyrColors.textDim,
                              ),
                            ),
                            if (isProcessing) ...[
                              const SizedBox(width: 16),
                              ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: ZephyrColors.error.withValues(alpha: 0.15),
                                  foregroundColor: ZephyrColors.error,
                                  side: BorderSide(color: ZephyrColors.error.withValues(alpha: 0.4)),
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                ),
                                onPressed: _isCancelling ? null : _cancelImport,
                                icon: _isCancelling
                                    ? const SizedBox(
                                        width: 12,
                                        height: 12,
                                        child: CircularProgressIndicator(strokeWidth: 2, color: ZephyrColors.error),
                                      )
                                    : const Icon(Icons.cancel_outlined, size: 16),
                                label: const Text('Cancel Import', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                              ),
                            ],
                          ],
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
                        valueColor: AlwaysStoppedAnimation<Color>(
                          status.status == 'cancelled'
                              ? ZephyrColors.textDim
                              : (status.status == 'completed' ? ZephyrColors.success : ZephyrColors.primary),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Metrics breakdown
                    Row(
                      children: [
                        _buildMetricCard(
                          label: 'Queued / Match',
                          count: status.queued,
                          color: ZephyrColors.success,
                          icon: Icons.queue_music_rounded,
                        ),
                        const SizedBox(width: 10),
                        _buildMetricCard(
                          label: 'Needs Review',
                          count: status.needsReview > 0 ? status.needsReview : status.reviewItems.length,
                          color: Colors.amberAccent,
                          icon: Icons.find_in_page_rounded,
                        ),
                        const SizedBox(width: 10),
                        _buildMetricCard(
                          label: 'Unavailable',
                          count: status.unavailable,
                          color: Colors.orangeAccent,
                          icon: Icons.cloud_off_rounded,
                        ),
                        const SizedBox(width: 10),
                        _buildMetricCard(
                          label: 'Failed',
                          count: status.failed,
                          color: ZephyrColors.error,
                          icon: Icons.error_outline_rounded,
                        ),
                      ],
                    ),

                    // Review Items (Needs Resolution) list
                    if (status.reviewItems.isNotEmpty) ...[
                      const SizedBox(height: 24),
                      Text(
                        'Needs Resolution (${status.reviewItems.length})',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.amberAccent,
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Select a YouTube match below to fulfill and import these tracks.',
                        style: TextStyle(
                          color: ZephyrColors.textDim,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 12),
                      ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: status.reviewItems.length,
                        separatorBuilder: (context, index) => const Divider(
                          color: ZephyrColors.bgLight,
                          height: 1,
                        ),
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
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      if (artistsList.isNotEmpty)
                                        Text(
                                          artistsList.join(', '),
                                          style: const TextStyle(
                                            color: ZephyrColors.textDim,
                                            fontSize: 12,
                                          ),
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
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                  onPressed: () async {
                                    final exc = ResolutionRequiredException(
                                      resolutionId: resId.isNotEmpty ? resId : null,
                                      trackId: trackId,
                                      title: title,
                                      artists: artistsList,
                                      candidates: candidatesList,
                                    );
                                    final selected = await ResolutionCandidateModal.show(
                                      context,
                                      exc,
                                      isImportResolution: true,
                                    );
                                    if (selected == true && mounted) {
                                      final updated = await _api.getImportStatus(status.jobId);
                                      setState(() {
                                        _importStatus = updated;
                                      });
                                    }
                                  },
                                  icon: const Icon(Icons.find_in_page_rounded, size: 16),
                                  label: const Text(
                                    'Select Match',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ],

                    // Failed Tracks list
                    if (status.failedTracks.isNotEmpty) ...[
                      const SizedBox(height: 24),
                      const Text(
                        'Failed / Unavailable Tracks',
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
                        separatorBuilder: (context, index) => const Divider(
                          color: ZephyrColors.bgLight,
                          height: 1,
                        ),
                        itemBuilder: (context, index) {
                          final failed = status.failedTracks[index];
                          final title = failed['title'] ?? 'Unknown Title';
                          final artist = failed['artist'] ?? 'Unknown Artist';
                          final reason = (failed['reason'] ?? 'Match score too low').toString();
                          final isUnavailable = reason.contains('PROVIDER_UNAVAILABLE') || reason.contains('unavailable');

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
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      Text(
                                        artist,
                                        style: const TextStyle(
                                          color: ZephyrColors.textDim,
                                          fontSize: 12,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isUnavailable
                                        ? Colors.orange.withValues(alpha: 0.15)
                                        : ZephyrColors.error.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(
                                      color: isUnavailable
                                          ? Colors.orange.withValues(alpha: 0.3)
                                          : ZephyrColors.error.withValues(alpha: 0.3),
                                    ),
                                  ),
                                  child: Text(
                                    reason,
                                    style: TextStyle(
                                      color: isUnavailable ? Colors.orangeAccent : ZephyrColors.error,
                                      fontSize: 11,
                                    ),
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
            const SizedBox(height: 80),
          ],
        ),
      ),
    );
  }
}
