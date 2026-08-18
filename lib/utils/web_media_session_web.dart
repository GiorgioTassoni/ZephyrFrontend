// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import '../api/zephyr_api.dart';
import '../models/models.dart';

void updateWebMediaSession(Track? track, dynamic playerNotifier) {
  if (track == null) return;
  try {
    final mediaSession = html.window.navigator.mediaSession;
    if (mediaSession != null) {
      final api = ZephyrApi();
      String art = track.coverUrl ?? '';
      if (art.isNotEmpty && art.startsWith('/')) {
        art = '${api.baseUrl}$art';
      }

      mediaSession.metadata = html.MediaMetadata({
        'title': track.title,
        'artist': track.artists.join(', '),
        'album': track.album ?? 'Zephyr',
        'artwork': art.isNotEmpty ? [{'src': art, 'sizes': '512x512', 'type': 'image/jpeg'}] : [],
      });

      mediaSession.setActionHandler('play', ([_]) => playerNotifier.togglePlayPause());
      mediaSession.setActionHandler('pause', ([_]) => playerNotifier.togglePlayPause());
      mediaSession.setActionHandler('previoustrack', ([_]) => playerNotifier.playPrevious());
      mediaSession.setActionHandler('nexttrack', ([_]) => playerNotifier.playNext());
      mediaSession.setActionHandler('seekbackward', ([_]) => playerNotifier.seekRelative(-5));
      mediaSession.setActionHandler('seekforward', ([_]) => playerNotifier.seekRelative(5));
      mediaSession.setActionHandler('stop', ([_]) => playerNotifier.pause());
    }
  } catch (_) {}
}
