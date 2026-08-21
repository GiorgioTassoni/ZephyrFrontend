import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/zephyr_api.dart';
import '../providers/auth_provider.dart';
import '../providers/player_provider.dart';
import '../screens/change_password_screen.dart';
import '../screens/login_screen.dart';
import '../screens/main_layout.dart';
import '../theme/colors.dart';
import '../utils/app_logger.dart';
import '../utils/root_navigator.dart';

/// Root application widget shared by every Zephyr shell (Android, Desktop).
///
/// Handles auth gating, forced password rotation and optional deep-link
/// entry (initialVideoId). Shells provide platform bootstrap in their own
/// main() and simply run `ProviderScope(child: ZephyrApp(...))`.
class ZephyrApp extends ConsumerStatefulWidget {
  final String? initialVideoId;
  const ZephyrApp({super.key, this.initialVideoId});

  @override
  ConsumerState<ZephyrApp> createState() => _ZephyrAppState();
}

class _ZephyrAppState extends ConsumerState<ZephyrApp> with WidgetsBindingObserver {
  bool _handledInitialDeepLink = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    AppLogger.instance.logLifecycle(state.name);
  }

  void _handleDeepLink(String videoId) async {
    if (_handledInitialDeepLink) return;
    _handledInitialDeepLink = true;

    try {
      final metadata = await ZephyrApi().getTrackMetadata(videoId);
      if (mounted) {
        ref.read(playerProvider.notifier).playTrack(metadata, [metadata]);
      }
    } catch (_) {
      // ignore
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAuthenticated = ref.watch(authProvider.select((s) => s.isAuthenticated));
    final isLoading = ref.watch(authProvider.select((s) => s.isLoading));
    final mustChangePassword = ref.watch(authProvider.select((s) => s.mustChangePassword));

    if (isAuthenticated && widget.initialVideoId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _handleDeepLink(widget.initialVideoId!);
      });
    }

    Widget homeWidget;
    if (isLoading) {
      homeWidget = const ZephyrSplash();
    } else if (isAuthenticated && mustChangePassword) {
      // S-07: block all navigation until password rotation is done
      homeWidget = const ChangePasswordScreen();
    } else if (isAuthenticated) {
      homeWidget = const MainLayout();
    } else {
      homeWidget = const LoginScreen();
    }

    return MaterialApp(
      navigatorKey: rootNavigatorKey,
      title: 'Zephyr self-hosted music player',
      debugShowCheckedModeBanner: false,
      theme: ZephyrColors.darkTheme,
      home: homeWidget,
    );
  }
}

// Gorgeous loading/splash screen that shows while verifying cached tokens
class ZephyrSplash extends StatelessWidget {
  const ZephyrSplash({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ZephyrColors.bgDark,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset(
              'References/Zephyr_trasp.png',
              width: 100,
              height: 100,
              errorBuilder: (context, error, stackTrace) => const Icon(
                Icons.music_note,
                color: ZephyrColors.primary,
                size: 100,
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'ZEPHYR',
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.w900,
                letterSpacing: 2.0,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 24),
            const SizedBox(
              width: 40,
              child: LinearProgressIndicator(
                backgroundColor: ZephyrColors.bgLight,
                valueColor: AlwaysStoppedAnimation<Color>(ZephyrColors.primary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
