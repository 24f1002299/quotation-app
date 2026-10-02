import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/colors.dart';
import '../theme/dimensions.dart';

/// 96dp hero mic button — forest green with a subtle idle pulse.
/// Performance-safe: single [AnimationController], no blur, no Lottie.
/// Shared by Home (voice hero) and Voice (recording indicator).
class MicButton extends StatefulWidget {
  final VoidCallback onTap;
  final bool isRecording;
  final String? elapsedLabel;
  final double size;

  const MicButton({
    super.key,
    required this.onTap,
    this.isRecording = false,
    this.elapsedLabel,
    this.size = AppDimensions.micButtonSize,
  });

  @override
  State<MicButton> createState() => _MicButtonState();
}

class _MicButtonState extends State<MicButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _scale = Tween<double>(begin: 1.0, end: 1.05).animate(
      CurvedAnimation(parent: _pulse, curve: Curves.easeInOut),
    );
    if (!widget.isRecording) _pulse.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(MicButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isRecording && _pulse.isAnimating) {
      _pulse.stop();
      _pulse.value = 0;
    } else if (!widget.isRecording && !_pulse.isAnimating) {
      _pulse.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bg = widget.isRecording ? kError : kForest;
    return Semantics(
      button: true,
      label: widget.isRecording ? 'Stop recording' : 'Tap to speak',
      child: GestureDetector(
        onTapDown: (_) => HapticFeedback.lightImpact(),
        onTap: () {
          HapticFeedback.lightImpact();
          widget.onTap();
        },
        child: ScaleTransition(
          scale: widget.isRecording
              ? const AlwaysStoppedAnimation(1.0)
              : _scale,
          child: Container(
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(
              color: bg,
              shape: BoxShape.circle,
              border: Border.all(
                color: bg.withValues(alpha: 0.25),
                width: 6,
              ),
            ),
            child: Center(
              child: widget.isRecording && widget.elapsedLabel != null
                  ? Text(
                      widget.elapsedLabel!,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    )
                  : Icon(
                      widget.isRecording
                          ? Icons.stop_rounded
                          : Icons.mic_rounded,
                      color: Colors.white,
                      size: widget.size * 0.42,
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
