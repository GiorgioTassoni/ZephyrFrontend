import 'package:flutter/material.dart';
import '../theme/colors.dart';

class SeekBar extends StatefulWidget {
  final Duration position;
  final Duration duration;
  final ValueChanged<Duration> onChangeEnd;

  const SeekBar({
    super.key,
    required this.position,
    required this.duration,
    required this.onChangeEnd,
  });

  @override
  State<SeekBar> createState() => _SeekBarState();
}

class _SeekBarState extends State<SeekBar> {
  double? _dragValue;

  @override
  Widget build(BuildContext context) {
    final max = widget.duration.inMilliseconds.toDouble();
    final value = _dragValue ?? widget.position.inMilliseconds.toDouble();

    // Clamp value to safe bounds
    final clampedValue = value.clamp(0.0, max > 0.0 ? max : 0.0);

    return Row(
      children: [
        Text(
          _formatDuration(Duration(milliseconds: clampedValue.toInt())),
          style: const TextStyle(color: ZephyrColors.textMuted, fontSize: 12),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: SliderTheme(
            data: SliderThemeData(
              trackHeight: 4,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
              activeTrackColor: ZephyrColors.primary,
              inactiveTrackColor: ZephyrColors.bgLight,
              thumbColor: ZephyrColors.primary,
              overlayColor: ZephyrColors.primary.withOpacity(0.2),
            ),
            child: Slider(
              min: 0.0,
              max: max > 0 ? max : 1.0, // avoid slider complaints about max <= min
              value: clampedValue,
              onChanged: (newValue) {
                setState(() {
                  _dragValue = newValue;
                });
              },
              onChangeEnd: (newValue) {
                setState(() {
                  _dragValue = null;
                });
                widget.onChangeEnd(Duration(milliseconds: newValue.toInt()));
              },
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          _formatDuration(widget.duration),
          style: const TextStyle(color: ZephyrColors.textMuted, fontSize: 12),
        ),
      ],
    );
  }

  String _formatDuration(Duration? duration) {
    if (duration == null) {
      return '--:--';
    }
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);

    final secondsStr = seconds.toString().padLeft(2, '0');
    if (hours > 0) {
      final minutesStr = minutes.toString().padLeft(2, '0');
      return '$hours:$minutesStr:$secondsStr';
    } else {
      return '$minutes:$secondsStr';
    }
  }
}
