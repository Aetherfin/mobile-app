import 'package:flutter/material.dart';

import '../core/jellyfin/models/quality.dart';
import '../design_tokens/tokens.dart';

/// Quality chip — mono-font, honest. Shown on the active track row's right
/// side and in Now Playing's metadata block.
///
/// NEVER fake "high quality" badges. The label reflects what the server
/// actually delivers (FLAC 24/96 vs AAC 192 transcoded), and the warning
/// border appears whenever the audio path is degraded.
class QualityChip extends StatelessWidget {
  const QualityChip({super.key, required this.quality, this.compact = false});

  final TrackQuality quality;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Audio quality',
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? AfSpacing.s8 : AfSpacing.s12,
          vertical: compact ? AfSpacing.s2 : AfSpacing.s4,
        ),
        decoration: BoxDecoration(
          color: AfColors.surfaceHigh,
          borderRadius: AfRadii.borderPill,
          border: quality.isDegraded
              ? Border.all(color: AfColors.semanticWarning, width: 1)
              : null,
        ),
        child: Text(
          quality.chipLabel,
          style: (compact ? AfTypography.monoSmall : AfTypography.mono)
              .copyWith(color: AfColors.textSecondary),
        ),
      ),
    );
  }
}
