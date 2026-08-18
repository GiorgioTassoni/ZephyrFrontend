import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../api/zephyr_api.dart';
import '../models/models.dart';
import '../providers/library_provider.dart';
import '../theme/colors.dart';
import '../theme/zephyr_theme.dart';
import '../widgets/resolution_candidate_modal.dart';

class ImportScreen extends ConsumerStatefulWidget {
  const ImportScreen({super.key});

  @override
  ConsumerState<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends ConsumerState<ImportScreen> {
  final _api = ZephyrApi();

  static const _savedImportsKey = 'csv_import_history';

  bool _isUploading = false;
  ImportStatus? _importStatus;
  Timer? _pollingTimer;
  String? _error;
  String? _selectedImportJobId;
  List<Map<String, dynamic>> _savedImports = [];

  @override
  void initState() {
    super.initState();
    _loadSavedImports();
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadSavedImports() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_savedImportsKey);
      if (raw == null) return;
      final decoded = jsonDecode(raw);
      if (decoded is! List) return;
      final imports = decoded
          .whereType<Map>()
          .map((entry) => Map<String, dynamic>.from(entry))
          .where((entry) => entry['job_id']?.toString().isNotEmpty == true)
          .toList();
      imports.sort((a, b) {
        final aDate = DateTime.tryParse(a['created_at']?.toString() ?? '');
        final bDate = DateTime.tryParse(b['created_at']?.toString() ?? '');
        return (bDate ?? DateTime.fromMillisecondsSinceEpoch(0)).compareTo(
          aDate ?? DateTime.fromMillisecondsSinceEpoch(0),
        );
      });
      if (mounted) setState(() => _savedImports = imports);
    } catch (e) {
      debugPrint('Could not load CSV import history: $e');
    }
  }

  Future<void> _persistSavedImports() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_savedImportsKey, jsonEncode(_savedImports));
  }

  String _nameForCsv(String path) {
    final fileName = path.split(Platform.pathSeparator).last;
    final extension = fileName.toLowerCase().endsWith('.csv')
        ? fileName.length - 4
        : fileName.length;
    return fileName.substring(0, extension).trim().isEmpty
        ? 'CSV import'
        : fileName.substring(0, extension).trim();
  }

  Future<void> _rememberImport(ImportStatus status, String name) async {
    final jobId = status.jobId;
    if (jobId.isEmpty) return;
    final previous = _savedImports.cast<Map<String, dynamic>?>().firstWhere(
      (entry) => entry?['job_id']?.toString() == jobId,
      orElse: () => null,
    );
    final record = <String, dynamic>{
      'job_id': jobId,
      'name': name.isNotEmpty
          ? name
          : (previous?['name']?.toString() ?? 'CSV import'),
      'status_url': status.statusUrl,
      'status': status.status,
      'created_at': status.createdAt.toIso8601String(),
      'total': status.total,
    };
    final updated = _savedImports
        .where((entry) => entry['job_id']?.toString() != jobId)
        .toList();
    updated.insert(0, record);
    if (!mounted) return;
    setState(() => _savedImports = updated);
    await _persistSavedImports();
  }

  Future<void> _selectSavedImport(String jobId) async {
    final record = _savedImports.firstWhere(
      (entry) => entry['job_id']?.toString() == jobId,
      orElse: () => <String, dynamic>{},
    );
    if (record.isEmpty) return;
    _pollingTimer?.cancel();
    setState(() {
      _selectedImportJobId = jobId;
      _importStatus = null;
      _error = null;
    });
    try {
      final status = await _api.getImportStatus(
        jobId,
        statusUrl: record['status_url']?.toString(),
      );
      if (!mounted) return;
      setState(() => _importStatus = status);
      await _rememberImport(status, record['name']?.toString() ?? 'CSV import');
      if (status.status != 'completed' && status.status != 'failed') {
        _startPolling(jobId);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Could not load this import: $e');
    }
  }

  Future<void> _removeSavedImport(String jobId) async {
    _pollingTimer?.cancel();
    setState(() {
      _savedImports = _savedImports
          .where((entry) => entry['job_id']?.toString() != jobId)
          .toList();
      if (_selectedImportJobId == jobId) {
        _selectedImportJobId = null;
        _importStatus = null;
      }
    });
    await _persistSavedImports();
  }

  Future<void> _pickAndImportCsv() async {
    setState(() {
      _isUploading = true;
      _error = null;
      _importStatus = null;
    });
    _pollingTimer?.cancel();

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv'],
        allowMultiple: false,
      );

      if (result != null && result.files.single.path != null) {
        final file = File(result.files.single.path!);
        final importName = _nameForCsv(file.path);
        final initialStatus = await _api.importCsv(file);
        await _rememberImport(initialStatus, importName);

        setState(() {
          _selectedImportJobId = initialStatus.jobId;
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
        final savedRecord = _savedImports.firstWhere(
          (entry) => entry['job_id']?.toString() == jobId,
          orElse: () => <String, dynamic>{},
        );
        final currentStatus = await _api.getImportStatus(
          jobId,
          statusUrl: savedRecord['status_url']?.toString(),
        );
        final existingName = _savedImports
            .firstWhere(
              (entry) => entry['job_id']?.toString() == jobId,
              orElse: () => <String, dynamic>{},
            )['name']
            ?.toString();
        setState(() {
          _selectedImportJobId = jobId;
          _importStatus = currentStatus;
        });
        await _rememberImport(currentStatus, existingName ?? 'CSV import');

        if (currentStatus.status == 'completed' ||
            currentStatus.status == 'failed') {
          _pollingTimer?.cancel();
          // Reload library as new tracks are imported
          ref.read(libraryProvider.notifier).loadLibrary();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Import job completed! Match success: '
                  '${currentStatus.processed - currentStatus.failed}/'
                  '${currentStatus.total}',
                ),
                backgroundColor: ZephyrColors.success,
              ),
            );
          }
        }
      } catch (e) {
        _pollingTimer?.cancel();
        setState(() {
          _error = 'Polling failed: $e';
        });
      }
    });
  }

  Widget _buildSavedImportsSelector() {
    final selected = _savedImports.cast<Map<String, dynamic>?>().firstWhere(
      (entry) => entry?['job_id']?.toString() == _selectedImportJobId,
      orElse: () => null,
    );
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
          const Icon(Icons.folder_open, color: ZephyrColors.primary),
          const SizedBox(width: 12),
          Expanded(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                isExpanded: true,
                value: selected?['job_id']?.toString(),
                hint: const Text('Open a saved CSV import'),
                items: _savedImports.map((entry) {
                  final jobId = entry['job_id'].toString();
                  final name = entry['name']?.toString() ?? 'CSV import';
                  final savedStatus = entry['status']?.toString() ?? 'unknown';
                  return DropdownMenuItem<String>(
                    value: jobId,
                    child: Text(
                      '$name  ·  ${savedStatus.replaceAll('_', ' ')}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  );
                }).toList(),
                onChanged: (jobId) {
                  if (jobId != null) _selectSavedImport(jobId);
                },
              ),
            ),
          ),
          if (selected != null)
            IconButton(
              tooltip: 'Remove saved import',
              icon: const Icon(
                Icons.delete_outline,
                color: ZephyrColors.textDim,
              ),
              onPressed: () =>
                  _removeSavedImport(selected['job_id'].toString()),
            ),
        ],
      ),
    );
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

            if (_savedImports.isNotEmpty) ...[
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
                    onPressed:
                        _isUploading ||
                            (status != null && status.status == 'processing')
                        ? null
                        : _pickAndImportCsv,
                    icon: const Icon(Icons.file_open),
                    label: const Text('Choose CSV File'),
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
                          style: const TextStyle(
                            fontSize: 14,
                            color: ZephyrColors.textDim,
                          ),
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
                        valueColor: const AlwaysStoppedAnimation<Color>(
                          ZephyrColors.primary,
                        ),
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
                          final title =
                              (item['source_title'] ?? 'Unknown Track')
                                  .toString();
                          final artistsList = item['source_artists'] is List
                              ? (item['source_artists'] as List)
                                    .map((e) => e.toString())
                                    .toList()
                              : <String>[];
                          final candidatesList = item['candidates'] is List
                              ? (item['candidates'] as List)
                                    .map(
                                      (c) => ResolutionCandidate.fromJson(
                                        Map<String, dynamic>.from(c),
                                      ),
                                    )
                                    .toList()
                              : <ResolutionCandidate>[];

                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8.0),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
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
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 8,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                  onPressed: () async {
                                    final exc = ResolutionRequiredException(
                                      resolutionId: resId.isNotEmpty
                                          ? resId
                                          : null,
                                      trackId: trackId,
                                      title: title,
                                      artists: artistsList,
                                      candidates: candidatesList,
                                    );
                                    final selected =
                                        await ResolutionCandidateModal.show(
                                          context,
                                          exc,
                                          isImportResolution: true,
                                        );
                                    if (selected == true && mounted) {
                                      // Refresh job status
                                      final updated = await _api
                                          .getImportStatus(
                                            status.jobId,
                                            statusUrl: status.statusUrl,
                                          );
                                      setState(() {
                                        _importStatus = updated;
                                      });
                                    }
                                  },
                                  icon: const Icon(
                                    Icons.find_in_page_rounded,
                                    size: 16,
                                  ),
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
                        separatorBuilder: (context, index) => const Divider(
                          color: ZephyrColors.bgLight,
                          height: 1,
                        ),
                        itemBuilder: (context, index) {
                          final failed = status.failedTracks[index];
                          final title = failed['title'] ?? 'Unknown Title';
                          final artist = failed['artist'] ?? 'Unknown Artist';
                          final reason =
                              failed['reason'] ?? 'Match score too low';

                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8.0),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
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
                                    color: ZephyrColors.error.withValues(
                                      alpha: 0.1,
                                    ),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    reason,
                                    style: const TextStyle(
                                      color: ZephyrColors.error,
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
          ],
        ),
      ),
    );
  }
}
