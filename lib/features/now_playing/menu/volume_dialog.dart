import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../design_tokens/tokens.dart';
import '../../../state/providers.dart';
import '../../../widgets/af_dialog.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Volume dialog
// ─────────────────────────────────────────────────────────────────────────────

void showVolumeDialog(BuildContext context, WidgetRef ref) {
  final svc = ref.read(playerServiceProvider);
  final spectral = ref.read(currentSpectralProvider);
  double volume = svc.volume;
  bool muted = svc.isMuted;
  showBlurDialog<void>(
    context: context,
    builder: (context, dismiss) => StatefulBuilder(
      builder: (ctx, setDialogState) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text('Volume', style: AfTypography.titleMedium),
              const Spacer(),
              IconButton(
                icon: Icon(
                  muted ? LucideIcons.volumeX : LucideIcons.volume2,
                  color: AfColors.textPrimary,
                  size: AfIconSizes.md,
                ),
                tooltip: 'Toggle mute',
                onPressed: () {
                  muted = !muted;
                  svc.setMute(muted);
                  setDialogState(() {});
                },
              ),
            ],
          ),
          const SizedBox(height: AfSpacing.s16),
          SliderTheme(
            data: SliderThemeData(
              activeTrackColor: spectral.primary,
              inactiveTrackColor: AfColors.surfaceHigh,
              thumbColor: spectral.primary,
              overlayColor: spectral.primary.withValues(alpha: 0.1),
            ),
            child: Slider(
              value: volume.clamp(0, 150),
              min: 0,
              max: 150,
              divisions: 30,
              label: '${volume.round()}%',
              onChanged: (v) {
                volume = v;
                setDialogState(() {});
              },
              onChangeEnd: svc.setVolume,
            ),
          ),
          Text(
            '${volume.round()}%',
            style: AfTypography.mono.copyWith(color: AfColors.textTertiary),
          ),
        ],
      ),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Audio delay dialog
// ─────────────────────────────────────────────────────────────────────────────

void showAudioDelayDialog(BuildContext context, WidgetRef ref) {
  final svc = ref.read(playerServiceProvider);
  final spectral = ref.read(currentSpectralProvider);
  double delayMs = svc.audioDelay.inMilliseconds.toDouble();
  showBlurDialog<void>(
    context: context,
    builder: (context, dismiss) => StatefulBuilder(
      builder: (ctx, setDialogState) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Audio delay', style: AfTypography.titleMedium),
          const SizedBox(height: AfSpacing.s12),
          Text(
            'Shift audio timing for Bluetooth sync',
            style: AfTypography.bodySmall.copyWith(
              color: AfColors.textTertiary,
            ),
          ),
          const SizedBox(height: AfSpacing.s16),
          SliderTheme(
            data: SliderThemeData(
              activeTrackColor: spectral.primary,
              inactiveTrackColor: AfColors.surfaceHigh,
              thumbColor: spectral.primary,
              overlayColor: spectral.primary.withValues(alpha: 0.1),
            ),
            child: Slider(
              value: delayMs.clamp(-500, 500),
              min: -500,
              max: 500,
              divisions: 20,
              label: '${delayMs.round()} ms',
              onChanged: (v) {
                delayMs = v;
                setDialogState(() {});
              },
              onChangeEnd: (v) =>
                  svc.setAudioDelay(Duration(milliseconds: v.round())),
            ),
          ),
          Text(
            '${delayMs.round()} ms',
            style: AfTypography.mono.copyWith(color: AfColors.textTertiary),
          ),
          const SizedBox(height: AfSpacing.s24),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () {
                  delayMs = 0;
                  svc.setAudioDelay(Duration.zero);
                  setDialogState(() {});
                },
                child: const Text('Reset'),
              ),
              const SizedBox(width: AfSpacing.s8),
              TextButton(onPressed: () => dismiss(), child: const Text('Done')),
            ],
          ),
        ],
      ),
    ),
  );
}
