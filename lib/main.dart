import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'providers/auth_provider.dart';
import 'screens/login_screen.dart';
import 'screens/main_layout.dart';
import 'theme/colors.dart';

void main() {
  runApp(
    const ProviderScope(
      child: ZephyrApp(),
    ),
  );
}

class ZephyrApp extends ConsumerWidget {
  const ZephyrApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authProvider);

    Widget homeWidget;
    if (authState.isLoading) {
      homeWidget = const ZephyrSplash();
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
