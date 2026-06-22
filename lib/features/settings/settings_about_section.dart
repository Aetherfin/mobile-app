import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../build_id.dart';
import '../../design_tokens/tokens.dart';
import '../../state/providers.dart';
import 'settings_sections.dart';
import 'settings_widgets.dart';

/// About section with version, source link, and licenses.
///
/// Uses [ConsumerWidget] for consistency but does not watch any providers.
class AboutSection extends ConsumerWidget {
  const AboutSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AfCollapsibleSection(
      title: 'About',
      child: SettingsGroup(
        children: [
          () {
            final info = ref.watch(packageInfoProvider).value;
            final version = info != null
                ? 'v${info.version}+${info.buildNumber} ($kBuildId)'
                : '...';
            return SettingsTile(
              icon: LucideIcons.info,
              title: 'Aetherfin $version',
              subtitle: 'Jellyfin-backed music player · FOSS',
            );
          }(),
          SettingsTile(
            icon: LucideIcons.code,
            title: 'Source code',
            subtitle: 'github.com/Aetherfin/mobile-app',
            trailing: const Icon(
              LucideIcons.externalLink,
              color: AfColors.textTertiary,
              size: 16,
            ),
            onTap: () =>
                launchSettingsUrl('https://github.com/Aetherfin/mobile-app'),
          ),
          SettingsTile(
            icon: LucideIcons.fileText,
            title: 'Licenses',
            subtitle: 'Open-source licenses',
            onTap: () => showLicensePage(
              context: context,
              applicationName: 'Aetherfin',
              applicationLegalese: '© 2025 Aetherfin contributors',
            ),
          ),
        ],
      ),
    );
  }
}
