import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../api/zephyr_api.dart';
import '../models/models.dart';
import '../providers/auth_provider.dart';
import '../providers/player_provider.dart';
import '../theme/colors.dart';
import '../theme/zephyr_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'toast.dart';

class UnresolvedTrackModal extends ConsumerStatefulWidget {
  final String trackId;
  final String title;
  final List<String> artists;
  final List<ResolutionCandidate>? initialCandidates;
  final String? initialResolutionId;

  const UnresolvedTrackModal({
    super.key,
    required this.trackId,
    required this.title,
    required this.artists,
    this.initialCandidates,
    this.initialResolutionId,
  });

  static Future<bool?> show(
    BuildContext context, {
    required String trackId,
    required String title,
    required List<String> artists,
    List<ResolutionCandidate>? initialCandidates,
    String? initialResolutionId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final autoSelectEnabled = prefs.getBool('auto_select_high_confidence') ?? true;

    if (autoSelectEnabled && initialCandidates != null && initialCandidates.isNotEmpty) {
      final candidates = List<ResolutionCandidate>.from(initialCandidates);
      candidates.sort((a, b) => b.matchScore.compareTo(a.matchScore));
      final top = candidates.first;

      if (top.matchScore >= 85 && top.videoType != 'OMV') {
        try {
          await ZephyrApi().selectTrackCandidate(
            trackId,
            resolutionId: initialResolutionId,
            videoId: top.videoId,
          );
          if (context.mounted) {
            ZephyrToast.show(
              context,
              '⚡ Auto-matched "${top.title}" (${top.matchScore}% match)',
            );
          }
          return true;
        } catch (_) {}
      }
    }

    if (!context.mounted) return false;
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => UnresolvedTrackModal(
        trackId: trackId,
        title: title,
        artists: artists,
        initialCandidates: initialCandidates,
        initialResolutionId: initialResolutionId,
      ),
    );
  }

  @override
  ConsumerState<UnresolvedTrackModal> createState() => _UnresolvedTrackModalState();
}

class _UnresolvedTrackModalState extends ConsumerState<UnresolvedTrackModal> {
  final _api = ZephyrApi();
  late TextEditingController _searchController;

  int _selectedTab = 0; // 0: Search YT, 1: Upload File
  List<ResolutionCandidate> _candidates = [];
  bool _isLoading = false;
  String? _submittingVideoId;
  String? _errorMessage;
  String? _resolutionId;

  @override
  void initState() {
    super.initState();
    _candidates = List.from(widget.initialCandidates ?? []);
    _resolutionId = widget.initialResolutionId;
    final initialQuery = '${widget.title} ${widget.artists.join(' ')}'.trim();
    _searchController = TextEditingController(text: initialQuery);

    if (_candidates.isEmpty) {
      _performSearch(initialQuery);
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _performSearch(String query) async {
    if (query.trim().isEmpty) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final res = await _api.searchTrackResolution(widget.trackId, query.trim());
      if (res['resolution_id'] != null) {
        _resolutionId = res['resolution_id'].toString();
      }
      List<ResolutionCandidate> fetched = [];
      final rawCand = res['candidates'];
      if (rawCand is List) {
        fetched = rawCand
            .map((c) => ResolutionCandidate.fromJson(Map<String, dynamic>.from(c)))
            .toList();
      }
      setState(() {
        _candidates = fetched;
        _isLoading = false;
        if (fetched.isEmpty) {
          _errorMessage = 'No YouTube Music results found for "$query". Try another search query.';
        }
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = e.toString();
      });
    }
  }

  Future<void> _selectCandidate(ResolutionCandidate candidate) async {
    setState(() {
      _submittingVideoId = candidate.videoId;
      _errorMessage = null;
    });

    try {
      await _api.selectTrackCandidate(
        widget.trackId,
        resolutionId: _resolutionId,
        videoId: candidate.videoId,
      );

      ref.read(playerProvider.notifier).clearResolvedCache(widget.trackId);
      if (mounted) {
        ZephyrToast.show(context, '⚡ Selection saved for "${candidate.title}"!');
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        final errStr = e.toString().toLowerCase();
        if (errStr.contains('422') || errStr.contains('invalid_resolution')) {
          try {
            final track = await _api.getTrackMetadata(widget.trackId);
            if (track.isDownloaded ||
                track.downloadStatus == 'completed' ||
                track.downloadStatus == 'pending' ||
                track.downloadStatus == 'downloading') {
              ref.read(playerProvider.notifier).clearResolvedCache(widget.trackId);
              ZephyrToast.show(context, 'Track resolved! Starting playback...');
              Navigator.of(context).pop(true);
              return;
            }
          } catch (_) {}
        }
        setState(() {
          _submittingVideoId = null;
          _errorMessage = 'Selection error: $e';
        });
      }
    }
  }

  Future<void> _pickAndUploadFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['mp3', 'flac', 'm4a', 'wav', 'ogg'],
      );
      if (result == null || result.files.single.path == null) return;

