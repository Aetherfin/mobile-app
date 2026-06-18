import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../design_tokens/tokens.dart';
import '../../state/providers.dart';
import '../../widgets/af_loading_indicator.dart';
import '../../widgets/press_scale.dart';

/// Play/pause button with spectral ambient glow and animations.
///
/// Animations:
/// - Scale bounce on play/pause toggle
/// - AnimatedSwitcher icon morph (pause ↔ play)
/// - Shadow blur radius pulse while playing
class PlayButton extends ConsumerStatefulWidget {
  const PlayButton({
    super.key,
    required this.isPlaying,
    required this.accent,
    required this.onTap,
  });
  final bool isPlaying;
  final Color accent;
  final VoidCallback onTap;

  @override
  ConsumerState<PlayButton> createState() => _PlayButtonState();
}

class _PlayButtonState extends ConsumerState<PlayButton>
    with TickerProviderStateMixin {
  late final AnimationController _scaleController = AnimationController(
    vsync: this,
    duration: AfDurations.bounce,
  );
  late final Animation<double> _scaleAnimation =
      Tween<double>(begin: 1.0, end: 0.85).animate(
        CurvedAnimation(parent: _scaleController, curve: AfCurves.easeInOut),
      );

  late final AnimationController _pulseController = AnimationController(
    vsync: this,
    duration: AfDurations.ambient,
  );
  late final Animation<double> _pulseAnimation =
      Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(parent: _pulseController, curve: AfCurves.easeInOut),
      );

  @override
  void dispose() {
    _scaleController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant PlayButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isPlaying != widget.isPlaying) {
      _scaleController.forward(from: 0.0);
      final reduced = MediaQuery.disableAnimationsOf(context);
      if (widget.isPlaying) {
        if (!reduced) {
          _pulseController.repeat(reverse: true);
        }
      } else {
        _pulseController.stop();
        _pulseController.value = 0.0;
      }
    }
  }

  static Color _contrastColor(Color accent) {
    return accent.computeLuminance() > 0.45
        ? AfColors.surfaceCanvas
        : AfColors.textOnPrimary;
  }

  @override
  Widget build(BuildContext context) {
    final isBuffering = ref.watch(isBufferingProvider);

    return PressScale(
      ensureHitTarget: false,
      onTap: widget.onTap,
      child: AnimatedBuilder(
        animation: Listenable.merge([_scaleController, _pulseController]),
        builder: (context, child) {
          final pulseBlur = 24.0 + 8.0 * _pulseAnimation.value;

          return Transform.scale(
            scale: _scaleAnimation.value,
            child: Container(
              width: AfSpacing.playButtonSize,
              height: AfSpacing.playButtonSize,
              decoration: BoxDecoration(
                color: widget.accent,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: widget.accent.withValues(alpha: 0.40),
                    blurRadius: pulseBlur,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: Center(
                child: isBuffering
                    ? AfLoadingIndicator(
                        size: AfSpacing.s24,
                        strokeWidth: 2.5,
                        color: _contrastColor(widget.accent),
                      )
                    : AnimatedSwitcher(
                        duration: AfDurations.quick,
                        transitionBuilder: (child, anim) =>
                            ScaleTransition(scale: anim, child: child),
                        child: Icon(
                          widget.isPlaying
                              ? LucideIcons.pause
                              : LucideIcons.play,
                          key: ValueKey(widget.isPlaying),
                          color: _contrastColor(widget.accent),
                          size: AfIconSizes.lg,
                        ),
                      ),
              ),
            ),
          );
        },
      ),
    );
  }
}
