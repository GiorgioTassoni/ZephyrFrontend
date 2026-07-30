import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../api/zephyr_api.dart';
import '../models/models.dart';
import '../providers/navigation_provider.dart';
import '../theme/colors.dart';

class ArtistLinks extends ConsumerWidget {
  final Track track;
  final TextStyle? style;
  final TextOverflow overflow;
  final int maxLines;
  final VoidCallback? onNavigate;

  const ArtistLinks({
    super.key,
    required this.track,
    this.style,
    this.overflow = TextOverflow.ellipsis,
    this.maxLines = 1,
    this.onNavigate,
  });

  static Future<void> handleTap({
    required BuildContext context,
    required WidgetRef ref,
    required String name,
    required String? channelId,
    VoidCallback? onNavigate,
  }) async {
    if (onNavigate != null) onNavigate();
    final navNotifier = ref.read(navigationProvider.notifier);

    // 1. Direct channelId
    if (channelId != null && channelId.isNotEmpty) {
      navNotifier.navigateTo(ScreenState(type: ScreenType.artist, id: channelId));
      return;
    }

    // 2. Query GET /api/artists/by-name/{name}
    try {
      final res = await ZephyrApi().getArtistByName(name);
      final id = (res['id'] ?? res['channel_id'] ?? res['browse_id'] ?? res['channelId'])?.toString();
      if (id != null && id.isNotEmpty) {
        navNotifier.navigateTo(ScreenState(type: ScreenType.artist, id: id));
        return;
      }
    } catch (_) {}

    // 3. Search YTMusic remotely for artist channel (remote: true)
    try {
      final searchRes = await ZephyrApi().search(name, remote: true);
      final results = searchRes['results'];
      List<dynamic> artists = [];
      if (results is Map && results.containsKey('artists')) {
        artists = (results['artists'] as List?) ?? [];
      } else if (searchRes['artists'] is List) {
        artists = searchRes['artists'] as List;
      }

      if (artists.isNotEmpty) {
        final firstArtist = artists.first;
        final id = (firstArtist['id'] ?? firstArtist['channel_id'] ?? firstArtist['browse_id'] ?? firstArtist['channelId'])?.toString();
        if (id != null && id.isNotEmpty) {
          navNotifier.navigateTo(ScreenState(type: ScreenType.artist, id: id));
          return;
        }
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final baseStyle = style ?? const TextStyle(fontSize: 12, color: ZephyrColors.textDim);
    final validArtists = track.artists.where((a) => a.trim().isNotEmpty).toList();

    if (validArtists.isEmpty) {
      return Text('Unknown Artist', style: baseStyle, maxLines: maxLines, overflow: overflow);
    }

    final children = <InlineSpan>[];

    for (int i = 0; i < validArtists.length; i++) {
      final name = validArtists[i];
      final hasId = i < track.artistsIds.length && track.artistsIds[i].isNotEmpty;
      final channelId = hasId ? track.artistsIds[i] : null;

      children.add(
        WidgetSpan(
          alignment: PlaceholderAlignment.baseline,
          baseline: TextBaseline.alphabetic,
          child: _ClickableArtistItem(
            name: name,
            style: baseStyle,
            onTap: () => handleTap(
              context: context,
              ref: ref,
              name: name,
              channelId: channelId,
              onNavigate: onNavigate,
            ),
          ),
        ),
      );

      if (i < validArtists.length - 1) {
        children.add(TextSpan(text: ', ', style: baseStyle));
      }
    }

    return Text.rich(
      TextSpan(children: children),
      maxLines: maxLines,
      overflow: overflow,
    );
  }
}

class _ClickableArtistItem extends StatefulWidget {
  final String name;
  final TextStyle style;
  final VoidCallback onTap;

  const _ClickableArtistItem({
    required this.name,
    required this.style,
    required this.onTap,
  });

  @override
  State<_ClickableArtistItem> createState() => _ClickableArtistItemState();
}

class _ClickableArtistItemState extends State<_ClickableArtistItem> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Text(
          widget.name,
          style: widget.style.copyWith(
            decoration: _isHovered ? TextDecoration.underline : TextDecoration.none,
            color: _isHovered ? ZephyrColors.text : widget.style.color,
          ),
        ),
      ),
    );
  }
}