      final file = File(result.files.single.path!);
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });

      await _api.uploadTrack(
        file: file,
        title: widget.title.isNotEmpty ? widget.title : widget.trackId,
        artists: widget.artists.isNotEmpty ? widget.artists.join(', ') : 'Unknown Artist',
        targetTrackId: widget.trackId,
      );

      ref.read(playerProvider.notifier).clearResolvedCache(widget.trackId);
      if (mounted) {
        ZephyrToast.show(context, '⚡ Track fulfilled with local audio file!');
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'File upload failed: $e';
        });
      }
    }
  }

  String _formatDuration(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    final isCuratorOrAdmin = authState.isCurator || authState.isAdmin;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 36),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 640, maxHeight: 740),
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: ZephyrColors.bgCard.withValues(alpha: 0.95),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.12),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.5),
                  blurRadius: 30,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: ZephyrColors.primary.withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.track_changes_rounded,
                        color: ZephyrColors.primary,
                        size: 26,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Track Resolution Needed',
                            style: TextStyle(
                              color: ZephyrColors.text,
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              letterSpacing: -0.5,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Choose how to match or fulfill this track:',
                            style: TextStyle(
                              color: ZephyrColors.textDim.withValues(alpha: 0.8),
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),

                // Target Track Info Card
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: ZephyrColors.bgLight.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.08),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.music_note_rounded, color: ZephyrColors.primary, size: 22),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.title.isNotEmpty ? widget.title : widget.trackId,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 14.5,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (widget.artists.isNotEmpty)
                              Text(
                                widget.artists.join(', '),
                                style: const TextStyle(
                                  color: ZephyrColors.textDim,
                                  fontSize: 12.5,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),

                // Option Select Tabs: 1. Search YouTube  |  2. Upload Audio File
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: () => setState(() => _selectedTab = 0),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            decoration: BoxDecoration(
                              color: _selectedTab == 0 ? ZephyrColors.bgCard : Colors.transparent,
                              borderRadius: BorderRadius.circular(9),
                              border: Border.all(
                                color: _selectedTab == 0 ? ZephyrColors.primary.withValues(alpha: 0.6) : Colors.transparent,
                                width: 1.2,
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.search_rounded,
                                  size: 16,
                                  color: _selectedTab == 0 ? ZephyrColors.primary : ZephyrColors.textDim,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  '1. Search YouTube',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: _selectedTab == 0 ? FontWeight.bold : FontWeight.normal,
                                    color: _selectedTab == 0 ? Colors.white : ZephyrColors.textDim,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      if (isCuratorOrAdmin)
                        Expanded(
                          child: GestureDetector(
                            onTap: () => setState(() => _selectedTab = 1),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              decoration: BoxDecoration(
                                color: _selectedTab == 1 ? ZephyrColors.bgCard : Colors.transparent,
                                borderRadius: BorderRadius.circular(9),
                                border: Border.all(
                                  color: _selectedTab == 1 ? Colors.indigoAccent.withValues(alpha: 0.6) : Colors.transparent,
                                  width: 1.2,
                                ),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.upload_file_rounded,
                                    size: 16,
                                    color: _selectedTab == 1 ? Colors.indigoAccent : ZephyrColors.textDim,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    '2. Upload Audio File',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: _selectedTab == 1 ? FontWeight.bold : FontWeight.normal,
                                      color: _selectedTab == 1 ? Colors.white : ZephyrColors.textDim,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Error banner
                if (_errorMessage != null) ...[
                  Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.redAccent.withValues(alpha: 0.4)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 18),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _errorMessage!,
                            style: const TextStyle(color: Colors.redAccent, fontSize: 12.5),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                // TAB 0: YouTube Search View
                if (_selectedTab == 0) ...[
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _searchController,
                          style: const TextStyle(color: ZephyrColors.text, fontSize: 13),
                          decoration: InputDecoration(
                            hintText: 'Type custom query to search YouTube Music...',
                            hintStyle: const TextStyle(color: ZephyrColors.textMuted, fontSize: 13),
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                            filled: true,
                            fillColor: Colors.black.withValues(alpha: 0.3),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: const BorderSide(color: ZephyrColors.primary),
                            ),
                          ),
                          onSubmitted: (val) => _performSearch(val),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        onPressed: _isLoading ? null : () => _performSearch(_searchController.text),
                        icon: const Icon(Icons.search_rounded, size: 16, color: ZephyrColors.primary),
                        label: const Text('Search', style: TextStyle(color: ZephyrColors.primary, fontWeight: FontWeight.bold, fontSize: 13)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: ZephyrColors.primary.withValues(alpha: 0.15),
                          foregroundColor: ZephyrColors.primary,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                            side: BorderSide(color: ZephyrColors.primary.withValues(alpha: 0.4)),
                          ),
                          elevation: 0,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // Candidates List
                  Expanded(
                    child: _isLoading
                        ? const Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                CircularProgressIndicator(color: ZephyrColors.primary),
                                SizedBox(height: 12),
                                Text(
                                  'Searching YouTube Music via backend API...',
                                  style: TextStyle(color: ZephyrColors.textDim, fontSize: 13),
                                ),
                              ],
                            ),
                          )
                        : _candidates.isEmpty
                            ? Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(Icons.search_off_rounded, size: 48, color: ZephyrColors.textDim),
                                    const SizedBox(height: 12),
                                    const Text(
                                      'No YouTube Music matches found.',
                                      style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Try modifying your search query above.',
                                      style: TextStyle(color: ZephyrColors.textDim.withValues(alpha: 0.8), fontSize: 12.5),
                                    ),
                                  ],
                                ),
                              )
                            : ListView.separated(
                                itemCount: _candidates.length,
                                separatorBuilder: (_, __) => const SizedBox(height: 10),
                                itemBuilder: (context, index) {
                                  final c = _candidates[index];
                                  final isSubmitting = _submittingVideoId == c.videoId;

                                  return Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: ZephyrColors.bgLight.withValues(alpha: 0.3),
                                      borderRadius: BorderRadius.circular(14),
                                      border: Border.all(
                                        color: isSubmitting
                                            ? ZephyrColors.primary
                                            : c.matchScore >= 80
                                                ? const Color(0xFF10B981).withValues(alpha: 0.4)
                                                : Colors.white.withValues(alpha: 0.08),
                                        width: c.matchScore >= 80 ? 1.2 : 1.0,
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        ClipRRect(
                                          borderRadius: BorderRadius.circular(8),
                                          child: c.thumbnail != null && c.thumbnail!.isNotEmpty
                                              ? CachedNetworkImage(
                                                  imageUrl: c.thumbnail!,
                                                  width: 52,
                                                  height: 52,
                                                  fit: BoxFit.cover,
                                                  errorWidget: (_, __, ___) => Container(
                                                    width: 52,
                                                    height: 52,
                                                    color: ZephyrColors.bgLight,
                                                    child: const Icon(Icons.music_note, color: ZephyrColors.textDim),
                                                  ),
                                                )
                                              : Container(
                                                  width: 52,
                                                  height: 52,
                                                  color: ZephyrColors.bgLight,
                                                  child: const Icon(Icons.music_note, color: ZephyrColors.textDim),
                                                ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                children: [
                                                  Expanded(
                                                    child: Text(
                                                      c.title,
                                                      style: const TextStyle(
                                                        color: Colors.white,
                                                        fontWeight: FontWeight.bold,
                                                        fontSize: 13.5,
                                                      ),
                                                      maxLines: 1,
                                                      overflow: TextOverflow.ellipsis,
                                                    ),
                                                  ),
                                                  if (c.matchScore > 0)
                                                    Padding(
                                                      padding: const EdgeInsets.only(left: 6),
                                                      child: ZephyrTheme.matchScoreBadge(c.matchScore),
                                                    ),
                                                ],
                                              ),
                                              const SizedBox(height: 2),
                                              Row(
                                                children: [
                                                  if (c.videoType == 'OMV' || c.videoType == 'VIDEO')
                                                    ZephyrTheme.omvBadge()
                                                  else if (c.videoType == 'MUSIC_VIDEO_TYPE_ATV' || c.videoType == 'ATV')
                                                    ZephyrTheme.atvBadge(),
                                                  Expanded(
                                                    child: Text(
                                                      '${c.artists.join(', ')} • ${_formatDuration(c.durationSeconds)}',
                                                      style: const TextStyle(color: ZephyrColors.textDim, fontSize: 11.5),
                                                      maxLines: 1,
                                                      overflow: TextOverflow.ellipsis,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        ElevatedButton.icon(
                                          onPressed: _submittingVideoId != null ? null : () => _selectCandidate(c),
                                          icon: isSubmitting
                                              ? const SizedBox(
                                                  width: 14,
                                                  height: 14,
                                                  child: CircularProgressIndicator(
                                                    strokeWidth: 2,
                                                    valueColor: AlwaysStoppedAnimation<Color>(ZephyrColors.bgDark),
                                                  ),
                                                )
                                              : const Icon(Icons.check_rounded, size: 15, color: ZephyrColors.bgDark),
                                          label: Text(
                                            isSubmitting ? 'Selecting...' : 'Select',
                                            style: const TextStyle(
                                              fontSize: 12,
                                              color: ZephyrColors.bgDark,
                                              fontWeight: FontWeight.bold,
                                              letterSpacing: 0.3,
                                            ),
                                          ),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: ZephyrColors.primary,
                                            foregroundColor: ZephyrColors.bgDark,
                                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                            shape: const StadiumBorder(),
                                            elevation: 0,
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                  ),
                ],

                // TAB 1: Upload Local Audio File
                if (_selectedTab == 1) ...[
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: ZephyrColors.bgLight.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: Colors.indigoAccent.withValues(alpha: 0.3),
                          style: BorderStyle.solid,
                          width: 1.5,
                        ),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.indigoAccent.withValues(alpha: 0.2),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.cloud_upload_rounded,
                              size: 44,
                              color: Colors.indigoAccent,
                            ),
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'Fulfill Track with Audio File',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'Upload a local MP3, FLAC, M4A, WAV, or OGG file to fulfill this track immediately.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: ZephyrColors.textDim, fontSize: 12.5),
                          ),
                          const SizedBox(height: 20),
                          ElevatedButton.icon(
                            onPressed: _isLoading ? null : _pickAndUploadFile,
                            icon: const Icon(Icons.folder_open_rounded, size: 18),
                            label: Text(_isLoading ? 'Uploading...' : 'Choose Audio File'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.indigoAccent,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              elevation: 0,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 16),

                // Footer Actions
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      style: TextButton.styleFrom(
                        foregroundColor: ZephyrColors.textDim,
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      ),
                      child: const Text('Cancel'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
