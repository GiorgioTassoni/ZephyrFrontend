import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/player_provider.dart';
import '../theme/colors.dart';
import '../screens/player_screen.dart';
import 'cover_image.dart';
import 'artist_links.dart';
import 'devices_modal.dart';

class MiniPlayer extends ConsumerWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playerState = ref.watch(playerProvider);
    final playerNotifier = ref.read(playerProvider.notifier);

    if (playerState.currentTrack == null) {
      return const SizedBox.shrink();
    }

    final track = playerState.currentTrack!;
    final effDur = playerState.effectiveDuration;
    final progress = effDur.inMilliseconds > 0
        ? playerState.position.inMilliseconds / effDur.inMilliseconds
        : 0.0;

    return Dismissible(
      key: const ValueKey('persistent_mini_player'),
      direction: DismissDirection.horizontal,
      confirmDismiss: (direction) async {
        if (direction == DismissDirection.endToStart) {
          playerNotifier.playNext();
          HapticFeedback.lightImpact();
        } else if (direction == DismissDirection.startToEnd) {
          playerNotifier.playPrevious();
          HapticFeedback.lightImpact();
        }
        return false;
      },
      background: Container(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: 24),
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: ZephyrColors.bgCard,
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Icon(Icons.skip_previous, color: ZephyrColors.primary, size: 28),
      ),
      secondaryBackground: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: ZephyrColors.bgCard,
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Icon(Icons.skip_next, color: ZephyrColors.primary, size: 28),
      ),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          Navigator.of(context).push(
            PageRouteBuilder(
              pageBuilder: (context, animation, secondaryAnimation) => const PlayerScreen(),
              transitionsBuilder: (context, animation, secondaryAnimation, child) {
                const begin = Offset(0.0, 1.0);
                const end = Offset.zero;
                const curve = Curves.easeOutCubic;
                var tween = Tween(begin: begin, end: end).chain(CurveTween(curve: curve));
                return SlideTransition(
                  position: animation.drive(tween),
                  child: child,
                );
              },
            ),
          );
        },
        child: Container(
          height: 64,
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: ZephyrColors.bgCard,
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.4),
                blurRadius: 10,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: Column(
            children: [
              Expanded(
                child: Row(
                  children: [
                    const SizedBox(width: 8),
                    CoverImage(
                      videoId: track.videoId,
                      coverUrl: track.coverUrl,
                      size: 48,
                      borderRadius: 4,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            track.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                              color: ZephyrColors.text,
                            ),
                          ),
                          Row(
                            children: [
                              Expanded(
                                child: ArtistLinks(
                                  track: track,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: ZephyrColors.textDim,
                                  ),
                                ),
                              ),
                              if (!playerState.isPlayerDevice && playerState.activeDeviceName != null)
                                GestureDetector(
                                  onTap: () => DevicesModal.show(context),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: ZephyrColors.primary.withValues(alpha: 0.2),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(Icons.devices, size: 12, color: ZephyrColors.primary),
                                        const SizedBox(width: 4),
                                        Text(
                                          playerState.activeDeviceName!,
                                          style: const TextStyle(
                                            fontSize: 10,
                                            color: ZephyrColors.primary,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    if (!playerState.isPlayerDevice)
                      IconButton(
                        icon: const Icon(
                          Icons.phonelink,
                          color: ZephyrColors.primary,
                          size: 22,
                        ),
                        tooltip: 'Play on this device',
                        onPressed: () => playerNotifier.takeoverPlayback(force: true),
                      ),
                    if (playerState.isLoading)
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 16.0),
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(ZephyrColors.primary),
                          ),
                        ),
                      )
                    else
                      IconButton(
                        icon: Icon(
                          playerState.isPlaying ? Icons.pause : Icons.play_arrow,
                          color: ZephyrColors.text,
                          size: 30,
                        ),
                        onPressed: () => playerNotifier.togglePlayPause(),
                      ),
                    const SizedBox(width: 8),
                  ],
                ),
              ),
              // Progress Bar at the bottom
              SizedBox(
                height: 2,
                child: LinearProgressIndicator(
                  value: progress,
                  backgroundColor: ZephyrColors.bgLight,
                  valueColor: const AlwaysStoppedAnimation<Color>(ZephyrColors.primary),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
