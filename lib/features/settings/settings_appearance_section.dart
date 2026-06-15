import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../state/providers.dart';
import 'settings_dialogs.dart';
import 'settings_widgets.dart';

/// Appearance settings section (app icon).
///
/// Rebuilds independently when [appIconProvider] changes.
class AppearanceSection extends ConsumerWidget {
  const AppearanceSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AfCollapsibleSection(
      title: 'Appearance',
      child: SettingsGroup(
        children: [
          SettingsTile(
            icon: LucideIcons.smartphone,
            title: 'App icon',
            subtitle: switch (ref.watch(appIconProvider)) {
              'MidnightIcon' => 'Midnight',
              'NordicIcon' => 'Nordic',
              'SunsetIcon' => 'Sunset',
              _ => 'Default',
            },
            onTap: () => showAppIconDialog(context, ref),
          ),
        ],
      ),
    );
  }
}
