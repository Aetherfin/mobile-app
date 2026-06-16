import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:mpv_audio_kit/mpv_audio_kit.dart' show Loop;

import '../../core/audio/af_loop_mode.dart';
import '../../core/audio/shuffle_mode.dart';
import '../../core/jellyfin/models/items.dart';
import '../../design_tokens/tokens.dart';
import '../../state/providers.dart';
import '../../utils/log.dart';
import '../../widgets/af_dialog.dart';
import 'transport_row.dart';

/// Transport controls — play/pause/skip/shuffle/repeat.
class ReactiveTransport extends ConsumerWidget {
  const ReactiveTransport({super.key, required this.track});
  final AfTrack track;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isPlaying = ref
        .watch(playingStreamProvider)
        .maybeWhen(data: (v) => v, orElse: () => false);
    final shuffleMode = ref
        .watch(shuffleModeProvider)
        .maybeWhen(data: (v) => v, orElse: () => ShuffleMode.off);
    final loopMode = ref
        .watch(loopModeProvider)
        .maybeWhen(data: (v) => v, orElse: () => AfLoopMode.off);
    final spectral = ref.watch(
      currentSpectralProvider.select((s) => (energy: s.energy, muted: s.muted)),
    );

    return TransportRow(
      isPlaying: isPlaying,
      shuffleOn: shuffleMode != ShuffleMode.off,
      shuffleMode: shuffleMode,
      loopMode: loopMode,
      repeatCount: ref.watch(repeatCountProvider),
      accent: spectral.energy,
      muted: spectral.muted,
      onShuffle: () {
        final svc = ref.read(playerServiceProvider);
        unawaited(
          svc.setAfShuffleMode(!svc.isShuffleEnabled).catchError((
            Object e,
            StackTrace s,
          ) {
            afLog('audio', 'setAfShuffleMode failed', error: e, stackTrace: s);
          }),
        );
      },
      onShuffleLongPress: () => _showShuffleOptions(context, ref),
      onRepeat: () {
        final svc = ref.read(playerServiceProvider);
        final currentMode = ref
            .read(loopModeProvider)
            .maybeWhen(data: (v) => v, orElse: () => AfLoopMode.off);
        switch (currentMode) {
          case AfLoopMode.off:
            unawaited(
              svc.setAfLoopMode(Loop.playlist).catchError((
                Object e,
                StackTrace s,
              ) {
                afLog('audio', 'setAfLoopMode failed', error: e, stackTrace: s);
              }),
            );
            break;
          case AfLoopMode.playlist:
            unawaited(
              svc.setAfLoopMode(Loop.file).catchError((Object e, StackTrace s) {
                afLog('audio', 'setAfLoopMode failed', error: e, stackTrace: s);
              }),
            );
            break;
          case AfLoopMode.file:
            ref.read(forNtimesModeProvider.notifier).set(true);
            unawaited(
              svc.setAfForNtimes(true).catchError((Object e, StackTrace s) {
                afLog(
                  'audio',
                  'setAfForNtimes failed',
                  error: e,
                  stackTrace: s,
                );
              }),
            );
            break;
          case AfLoopMode.forNtimes:
            ref.read(forNtimesModeProvider.notifier).set(false);
            svc.setLoopModeOffSync();
            unawaited(
              svc.setAfForNtimes(false).catchError((Object e, StackTrace s) {
                afLog(
                  'audio',
                  'setAfForNtimes failed',
                  error: e,
                  stackTrace: s,
                );
              }),
            );
            break;
        }
      },
      onPlayPause: () {
        final svc = ref.read(playerServiceProvider);
        isPlaying ? svc.pause() : svc.play();
      },
      onPrev: () => ref.read(playerServiceProvider).skipToPrevious(),
      onNext: () => ref.read(playerServiceProvider).skipToNext(),
    );
  }

  void _showShuffleOptions(BuildContext context, WidgetRef ref) {
    showBlurDialog(
      context: context,
      builder: (context, dismiss) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Shuffle options', style: AfTypography.titleMedium),
          const SizedBox(height: AfSpacing.s16),
          ListTile(
            leading: const Icon(LucideIcons.shuffle),
            title: const Text('Shuffle all'),
            onTap: () {
              dismiss();
              ref.read(playerServiceProvider).setAfShuffleMode(true);
            },
          ),
          ListTile(
            leading: const Icon(LucideIcons.arrowDownWideNarrow),
            title: const Text('Shuffle next'),
            subtitle: const Text('Only upcoming tracks'),
            onTap: () {
              dismiss();
              ref.read(playerServiceProvider).setAfShuffleTail();
            },
          ),
        ],
      ),
    );
  }
}
