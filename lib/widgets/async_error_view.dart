import 'package:flutter/material.dart';

import '../design_tokens/tokens.dart';
import '../utils/display_error.dart';

/// Inline error card for failed `AsyncValue` fetches.
///
/// Replaces the `AsyncValue.maybeWhen(data:, orElse: …)` anti-pattern
/// that used to collapse `loading` **and** `error` into a blank
/// placeholder (or an infinite spinner). When the server was
/// unreachable, the auth token had expired, or the backend returned a
/// 5xx, the user got no feedback — natural read was "library is empty"
/// or "this is just taking forever".
///
/// Two layouts:
///
/// - **Compact** (`compactHeight` provided): an inline horizontal row
///   sized to match the loading skeleton, so layout doesn't jump when
///   an error surfaces mid-fetch on a Home rail.
/// - **Centered** (`compactHeight == null`): a centered column suitable
///   for full-screen sections (Library Albums / Artists / Songs /
///   Playlists / Genres / Liked).
///
/// In both cases the rendered error message goes through
/// [displayError], which strips the `api_key` / `t` / `s` / `u` query
/// params Dio embeds in `DioException.toString()`.
class AsyncErrorView extends StatelessWidget {
  final String label;
  final Object error;
  final VoidCallback onRetry;

  /// When set, renders an inline row of exactly this height. When null,
  /// renders a centered column with vertical breathing room.
  final double? compactHeight;

  const AsyncErrorView({
    super.key,
    required this.label,
    required this.error,
    required this.onRetry,
  }) : compactHeight = null;

  const AsyncErrorView.compact({
    super.key,
    required this.label,
    required this.error,
    required this.onRetry,
    required double height,
  }) : compactHeight = height;

  @override
  Widget build(BuildContext context) {
    final compactHeight = this.compactHeight;
    if (compactHeight != null) {
      return SizedBox(
        height: compactHeight,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AfSpacing.s16),
          child: Row(
            children: [
              const Icon(
                Icons.cloud_off_rounded,
                color: AfColors.semanticError,
                size: 20,
              ),
              const SizedBox(width: AfSpacing.s8),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AfTypography.bodyMedium.copyWith(
                        color: AfColors.textPrimary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Text(
                      displayError(error),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AfTypography.caption.copyWith(
                        color: AfColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AfSpacing.s8),
              TextButton(
                onPressed: onRetry,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    // Centered layout — used by full-screen sections (Library tabs).
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AfSpacing.s24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.cloud_off_rounded,
              color: AfColors.semanticError,
              size: 40,
            ),
            const SizedBox(height: AfSpacing.s12),
            Text(
              label,
              textAlign: TextAlign.center,
              style: AfTypography.titleSmall.copyWith(
                color: AfColors.textPrimary,
              ),
            ),
            const SizedBox(height: AfSpacing.s4),
            Text(
              displayError(error),
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: AfTypography.bodySmall.copyWith(
                color: AfColors.textSecondary,
              ),
            ),
            const SizedBox(height: AfSpacing.s16),
            FilledButton.tonal(
              onPressed: onRetry,
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
