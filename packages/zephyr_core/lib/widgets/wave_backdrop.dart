import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme/colors.dart';

/// 60 FPS Custom Canvas Sine-Wave Backdrop
/// Renders an actual curved vector wave coming down from top (~55% height)
/// filled with the track ambient color gradient fading into dark background.
class ZephyrWaveBackdrop extends StatefulWidget {
  final Color ambientColor;
  final Widget child;

  const ZephyrWaveBackdrop({
    super.key,
    required this.ambientColor,
    required this.child,
  });

  @override
  State<ZephyrWaveBackdrop> createState() => _ZephyrWaveBackdropState();
}

class _ZephyrWaveBackdropState extends State<ZephyrWaveBackdrop> with TickerProviderStateMixin {
  AnimationController? _controller;

  AnimationController get controller {
    _controller ??= AnimationController(
      vsync: this,
      duration: const Duration(seconds: 28),
    )..repeat();
    return _controller!;
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final activeController = controller;

    return Stack(
      children: [
        // Solid background base
        Container(color: ZephyrColors.bgDark),

        // Animated Vector Waves Canvas
        AnimatedBuilder(
          animation: activeController,
          builder: (context, child) {
            return CustomPaint(
              size: Size.infinite,
              painter: _ZephyrWavePainter(
                ambientColor: widget.ambientColor,
                phase: activeController.value * 2 * math.pi,
              ),
            );
          },
        ),

        // Child Content
        widget.child,
      ],
    );
  }
}

class _ZephyrWavePainter extends CustomPainter {
  final Color ambientColor;
  final double phase;

  _ZephyrWavePainter({
    required this.ambientColor,
    required this.phase,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final width = size.width;
    final height = size.height;

    // Target wave center ~55% height
    final baseHeight = height * 0.42;
    final amplitude = height * 0.08;

    // --- Single Wave Shape ---
    final path = Path()..moveTo(0, 0);
    for (double x = 0; x <= width; x += 4) {
      final y = baseHeight +
          math.sin((x / width * 4 * math.pi) + phase) * amplitude +
          math.cos((x / width * 2 * math.pi) - (phase * 2)) * (amplitude * 0.35);
      path.lineTo(x, y);
    }
    path.lineTo(width, 0);
    path.close();

    final paint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          ambientColor.withValues(alpha: 0.28),
          ZephyrColors.bgDark,
        ],
        stops: const [0.0, 0.80],
      ).createShader(Rect.fromLTWH(0, 0, width, baseHeight + amplitude));

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _ZephyrWavePainter oldDelegate) {
    return oldDelegate.phase != phase || oldDelegate.ambientColor != ambientColor;
  }
}
