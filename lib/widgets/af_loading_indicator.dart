import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../design_tokens/tokens.dart';

/// Thin indeterminate progress indicator matching Aetherfin's accent color.
class AfLoadingIndicator extends StatelessWidget {
  const AfLoadingIndicator({
    this.size = 20,
    this.strokeWidth = 2,
    this.color,
    super.key,
  });

  final double size;
  final double strokeWidth;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.maybeOf(context);
    if (mediaQuery?.disableAnimations == true) {
      return Icon(
        LucideIcons.circle,
        size: size * 0.5,
        color: color ?? AfColors.textSecondary,
      );
    }
    return SizedBox(
      width: size,
      height: size,
      child: CircularProgressIndicator(
        strokeWidth: strokeWidth,
        color: color ?? AfColors.textSecondary,
        strokeCap: StrokeCap.round,
      ),
    );
  }
}
