import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/audio/offline_cache_service.dart';
import '../../core/audio/player_settings_store.dart';
import '../../design_tokens/tokens.dart';
import '../../state/providers.dart';
import 'settings_dialogs.dart';
import 'settings_widgets.dart';

/// Audio settings: output, network & cache, offline cache, audio processing.
///
/// Rebuilds independently when player streams, [maxBitrateProvider],
/// [offlineCacheEnabledProvider], or [smartQueueEnabledProvider] change.
class AudioSection extends ConsumerWidget {
  const AudioSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final svc = ref.read(playerServiceProvider);
    final isLocal = ref.watch(appModeProvider) == AppMode.local;

    return Column(
      children: [
        // ── Audio output ──────────────────────────────────────────
        AfCollapsibleSection(
          title: 'Audio output',
          child: SettingsGroup(
            children: [
              () {
                final params = ref.watch(audioOutParamsProvider).value;
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
              }(),
              () {
                final device = ref.watch(audioDeviceProvider).value;
                final label = device?.description.isNotEmpty == true
                    ? device!.description
                    : device?.name ?? 'Auto';
                return SettingsTile(
                  icon: LucideIcons.speaker,
                  title: 'Audio device',
                  subtitle: label,
                  onTap: () => showAudioDeviceDialog(context, ref),
                );
              }(),
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
              () {
                final enabled =
                    ref.watch(audioExclusiveProvider).value ?? false;
                return SettingsSwitchTile(
                  icon: LucideIcons.lock,
                  title: 'Exclusive mode',
                  subtitle: 'Bypass OS mixer for bit-perfect output',
                  value: enabled,
                  onChanged: (v) {
                    unawaited(svc.setAudioExclusive(v));
                    unawaited(PlayerSettingsStore.saveExclusive(v));
                  },
                );
              }(),
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
                onTap: () => showStreamingQualityDialog(context, ref),
              ),
              SettingsTile(
                icon: LucideIcons.rotateCcw,
                title: 'Cache duration',
                subtitle: 'How far ahead to buffer',
                onTap: () => showCacheDurationDialog(context, ref),
              ),
              SettingsTile(
                icon: LucideIcons.hardDrive,
                title: 'Buffer size',
                subtitle: 'Audio hardware buffer (latency vs stability)',
                onTap: () => showAudioBufferDialog(context, ref),
              ),
              () {
                final enabled =
                    ref.watch(audioStreamSilenceProvider).value ?? false;
                return SettingsSwitchTile(
                  icon: LucideIcons.volume2,
                  title: 'Keep audio active on pause',
                  subtitle: 'Eliminates click/pop on resume',
                  value: enabled,
                  onChanged: (v) {
                    unawaited(svc.setAudioStreamSilence(v));
                    unawaited(PlayerSettingsStore.saveStreamSilence(v));
                  },
                );
              }(),
              () {
                final enabled =
                    ref.watch(audioCachePauseInitialProvider).value ?? false;
                return SettingsSwitchTile(
                  icon: LucideIcons.loader,
                  title: 'Buffer before playing',
                  subtitle: 'Smoother start on streams',
                  value: enabled,
                  onChanged: (v) {
                    unawaited(
                      svc.setCache(svc.cacheSettings.copyWith(pauseInitial: v)),
                    );
                    unawaited(PlayerSettingsStore.saveCachePauseInitial(v));
                  },
                );
              }(),
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
                    final enabled = ref2.watch(offlineCacheEnabledProvider);
                    return SettingsSwitchTile(
                      icon: LucideIcons.hardDrive,
                      title: 'Cache tracks offline',
                      subtitle: enabled
                          ? 'Save streamed tracks to device storage'
                          : 'Always stream from server',
                      value: enabled,
                      onChanged: (v) {
                        ref.read(offlineCacheEnabledProvider.notifier).set(v);
                        unawaited(
                          PlayerSettingsStore.saveOfflineCacheEnabled(v),
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
                  onTap: () => showOfflineCacheSizeDialog(context, ref),
                ),
              ],
            ),
          ),

        if (!isLocal) const SizedBox(height: AfSpacing.s24),

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
                subtitle: 'Pre-load next playlist entry in background',
                value: svc.prefetchPlaylist,
                onChanged: (v) {
                  unawaited(svc.setPrefetchPlaylist(v));
                  unawaited(PlayerSettingsStore.savePrefetchPlaylist(v));
                },
              ),
              SettingsSwitchTile(
                icon: LucideIcons.lightbulb,
                title: 'Smart queue',
                subtitle: 'Learn from skips and plays for better suggestions',
                value: ref.watch(smartQueueEnabledProvider),
                onChanged: (v) {
                  ref.read(smartQueueEnabledProvider.notifier).set(v);
                },
              ),
            ],
          ),
        ),
      ],
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
