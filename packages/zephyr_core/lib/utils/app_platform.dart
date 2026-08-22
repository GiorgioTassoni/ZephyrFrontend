/// Runtime platform profile for behavior subdivision.
///
/// The shared core contains no `Platform.is*` branching for behavioral
/// decisions. Instead, each app shell declares its form factor once at
/// startup in its own main(), and shared code queries [AppPlatform]:
///
///   - apps/zephyr_desktop  -> ZephyrFormFactor.desktop
///   - apps/zephyr_mobile   -> ZephyrFormFactor.mobile
///
/// Defaults to [ZephyrFormFactor.mobile] so tests and widgets that run
/// without a shell bootstrap behave like the mobile app.
library;

enum ZephyrFormFactor { mobile, desktop }

class AppPlatform {
  AppPlatform._();

  /// Declared by the running shell before runApp().
  static ZephyrFormFactor formFactor = ZephyrFormFactor.mobile;

  static bool get isDesktop => formFactor == ZephyrFormFactor.desktop;
  static bool get isMobile => formFactor == ZephyrFormFactor.mobile;
}
