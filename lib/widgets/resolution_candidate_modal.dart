import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../api/zephyr_api.dart';
import '../models/models.dart';
import '../providers/auth_provider.dart';
import '../theme/colors.dart';

import 'package:shared_preferences/shared_preferences.dart';
import 'toast.dart';

class ResolutionCandidateModal extends ConsumerStatefulWidget {
  final ResolutionRequiredException exception;
  final bool isImportResolution;

  const ResolutionCandidateModal({
    super.key,
    required this.exception,
    this.isImportResolution = false,
  });

  static Future<bool?> show(
    BuildContext context,
    ResolutionRequiredException exception, {
    bool isImportResolution = false,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final autoSelectEnabled =
        prefs.getBool('auto_select_high_confidence') ?? true;

    if (autoSelectEnabled && exception.candidates.isNotEmpty) {
      final candidates = List<ResolutionCandidate>.from(exception.candidates);
      candidates.sort((a, b) => b.matchScore.compareTo(a.matchScore));
      final top = candidates.first;

      final isHighConfidence = top.matchScore >= 85 && top.videoType != 'OMV';

      if (isHighConfidence) {
        try {
          if (isImportResolution && exception.resolutionId != null) {
            await ZephyrApi().selectImportResolution(
              exception.resolutionId!,
              top.videoId,
            );
          } else {
            await ZephyrApi().selectTrackCandidate(
              exception.trackId,
              resolutionId: exception.resolutionId,
              videoId: top.videoId,
            );
          }
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
      builder: (context) => ResolutionCandidateModal(
        exception: exception,
        isImportResolution: isImportResolution,
      ),
    );
  }

  @override
  ConsumerState<ResolutionCandidateModal> createState() =>
      _ResolutionCandidateModalState();
}

class _ResolutionCandidateModalState
    extends ConsumerState<ResolutionCandidateModal> {
  List<ResolutionCandidate> _candidates = [];
  bool _isLoadingCandidates = false;
  String? _submittingVideoId;
  String? _errorMessage;
  String? _resolutionId;
  late TextEditingController _searchController;

  @override
  void initState() {
    super.initState();
    _candidates = List.from(widget.exception.candidates);
    _resolutionId = widget.exception.resolutionId;
    final initialQuery =
        '${widget.exception.title} ${widget.exception.artists.join(' ')}'
            .trim();
    _searchController = TextEditingController(text: initialQuery);
    if (_candidates.isEmpty) {
      _fetchCandidatesFromApi();
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchCandidatesFromApi() async {
    setState(() => _isLoadingCandidates = true);
    try {
      final res =
          widget.isImportResolution && widget.exception.resolutionId != null
          ? await ZephyrApi().retryImportResolution(
              widget.exception.resolutionId!,
            )
          : await ZephyrApi().getTrackResolution(widget.exception.trackId);
      if (res != null) {
        if (res['resolution_id'] != null) {
          _resolutionId = res['resolution_id'].toString();
        }
        final rawCand =
            res['candidates'] ??
            (res['detail'] is Map ? res['detail']['candidates'] : null);
        if (rawCand is List) {
          final fetched = rawCand
              .map(
                (c) =>
                    ResolutionCandidate.fromJson(Map<String, dynamic>.from(c)),
              )
              .toList();
          setState(() {
            _candidates = fetched;
            _isLoadingCandidates = false;
          });
          return;
        }
      }
      setState(() => _isLoadingCandidates = false);
    } catch (e) {
      setState(() {
        _isLoadingCandidates = false;
        _errorMessage = 'Could not load candidates: $e';
      });
    }
  }

  Future<void> _performCustomSearch(String query) async {
    if (query.trim().isEmpty) return;
    setState(() {
      _isLoadingCandidates = true;
      _errorMessage = null;
    });

    try {
      final res =
          widget.isImportResolution && widget.exception.resolutionId != null
          ? await ZephyrApi().retryImportResolution(
              widget.exception.resolutionId!,
            )
          : await ZephyrApi().searchTrackResolution(
              widget.exception.trackId,
              query.trim(),
            );
      if (res['resolution_id'] != null) {
        _resolutionId = res['resolution_id'].toString();
      }
      List<ResolutionCandidate> fetched = [];
      final rawCand = res['candidates'];
      if (rawCand is List) {
        fetched = rawCand
            .map(
              (c) => ResolutionCandidate.fromJson(Map<String, dynamic>.from(c)),
            )
            .toList();
      }
      setState(() {
        _candidates = fetched;
        _isLoadingCandidates = false;
        if (fetched.isEmpty) {
          _errorMessage =
              'No YouTube Music results found for "$query". Try another search term.';
        }
      });
    } catch (e) {
      setState(() {
        _isLoadingCandidates = false;
        _errorMessage = 'Search error: $e';
      });
    }
  }

  Future<void> _fulfillWithFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['mp3', 'flac', 'm4a', 'wav', 'ogg'],
      );
      if (result == null || result.files.single.path == null) return;

      setState(() {
        _isLoadingCandidates = true;
        _errorMessage = null;
      });

      final file = File(result.files.single.path!);
      await ZephyrApi().uploadTrack(
        file: file,
        title: widget.exception.title.isNotEmpty
            ? widget.exception.title
            : widget.exception.trackId,
        artists: widget.exception.artists.isNotEmpty
            ? widget.exception.artists.join(', ')
            : 'Unknown Artist',
        targetTrackId: widget.exception.trackId,
      );

      if (mounted) {
        ZephyrToast.show(context, '⚡ Track fulfilled with local audio file!');
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingCandidates = false;
          _errorMessage = 'Failed to fulfill track: $e';
        });
      }
    }
  }

