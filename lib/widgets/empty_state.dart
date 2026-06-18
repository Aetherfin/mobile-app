import 'package:flutter/material.dart';

import '../design_tokens/tokens.dart';

/// Soft empty illustration + copy + optional CTA.
///
/// Canonical layout for empty states across the app.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.body,
    this.actionLabel,
    this.onAction,
    this.mutedColor = AfColors.accentMuted,
  });

  final IconData icon;
  final String title;
  final String? body;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Color mutedColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AfSpacing.gutterGenerous,
        vertical: AfSpacing.s32,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  mutedColor.withValues(alpha: 0.15),
                  mutedColor.withValues(alpha: 0.0),
                ],
              ),
            ),
            child: ExcludeSemantics(
              child: Icon(icon, size: 48, color: mutedColor),
            ),
          ),
          const SizedBox(height: AfSpacing.s16),
          Semantics(
            header: true,
            child: Text(
              title,
              textAlign: TextAlign.center,
              style: AfTypography.titleMedium.copyWith(
                color: AfColors.textPrimary,
              ),
            ),
          ),
          if (body != null) ...[
            const SizedBox(height: AfSpacing.s8),
            Text(
              body!,
              textAlign: TextAlign.center,
              style: AfTypography.bodyMedium.copyWith(
                color: AfColors.textSecondary,
              ),
            ),
          ],
          if (actionLabel != null) ...[
            const SizedBox(height: AfSpacing.s24),
            ElevatedButton(onPressed: onAction, child: Text(actionLabel!)),
          ],
        ],
      ),
    );
  }
}
