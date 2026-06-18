import 'package:flutter/material.dart';

import '../design_tokens/tokens.dart';
import 'press_scale.dart';

/// Section title with optional "See all" action.
///
/// `Recently Played                    See More ›`
///
/// 24dp top spacing, 12dp bottom spacing (callers handle the spacing wrappers).
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.actionLabel,
    this.onActionTap,
    this.uppercase = false,
    this.spectralPrimary,
  });

  final String title;
  final String? actionLabel;
  final VoidCallback? onActionTap;

  /// When true, the title is uppercased and rendered in `label` style
  /// (used for sub-section headers like `PUBLIC PLAYLISTS`).
  final bool uppercase;

  /// Spectral accent color for the action label. Pass from parent to avoid
  /// watching [currentSpectralProvider] inside this widget.
  final Color? spectralPrimary;

  @override
  Widget build(BuildContext context) {
    final titleStyle = uppercase
        ? AfTypography.label.copyWith(color: AfColors.textSecondary)
        : AfTypography.titleMedium.copyWith(color: AfColors.textPrimary);

    return Padding(
      padding: const EdgeInsets.only(bottom: AfSpacing.s12),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              header: true,
              child: Text(
                uppercase ? title.toUpperCase() : title,
                style: titleStyle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          if (actionLabel != null)
            FocusPressScale(
              onTap: onActionTap,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AfSpacing.s8,
                    vertical: AfSpacing.s4,
                  ),
                  child: Text(
                    '$actionLabel ›',
                    style: AfTypography.bodySmall.copyWith(
                      color: spectralPrimary ?? AfColors.textTertiary,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
