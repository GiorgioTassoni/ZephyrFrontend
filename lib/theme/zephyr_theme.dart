import 'package:flutter/material.dart';
import 'colors.dart';

/// Centralized Design System & Design Tokens for Zephyr (Art Bible)
class ZephyrTheme {
  // --- COLOR TOKENS ---
  static const Color primary = ZephyrColors.primary; // #F59E0B Amber
  static const Color primaryLight = Color(0xFFFBBF24);
  static Color primaryGlass = ZephyrColors.primary.withValues(alpha: 0.15);

  static const Color bgDark = ZephyrColors.bgDark;   // #121212
  static const Color bgCard = ZephyrColors.bgCard;   // #1E1E1E
  static const Color bgLight = ZephyrColors.bgLight; // #282828

  // Accents
  static const Color accentAudio = Color(0xFF06B6D4);   // Cyan/Teal (ATV)
  static const Color accentVideo = Color(0xFF8B5CF6);   // Purple (OMV)
  static const Color accentSuccess = Color(0xFF10B981); // Emerald Green (80%+ match)
  static const Color accentInfo = Color(0xFF3B82F6);    // Blue (60-79% match)
  static const Color accentMuted = Color(0xFF94A3B8);   // Slate Grey (<60% match)

  // Text Colors
  static const Color textPrimary = ZephyrColors.text;
  static const Color textSecondary = ZephyrColors.textDim;
  static const Color textMuted = ZephyrColors.textMuted;

  // --- TYPOGRAPHY SCALE ---
  static const TextStyle displayH1 = TextStyle(
    color: textPrimary,
    fontSize: 24,
    fontWeight: FontWeight.bold,
    letterSpacing: 0.0,
  );

  static const TextStyle dialogTitleH2 = TextStyle(
    color: textPrimary,
    fontSize: 20,
    fontWeight: FontWeight.bold,
    letterSpacing: 0.0,
  );

  static const TextStyle sectionTitleH3 = TextStyle(
    color: textPrimary,
    fontSize: 16,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.0,
  );

  static const TextStyle bodyBold = TextStyle(
    color: textPrimary,
    fontSize: 14,
    fontWeight: FontWeight.bold,
  );

  static const TextStyle bodyRegular = TextStyle(
    color: textPrimary,
    fontSize: 13,
    fontWeight: FontWeight.normal,
  );

  static const TextStyle captionDim = TextStyle(
    color: textSecondary,
    fontSize: 12.5,
    fontWeight: FontWeight.normal,
  );

  static const TextStyle badgeLabel = TextStyle(
    fontSize: 10,
    fontWeight: FontWeight.bold,
    letterSpacing: 0.2,
  );

  // --- STYLED BUTTON BUILDERS ---
  
  /// Primary Action Capsule Pill Button ([ ✓ Select ])
  static ButtonStyle primaryPillStyle() {
    return ElevatedButton.styleFrom(
      backgroundColor: primary,
      foregroundColor: bgDark,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      shape: const StadiumBorder(),
      elevation: 0,
    );
  }

  /// Secondary Outlined Glass Button (Search query, secondary actions)
  static ButtonStyle glassOutlinedStyle({Color accentColor = primary}) {
    return ElevatedButton.styleFrom(
      backgroundColor: accentColor.withValues(alpha: 0.15),
      foregroundColor: accentColor,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: accentColor.withValues(alpha: 0.4)),
      ),
      elevation: 0,
    );
  }

  // --- BADGE BUILDERS ---

  /// ATV (Audio Track) Badge Widget
  static Widget atvBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
      margin: const EdgeInsets.only(right: 6),
      decoration: BoxDecoration(
        color: accentAudio.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.audiotrack_rounded, color: accentAudio, size: 12),
          SizedBox(width: 3),
          Text(
            'Audio Track (ATV)',
            style: TextStyle(
              color: accentAudio,
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  /// OMV (Music Video) Badge Widget
  static Widget omvBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
      margin: const EdgeInsets.only(right: 6),
      decoration: BoxDecoration(
        color: accentVideo.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.videocam_rounded, color: accentVideo, size: 12),
          SizedBox(width: 3),
          Text(
            'Music Video (OMV)',
            style: TextStyle(
              color: accentVideo,
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  /// Match Score Badge Widget
  static Widget matchScoreBadge(int score) {
    Color color;
    if (score >= 80) {
      color = accentSuccess;
    } else if (score >= 60) {
      color = accentInfo;
    } else {
      color = accentMuted;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        '$score% match',
        style: TextStyle(
          color: color,
          fontSize: 10.5,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
