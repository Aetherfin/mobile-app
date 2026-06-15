import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../design_tokens/tokens.dart';
import '../state/providers.dart';

/// Renders text with a gradient shader.
///
/// By default uses the current artwork spectral colors from
/// [currentSpectralProvider]. Pass [colors] to override.
class GradientHeader extends ConsumerWidget {
  const GradientHeader({
    super.key,
    required this.text,
    this.colors,
    this.style,
  });

  final String text;

  /// Optional override for gradient colors.
  /// When null, uses spectral primary + secondary.
  final List<Color>? colors;

  /// Optional override for text style.
  /// When null, uses [AfTypography.display] with [AfColors.textOnPrimary].
  final TextStyle? style;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final List<Color> gradientColors =
        colors ??
        ref.watch(
          currentSpectralProvider.select((s) => [s.primary, s.secondary]),
        );

    return ShaderMask(
      shaderCallback: (bounds) =>
          LinearGradient(colors: gradientColors).createShader(bounds),
      child: Text(
        text,
        style:
            style ??
            AfTypography.display.copyWith(color: AfColors.textOnPrimary),
      ),
    );
  }
}
