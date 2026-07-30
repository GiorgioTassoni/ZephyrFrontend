import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'api/zephyr_api.dart';
import 'providers/auth_provider.dart';
import 'providers/player_provider.dart';
import 'screens/change_password_screen.dart';
import 'screens/login_screen.dart';
import 'screens/main_layout.dart';
import 'theme/colors.dart';

String? _extractVideoIdFromDeepLink(String rawUrl) {
  try {
    final uri = Uri.parse(rawUrl);
    if (uri.scheme == 'zephyr') {
      if (uri.host == 'track' && uri.pathSegments.isNotEmpty) {
        return uri.pathSegments.first;
      } else if (uri.path.contains('/track/')) {
        final parts = uri.path.split('/track/');
        if (parts.length > 1) return parts[1].split('/')[0];
      } else if (uri.queryParameters.containsKey('v')) {
        return uri.queryParameters['v'];
      }
    } else if (uri.path.contains('/track/')) {
      final parts = uri.path.split('/track/');
      if (parts.length > 1) return parts[1].split('/')[0];
    }
  } catch (_) {}
  return null;
}

void main(List<String> args) {
  WidgetsFlutterBinding.ensureInitialized();
  
  String? initialVideoId;
  if (args.isNotEmpty) {
    for (final arg in args) {
      final vId = _extractVideoIdFromDeepLink(arg);
      if (vId != null && vId.isNotEmpty) {
        initialVideoId = vId;
        break;
      }
    }
  }

  runApp(
    ProviderScope(
      child: ZephyrApp(initialVideoId: initialVideoId),
    ),
  );
}

class ZephyrApp extends ConsumerStatefulWidget {
  final String? initialVideoId;
  const ZephyrApp({super.key, this.initialVideoId});

  @override
  ConsumerState<ZephyrApp> createState() => _ZephyrAppState();
}

class _ZephyrAppState extends ConsumerState<ZephyrApp> {
  bool _handledInitialDeepLink = false;

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
    final authState = ref.watch(authProvider);

    if (authState.isAuthenticated && widget.initialVideoId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _handleDeepLink(widget.initialVideoId!);
      });
    }

    Widget homeWidget;
    if (authState.isLoading) {
      homeWidget = const ZephyrSplash();
    } else if (authState.isAuthenticated && authState.mustChangePassword) {
      // S-07: block all navigation until password rotation is done
      homeWidget = const ChangePasswordScreen();
    } else if (authState.isAuthenticated) {
      homeWidget = const MainLayout();
    } else {
      homeWidget = const LoginScreen();
    }

    return MaterialApp(
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
