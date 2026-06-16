import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/audio/offline_cache_service.dart';
import '../../../core/audio/player_settings_store.dart';
import '../../../design_tokens/tokens.dart';
import '../../../state/providers.dart';
import '../../../widgets/af_dialog.dart';
import '../../../widgets/bottom_sheet.dart';
import '../settings_widgets.dart';

/// Bottom sheet to pick max offline cache size.
void showOfflineCacheSizeDialog(BuildContext context, WidgetRef ref) {
  const options = <(int, String)>[
    (500 * 1024 * 1024, '500 MB'),
    (1024 * 1024 * 1024, '1 GB'),
    (2 * 1024 * 1024 * 1024, '2 GB'),
    (5 * 1024 * 1024 * 1024, '5 GB'),
    (10 * 1024 * 1024 * 1024, '10 GB'),
  ];

  final currentSize = ref.read(offlineCacheMaxSizeProvider);
  final label = OfflineCacheService.formatSize(currentSize);

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
          child: Text('Max cache size', style: AfTypography.titleSmall),
        ),
        const SizedBox(height: AfSpacing.s4),
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AfSpacing.gutterGenerous,
          ),
          child: Text(
            'Currently: $label',
            style: AfTypography.bodySmall.copyWith(
              color: AfColors.textTertiary,
            ),
          ),
        ),
        const SizedBox(height: AfSpacing.s8),
        for (final (bytes, label) in options)
          OptionTile(
            label: label,
            isActive: bytes == currentSize,
            onTap: () {
              ref.read(offlineCacheMaxSizeProvider.notifier).set(bytes);
              unawaited(PlayerSettingsStore.saveOfflineCacheMaxSize(bytes));
              // Trigger eviction with new limit.
              final cache = ref.read(offlineCacheServiceProvider);
              unawaited(cache.evictLRU(maxCacheSizeBytes: bytes));
              dismiss();
            },
          ),
      ],
    ),
  );
}

/// Confirmation dialog for clearing the offline cache.
Future<bool> showOfflineCacheClearDialog(
  BuildContext context,
  WidgetRef ref,
) async {
  final cache = ref.read(offlineCacheServiceProvider);
  final size = await cache.cacheSize();
  final count = await cache.cachedCount();
  final label = size > 0 ? OfflineCacheService.formatSize(size) : '0 B';

  if (!context.mounted) return false;

  final confirmed = await showBlurDialog<bool>(
    context: context,
    builder: (context, dismiss) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Clear offline cache?', style: AfTypography.titleMedium),
        const SizedBox(height: AfSpacing.s12),
        Text(
          count == 1
              ? '1 cached track ($label) will be deleted.'
              : '$count cached tracks ($label) will be deleted.',
          style: AfTypography.bodyMedium,
        ),
        const SizedBox(height: AfSpacing.s24),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: () => dismiss(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => dismiss(true),
              child: Text(
                'Clear cache',
                style: AfTypography.bodyMedium.copyWith(
                  color: AfColors.semanticError,
                ),
              ),
            ),
          ],
        ),
      ],
    ),
  );
  return confirmed == true;
}
