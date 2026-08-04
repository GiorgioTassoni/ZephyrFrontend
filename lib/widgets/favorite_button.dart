import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme/colors.dart';

class FavoriteButton extends StatefulWidget {
  final bool isFavorite;
  final VoidCallback onTap;
  final double size;
  final Color? activeColor;
  final Color? inactiveColor;
  final String? tooltip;

  const FavoriteButton({
    super.key,
    required this.isFavorite,
    required this.onTap,
    this.size = 22.0,
    this.activeColor,
    this.inactiveColor,
    this.tooltip,
  });

  @override
  State<FavoriteButton> createState() => _FavoriteButtonState();
}

class _FavoriteButtonState extends State<FavoriteButton> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 400),
  );

  late final Animation<double> _scaleAnimation = TweenSequence<double>([
    TweenSequenceItem(
      tween: Tween<double>(begin: 1.0, end: 1.45).chain(CurveTween(curve: Curves.easeOutCubic)),
      weight: 35,
    ),
    TweenSequenceItem(
      tween: Tween<double>(begin: 1.45, end: 0.85).chain(CurveTween(curve: Curves.easeInOut)),
      weight: 35,
    ),
    TweenSequenceItem(
      tween: Tween<double>(begin: 0.85, end: 1.0).chain(CurveTween(curve: Curves.easeOutBack)),
      weight: 30,
    ),
  ]).animate(_controller);

  @override
  void didUpdateWidget(FavoriteButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isFavorite && !oldWidget.isFavorite) {
      _controller.forward(from: 0.0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleTap() {
    _controller.forward(from: 0.0);
    widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    final activeCol = widget.activeColor ?? ZephyrColors.primary;
    final inactiveCol = widget.inactiveColor ?? ZephyrColors.textDim;

    return IconButton(
      splashRadius: widget.size * 1.2,
      padding: EdgeInsets.all((widget.size * 0.3).clamp(4.0, 8.0)),
      constraints: const BoxConstraints(),
      tooltip: widget.tooltip ?? (widget.isFavorite ? 'Remove from Favorites' : 'Add to Favorites'),
      onPressed: _handleTap,
      icon: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return CustomPaint(
            foregroundPainter: _controller.isAnimating && widget.isFavorite
                ? _ParticleBurstPainter(
                    progress: Curves.easeOutCubic.transform(_controller.value),
                    primaryColor: activeCol,
                  )
                : null,
            child: ScaleTransition(
              scale: _scaleAnimation,
              child: Icon(
                widget.isFavorite ? Icons.favorite : Icons.favorite_border,
                color: widget.isFavorite ? activeCol : inactiveCol,
                size: widget.size,
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ParticleBurstPainter extends CustomPainter {
  final double progress;
  final Color primaryColor;

  static const List<Color> _particleColors = [
    Color(0xFFFFC107), // Gold
    Color(0xFFFF4081), // Vibrant Pink
    Color(0xFF1DB954), // Spotify Green
    Color(0xFFE91E63), // Rose
    Color(0xFF00E676), // Bright Mint
    Color(0xFFFF5722), // Deep Orange
    Color(0xFFE040FB), // Neon Purple
    Color(0xFFFFD54F), // Amber
  ];

  _ParticleBurstPainter({
    required this.progress,
    required this.primaryColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0.0 || progress >= 1.0) return;

    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = math.max(size.width, size.height) * 0.95;
    final currentDist = progress * maxRadius;
    final alpha = (1.0 - progress).clamp(0.0, 1.0);
    final particleRadius = (1.0 - progress * 0.6) * 2.8;

    final paint = Paint()..style = PaintingStyle.fill;

    // Draw 8 radial particles bursting outward
    const int count = 8;
    for (int i = 0; i < count; i++) {
      final angle = i * (2 * math.pi / count);
      final dx = center.dx + math.cos(angle) * currentDist;
      final dy = center.dy + math.sin(angle) * currentDist;

      final color = _particleColors[i % _particleColors.length];
      paint.color = color.withValues(alpha: alpha);

      canvas.drawCircle(Offset(dx, dy), particleRadius, paint);
    }
  }

  @override
  bool shouldRepaint(_ParticleBurstPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}