  String _formatDuration(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  Color _getScoreColor(int score) {
    if (score >= 80) return Colors.greenAccent;
    if (score >= 60) return Colors.amberAccent;
    return Colors.orangeAccent;
  }

  String _formatReason(String reason) {
    switch (reason) {
      case 'feat_variant':
        return 'feat. credit normalized';
      case 'version_marker_mismatch':
        return 'version marker mismatch';
      case 'title_exact':
        return 'exact title';
      case 'artist_exact':
        return 'exact artist';
      case 'title_related':
        return 'related title';
      case 'artist_related':
        return 'related artist';
      default:
        return reason.replaceAll('_', ' ');
    }
  }

  Future<void> _selectCandidate(ResolutionCandidate candidate) async {
    setState(() {
      _submittingVideoId = candidate.videoId;
      _errorMessage = null;
    });

    try {
      final activeResId = _resolutionId ?? widget.exception.resolutionId;
      if (widget.isImportResolution && activeResId != null) {
        await ZephyrApi().selectImportResolution(
          activeResId,
          candidate.videoId,
        );
      } else if (activeResId != null) {
        // Generic track resolution selection
        await ZephyrApi().selectTrackCandidate(
          widget.exception.trackId,
          resolutionId: activeResId,
          videoId: candidate.videoId,
        );
      } else {
        // Fallback selection directly with trackId
        await ZephyrApi().selectTrackCandidate(
          widget.exception.trackId,
          resolutionId: null,
          videoId: candidate.videoId,
        );
      }

      ZephyrApi().clearProxyStreamError(widget.exception.trackId);
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        final errStr = e.toString().toLowerCase();
        if (!widget.isImportResolution &&
            (errStr.contains('422') || errStr.contains('invalid_resolution'))) {
          try {
            final track = await ZephyrApi().getTrackMetadata(
              widget.exception.trackId,
            );
            if (track.isDownloaded ||
                track.downloadStatus == 'completed' ||
                track.downloadStatus == 'pending' ||
                track.downloadStatus == 'downloading') {
              ZephyrToast.show(context, 'Track resolved! Starting playback...');
              Navigator.of(context).pop(true);
              return;
            }
          } catch (_) {}
        }
        setState(() {
          _submittingVideoId = null;
          _errorMessage = e.toString();
        });
      }
    }
  }

