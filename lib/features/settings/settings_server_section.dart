import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/local/app_mode_store.dart';
import '../../app/router.dart';
import '../../utils/log.dart';
import '../../design_tokens/tokens.dart';
import '../../state/providers.dart';
import '../../widgets/af_dialog.dart';
import 'settings_widgets.dart';

/// Server info + switch mode section.
///
/// Rebuilds independently when [authProvider] or [appModeProvider] change.
class ServerSection extends ConsumerWidget {
  const ServerSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    final mode = ref.watch(appModeProvider);
    final isLocal = mode == AppMode.local;

    return Column(
      children: [
        // ── Server info (server mode only) ────────────────────────
        if (!isLocal && mode != AppMode.youtubeMusic)
          AfCollapsibleSection(
            title: 'Server',
            child: SettingsGroup(
              children: [
                SettingsTile(
                  icon: LucideIcons.server,
                  title: auth?.server.name ?? 'Not connected',
                  subtitle: auth?.server.baseUrl,
                ),
                if (auth != null)
                  SettingsTile(
                    icon: LucideIcons.user,
                    title: auth.userName,
                    subtitle:
                        auth.serverType.name[0].toUpperCase() +
                        auth.serverType.name.substring(1),
                  ),
                SettingsTile(
                  icon: LucideIcons.arrowLeftRight,
                  title: 'Switch server',
                  subtitle: 'Connect to a different server',
                  onTap: () => context.go('/onboarding/discover'),
                ),
                if (auth != null)
                  SettingsTile(
                    icon: LucideIcons.logOut,
                    title: 'Sign out',
                    subtitle: 'Disconnect from ${auth.server.name}',
                    danger: true,
                    onTap: () async {
                      final confirmed = await showBlurDialog<bool>(
                        context: context,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text('Sign out?', style: AfTypography.titleMedium),
                            const SizedBox(height: AfSpacing.s12),
                            Text(
                              'You will be disconnected from ${auth.server.name}.',
                              style: AfTypography.bodyMedium,
                            ),
                            const SizedBox(height: AfSpacing.s24),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                TextButton(
                                  onPressed: () =>
                                      Navigator.pop(context, false),
                                  child: const Text('Cancel'),
                                ),
                                Focus(
                                  autofocus: true,
                                  child: ElevatedButton(
                                    onPressed: () =>
                                        Navigator.pop(context, true),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AfColors.semanticError,
                                      foregroundColor: AfColors.textOnPrimary,
                                    ),
                                    child: const Text('Sign out'),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                      if (confirmed == true && context.mounted) {
                        await ref.read(authProvider.notifier).clear();
                        await AppModeStore.clear();
                        ref.read(appModeProvider.notifier).state = null;
                        if (context.mounted) context.go('/');
                      }
                    },
                  ),
              ],
            ),
          ),

        const SizedBox(height: AfSpacing.s24),

        // ── Switch mode ──────────────────────────────────────────
        SettingsGroup(
          children: [
            SettingsTile(
              icon: LucideIcons.arrowLeftRight,
              title: 'Switch mode',
              subtitle: isLocal
                  ? 'Currently: Local files'
                  : mode == AppMode.youtubeMusic
                  ? 'Currently: YouTube Music'
                  : 'Currently: Server',
              onTap: () async {
                final confirmed = await showBlurDialog<bool>(
                  context: context,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('Switch mode?', style: AfTypography.titleMedium),
                      const SizedBox(height: AfSpacing.s12),
                      Text(
                        'This will return you to the mode selection screen.',
                        style: AfTypography.bodyMedium,
                      ),
                      const SizedBox(height: AfSpacing.s24),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text('Cancel'),
                          ),
                          TextButton(
                            onPressed: () => Navigator.pop(context, true),
                            child: const Text('Switch'),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
                if (confirmed == true) {
                  // Reset router state first so redirect sends
                  // user to onboarding if settings screen is disposed.
                  resetRouterMode();
                  setRouterAuthState(auth: null);
                  notifyAuthChanged();
                  try {
                    await ref.read(authProvider.notifier).clear();
                  } on Exception catch (e) {
                    afLog(
                      'settings',
                      'Auth clear failed during reset',
                      error: e,
                    );
                  }
                  try {
                    await AppModeStore.clear();
                  } on Exception catch (e) {
                    afLog(
                      'settings',
                      'AppMode clear failed during reset',
                      error: e,
                    );
                  }
                  try {
                    ref.read(appModeProvider.notifier).state = null;
                  } on Exception catch (e) {
                    afLog('settings', 'AppMode state reset failed', error: e);
                  }
                  if (context.mounted) {
                    context.go('/');
                  } else {
                    appRouter.go('/');
                  }
                }
              },
            ),
          ],
        ),
      ],
    );
  }
}
