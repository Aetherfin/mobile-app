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
import 'package:mpv_audio_kit/mpv_audio_kit.dart' show AudioParams, Device;
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/audio/offline_cache_service.dart';
import '../../core/audio/player_settings_store.dart';
import '../../core/local/app_mode_store.dart';
import '../../home_widget/home_widget_manager.dart';
import '../../app/router.dart';
import '../../build_id.dart';
import '../../utils/log.dart';
import '../../design_tokens/tokens.dart';
import '../../state/lastfm_sync_provider.dart';
import '../../state/providers.dart';
import '../../widgets/af_dialog.dart';
import '../../widgets/af_scrollbar.dart';
import '../../state/youtube_music_providers.dart';
import 'settings_dialogs.dart';
import 'settings_sections.dart';
import 'settings_widgets.dart';

// ── Screen ───────────────────────────────────────────────────────────────────

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    final svc = ref.read(playerServiceProvider);
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
                                  onTap: () =>
                                      context.go('/onboarding/discover'),
                                ),
                                if (auth != null)
                                  SettingsTile(
                                    icon: LucideIcons.logOut,
                                    title: 'Sign out',
                                    subtitle:
                                        'Disconnect from ${auth.server.name}',
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
                                              'Sign out?',
                                              style: AfTypography.titleMedium,
                                            ),
                                            const SizedBox(
                                              height: AfSpacing.s12,
                                            ),
                                            Text(
                                              'You will be disconnected from ${auth.server.name}.',
                                              style: AfTypography.bodyMedium,
                                            ),
                                            const SizedBox(
                                              height: AfSpacing.s24,
                                            ),
                                            Row(
                                              mainAxisAlignment:
                                                  MainAxisAlignment.end,
                                              children: [
                                                TextButton(
                                                  onPressed: () =>
                                                      Navigator.pop(
                                                        context,
                                                        false,
                                                      ),
                                                  child: const Text('Cancel'),
                                                ),
                                                Focus(
                                                  autofocus: true,
                                                  child: ElevatedButton(
                                                    onPressed: () =>
                                                        Navigator.pop(
                                                          context,
                                                          true,
                                                        ),
                                                    style:
                                                        ElevatedButton.styleFrom(
                                                          backgroundColor:
                                                              AfColors
                                                                  .semanticError,
                                                          foregroundColor:
                                                              AfColors
                                                                  .textOnPrimary,
                                                        ),
                                                    child: const Text(
                                                      'Sign out',
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      );
                                      if (confirmed == true &&
                                          context.mounted) {
                                        await ref
                                            .read(authProvider.notifier)
                                            .clear();
                                        await AppModeStore.clear();
                                        ref
                                                .read(appModeProvider.notifier)
                                                .state =
                                            null;
                                        if (context.mounted) context.go('/');
                                      }
                                    },
                                  ),
                              ],
                            ),
                          ),

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

                        // ── Switch mode ─────────────────────────────────────────
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
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      Text(
                                        'Switch mode?',
                                        style: AfTypography.titleMedium,
                                      ),
                                      const SizedBox(height: AfSpacing.s12),
                                      Text(
                                        'This will return you to the mode selection screen.',
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
                                          TextButton(
                                            onPressed: () =>
                                                Navigator.pop(context, true),
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
                                    await ref
                                        .read(authProvider.notifier)
                                        .clear();
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
                                    ref.read(appModeProvider.notifier).state =
                                        null;
                                  } on Exception catch (e) {
                                    afLog(
                                      'settings',
                                      'AppMode state reset failed',
                                      error: e,
                                    );
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

                        const SizedBox(height: AfSpacing.s24),

                        // ── Appearance ───────────────────────────────────────────
                        AfCollapsibleSection(
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
                        ),

                        const SizedBox(height: AfSpacing.s24),

                        // ── Audio output ─────────────────────────────────────────
                        AfCollapsibleSection(
                          title: 'Audio output',
                          child: SettingsGroup(
                            children: [
                              StreamBuilder<AudioParams>(
                                stream: ref
                                    .read(playerServiceProvider)
                                    .audioOutParamsStream,
                                initialData: ref
                                    .read(playerServiceProvider)
                                    .audioOutParams,
                                builder: (context, snap) {
                                  final params = snap.data;
                                  final rate = params?.sampleRate;
                                  final fmt = params?.format;
                                  final ch = params?.channelCount;
                                  final hasData = rate != null && rate > 0;
                                  return SettingsTile(
                                    icon: LucideIcons.waves,
                                    title: 'Current output',
                                    subtitle: hasData
                                        ? '$rate Hz · ${fmt?.name ?? "auto"} · ${ch}ch'
                                        : 'Not active — start playback first',
                                  );
                                },
                              ),
                              StreamBuilder<Device>(
                                stream: svc.audioDeviceStream,
                                initialData: svc.audioDevice,
                                builder: (context, snap) {
                                  final device = snap.data;
                                  final label =
                                      device?.description.isNotEmpty == true
                                      ? device!.description
                                      : device?.name ?? 'Auto';
                                  return SettingsTile(
                                    icon: LucideIcons.speaker,
                                    title: 'Audio device',
                                    subtitle: label,
                                    onTap: () =>
                                        showAudioDeviceDialog(context, ref),
                                  );
                                },
                              ),
                              SettingsTile(
                                icon: LucideIcons.gauge,
                                title: 'Sample rate',
                                subtitle: 'Force output sample rate for DAC',
                                onTap: () => showSampleRateDialog(context, ref),
                              ),
                              SettingsTile(
                                icon: LucideIcons.cpu,
                                title: 'Bit depth',
                                subtitle: 'Force output format',
                                onTap: () => showFormatDialog(context, ref),
                              ),
                              StreamBuilder<bool>(
                                stream: svc.audioExclusiveStream,
                                initialData: svc.audioExclusive,
                                builder: (context, snap) {
                                  final enabled = snap.data ?? false;
                                  return SettingsSwitchTile(
                                    icon: LucideIcons.lock,
                                    title: 'Exclusive mode',
                                    subtitle:
                                        'Bypass OS mixer for bit-perfect output',
                                    value: enabled,
                                    onChanged: (v) {
                                      unawaited(svc.setAudioExclusive(v));
                                      unawaited(
                                        PlayerSettingsStore.saveExclusive(v),
                                      );
                                    },
                                  );
                                },
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: AfSpacing.s24),

                        // ── Network & cache ──────────────────────────────────────
                        AfCollapsibleSection(
                          title: 'Network & cache',
                          child: SettingsGroup(
                            children: [
                              SettingsTile(
                                icon: LucideIcons.music,
                                title: 'Streaming quality',
                                subtitle: ref.watch(maxBitrateProvider) == 0
                                    ? 'Original / Lossless'
                                    : '${ref.watch(maxBitrateProvider)} kbps',
                                onTap: () =>
                                    showStreamingQualityDialog(context, ref),
                              ),
                              SettingsTile(
                                icon: LucideIcons.rotateCcw,
                                title: 'Cache duration',
                                subtitle: 'How far ahead to buffer',
                                onTap: () =>
                                    showCacheDurationDialog(context, ref),
                              ),
                              SettingsTile(
                                icon: LucideIcons.hardDrive,
                                title: 'Buffer size',
                                subtitle:
                                    'Audio hardware buffer (latency vs stability)',
                                onTap: () =>
                                    showAudioBufferDialog(context, ref),
                              ),
                              StreamBuilder<bool>(
                                stream: svc.audioStreamSilenceStream,
                                initialData: svc.audioStreamSilence,
                                builder: (context, snap) {
                                  final enabled = snap.data ?? false;
                                  return SettingsSwitchTile(
                                    icon: LucideIcons.volume2,
                                    title: 'Keep audio active on pause',
                                    subtitle: 'Eliminates click/pop on resume',
                                    value: enabled,
                                    onChanged: (v) {
                                      unawaited(svc.setAudioStreamSilence(v));
                                      unawaited(
                                        PlayerSettingsStore.saveStreamSilence(
                                          v,
                                        ),
                                      );
                                    },
                                  );
                                },
                              ),
                              StreamBuilder<bool>(
                                stream: svc.cacheStream.map(
                                  (c) => c.pauseInitial,
                                ),
                                initialData: svc.cacheSettings.pauseInitial,
                                builder: (context, snap) {
                                  final enabled = snap.data ?? false;
                                  return SettingsSwitchTile(
                                    icon: LucideIcons.loader,
                                    title: 'Buffer before playing',
                                    subtitle: 'Smoother start on streams',
                                    value: enabled,
                                    onChanged: (v) {
                                      unawaited(
                                        svc.setCache(
                                          svc.cacheSettings.copyWith(
                                            pauseInitial: v,
                                          ),
                                        ),
                                      );
                                      unawaited(
                                        PlayerSettingsStore.saveCachePauseInitial(
                                          v,
                                        ),
                                      );
                                    },
                                  );
                                },
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: AfSpacing.s24),

                        // ── Offline cache (server mode only) ─────────────────────
                        if (!isLocal)
                          AfCollapsibleSection(
                            title: 'Offline cache',
                            child: SettingsGroup(
                              children: [
                                Consumer(
                                  builder: (context, ref2, _) {
                                    final enabled = ref2.watch(
                                      offlineCacheEnabledProvider,
                                    );
                                    return SettingsSwitchTile(
                                      icon: LucideIcons.hardDrive,
                                      title: 'Cache tracks offline',
                                      subtitle: enabled
                                          ? 'Save streamed tracks to device storage'
                                          : 'Always stream from server',
                                      value: enabled,
                                      onChanged: (v) {
                                        ref
                                                .read(
                                                  offlineCacheEnabledProvider
                                                      .notifier,
                                                )
                                                .state =
                                            v;
                                        unawaited(
                                          PlayerSettingsStore.saveOfflineCacheEnabled(
                                            v,
                                          ),
                                        );
                                      },
                                    );
                                  },
                                ),
                                _CacheUsageTile(),
                                SettingsTile(
                                  icon: LucideIcons.hardDrive,
                                  title: 'Max cache size',
                                  subtitle: OfflineCacheService.formatSize(
                                    ref.watch(offlineCacheMaxSizeProvider),
                                  ),
                                  onTap: () =>
                                      showOfflineCacheSizeDialog(context, ref),
                                ),
                              ],
                            ),
                          ),

                        const SizedBox(height: AfSpacing.s24),

                        // ── Audio processing ─────────────────────────────────────
                        AfCollapsibleSection(
                          title: 'Audio processing',
                          child: SettingsGroup(
                            children: [
                              SettingsTile(
                                icon: LucideIcons.slidersHorizontal,
                                title: 'ReplayGain',
                                subtitle: 'Volume normalization across tracks',
                                onTap: () => showReplayGainDialog(context, ref),
                              ),
                              SettingsTile(
                                icon: LucideIcons.skipForward,
                                title: 'Gapless playback',
                                subtitle: 'Seamless transitions between tracks',
                                onTap: () => showGaplessDialog(context, ref),
                              ),
                              SettingsSwitchTile(
                                icon: LucideIcons.download,
                                title: 'Prefetch next track',
                                subtitle:
                                    'Pre-load next playlist entry in background',
                                value: svc.prefetchPlaylist,
                                onChanged: (v) {
                                  unawaited(svc.setPrefetchPlaylist(v));
                                  unawaited(
                                    PlayerSettingsStore.savePrefetchPlaylist(v),
                                  );
                                },
                              ),
                              SettingsSwitchTile(
                                icon: LucideIcons.lightbulb,
                                title: 'Smart queue',
                                subtitle:
                                    'Learn from skips and plays for better suggestions',
                                value: ref.watch(smartQueueEnabledProvider),
                                onChanged: (v) {
                                  ref
                                          .read(
                                            smartQueueEnabledProvider.notifier,
                                          )
                                          .state =
                                      v;
                                },
                              ),
                            ],
                          ),
                        ),

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
                        AfCollapsibleSection(
                          title: 'About',
                          child: SettingsGroup(
                            children: [
                              FutureBuilder<PackageInfo>(
                                future: PackageInfo.fromPlatform(),
                                builder: (context, snap) {
                                  final version = snap.data != null
                                      ? 'v${snap.data!.version}+${snap.data!.buildNumber} ($kBuildId)'
                                      : '...';
                                  return SettingsTile(
                                    icon: LucideIcons.info,
                                    title: 'Aetherfin $version',
                                    subtitle:
                                        'Jellyfin-backed music player · FOSS',
                                  );
                                },
                              ),
                              SettingsTile(
                                icon: LucideIcons.code,
                                title: 'Source code',
                                subtitle: 'github.com/Aetherfin/mobile-app',
                                trailing: const Icon(
                                  LucideIcons.externalLink,
                                  color: AfColors.textTertiary,
                                  size: 16,
                                ),
                                onTap: () => launchSettingsUrl(
                                  'https://github.com/Aetherfin/mobile-app',
                                ),
                              ),
                              SettingsTile(
                                icon: LucideIcons.fileText,
                                title: 'Licenses',
                                subtitle: 'Open-source licenses',
                                onTap: () => showLicensePage(
                                  context: context,
                                  applicationName: 'Aetherfin',
                                  applicationLegalese:
                                      '© 2025 Aetherfin contributors',
                                ),
                              ),
                            ],
                          ),
                        ),

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

// ── Cache usage tile ─────────────────────────────────────────────────────────

class _CacheUsageTile extends ConsumerStatefulWidget {
  @override
  ConsumerState<_CacheUsageTile> createState() => _CacheUsageTileState();
}

class _CacheUsageTileState extends ConsumerState<_CacheUsageTile> {
  int _cacheSize = 0;
  int _cacheCount = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final cache = ref.read(offlineCacheServiceProvider);
    final size = await cache.cacheSize();
    final count = await cache.cachedCount();
    if (mounted) {
      setState(() {
        _cacheSize = size;
        _cacheCount = count;
        _loading = false;
      });
    }
  }

  Future<void> _clearCache() async {
    final confirmed = await showOfflineCacheClearDialog(context, ref);
    if (confirmed && mounted) {
      await ref.read(offlineCacheServiceProvider).clearCache();
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Cache cleared')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final maxSize = ref.watch(offlineCacheMaxSizeProvider);
    final usedLabel = OfflineCacheService.formatSize(_cacheSize);
    final maxLabel = OfflineCacheService.formatSize(maxSize);
    return SettingsTile(
      icon: LucideIcons.database,
      title: _loading ? 'Cache usage…' : 'Cache usage',
      subtitle: _loading
          ? null
          : '$_cacheCount tracks · $usedLabel / $maxLabel',
      trailing: _loading
          ? null
          : TextButton(
              onPressed: _cacheSize > 0 ? _clearCache : null,
              child: const Text('Clear'),
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
