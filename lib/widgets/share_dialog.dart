import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/models.dart';
import '../theme/colors.dart';
import 'toast.dart';

void showShareDialog(BuildContext context, WidgetRef ref, Track track) {
  final zephyrLink = 'zephyr://track/${track.videoId}';
  final ytLink = 'https://music.youtube.com/watch?v=${track.videoId}';
  final artistText = track.artists.isNotEmpty ? track.artists.join(', ') : 'Unknown Artist';

  showDialog(
    context: context,
    builder: (context) {
      return Dialog(
        backgroundColor: ZephyrColors.bgCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Container(
          width: 420,
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Share Song',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: ZephyrColors.text,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: ZephyrColors.textDim),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '${track.title} • $artistText',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 14,
                  color: ZephyrColors.textDim,
                ),
              ),
              const SizedBox(height: 24),

              // Option 1: Zephyr App Link
              _ShareOptionCard(
                icon: Icons.electric_bolt_rounded,
                iconColor: ZephyrColors.primary,
                title: 'Share Zephyr Link',
                subtitle: zephyrLink,
                description: 'Opens directly in Zephyr player app',
                onTap: () {
                  final text = 'Listening to "${track.title}" by $artistText on Zephyr\n$zephyrLink';
                  Clipboard.setData(ClipboardData(text: text));
                  Navigator.of(context).pop();
                  ZephyrToast.show(context, 'Zephyr link copied to clipboard!');
                },
              ),

              const SizedBox(height: 12),

              // Option 2: YouTube Music Link
              _ShareOptionCard(
                icon: Icons.play_circle_fill_rounded,
                iconColor: const Color(0xFFFF3B30),
                title: 'Share YouTube Music Link',
                subtitle: ytLink,
                description: 'Opens in web browser or YouTube Music app',
                onTap: () {
                  final text = 'Listening to "${track.title}" by $artistText\n$ytLink';
                  Clipboard.setData(ClipboardData(text: text));
                  Navigator.of(context).pop();
                  ZephyrToast.show(context, 'YouTube Music link copied to clipboard!');
                },
              ),
            ],
          ),
        ),
      );
    },
  );
}

class _ShareOptionCard extends StatefulWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final String description;
  final VoidCallback onTap;

  const _ShareOptionCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.description,
    required this.onTap,
  });

  @override
  State<_ShareOptionCard> createState() => _ShareOptionCardState();
}

class _ShareOptionCardState extends State<_ShareOptionCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _isHovered ? ZephyrColors.bgLight : ZephyrColors.bgDark,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _isHovered ? ZephyrColors.primary.withValues(alpha: 0.5) : ZephyrColors.bgLight,
              width: 1.5,
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: widget.iconColor.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(widget.icon, color: widget.iconColor, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: ZephyrColors.text,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      widget.description,
                      style: const TextStyle(
                        fontSize: 12,
                        color: ZephyrColors.textDim,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.copy_rounded, color: ZephyrColors.textDim, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}
