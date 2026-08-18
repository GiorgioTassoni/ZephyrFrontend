# 🎨 THE ZEPHYR ART BIBLE & DESIGN SYSTEM

This rule defines the strict design system, visual hierarchy, typography, colors, and component styles for the entire **Zephyr** application.

---

## 1. 🌈 Color Palette (`ZephyrColors` & `ZephyrTheme`)

| Color Token | Hex / Value | Usage |
| :--- | :--- | :--- |
| **`primary`** | `#F59E0B` (Amber) | Brand identity, primary CTAs, active player highlights, selection pills |
| **`bgDark`** | `#121212` / `#12131C` | Scaffold background, dark canvas, main application backdrop |
| **`bgCard`** | `#1E1E1E` / `#181924` | Dialog containers, card surfaces, modal background |
| **`bgLight`** | `#282828` / `#222433` | Input fields, active row hover background, elevated list items |
| **`accentAudio`** | `#06B6D4` (Cyan/Teal) | Audio Track (ATV) badges & audio metadata indicators |
| **`accentVideo`** | `#8B5CF6` (Purple) | Music Video (OMV) badges & video indicators |
| **`accentSuccess`** | `#10B981` (Emerald) | High match scores ($\ge 80\%$), completed downloads, successful resolutions |
| **`accentInfo`** | `#3B82F6` (Vibrant Blue) | Medium match scores ($60-79\%$), informational badges |
| **`accentMuted`** | `#94A3B8` (Slate Grey) | Low match scores ($<60\%$), muted tags |
| **`textPrimary`** | `#FFFFFF` (White) | Main titles, active labels, track names |
| **`textSecondary`**| `#B3B3B3` (Light Grey) | Subtitles, artist names, metadata details |
| **`textMuted`** | `#727272` (Muted Grey) | Timestamps, placeholder text, hints |

---

## 2. 🔤 Typography & Hierarchy

- **Page Titles / H1**: 24px, Bold, `-0.5px` letter spacing.
- **Modal Header / H2**: 20px, Bold, `-0.4px` letter spacing.
- **Card Title / H3**: 16px, Semi-Bold (`w600`).
- **Track Title / List Bold**: 14px, Bold.
- **Body Text**: 13px–14px, Regular.
- **Metadata & Subtitle**: 12.5px, Regular (`textSecondary`).
- **Badges**: 10px, Bold, Cyan (`#06B6D4`) for ATV, Purple (`#8B5CF6`) for OMV.
- **Button Text**: 12px–13px, Bold, dark text (`#121212`) on solid amber, amber text on glass buttons.

---

## 3. 🔘 Control & Button Hierarchy

1. **Primary Action Button (`StadiumBorder()`)**:
   - Shape: Capsule / Stadium Pill (`StadiumBorder()`).
   - Background: `ZephyrColors.primary` (#F59E0B).
   - Text & Icon: `ZephyrColors.bgDark` (#121212), Bold.
   - Example: Candidate `[ ✓ Select ]` pill buttons.

2. **Secondary / Query Action Button (`Glass Outlined`)**:
   - Background: `primary.withValues(alpha: 0.15)`.
   - Border: `primary.withValues(alpha: 0.4)`.
   - Text & Icon: `ZephyrColors.primary` (#F59E0B), Bold.
   - Example: Search query button next to search inputs.

3. **Segmented Navigation Tabs**:
   - Active Tab: `ZephyrColors.bgCard` with subtle glowing amber border (`primary 60%`), white text, amber icon.
   - Inactive Tab: Transparent background with `textDim` text.

---

## 4. 📐 Geometry & Corner Radius

- **Modal / Dialog Windows**: `24px` radius + `BackdropFilter` glass blur (sigma 16).
- **Cards & Row Tiles**: `14px` radius.
- **Search Fields & Inputs**: `10px` radius.
- **Primary Buttons**: `StadiumBorder()` (Capsule pill).
- **Badges**: `4px` - `6px` radius.

---

## 5. ✨ Card Hover Interactions & Motion

- **Card Background**: Static `ZephyrColors.bgCard` (no inner background fill fade on hover).
- **Position & Scale**: Zero positional translation and zero scale movement on hover (cards stay fixed in place).
- **Card Drop Shadow**: Static subtle drop shadow (no outer shadow glow fade on hover).
- **Hover Visual Indicator**: Crisp amber border highlight (`ZephyrColors.primary` at `0.7–0.8` alpha) only.

---

## 6. 🛠️ Code Reference

All components should consume design tokens directly from:
`lib/theme/zephyr_theme.dart` & `lib/theme/colors.dart`
