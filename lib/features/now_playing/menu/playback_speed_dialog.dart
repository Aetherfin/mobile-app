import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../design_tokens/tokens.dart';
import '../../../state/providers.dart';
import '../../../widgets/bottom_sheet.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Speed dialog
// ─────────────────────────────────────────────────────────────────────────────

void showSpeedDialog(BuildContext context, WidgetRef ref) {
  const speeds = <double>[0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0];
  final current = ref.read(playerServiceProvider).speed;
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
          child: Text('Playback speed', style: AfTypography.titleSmall),
        ),
        const SizedBox(height: AfSpacing.s8),
        for (final s in speeds)
          ListTile(
            title: Text(
              '${s.toStringAsFixed(s == s.roundToDouble() ? 1 : 2)}×',
              style: AfTypography.bodyMedium,
            ),
            trailing: (s - current).abs() < 0.001
                ? const Icon(LucideIcons.check, size: AfIconSizes.sm)
                : null,
            onTap: () {
              unawaited(ref.read(playerServiceProvider).setAfSpeed(s));
              dismiss();
            },
          ),
      ],
    ),
  );
}
