import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/audio/player_settings_store.dart';
import '../../home_widget/home_widget_manager.dart';
import '../../app/router.dart';
import '../../utils/log.dart';
import '../../design_tokens/tokens.dart';
import '../../state/lastfm_sync_provider.dart';
import '../../state/providers.dart';
import '../../widgets/af_dialog.dart';
import '../../widgets/af_scrollbar.dart';
import '../../state/youtube_music_providers.dart';
import 'settings_about_section.dart';
import 'settings_appearance_section.dart';
import 'settings_audio_section.dart';
import 'settings_dialogs.dart';
import 'settings_sections.dart';
import 'settings_server_section.dart';
import 'settings_widgets.dart';

// ── Screen ───────────────────────────────────────────────────────────────────

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(appModeProvider);
    final isLocal = mode == AppMode.local;

    return FocusTraversalGroup(
      child: Scaffold(
        backgroundColor: AfColors.surfaceCanvas,
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: AfLayout.maxContentWidth,
                  ),
                  child: AfScrollbar(
                    child: ListView(
                      physics: const ClampingScrollPhysics(),
                      padding: const EdgeInsets.symmetric(
                        horizontal: AfSpacing.s16,
                      ),
                      children: [
                        // ── Page header ─────────────────────────────────────────
                        Padding(
                          padding: const EdgeInsets.only(
                            bottom: AfSpacing.s24,
                            left: AfSpacing.s4,
                          ),
                          child: Row(
                            children: [
                              IconButton(
                                icon: const Icon(LucideIcons.arrowLeft),
                                onPressed: () => context.pop(),
                                tooltip: 'Back',
                              ),
                              Text('Settings', style: AfTypography.display),
                            ],
                          ),
                        ),

                        // ── Server (server mode) ────────────────────────────────
                        const ServerSection(),

                        // ── YouTube Music Account ───────────────────────────────
                        if (mode == AppMode.youtubeMusic)
                          _YouTubeMusicAccountSection(),

                        // ── Music Folders (local mode only) ─────────────────────
                        if (isLocal)
                          const AfCollapsibleSection(
                            title: 'Music folders',
                            child: MusicFoldersCard(),
                          ),

                        const SizedBox(height: AfSpacing.s24),

                        const SizedBox(height: AfSpacing.s24),

                        // ── Appearance ───────────────────────────────────────────
                        const AppearanceSection(),

                        const SizedBox(height: AfSpacing.s24),

                        // ── Audio ───────────────────────────────────────────────
                        const AudioSection(),

                        const SizedBox(height: AfSpacing.s24),

                        // ── Last.fm Scrobbling ───────────────────────────────────
                        const AfCollapsibleSection(
                          title: 'Last.fm',
                          child: _LastFmSettingsBody(),
                        ),

                        const SizedBox(height: AfSpacing.s24),

                        // ── Advanced ─────────────────────────────────────────────
                        AfCollapsibleSection(
                          title: 'Advanced',
                          child: SettingsGroup(
                            children: [
                              SettingsTile(
                                icon: LucideIcons.trash2,
                                title: 'Clear app data',
                                subtitle: 'Reset app to initial state',
                                danger: true,
                                onTap: () async {
                                  final confirmed = await showBlurDialog<bool>(
                                    context: context,
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        Text(
                                          'Clear app data?',
                                          style: AfTypography.titleMedium,
                                        ),
                                        const SizedBox(height: AfSpacing.s12),
                                        Text(
                                          'This will wipe all local data, settings, and downloaded metadata. You will need to set up the app again.',
                                          style: AfTypography.bodyMedium,
                                        ),
                                        const SizedBox(height: AfSpacing.s24),
                                        Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.end,
                                          children: [
                                            TextButton(
                                              onPressed: () =>
                                                  Navigator.pop(context, false),
                                              child: const Text('Cancel'),
                                            ),
                                            Focus(
                                              autofocus: true,
                                              child: ElevatedButton(
                                                onPressed: () => Navigator.pop(
                                                  context,
                                                  true,
                                                ),
                                                style: ElevatedButton.styleFrom(
                                                  backgroundColor:
                                                      AfColors.semanticError,
                                                  foregroundColor:
                                                      AfColors.textOnPrimary,
                                                ),
                                                child: const Text('Clear data'),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  );
                                  if (confirmed == true && context.mounted) {
                                    // ── Step 1: Reset router state BEFORE destructive ops ──
                                    // This ensures the redirect sends the user to onboarding
                                    // even if the settings screen is disposed mid-operation.
                                    resetRouterMode();
                                    setRouterAuthState(auth: null);
                                    notifyAuthChanged();

                                    // ── Step 2: Clear all persistent storage ──
                                    try {
                                      final prefs =
                                          await SharedPreferences.getInstance();
                                      await prefs.clear();
                                    } on Exception catch (e) {
                                      afLog(
                                        'settings',
                                        'SharedPreferences clear failed',
                                        error: e,
                                      );
                                    }

                                    try {
                                      const secureStorage =
                                          FlutterSecureStorage();
                                      await secureStorage.deleteAll();
                                    } on Exception catch (e) {
                                      afLog(
                                        'settings',
                                        'SecureStorage clear failed',
                                        error: e,
                                      );
                                    }

                                    // ── Step 3: Close and delete database + sidecar files ──
                                    try {
                                      final db = ref.read(appDatabaseProvider);
                                      await db.close();
                                      final dbFolder =
                                          await getApplicationDocumentsDirectory();
                                      final dbBase = p.join(
                                        dbFolder.path,
                                        'aetherfin_drift.db',
                                      );
                                      // Delete main DB and WAL/SHM sidecar files.
                                      for (final suffix in [
                                        '',
                                        '-shm',
                                        '-wal',
                                      ]) {
                                        final f = File('$dbBase$suffix');
                                        if (f.existsSync()) await f.delete();
                                      }
                                      ref.invalidate(appDatabaseProvider);
                                    } on Exception catch (e) {
                                      afLog(
                                        'settings',
                                        'Database cleanup failed',
                                        error: e,
                                      );
                                    }

                                    // ── Step 4: Delete all cache directories ──
                                    // Audio cache (offline downloaded tracks)
                                    try {
                                      final supportDir =
                                          await getApplicationSupportDirectory();
                                      final audioCacheDir = Directory(
                                        p.join(supportDir.path, 'audio_cache'),
                                      );
                                      if (await audioCacheDir.exists()) {
                                        await audioCacheDir.delete(
                                          recursive: true,
                                        );
                                      }
                                    } on Exception catch (e) {
                                      afLog(
                                        'settings',
                                        'Audio cache cleanup failed',
                                        error: e,
                                      );
                                    }

                                    // Artwork cache (server-mode cover images)
                                    // and local cover cache (extracted from audio files)
                                    try {
                                      final cacheDir =
                                          await getApplicationCacheDirectory();
                                      for (final subdir in [
                                        'artwork_cache',
                                        'local_covers',
                                      ]) {
                                        final dir = Directory(
                                          p.join(cacheDir.path, subdir),
                                        );
                                        if (await dir.exists()) {
                                          await dir.delete(recursive: true);
                                        }
                                      }
                                    } on Exception catch (e) {
                                      afLog(
                                        'settings',
                                        'Artwork cache cleanup failed',
                                        error: e,
                                      );
                                    }

                                    // ── Step 5: Clear home widget ──
                                    try {
                                      await HomeWidgetManager.clear();
                                    } on Exception catch (e) {
                                      afLog(
                                        'settings',
                                        'Home widget clear failed',
                                        error: e,
                                      );
                                    }

                                    // ── Step 6: Clear Riverpod providers ──
                                    try {
                                      ref.read(appModeProvider.notifier).state =
                                          null;
                                      ref
                                              .read(
                                                localOnboardingCompletedProvider
                                                    .notifier,
                                              )
                                              .state =
                                          false;
                                      await ref
                                          .read(authProvider.notifier)
                                          .clear();
                                    } on Exception catch (e) {
                                      afLog(
                                        'settings',
                                        'Provider state reset failed',
                                        error: e,
                                      );
                                    }

                                    // ── Step 7: Navigate to onboarding ──
                                    // Use root navigator directly in case the settings
                                    // screen was disposed during the clearing steps.
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
                        ),

                        const SizedBox(height: AfSpacing.s24),

                        // ── About ────────────────────────────────────────────────
                        const AboutSection(),

                        // ── Footer caption ───────────────────────────────────────
                        Center(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              vertical: AfSpacing.s24,
                            ),
                            child: FutureBuilder<PackageInfo>(
                              future: PackageInfo.fromPlatform(),
                              builder: (context, snap) {
                                final version = snap.data != null
                                    ? 'v${snap.data!.version}+${snap.data!.buildNumber}'
                                    : '...';
                                return Text(
                                  'Aetherfin $version · Android',
                                  style: AfTypography.overline.copyWith(
                                    color: AfColors.textDisabled,
                                  ),
                                );
                              },
                            ),
                          ),
                        ),

                        const SizedBox(height: AfSpacing.s24),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

// ── Last.fm section ──────────────────────────────────────────────────────────

class _LastFmSettingsBody extends ConsumerWidget {
  const _LastFmSettingsBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final apiKey = ref.watch(lastfmApiKeyProvider);
    final apiSecret = ref.watch(lastfmApiSecretProvider);
    final sessionKey = ref.watch(lastfmSessionKeyProvider);
    final username = ref.watch(lastfmUsernameProvider);
    final scrobbleEnabled = ref.watch(lastfmScrobbleEnabledProvider);
    final lastfmStatus = ref.watch(lastfmStatusProvider);
    final spectral = ref.watch(
      currentSpectralProvider.select((s) => s.primary),
    );

    final hasCredentials = apiKey.isNotEmpty && apiSecret.isNotEmpty;
    final isConnected = sessionKey.isNotEmpty;

    return SettingsGroup(
      children: [
        SettingsTile(
          icon: LucideIcons.key,
          title: 'API Credentials',
          subtitle: hasCredentials
              ? 'Key: ${apiKey.substring(0, apiKey.length > 8 ? 8 : apiKey.length)}…'
              : 'Not configured — set to scrobble',
          onTap: () => showLastFmApiConfigDialog(context, ref),
        ),
        if (hasCredentials && !isConnected)
          SettingsTile(
            icon: LucideIcons.link,
            title: 'Link Last.fm Account',
            subtitle: 'Log in with username and password',
            onTap: () => showLastFmLoginDialog(context, ref),
          ),
        if (isConnected) ...[
          SettingsTile(
            icon: LucideIcons.user,
            title: 'Connected as $username',
            subtitle: 'Tap to disconnect / sign out',
            onTap: () => showLastFmSignOutDialog(context, ref),
          ),
          SettingsTile(
            icon: LucideIcons.refreshCw,
            title: 'Sync Liked Tracks',
            subtitle: 'Sync favorites between library and Last.fm',
            onTap: () async {
              unawaited(
                showBlurDialog(
                  context: context,
                  barrierDismissible: false,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: spectral,
                        ),
                      ),
                      const SizedBox(width: AfSpacing.s16),
                      Text(
                        'Syncing favorites...',
                        style: AfTypography.bodyMedium.copyWith(
                          color: AfColors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
              );

              try {
                final syncFn = ref.read(lastFmSyncProvider);
                final result = await syncFn();
                if (context.mounted) {
                  Navigator.pop(context);
                } // Close dialog

                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Synced! Added ${result.toApp} tracks locally, '
                        'loved ${result.toLastFm} on Last.fm.',
                      ),
                    ),
                  );
                }
              } on Exception catch (e) {
                if (context.mounted) {
                  Navigator.pop(context);
                } // Close dialog
                if (context.mounted) {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text('Sync failed: $e')));
                }
              }
            },
          ),
          SettingsSwitchTile(
            icon: LucideIcons.checkSquare,
            title: 'Scrobble tracks',
            subtitle: 'Submit played tracks to profile',
            value: scrobbleEnabled,
            onChanged: (v) {
              ref.read(lastfmScrobbleEnabledProvider.notifier).state = v;
              unawaited(PlayerSettingsStore.saveLastFmScrobbleEnabled(v));
            },
          ),
          if (lastfmStatus != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AfSpacing.s16,
                AfSpacing.s4,
                AfSpacing.s16,
                AfSpacing.s4,
              ),
              child: Text(
                lastfmStatus,
                style: AfTypography.caption.copyWith(
                  color: lastfmStatus.startsWith('ERROR')
                      ? AfColors.semanticError
                      : AfColors.textTertiary,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
      ],
    );
  }
}

/// YouTube Music account section shown in settings when in YouTube Music mode.
class _YouTubeMusicAccountSection extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(youtubeAuthProvider);
    final isLoggedIn = auth?.isValid == true;

    return AfCollapsibleSection(
      title: 'YouTube Music',
      child: SettingsGroup(
        children: [
          SettingsTile(
            icon: LucideIcons.user,
            title: isLoggedIn
                ? (auth!.email.isNotEmpty ? auth.email : 'Signed in')
                : 'Not signed in',
            subtitle: isLoggedIn
                ? 'Google account connected'
                : 'Sign in for personalized content',
          ),
          if (isLoggedIn)
            SettingsTile(
              icon: LucideIcons.logOut,
              title: 'Sign out',
              subtitle: 'Disconnect Google account',
              danger: true,
              onTap: () async {
                final confirmed = await showBlurDialog<bool>(
                  context: context,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Sign out of YouTube Music?',
                        style: AfTypography.titleMedium,
                      ),
                      const SizedBox(height: AfSpacing.s12),
                      Text(
                        'You will lose access to personalized recommendations.',
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
                          Focus(
                            autofocus: true,
                            child: ElevatedButton(
                              onPressed: () => Navigator.pop(context, true),
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
                  await ref.read(youtubeAuthProvider.notifier).clear();
                  ref.invalidate(youtubeHomeProvider);
                }
              },
            )
          else
            SettingsTile(
              icon: LucideIcons.logIn,
              title: 'Sign in',
              subtitle: 'Connect your Google account',
              onTap: () => context.push('/onboarding/youtube-login'),
            ),
        ],
      ),
    );
  }
}
