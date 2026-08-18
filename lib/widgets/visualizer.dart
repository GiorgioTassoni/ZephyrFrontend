import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme/zephyr_theme.dart';

/// 60 FPS Animated Audio Visualizer Bars Widget
class ZephyrVisualizer extends StatefulWidget {
  final bool isPlaying;
  final double height;
  final Color? barColor;

  const ZephyrVisualizer({
    super.key,
    required this.isPlaying,
    this.height = 24.0,
    this.barColor,
  });

  @override
  State<ZephyrVisualizer> createState() => _ZephyrVisualizerState();
}

class _ZephyrVisualizerState extends State<ZephyrVisualizer> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  final int _barCount = 5;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    if (widget.isPlaying) {
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(ZephyrVisualizer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isPlaying != oldWidget.isPlaying) {
      if (widget.isPlaying) {
        _controller.repeat();
      } else {
        _controller.stop();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final activeColor = widget.barColor ?? ZephyrTheme.primary;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return SizedBox(
          height: widget.height,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: List.generate(_barCount, (index) {
              final phase = (index * 0.45);
              final animValue = widget.isPlaying
                  ? (math.sin((_controller.value * math.pi * 2) + phase).abs())
                  : 0.15;
              final barHeight = (widget.height * 0.2) + (animValue * widget.height * 0.8);

              return Container(
                width: 3.5,
                height: barHeight,
                margin: const EdgeInsets.symmetric(horizontal: 2.0),
                decoration: BoxDecoration(
                  color: widget.isPlaying
                      ? activeColor.withValues(alpha: 0.7 + (animValue * 0.3))
                      : activeColor.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(3.0),
                  boxShadow: widget.isPlaying
                      ? [
                          BoxShadow(
                            color: activeColor.withValues(alpha: 0.4),
                            blurRadius: 4,
                            spreadRadius: 0.5,
                          )
                        ]
                      : null,
                ),
              );
            }),
          ),
        );
      },
    );
  }
}
