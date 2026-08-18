import 'package:flutter/foundation.dart';
import 'package:flutter_carplay/flutter_carplay.dart';

/// Service to handle Apple CarPlay template UI (ListTemplate, GridTemplate, NowPlaying).
class ZephyrCarPlayService {
  static final ZephyrCarPlayService _instance = ZephyrCarPlayService._internal();
  factory ZephyrCarPlayService() => _instance;
  ZephyrCarPlayService._internal();

  bool _isInitialized = false;

  /// Initialize CarPlay controller for iOS
  void init({
    required VoidCallback onOpenFavorites,
    required VoidCallback onOpenPlaylists,
  }) {
    if (defaultTargetPlatform != TargetPlatform.iOS || _isInitialized) return;

    try {
      FlutterCarplay.setRootTemplate(
        rootTemplate: CPTabBarTemplate(
          templates: [
            CPListTemplate(
              title: 'Library',
              systemIcon: 'music.note.list',
              sections: [
                CPListSection(
                  items: [
                    CPListItem(
                      text: 'Favorite Songs',
                      detailText: 'Your liked tracks',
                      onPress: (complete, self) {
                        onOpenFavorites();
                        complete();
                      },
                    ),
                    CPListItem(
                      text: 'Your Playlists',
                      detailText: 'Custom playlist library',
                      onPress: (complete, self) {
                        onOpenPlaylists();
                        complete();
                      },
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      );
      _isInitialized = true;
    } catch (e) {
      debugPrint('CarPlay init notice: $e');
    }
  }
}
