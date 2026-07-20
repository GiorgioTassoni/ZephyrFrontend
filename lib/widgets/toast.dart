import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import '../theme/colors.dart';

class ZephyrToast {
  static OverlayEntry? _currentEntry;
  static Timer? _timer;

  static void show(BuildContext context, String message, {bool isError = false}) {
    _timer?.cancel();
    if (_currentEntry != null) {
      _currentEntry!.remove();
      _currentEntry = null;
    }

    final overlay = Overlay.of(context);
    
    _currentEntry = OverlayEntry(
      builder: (context) {
        return _ToastWidget(
          message: message,
          isError: isError,
          onDismiss: () {
            _currentEntry?.remove();
            _currentEntry = null;
          },
        );
      },
    );

    overlay.insert(_currentEntry!);
    
    _timer = Timer(const Duration(seconds: 2, milliseconds: 500), () {
      if (_currentEntry != null) {
        _currentEntry!.remove();
        _currentEntry = null;
      }
    });
  }
}

class _ToastWidget extends StatefulWidget {
  final String message;
  final bool isError;
  final VoidCallback onDismiss;

  const _ToastWidget({
    required this.message,
    required this.isError,
    required this.onDismiss,
  });

  @override
  State<_ToastWidget> createState() => _ToastWidgetState();
}

class _ToastWidgetState extends State<_ToastWidget> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _opacity;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    
    _opacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );
    
    _scale = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutBack),
    );

    _controller.forward();

    // Start fade out animation slightly before total duration
    Future.delayed(const Duration(seconds: 2, milliseconds: 200), () {
      if (mounted) {
        _controller.reverse();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final baseColor = widget.isError ? ZephyrColors.error : const Color(0xFF1DB954);

    return Positioned(
      top: 40,
      left: 0,
      right: 0,
      child: Center(
        child: FadeTransition(
          opacity: _opacity,
          child: ScaleTransition(
            scale: _scale,
            child: Material(
              color: Colors.transparent,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.25),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      decoration: BoxDecoration(
                        color: baseColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: baseColor.withValues(alpha: 0.8),
                          width: 1.5,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            widget.isError ? Icons.error_outline : Icons.check_circle_outline,
                            color: baseColor.withValues(alpha: 0.9),
                            size: 20,
                          ),
                          const SizedBox(width: 10),
                          Flexible(
                            child: Text(
                              widget.message,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
