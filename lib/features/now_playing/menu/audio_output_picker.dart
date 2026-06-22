import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../design_tokens/tokens.dart';
import '../../../state/providers.dart';
import '../../../widgets/bottom_sheet.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Output dialog
// ─────────────────────────────────────────────────────────────────────────────

void showOutputDialog(BuildContext context, WidgetRef ref) {
  showBlurBottomSheet<void>(
    context: context,
    builder: (context, dismiss) => ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 360, maxHeight: 480),
      child: OutputDialogContent(dismiss: dismiss),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Output dialog content
// ─────────────────────────────────────────────────────────────────────────────

class OutputDialogContent extends ConsumerWidget {
  const OutputDialogContent({super.key, required this.dismiss});

  final void Function() dismiss;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final svc = ref.watch(playerServiceProvider);
    final spectral = ref.watch(
      currentSpectralProvider.select((s) => s.primary),
    );

    final devices = ref.watch(audioDevicesProvider).value ?? [];
    final active = ref.watch(audioDeviceProvider).value;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AfSpacing.s16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AfSpacing.gutterGenerous,
            ),
            child: Text('Output', style: AfTypography.titleSmall),
          ),
          const SizedBox(height: AfSpacing.s8),
          if (devices.isEmpty)
            Padding(
              padding: const EdgeInsets.all(AfSpacing.gutterGenerous),
              child: Text(
                'No audio devices found.\nStart playback first.',
                style: AfTypography.bodyMedium.copyWith(
                  color: AfColors.textTertiary,
                ),
                textAlign: TextAlign.center,
              ),
            )
          else
            ...devices.map((device) {
              final isActive = active?.name == device.name;
              return ListTile(
                leading: iconForDevice(
                  device.description.isNotEmpty
                      ? device.description
                      : device.name,
                  color: isActive ? spectral : AfColors.textSecondary,
                ),
                title: Text(
                  device.description.isNotEmpty
                      ? device.description
                      : device.name,
                  style: AfTypography.bodyMedium,
                ),
                trailing: isActive
                    ? Icon(
                        LucideIcons.check,
                        color: spectral,
                        size: AfIconSizes.sm,
                      )
                    : null,
                onTap: () async {
                  await svc.setAudioDevice(device);
                  dismiss();
                },
              );
            }),
        ],
      ),
    );
  }

  Widget iconForDevice(String name, {required Color color}) {
    final n = name.toLowerCase();
    if (n.contains('bluetooth') || n.contains('bt')) {
      return Icon(LucideIcons.bluetooth, color: color, size: AfIconSizes.sm);
    }
    if (n.contains('headphone') ||
        n.contains('headset') ||
        n.contains('earphone') ||
        n.contains('airpod')) {
      return Icon(LucideIcons.headphones, color: color, size: AfIconSizes.sm);
    }
    if (n.contains('speaker')) {
      return Icon(LucideIcons.speaker, color: color, size: AfIconSizes.sm);
    }
    if (n.contains('hdmi')) {
      return Icon(LucideIcons.monitor, color: color, size: AfIconSizes.sm);
    }
    if (n.contains('usb')) {
      return Icon(LucideIcons.usb, color: color, size: AfIconSizes.sm);
    }
    return Icon(LucideIcons.smartphone, color: color, size: AfIconSizes.sm);
  }
}
