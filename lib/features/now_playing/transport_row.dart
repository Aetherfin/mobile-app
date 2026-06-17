import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/audio/af_loop_mode.dart';
import '../../core/audio/shuffle_mode.dart';
import '../../design_tokens/tokens.dart';
import '../../widgets/press_scale.dart';
import 'play_button.dart';

/// Transport row — pure widget, no Riverpod.
class TransportRow extends StatelessWidget {
  const TransportRow({
    super.key,
    required this.isPlaying,
    required this.shuffleOn,
    required this.shuffleMode,
    required this.loopMode,
    required this.repeatCount,
    required this.accent,
    required this.muted,
    required this.onPlayPause,
    required this.onPrev,
    required this.onNext,
    required this.onShuffle,
    required this.onShuffleLongPress,
    required this.onRepeat,
  });
  final bool isPlaying;
  final bool shuffleOn;
  final ShuffleMode shuffleMode;
  final AfLoopMode loopMode;
  final int repeatCount;
  final Color accent;
  final Color muted;
  final VoidCallback onPlayPause;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final VoidCallback onShuffle;
  final VoidCallback onShuffleLongPress;
  final VoidCallback onRepeat;

  static IconData _loopIcon(AfLoopMode mode) {
    return switch (mode) {
      AfLoopMode.file => LucideIcons.repeat1,
      AfLoopMode.playlist => LucideIcons.repeat,
      AfLoopMode.off => LucideIcons.repeat,
      AfLoopMode.forNtimes => LucideIcons.repeat,
    };
  }

  static Color _loopColor(AfLoopMode mode, Color accent) {
    return mode == AfLoopMode.off ? AfColors.textTertiary : accent;
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Tooltip(
          message: 'Shuffle',
          child: Semantics(
            label: 'Shuffle',
            button: true,
            child: GestureDetector(
              onLongPress: onShuffleLongPress,
              child: TransportButton(
                icon: Icon(
                  shuffleMode == ShuffleMode.tail
                      ? LucideIcons.arrowDownWideNarrow
                      : LucideIcons.shuffle,
                  size: AfIconSizes.sm,
                  color: shuffleOn ? accent : AfColors.textTertiary,
                ),
                onTap: onShuffle,
              ),
            ),
          ),
        ),
        const SizedBox(width: AfSpacing.s12),
        Tooltip(
          message: 'Previous track',
          child: Semantics(
            label: 'Previous track',
            child: TransportButton(
              icon: const Icon(
                LucideIcons.skipBack,
                size: AfIconSizes.lg,
                color: AfColors.textPrimary,
              ),
              onTap: onPrev,
            ),
          ),
        ),
        const SizedBox(width: AfSpacing.s16),
        Tooltip(
          message: isPlaying ? 'Pause' : 'Play',
          child: Semantics(
            label: isPlaying ? 'Pause' : 'Play',
            child: PlayButton(
              isPlaying: isPlaying,
              accent: accent,
              onTap: onPlayPause,
            ),
          ),
        ),
        const SizedBox(width: AfSpacing.s16),
        Tooltip(
          message: 'Next track',
          child: Semantics(
            label: 'Next track',
            child: TransportButton(
              icon: const Icon(
                LucideIcons.skipForward,
                size: AfIconSizes.lg,
                color: AfColors.textPrimary,
              ),
              onTap: onNext,
            ),
          ),
        ),
        const SizedBox(width: AfSpacing.s12),
        Tooltip(
          message: loopMode == AfLoopMode.off ? 'Repeat off' : 'Repeat',
          child: Semantics(
            label: loopMode == AfLoopMode.off ? 'Repeat off' : 'Repeat',
            button: true,
            child: TransportButton(
              icon: Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(
                    _loopIcon(loopMode),
                    size: AfIconSizes.sm,
                    color: _loopColor(loopMode, accent),
                  ),
                  if (loopMode == AfLoopMode.forNtimes)
                    Positioned(
                      right: -6,
                      top: -4,
                      child: Container(
                        padding: const EdgeInsets.all(AfSpacing.s2),
                        decoration: BoxDecoration(
                          color: muted,
                          shape: BoxShape.circle,
                        ),
                        child: Text(
                          '$repeatCount',
                          style: AfTypography.caption.copyWith(
                            color: AfColors.textOnPrimary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              onTap: onRepeat,
            ),
          ),
        ),
      ],
    );
  }
}

/// Shared transport button widget.
class TransportButton extends StatelessWidget {
  const TransportButton({super.key, required this.icon, required this.onTap});
  final Widget icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressScale(
      onTap: onTap,
      child: SizedBox(
        width: AfSpacing.minHitTarget,
        height: AfSpacing.minHitTarget,
        child: Center(child: icon),
      ),
    );
  }
}
