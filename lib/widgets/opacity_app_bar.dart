import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../design_tokens/tokens.dart';

/// Scroll-aware app bar that fades in with a blur background as the user
/// scrolls past [threshold]. Used on detail screens (album, artist, genre).
class OpacityAppBar extends StatelessWidget {
  const OpacityAppBar({
    super.key,
    required this.scrollOffset,
    required this.threshold,
    required this.title,
    required this.onBack,
    this.onMore,
  });

  final double scrollOffset;
  final double threshold;
  final String title;
  final VoidCallback onBack;

  /// Optional trailing action. When null, a 48dp spacer is shown instead.
  final VoidCallback? onMore;

  @override
  Widget build(BuildContext context) {
    final t = (scrollOffset / threshold).clamp(0.0, 1.0);
    final bg = Color.lerp(
      AfColors.transparent,
      AfColors.surfaceCanvas.withValues(alpha: 0.75),
      t,
    )!;
    final content = _buildContent(context, bg, t);
    if (t <= 0.01) return content;
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: content,
      ),
    );
  }

  Widget _buildContent(BuildContext context, Color bg, double t) {
    return Container(
      color: bg,
      padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top),
      child: SizedBox(
        height: kToolbarHeight,
        child: Row(
          children: [
            IconButton(
              tooltip: 'Go back',
              icon: const Icon(
                LucideIcons.arrowLeft,
                color: AfColors.textPrimary,
                size: 24,
              ),
              onPressed: onBack,
            ),
            Expanded(
              child: Opacity(
                opacity: t,
                child: Text(
                  title,
                  textAlign: TextAlign.center,
                  style: AfTypography.titleSmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            if (onMore != null)
              IconButton(
                tooltip: 'More options',
                icon: const Icon(
                  LucideIcons.ellipsis,
                  color: AfColors.textPrimary,
                  size: 24,
                ),
                onPressed: onMore,
              )
            else
              const SizedBox(width: AfSpacing.s48),
          ],
        ),
      ),
    );
  }
}
