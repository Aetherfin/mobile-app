import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/audio/player_settings_store.dart';
import '../../../design_tokens/tokens.dart';
import '../../../state/providers.dart';
import '../../../widgets/bottom_sheet.dart';
import '../settings_widgets.dart';

/// Bottom sheet to pick streaming quality (max bitrate).
void showStreamingQualityDialog(BuildContext context, WidgetRef ref) {
  const options = <(int, String, String?)>[
    (
      0,
      'Original / Lossless',
      'Stream original audio files without transcoding',
    ),
    (320, '320 kbps', 'High quality compressed stream'),
    (256, '256 kbps', 'Very good balance of quality and speed'),
    (192, '192 kbps', 'Medium quality, standard compression'),
    (128, '128 kbps', 'Low quality, recommended for cellular data'),
    (96, '96 kbps', 'Data saver, uses minimal bandwidth'),
  ];

  final currentQuality = ref.read(maxBitrateProvider);

  showBlurBottomSheet<void>(
    context: context,
    builder: (context, dismiss) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AfSpacing.gutterGenerous,
          ),
          child: Text('Streaming quality', style: AfTypography.titleSmall),
        ),
        const SizedBox(height: AfSpacing.s4),
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AfSpacing.gutterGenerous,
          ),
          child: Text(
            'Limits the stream bitrate. Transcoding is performed on-the-fly by the server if needed.',
            style: AfTypography.bodySmall.copyWith(
              color: AfColors.textTertiary,
            ),
          ),
        ),
        const SizedBox(height: AfSpacing.s8),
        for (final (kbps, label, subtitle) in options)
          OptionTile(
            label: label,
            subtitle: subtitle,
            isActive: kbps == currentQuality,
            onTap: () {
              ref.read(maxBitrateProvider.notifier).set(kbps);
              unawaited(PlayerSettingsStore.saveMaxBitrate(kbps));
              dismiss();
            },
          ),
      ],
    ),
  );
}
