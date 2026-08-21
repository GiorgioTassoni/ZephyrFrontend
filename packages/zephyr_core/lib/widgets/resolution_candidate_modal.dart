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
  List<ResolutionCandidate> _localMatches = [];
  String? _provider;
  bool _isLoadingCandidates = false;
  String? _submittingVideoId;
  bool _isSkipping = false;
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

  String? _getEffectiveThumbnail(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    if (raw.startsWith('http://') || raw.startsWith('https://')) return raw;
    final base = ZephyrApi().baseUrl;
    return '$base${raw.startsWith('/') ? '' : '/'}$raw';
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
        if (res['provider'] != null) {
          _provider = res['provider'].toString();
        }
        final rawLocal = res['local_matches'];
        List<ResolutionCandidate> fetchedLocal = [];
        if (rawLocal is List) {
          fetchedLocal = rawLocal
              .map((c) => ResolutionCandidate.fromJson(Map<String, dynamic>.from(c)))
              .toList();
        }

        final rawCand =
            res['candidates'] ??
            (res['detail'] is Map ? res['detail']['candidates'] : null);
        if (rawCand is List || rawLocal is List) {
          final fetchedCand = (rawCand is List)
              ? rawCand
                  .map(
                    (c) =>
                        ResolutionCandidate.fromJson(Map<String, dynamic>.from(c)),
                  )
                  .toList()
              : <ResolutionCandidate>[];
          setState(() {
            _localMatches = fetchedLocal;
            _candidates = fetchedCand;
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
      final activeResId = _resolutionId ?? widget.exception.resolutionId;
      final res =
          widget.isImportResolution && activeResId != null
          ? await ZephyrApi().searchImportResolution(
              activeResId,
              query.trim(),
            )
          : await ZephyrApi().searchTrackResolution(
              widget.exception.trackId,
              query.trim(),
            );
      if (res['resolution_id'] != null) {
        _resolutionId = res['resolution_id'].toString();
      }
      if (res['provider'] != null) {
        _provider = res['provider'].toString();
      }

      List<ResolutionCandidate> fetchedLocal = [];
      final rawLocal = res['local_matches'];
      if (rawLocal is List) {
        fetchedLocal = rawLocal
            .map((c) => ResolutionCandidate.fromJson(Map<String, dynamic>.from(c)))
            .toList();
      }

      List<ResolutionCandidate> fetchedCand = [];
      final rawCand = res['candidates'];
      if (rawCand is List) {
        fetchedCand = rawCand
            .map(
              (c) => ResolutionCandidate.fromJson(Map<String, dynamic>.from(c)),
            )
            .toList();
      }
      setState(() {
        _localMatches = fetchedLocal;
        _candidates = fetchedCand;
        _isLoadingCandidates = false;
        if (fetchedCand.isEmpty && fetchedLocal.isEmpty) {
          _errorMessage =
              'No results found for "$query". Try another search term.';
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

      final file = File(result.files.single.path!);
      final trackId = widget.exception.trackId.trim();

      File? coverFile;
      if (trackId.isEmpty) {
        if (!mounted) return;
        ZephyrToast.show(context, 'Please select a cover image for this new track.');
        final coverResult = await FilePicker.platform.pickFiles(
          type: FileType.image,
        );
        if (coverResult == null || coverResult.files.single.path == null) {
          if (mounted) {
            ZephyrToast.show(context, 'Upload cancelled: Cover image is required for new tracks.', isError: true);
          }
          return;
        }
        coverFile = File(coverResult.files.single.path!);
      }

      setState(() {
        _isLoadingCandidates = true;
        _errorMessage = null;
      });

      await ZephyrApi().uploadTrack(
        file: file,
        cover: coverFile,
        title: widget.exception.title.isNotEmpty
            ? widget.exception.title
            : (trackId.isNotEmpty ? trackId : file.path.split(Platform.pathSeparator).last),
        artists: widget.exception.artists.isNotEmpty
            ? widget.exception.artists.join(', ')
            : 'Unknown Artist',
        targetTrackId: trackId.isNotEmpty ? trackId : null,
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

  Widget _buildCandidateCard(
    ResolutionCandidate c, {
    bool isLocal = false,
    bool isSelectionDisabled = false,
  }) {
    final isSubmitting = _submittingVideoId == c.videoId;
    final isOMV = c.videoType == 'OMV';
    final thumbUrl = _getEffectiveThumbnail(c.thumbnail);
    final isMobile = MediaQuery.of(context).size.width < 600;

    final thumbnailWidget = ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: thumbUrl != null && thumbUrl.isNotEmpty
          ? CachedNetworkImage(
              imageUrl: thumbUrl,
              width: isMobile ? 46 : 52,
              height: isMobile ? 46 : 52,
              fit: BoxFit.cover,
              placeholder: (context, url) => Container(
                width: isMobile ? 46 : 52,
                height: isMobile ? 46 : 52,
                color: ZephyrColors.bgDark,
                child: const Icon(
                  Icons.music_note,
                  color: ZephyrColors.textDim,
                  size: 22,
                ),
              ),
              errorWidget: (context, url, error) => Container(
                width: isMobile ? 46 : 52,
                height: isMobile ? 46 : 52,
                color: ZephyrColors.bgDark,
                child: const Icon(
                  Icons.music_note,
                  color: ZephyrColors.textDim,
                  size: 22,
                ),
              ),
            )
          : Container(
              width: isMobile ? 46 : 52,
              height: isMobile ? 46 : 52,
              color: ZephyrColors.bgDark,
              child: Icon(
                isLocal ? Icons.folder_rounded : Icons.music_note,
                color: isLocal ? Colors.tealAccent : ZephyrColors.textDim,
                size: 22,
              ),
            ),
    );

    final detailsColumn = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
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
                maxLines: isMobile ? 2 : 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 6),
            if (isLocal)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.tealAccent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: Colors.tealAccent.withValues(alpha: 0.4),
                  ),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.check_circle_outline_rounded, color: Colors.tealAccent, size: 12),
                    SizedBox(width: 3),
                    Text(
                      'In Library',
                      style: TextStyle(
                        color: Colors.tealAccent,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              )
            else if (c.matchScore > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: _getScoreColor(c.matchScore).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: _getScoreColor(c.matchScore).withValues(alpha: 0.4),
                  ),
                ),
                child: Text(
                  '${c.matchScore}% match',
                  style: TextStyle(
                    color: _getScoreColor(c.matchScore),
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
            if (isLocal)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                decoration: BoxDecoration(
                  color: Colors.teal.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: Colors.tealAccent.withValues(alpha: 0.4),
                  ),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.sd_storage_rounded, color: Colors.tealAccent, size: 12),
                    SizedBox(width: 3),
                    Text(
                      'Local Audio (No Download)',
                      style: TextStyle(
                        color: Colors.tealAccent,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              )
            else if (isOMV)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.purple.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: Colors.purpleAccent.withValues(alpha: 0.4),
                  ),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.videocam_rounded, color: Colors.purpleAccent, size: 12),
                    SizedBox(width: 4),
                    Text(
                      'Official Video (OMV)',
                      style: TextStyle(
                        color: Colors.purpleAccent,
                        fontSize: 10.5,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              )
            else
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                margin: const EdgeInsets.only(right: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFF06B6D4).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.audiotrack_rounded, color: Color(0xFF06B6D4), size: 12),
                    const SizedBox(width: 3),
                    Text(
                      c.provider != null ? '${c.provider!.toUpperCase()} Track' : 'Audio Track (ATV)',
                      style: const TextStyle(
                        color: Color(0xFF06B6D4),
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ...c.matchReasons.map((reason) {
              final isFeat = reason == 'feat_variant';
              final isMismatch = reason == 'version_marker_mismatch';
              final color = isFeat
                  ? Colors.tealAccent
                  : (isMismatch ? Colors.orangeAccent : ZephyrColors.textDim);
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(4),
                  border: isFeat || isMismatch
                      ? Border.all(color: color.withValues(alpha: 0.3))
                      : null,
                ),
                child: Text(
                  _formatReason(reason),
                  style: TextStyle(
                    color: color,
                    fontSize: 10,
                    fontWeight: isFeat || isMismatch ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              );
            }),
          ],
        ),
      ],
    );

    final selectButton = ElevatedButton.icon(
      onPressed: (_submittingVideoId != null || isSelectionDisabled)
          ? null
          : () => _selectCandidate(c),
      icon: isSubmitting
          ? const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(ZephyrColors.bgDark),
              ),
            )
          : const Icon(Icons.check_rounded, size: 15),
      label: Text(
        isSubmitting
            ? (isLocal ? 'Linking...' : 'Selecting...')
            : (isLocal ? 'Link Track' : 'Select Match'),
        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: isLocal ? Colors.tealAccent : ZephyrColors.primary,
        foregroundColor: ZephyrColors.bgDark,
        padding: EdgeInsets.symmetric(
          horizontal: isMobile ? 16 : 14,
          vertical: isMobile ? 11 : 10,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
        elevation: 0,
      ),
    );

    return Container(
      padding: EdgeInsets.all(isMobile ? 12 : 14),
      decoration: BoxDecoration(
        color: isLocal
            ? Colors.teal.withValues(alpha: 0.1)
            : ZephyrColors.bgLight.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isLocal
              ? Colors.tealAccent.withValues(alpha: 0.35)
              : (isOMV
                  ? Colors.purple.withValues(alpha: 0.3)
                  : Colors.white.withValues(alpha: 0.08)),
        ),
      ),
      child: isMobile
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    thumbnailWidget,
                    const SizedBox(width: 12),
                    Expanded(child: detailsColumn),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: selectButton,
                ),
              ],
            )
          : Row(
              children: [
                thumbnailWidget,
                const SizedBox(width: 14),
                Expanded(child: detailsColumn),
                const SizedBox(width: 12),
                selectButton,
              ],
            ),
    );
  }

  Future<void> _selectCandidate(ResolutionCandidate candidate) async {
    final activeResId = _resolutionId ?? widget.exception.resolutionId;
    debugPrint(
      '🎯 [ResolutionModal] User selected candidate: id="${candidate.videoId}", '
      'title="${candidate.title}", provider="${candidate.provider}", '
      'isLocal=${candidate.isLocal}, resolutionId="$activeResId", '
      'isImport=${widget.isImportResolution}',
    );

    setState(() {
      _submittingVideoId = candidate.videoId;
      _errorMessage = null;
    });

    try {
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

  Future<void> _skipSong() async {
    final activeResId = _resolutionId ?? widget.exception.resolutionId;
    if (activeResId == null) {
      Navigator.of(context).pop(false);
      return;
    }

    setState(() {
      _isSkipping = true;
      _errorMessage = null;
    });

    try {
      await ZephyrApi().skipImportResolution(activeResId);
      if (mounted) {
        ZephyrToast.show(context, 'Track skipped from import');
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        final errStr = e.toString().toLowerCase();
        if (errStr.contains('422')) {
          Navigator.of(context).pop(true);
          return;
        }
        setState(() {
          _isSkipping = false;
          _errorMessage = 'Failed to skip song: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final exp = widget.exception;
    final isSelectionDisabled =
        exp.resolutionId == null && exp.candidates.isEmpty;
    final isMobile = MediaQuery.of(context).size.width < 600;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.symmetric(
        horizontal: isMobile ? 10 : 24,
        vertical: isMobile ? 16 : 36,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(isMobile ? 18 : 24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(
            constraints: BoxConstraints(
              maxWidth: 620,
              maxHeight: isMobile
                  ? MediaQuery.of(context).size.height * 0.92
                  : 720,
            ),
            padding: EdgeInsets.all(isMobile ? 16 : 28),
            decoration: BoxDecoration(
              color: ZephyrColors.bgCard.withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(isMobile ? 18 : 24),
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
                      padding: EdgeInsets.all(isMobile ? 8 : 12),
                      decoration: BoxDecoration(
                        color: ZephyrColors.primary.withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.find_in_page_rounded,
                        color: ZephyrColors.primary,
                        size: isMobile ? 20 : 26,
                      ),
                    ),
                    SizedBox(width: isMobile ? 10 : 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Match Selection Required',
                            style: TextStyle(
                              color: ZephyrColors.text,
                              fontSize: isMobile ? 16.5 : 20,
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
                              fontSize: isMobile ? 11.5 : 13,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                SizedBox(height: isMobile ? 12 : 20),

                // Target Track Info Card
                Container(
                  padding: EdgeInsets.all(isMobile ? 10 : 14),
                  decoration: BoxDecoration(
                    color: ZephyrColors.bgLight.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.08),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.music_note_rounded,
                        color: ZephyrColors.primary,
                        size: isMobile ? 18 : 20,
                      ),
                      SizedBox(width: isMobile ? 8 : 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              exp.title.isNotEmpty ? exp.title : 'Track Match',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: isMobile ? 13.5 : 14.5,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (exp.artists.isNotEmpty)
                              Text(
                                exp.artists.join(', '),
                                style: TextStyle(
                                  color: ZephyrColors.textDim,
                                  fontSize: isMobile ? 11.5 : 12.5,
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
                            horizontal: 6,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.3),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            _formatDuration(exp.durationSeconds!),
                            style: TextStyle(
                              color: ZephyrColors.textDim,
                              fontSize: isMobile ? 11 : 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                SizedBox(height: isMobile ? 10 : 12),

                // Custom Search Input Box (Escape hatch)
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        style: TextStyle(
                          color: ZephyrColors.text,
                          fontSize: isMobile ? 12 : 13,
                        ),
                        decoration: InputDecoration(
                          hintText: 'Search custom YouTube Music query...',
                          hintStyle: TextStyle(
                            color: ZephyrColors.textMuted,
                            fontSize: isMobile ? 12 : 13,
                          ),
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: isMobile ? 10 : 14,
                            vertical: isMobile ? 8 : 10,
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
                        size: 15,
                        color: ZephyrColors.primary,
                      ),
                      label: Text(
                        'Search',
                        style: TextStyle(
                          color: ZephyrColors.primary,
                          fontWeight: FontWeight.bold,
                          fontSize: isMobile ? 12 : 13,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: ZephyrColors.primary.withValues(
                          alpha: 0.15,
                        ),
                        foregroundColor: ZephyrColors.primary,
                        padding: EdgeInsets.symmetric(
                          horizontal: isMobile ? 10 : 14,
                          vertical: isMobile ? 8 : 10,
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
                SizedBox(height: isMobile ? 10 : 14),

                if (_errorMessage != null) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
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
                          size: 16,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _errorMessage!,
                            style: const TextStyle(
                              color: Colors.redAccent,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                ],

                // Candidates / Local Matches List
                Expanded(
                  child: _isLoadingCandidates
                      ? const Center(
                          child: CircularProgressIndicator(
                            color: ZephyrColors.primary,
                          ),
                        )
                      : (_candidates.isEmpty && _localMatches.isEmpty)
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
                      : ListView(
                          shrinkWrap: true,
                          children: [
                            // ── 1. Local Matches Section ("Already in your library") ──
                            if (_localMatches.isNotEmpty) ...[
                              Row(
                                children: [
                                  const Icon(
                                    Icons.library_music_rounded,
                                    size: 14,
                                    color: Colors.tealAccent,
                                  ),
                                  const SizedBox(width: 6),
                                  const Text(
                                    'ALREADY IN YOUR LIBRARY',
                                    style: TextStyle(
                                      color: Colors.tealAccent,
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 1.0,
                                    ),
                                  ),
                                  const Spacer(),
                                  Text(
                                    '${_localMatches.length} match${_localMatches.length > 1 ? 'es' : ''}',
                                    style: TextStyle(
                                      color: Colors.tealAccent.withValues(alpha: 0.7),
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              ..._localMatches.map((c) => Padding(
                                    padding: const EdgeInsets.only(bottom: 10),
                                    child: _buildCandidateCard(
                                      c,
                                      isLocal: true,
                                      isSelectionDisabled: isSelectionDisabled,
                                    ),
                                  )),
                              const SizedBox(height: 14),
                            ],

                            // ── 2. Provider Candidates Section ──
                            if (_candidates.isNotEmpty) ...[
                              Row(
                                children: [
                                  Text(
                                    _provider != null
                                        ? '${_provider!.toUpperCase()} RESULTS'
                                        : 'ONLINE CANDIDATES',
                                    style: const TextStyle(
                                      color: ZephyrColors.textDim,
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 1.0,
                                    ),
                                  ),
                                  const Spacer(),
                                  Text(
                                    '${_candidates.length} result${_candidates.length > 1 ? 's' : ''}',
                                    style: const TextStyle(
                                      color: ZephyrColors.textDim,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              ..._candidates.map((c) => Padding(
                                    padding: const EdgeInsets.only(bottom: 10),
                                    child: _buildCandidateCard(
                                      c,
                                      isLocal: false,
                                      isSelectionDisabled: isSelectionDisabled,
                                    ),
                                  )),
                            ],
                          ],
                        ),
                ),
                SizedBox(height: isMobile ? 12 : 20),

                // Footer Buttons (Responsive Wrap layout)
                Builder(
                  builder: (context) {
                    final authState = ref.watch(authProvider);
                    final isCuratorOrAdmin =
                        authState.isCurator || authState.isAdmin;
                    return Align(
                      alignment: Alignment.centerRight,
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        alignment: WrapAlignment.end,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          if (isCuratorOrAdmin)
                            ElevatedButton.icon(
                              onPressed:
                                  _submittingVideoId != null ||
                                      _isLoadingCandidates
                                  ? null
                                  : _fulfillWithFile,
                              icon: const Icon(
                                Icons.upload_file_rounded,
                                size: 15,
                              ),
                              label: const Text('Fulfill with File'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.indigoAccent,
                                foregroundColor: Colors.white,
                                padding: EdgeInsets.symmetric(
                                  horizontal: isMobile ? 10 : 14,
                                  vertical: isMobile ? 8 : 10,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                elevation: 0,
                              ),
                            ),
                          if (widget.isImportResolution)
                            OutlinedButton.icon(
                              onPressed: (_submittingVideoId != null ||
                                      _isSkipping ||
                                      _isLoadingCandidates)
                                  ? null
                                  : _skipSong,
                              icon: _isSkipping
                                  ? const SizedBox(
                                      width: 14,
                                      height: 14,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        valueColor:
                                            AlwaysStoppedAnimation<Color>(
                                          Colors.redAccent,
                                        ),
                                      ),
                                    )
                                  : const Icon(
                                      Icons.skip_next_rounded,
                                      size: 15,
                                      color: Colors.redAccent,
                                    ),
                              label: Text(
                                _isSkipping ? 'Skipping...' : 'Skip Song',
                                style: const TextStyle(
                                  color: Colors.redAccent,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(color: Colors.redAccent),
                                padding: EdgeInsets.symmetric(
                                  horizontal: isMobile ? 10 : 14,
                                  vertical: isMobile ? 8 : 10,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                            ),
                          TextButton(
                            onPressed: _submittingVideoId != null || _isSkipping
                                ? null
                                : _cancel,
                            style: TextButton.styleFrom(
                              foregroundColor: ZephyrColors.textDim,
                              padding: EdgeInsets.symmetric(
                                horizontal: isMobile ? 12 : 20,
                                vertical: isMobile ? 8 : 12,
                              ),
                            ),
                            child: const Text('Cancel'),
                          ),
                        ],
                      ),
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
