import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../design_tokens/tokens.dart';
import '../../state/providers.dart';

/// Audio output picker — lists real audio devices from mpv_audio_kit and
/// lets the user switch between them (headphones, Bluetooth, speakers, etc.).
class CastPickerScreen extends ConsumerWidget {
  const CastPickerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final svc = ref.watch(playerServiceProvider);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(LucideIcons.x),
          tooltip: 'Close',
          onPressed: () => Navigator.maybePop(context),
        ),
        title: Text('Output', style: AfTypography.titleMedium),
      ),
      body: SafeArea(
        child: () {
          final devices = ref.watch(audioDevicesProvider).value ?? [];
          final active = ref.watch(audioDeviceProvider).value;

          if (devices.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(AfSpacing.gutterGenerous),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      LucideIcons.speaker,
                      size: 48,
                      color: AfColors.textTertiary,
                    ),
                    const SizedBox(height: AfSpacing.s16),
                    Text(
                      'No audio devices found.\nStart playback first.',
                      style: AfTypography.bodyMedium.copyWith(
                        color: AfColors.textTertiary,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.symmetric(
              horizontal: AfSpacing.s16,
              vertical: AfSpacing.s8,
            ),
            itemCount: devices.length,
            separatorBuilder: (context, index) =>
                const SizedBox(height: AfSpacing.s8),
            itemBuilder: (context, i) {
              final device = devices[i];
              final isActive = active?.name == device.name;
              return ListTile(
                leading: Icon(
                  _iconForDevice(
                    device.description.isNotEmpty
                        ? device.description
                        : device.name,
                  ),
                  color: isActive
                      ? AfColors.accentPrimary
                      : AfColors.textSecondary,
                ),
                title: Text(
                  device.description.isNotEmpty
                      ? device.description
                      : device.name,
                  style: AfTypography.titleSmall,
                ),
                subtitle: Text(
                  device.name,
                  style: AfTypography.bodySmall.copyWith(
                    color: AfColors.textTertiary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: isActive
                    ? const Icon(
                        LucideIcons.check,
                        color: AfColors.accentPrimary,
                      )
                    : null,
                tileColor: AfColors.surfaceBase,
                shape: const RoundedRectangleBorder(
                  borderRadius: AfRadii.borderMd,
                ),
                onTap: () async {
                  await svc.setAudioDevice(device);
                  if (context.mounted) {
                    unawaited(Navigator.maybePop(context));
                  }
                },
              );
            },
          );
        }(),
      ),
    );
  }

  IconData _iconForDevice(String name) {
    final n = name.toLowerCase();
    if (n.contains('bluetooth') || n.contains('bt')) {
      return LucideIcons.bluetooth;
    }
    if (n.contains('headphone') ||
        n.contains('headset') ||
        n.contains('earphone') ||
        n.contains('airpod')) {
      return LucideIcons.headphones;
    }
    if (n.contains('speaker')) return LucideIcons.speaker;
    if (n.contains('hdmi')) return LucideIcons.monitor;
    if (n.contains('usb')) return LucideIcons.usb;
    return LucideIcons.smartphone;
  }
}