  Future<void> _cancel() async {
    try {
      if (!widget.isImportResolution && widget.exception.trackId.isNotEmpty) {
        await ZephyrApi().cancelTrackResolution(
          widget.exception.trackId,
          resolutionId: widget.exception.resolutionId,
        );
      }
    } catch (_) {}
    if (mounted) {
      Navigator.of(context).pop(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final exp = widget.exception;
    final isSelectionDisabled =
        exp.resolutionId == null && exp.candidates.isEmpty;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 36),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 620, maxHeight: 720),
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: ZephyrColors.bgCard.withValues(alpha: 0.9),
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
                        Icons.find_in_page_rounded,
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
                            'Match Selection Required',
                            style: TextStyle(
                              color: ZephyrColors.text,
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              letterSpacing: -0.5,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Multiple YouTube Music sources found. Select the correct match.',
                            style: TextStyle(
                              color: ZephyrColors.textDim.withValues(
                                alpha: 0.8,
                              ),
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

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
                      const Icon(
                        Icons.music_note_rounded,
                        color: ZephyrColors.primary,
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              exp.title.isNotEmpty ? exp.title : 'Track Match',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 14.5,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (exp.artists.isNotEmpty)
                              Text(
                                exp.artists.join(', '),
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
                      if (exp.durationSeconds != null &&
                          exp.durationSeconds! > 0)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.3),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            _formatDuration(exp.durationSeconds!),
                            style: const TextStyle(
                              color: ZephyrColors.textDim,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // Custom Search Input Box (Escape hatch)
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        style: const TextStyle(
                          color: ZephyrColors.text,
                          fontSize: 13,
                        ),
                        decoration: InputDecoration(
                          hintText: 'Search custom YouTube Music query...',
                          hintStyle: const TextStyle(
                            color: ZephyrColors.textMuted,
                            fontSize: 13,
                          ),
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          filled: true,
                          fillColor: Colors.black.withValues(alpha: 0.3),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(
                              color: Colors.white.withValues(alpha: 0.1),
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(
                              color: Colors.white.withValues(alpha: 0.1),
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(
                              color: ZephyrColors.primary,
                            ),
                          ),
                        ),
                        onSubmitted: (val) => _performCustomSearch(val),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      onPressed: _isLoadingCandidates
                          ? null
                          : () => _performCustomSearch(_searchController.text),
                      icon: const Icon(
                        Icons.search_rounded,
                        size: 16,
                        color: ZephyrColors.primary,
                      ),
                      label: const Text(
                        'Search',
                        style: TextStyle(
                          color: ZephyrColors.primary,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: ZephyrColors.primary.withValues(
                          alpha: 0.15,
                        ),
                        foregroundColor: ZephyrColors.primary,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                          side: BorderSide(
                            color: ZephyrColors.primary.withValues(alpha: 0.4),
                          ),
                        ),
                        elevation: 0,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                if (_errorMessage != null) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: Colors.redAccent.withValues(alpha: 0.4),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.error_outline_rounded,
                          color: Colors.redAccent,
                          size: 18,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _errorMessage!,
                            style: const TextStyle(
                              color: Colors.redAccent,
                              fontSize: 12.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                ],

                const Text(
                  'CANDIDATES',
                  style: TextStyle(
                    color: ZephyrColors.textDim,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.0,
                  ),
                ),
                const SizedBox(height: 10),

                // Candidates List
                Expanded(
                  child: _isLoadingCandidates
                      ? const Center(
                          child: CircularProgressIndicator(
                            color: ZephyrColors.primary,
                          ),
                        )
                      : _candidates.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                'No candidates available for selection.',
                                style: TextStyle(
                                  color: ZephyrColors.textDim.withValues(
                                    alpha: 0.7,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: ZephyrColors.primary,
                                ),
                                onPressed: _fetchCandidatesFromApi,
                                icon: const Icon(
                                  Icons.refresh,
                                  color: Colors.black,
                                  size: 18,
                                ),
                                label: const Text(
                                  'Fetch Candidates',
                                  style: TextStyle(color: Colors.black),
                                ),
                              ),
                            ],
                          ),
                        )
                      : ListView.separated(
                          shrinkWrap: true,
                          itemCount: _candidates.length,
                          separatorBuilder: (context, index) =>
                              const SizedBox(height: 10),
                          itemBuilder: (context, index) {
                            final c = _candidates[index];
                            final isSubmitting =
                                _submittingVideoId == c.videoId;
                            final isOMV = c.videoType == 'OMV';

                            return Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: ZephyrColors.bgLight.withValues(
                                  alpha: 0.25,
                                ),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: isOMV
                                      ? Colors.purple.withValues(alpha: 0.3)
                                      : Colors.white.withValues(alpha: 0.08),
                                ),
                              ),
                              child: Row(
                                children: [
                                  // Candidate Thumbnail
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child:
                                        c.thumbnail != null &&
                                            c.thumbnail!.isNotEmpty
                                        ? CachedNetworkImage(
                                            imageUrl: c.thumbnail!,
                                            width: 52,
                                            height: 52,
                                            fit: BoxFit.cover,
                                            placeholder: (context, url) =>
                                                Container(
                                                  width: 52,
                                                  height: 52,
                                                  color: ZephyrColors.bgDark,
                                                  child: const Icon(
                                                    Icons.music_note,
                                                    color: ZephyrColors.textDim,
                                                    size: 24,
                                                  ),
                                                ),
                                            errorWidget:
                                                (
                                                  context,
                                                  url,
                                                  error,
                                                ) => Container(
                                                  width: 52,
                                                  height: 52,
                                                  color: ZephyrColors.bgDark,
                                                  child: const Icon(
                                                    Icons.music_note,
                                                    color: ZephyrColors.textDim,
                                                    size: 24,
                                                  ),
                                                ),
                                          )
                                        : Container(
                                            width: 52,
                                            height: 52,
                                            color: ZephyrColors.bgDark,
                                            child: const Icon(
                                              Icons.music_note,
                                              color: ZephyrColors.textDim,
                                              size: 24,
                                            ),
                                          ),
                                  ),
                                  const SizedBox(width: 14),

                                  // Details
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                c.title,
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.w600,
                                                  fontSize: 14,
                                                ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                            const SizedBox(width: 6),
                                            // Match score chip
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 6,
                                                    vertical: 2,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: _getScoreColor(
                                                  c.matchScore,
                                                ).withValues(alpha: 0.15),
                                                borderRadius:
                                                    BorderRadius.circular(6),
                                                border: Border.all(
                                                  color: _getScoreColor(
                                                    c.matchScore,
                                                  ).withValues(alpha: 0.4),
                                                ),
                                              ),
                                              child: Text(
                                                '${c.matchScore}% match',
                                                style: TextStyle(
                                                  color: _getScoreColor(
                                                    c.matchScore,
                                                  ),
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          '${c.artists.join(', ')} • ${_formatDuration(c.durationSeconds)}',
                                          style: const TextStyle(
                                            color: ZephyrColors.textDim,
                                            fontSize: 12,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 6),
                                        Wrap(
                                          spacing: 6,
                                          runSpacing: 4,
                                          children: [
                                            // Video Type Badge
                                            if (isOMV)
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 6,
                                                      vertical: 2,
                                                    ),
                                                decoration: BoxDecoration(
                                                  color: Colors.purple
                                                      .withValues(alpha: 0.2),
                                                  borderRadius:
                                                      BorderRadius.circular(4),
                                                  border: Border.all(
                                                    color: Colors.purpleAccent
                                                        .withValues(alpha: 0.4),
                                                  ),
                                                ),
                                                child: const Row(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: [
                                                    Icon(
                                                      Icons.videocam_rounded,
                                                      color:
                                                          Colors.purpleAccent,
                                                      size: 12,
                                                    ),
                                                    SizedBox(width: 4),
                                                    Text(
                                                      'Official Video (OMV)',
                                                      style: TextStyle(
                                                        color:
                                                            Colors.purpleAccent,
                                                        fontSize: 10.5,
                                                        fontWeight:
                                                            FontWeight.bold,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              )
                                            else
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 6,
                                                      vertical: 1.5,
                                                    ),
                                                margin: const EdgeInsets.only(
                                                  right: 6,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: const Color(
                                                    0xFF06B6D4,
                                                  ).withValues(alpha: 0.15),
                                                  borderRadius:
                                                      BorderRadius.circular(4),
                                                ),
                                                child: const Row(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: [
                                                    Icon(
                                                      Icons.audiotrack_rounded,
                                                      color: Color(0xFF06B6D4),
                                                      size: 12,
                                                    ),
                                                    SizedBox(width: 3),
                                                    Text(
                                                      'Audio Track (ATV)',
                                                      style: TextStyle(
                                                        color: Color(
                                                          0xFF06B6D4,
                                                        ),
                                                        fontSize: 10,
                                                        fontWeight:
                                                            FontWeight.bold,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ...c.matchReasons.map((reason) {
                                              final isFeat =
                                                  reason == 'feat_variant';
                                              final isMismatch =
                                                  reason ==
                                                  'version_marker_mismatch';
                                              final color = isFeat
                                                  ? Colors.tealAccent
                                                  : (isMismatch
                                                        ? Colors.orangeAccent
                                                        : ZephyrColors.textDim);
                                              return Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 6,
                                                      vertical: 2,
                                                    ),
                                                decoration: BoxDecoration(
                                                  color: color.withValues(
                                                    alpha: 0.12,
                                                  ),
                                                  borderRadius:
                                                      BorderRadius.circular(4),
                                                  border: isFeat || isMismatch
                                                      ? Border.all(
                                                          color: color
                                                              .withValues(
                                                                alpha: 0.3,
                                                              ),
                                                        )
                                                      : null,
                                                ),
                                                child: Text(
                                                  _formatReason(reason),
                                                  style: TextStyle(
                                                    color: color,
                                                    fontSize: 10,
                                                    fontWeight:
                                                        isFeat || isMismatch
                                                        ? FontWeight.bold
                                                        : FontWeight.normal,
                                                  ),
                                                ),
                                              );
                                            }),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 12),

                                  // Select Button
                                  ElevatedButton.icon(
                                    onPressed:
                                        (_submittingVideoId != null ||
                                            isSelectionDisabled)
                                        ? null
                                        : () => _selectCandidate(c),
                                    icon: isSubmitting
                                        ? const SizedBox(
                                            width: 14,
                                            height: 14,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              valueColor:
                                                  AlwaysStoppedAnimation<Color>(
                                                    ZephyrColors.bgDark,
                                                  ),
                                            ),
                                          )
                                        : const Icon(
                                            Icons.check_rounded,
                                            size: 15,
                                            color: ZephyrColors.bgDark,
                                          ),
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
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 14,
                                        vertical: 8,
                                      ),
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
                const SizedBox(height: 20),

                // Footer Buttons
                Builder(
                  builder: (context) {
                    final authState = ref.watch(authProvider);
                    final isCuratorOrAdmin =
                        authState.isCurator || authState.isAdmin;
                    return Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        if (isCuratorOrAdmin) ...[
                          ElevatedButton.icon(
                            onPressed:
                                _submittingVideoId != null ||
                                    _isLoadingCandidates
                                ? null
                                : _fulfillWithFile,
                            icon: const Icon(
                              Icons.upload_file_rounded,
                              size: 16,
                            ),
                            label: const Text('Fulfill with Local File'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.indigoAccent,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 10,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                              elevation: 0,
                            ),
                          ),
                          const Spacer(),
                        ],
                        TextButton(
                          onPressed: _submittingVideoId != null
                              ? null
                              : _cancel,
                          style: TextButton.styleFrom(
                            foregroundColor: ZephyrColors.textDim,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 12,
                            ),
                          ),
                          child: const Text('Cancel'),
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
