import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../design_tokens/tokens.dart';
import '../../../state/providers.dart';
import '../../../widgets/af_dialog.dart';

// ─────────────────────────────────────────────────────────────────────────────
// A-B Loop dialog
// ─────────────────────────────────────────────────────────────────────────────

void showAbLoopDialog(BuildContext context, WidgetRef ref) {
  final svc = ref.read(playerServiceProvider);
  final spectral = ref.read(currentSpectralProvider);
  showBlurDialog<void>(
    context: context,
    builder: (context, dismiss) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('A-B Loop', style: AfTypography.titleMedium),
        const SizedBox(height: AfSpacing.s12),
        Text(
          'Set markers to loop a section of the track.',
          style: AfTypography.bodySmall.copyWith(color: AfColors.textTertiary),
        ),
        const SizedBox(height: AfSpacing.s16),
        FilledButton.icon(
          onPressed: () async {
            final pos = await svc.getRawPosition();
            await svc.setAbLoopA(pos);
            ref.read(abLoopAProvider.notifier).set(pos);
            dismiss();
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Loop start: ${fmtDuration(pos)}')),
              );
            }
          },
          icon: const Icon(LucideIcons.flag, size: 18),
          label: const Text('Set A (start)'),
          style: FilledButton.styleFrom(
            backgroundColor: spectral.primary,
            foregroundColor: AfColors.surfaceCanvas,
          ),
        ),
        const SizedBox(height: AfSpacing.s8),
        FilledButton.icon(
          onPressed: () async {
            final pos = await svc.getRawPosition();
            await svc.setAbLoopB(pos);
            ref.read(abLoopBProvider.notifier).set(pos);
            dismiss();
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Loop end: ${fmtDuration(pos)}')),
              );
            }
          },
          icon: const Icon(LucideIcons.flag, size: 18),
          label: const Text('Set B (end)'),
          style: FilledButton.styleFrom(
            backgroundColor: spectral.primary,
            foregroundColor: AfColors.surfaceCanvas,
          ),
        ),
        const SizedBox(height: AfSpacing.s8),
        OutlinedButton.icon(
          onPressed: () async {
            await svc.setAbLoopA(null);
            await svc.setAbLoopB(null);
            ref.read(abLoopAProvider.notifier).set(null);
            ref.read(abLoopBProvider.notifier).set(null);
            dismiss();
            if (context.mounted) {
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text('A-B loop cleared')));
            }
          },
          icon: const Icon(LucideIcons.x, size: 18),
          label: const Text('Clear loop'),
          style: OutlinedButton.styleFrom(
            foregroundColor: AfColors.semanticError,
            side: const BorderSide(color: AfColors.surfaceHigh),
          ),
        ),
      ],
    ),
  );
}

String fmtDuration(Duration d) {
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$m:$s';
}
