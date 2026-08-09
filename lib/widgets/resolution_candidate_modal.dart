import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../api/zephyr_api.dart';
import '../models/models.dart';
import '../theme/colors.dart';

class ResolutionCandidateModal extends StatefulWidget {
  final ResolutionRequiredException exception;

  const ResolutionCandidateModal({
    super.key,
    required this.exception,
  });

  static Future<bool?> show(BuildContext context, ResolutionRequiredException exception) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => ResolutionCandidateModal(exception: exception),
    );
  }

  @override
  State<ResolutionCandidateModal> createState() => _ResolutionCandidateModalState();
}

class _ResolutionCandidateModalState extends State<ResolutionCandidateModal> {
  String? _submittingVideoId;
  String? _errorMessage;

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

  Future<void> _selectCandidate(ResolutionCandidate candidate) async {
    setState(() {
      _submittingVideoId = candidate.videoId;
      _errorMessage = null;
    });

    try {
      if (widget.exception.resolutionId != null) {
        // Generic track resolution selection
        await ZephyrApi().selectTrackCandidate(
          widget.exception.trackId,
          resolutionId: widget.exception.resolutionId,
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

      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _submittingVideoId = null;
          _errorMessage = e.toString();
        });
      }
    }
  }

  Future<void> _cancel() async {
    try {
      if (widget.exception.trackId.isNotEmpty) {
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
    final isSelectionDisabled = exp.resolutionId == null && exp.candidates.isEmpty;

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
                              color: ZephyrColors.textDim.withValues(alpha: 0.8),
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
                      const Icon(Icons.music_note_rounded, color: ZephyrColors.primary, size: 20),
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
                      if (exp.durationSeconds != null && exp.durationSeconds! > 0)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
                const SizedBox(height: 16),

                if (_errorMessage != null) ...[
                  Container(
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
                  child: exp.candidates.isEmpty
                      ? Center(
                          child: Text(
                            'No candidates available for selection.',
                            style: TextStyle(color: ZephyrColors.textDim.withValues(alpha: 0.7)),
                          ),
                        )
                      : ListView.separated(
                          shrinkWrap: true,
                          itemCount: exp.candidates.length,
                          separatorBuilder: (context, index) => const SizedBox(height: 10),
                          itemBuilder: (context, index) {
                            final c = exp.candidates[index];
                            final isSubmitting = _submittingVideoId == c.videoId;
                            final isOMV = c.videoType == 'OMV';

                            return Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: ZephyrColors.bgLight.withValues(alpha: 0.25),
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
                                    child: c.thumbnail != null && c.thumbnail!.isNotEmpty
                                        ? CachedNetworkImage(
                                            imageUrl: c.thumbnail!,
                                            width: 52,
                                            height: 52,
                                            fit: BoxFit.cover,
                                            placeholder: (context, url) => Container(
                                              width: 52,
                                              height: 52,
                                              color: ZephyrColors.bgDark,
                                              child: const Icon(Icons.music_note, color: ZephyrColors.textDim, size: 24),
                                            ),
                                            errorWidget: (context, url, error) => Container(
                                              width: 52,
                                              height: 52,
                                              color: ZephyrColors.bgDark,
                                              child: const Icon(Icons.music_note, color: ZephyrColors.textDim, size: 24),
                                            ),
                                          )
                                        : Container(
                                            width: 52,
                                            height: 52,
                                            color: ZephyrColors.bgDark,
                                            child: const Icon(Icons.music_note, color: ZephyrColors.textDim, size: 24),
                                          ),
                                  ),
                                  const SizedBox(width: 14),

                                  // Details
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
                                            // Video Type Badge
                                            if (isOMV)
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                decoration: BoxDecoration(
                                                  color: Colors.purple.withValues(alpha: 0.2),
                                                  borderRadius: BorderRadius.circular(4),
                                                  border: Border.all(color: Colors.purpleAccent.withValues(alpha: 0.4)),
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
                                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                decoration: BoxDecoration(
                                                  color: ZephyrColors.primary.withValues(alpha: 0.15),
                                                  borderRadius: BorderRadius.circular(4),
                                                ),
                                                child: const Row(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    Icon(Icons.audiotrack_rounded, color: ZephyrColors.primary, size: 12),
                                                    SizedBox(width: 4),
                                                    Text(
                                                      'Audio Track (ATV)',
                                                      style: TextStyle(
                                                        color: ZephyrColors.primary,
                                                        fontSize: 10.5,
                                                        fontWeight: FontWeight.bold,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ...c.matchReasons.map(
                                              (reason) => Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                decoration: BoxDecoration(
                                                  color: Colors.white.withValues(alpha: 0.06),
                                                  borderRadius: BorderRadius.circular(4),
                                                ),
                                                child: Text(
                                                  reason,
                                                  style: TextStyle(
                                                    color: ZephyrColors.textDim.withValues(alpha: 0.8),
                                                    fontSize: 10,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 12),

                                  // Select Button
                                  ElevatedButton(
                                    onPressed: (_submittingVideoId != null || isSelectionDisabled)
                                        ? null
                                        : () => _selectCandidate(c),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: ZephyrColors.primary,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      elevation: 0,
                                    ),
                                    child: isSubmitting
                                        ? const SizedBox(
                                            width: 16,
                                            height: 16,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                            ),
                                          )
                                        : const Text('Select', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold)),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
                const SizedBox(height: 20),

                // Footer Buttons
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: _submittingVideoId != null ? null : _cancel,
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
