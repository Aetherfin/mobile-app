import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/providers.dart';
import '../../utils/log.dart';
import '../jellyfin/models/items.dart';
import 'play_actions_helpers.dart';

/// Cross-cutting "Play" entry points used by every screen so that we
/// don't replicate the wiring (and so the spectral provider always
/// updates first — per spec §3.4).
class PlayActions {
  PlayActions(this.ref);
  final Ref ref;

  /// Replace the queue with [tracks] and start playback at [startIndex].
  /// If shuffle mode is ON, the selected track plays first and the rest
  /// are shuffled below it.
  Future<void> playQueue(List<AfTrack> tracks, {int startIndex = 0}) async {
    if (tracks.isEmpty) return;
    final svc = ref.read(playerServiceProvider);

    final safeIndex = startIndex < 0
        ? 0
        : (startIndex >= tracks.length ? tracks.length - 1 : startIndex);

    // Don't pre-shuffle here — let mpv's shuffle mode handle randomization.
    final wasShuffleEnabled = svc.isShuffleEnabled == true;
    try {
      final mode = ref.read(appModeProvider);
      final backend = ref.read(musicBackendProvider);
      await svc.playQueue(
        tracks,
        startIndex: safeIndex,
        resolveStreamUrl: (t) => resolveStreamUrl(t, ref),
        // No auth headers needed for local files.
        streamHeaders: mode == AppMode.local
            ? const {}
            : (backend?.authHeaders ?? const {}),
      );
      if (wasShuffleEnabled) {
        await svc.setAfShuffleMode(true);
      }
      ref.read(currentTrackProvider.notifier).set(tracks[safeIndex]);

      // Save to queue history (non-critical — log warnings, don't throw)
      try {
        final repo = ref.read(queueHistoryRepositoryProvider);
        final sourceLabel = computeSourceLabel(tracks);
        final sourceType = computeSourceType();
        final sourceId = tracks.isNotEmpty
            ? tracks[0].albumId ?? tracks[0].artistId
            : null;
        await repo.save(
          trackIds: tracks.map((t) => t.id).toList(),
          sourceLabel: sourceLabel,
          sourceType: sourceType,
          sourceId: sourceId,
        );
      } on Exception catch (e, stack) {
        afLog('data', 'queueHistory save failed', error: e, stackTrace: stack);
      }
    } on Exception catch (e, stack) {
      afLog('audio', 'playQueue failed', error: e, stackTrace: stack);
      rethrow;
    }
  }

  Future<void> playAlbum(List<AfTrack> tracks) => playQueue(tracks);

  Future<void> playSingle(AfTrack track) async {
    await playQueue([track], startIndex: 0);

    final svc = ref.read(playerServiceProvider);
    final existingIds = svc.currentQueue.map((t) => t.id).toSet();
    final toAppend = <AfTrack>[];

    // 1. Smart queue buffer
    if (ref.read(smartQueueEnabledProvider)) {
      final sq = ref.read(smartQueueManagerProvider);
      await sq.refillBuffer(track);
      for (final t in sq.dequeueBatch(20)) {
        if (toAppend.length >= 20) break;
        if (existingIds.add(t.id)) toAppend.add(t);
      }
    }

    // 2. Fallback until we hit 20
    if (toAppend.length < 20) {
      final similar = await getSimilarTracks(track, existingIds, ref);
      for (final t in similar) {
        if (toAppend.length >= 20) break;
        if (existingIds.add(t.id)) toAppend.add(t);
      }
    }

    if (toAppend.isEmpty) return;
    await svc.appendQueue(
      toAppend,
      resolveStreamUrl: (t) => resolveStreamUrl(t, ref),
    );
  }

  /// Play a track followed by all other tracks scored and sorted by smart queue.
  Future<void> playSmartQueue(AfTrack seed, List<AfTrack> allTracks) async {
    if (allTracks.isEmpty) return;
    final sqEnabled = ref.read(smartQueueEnabledProvider);

    List<AfTrack> sorted;
    if (sqEnabled && allTracks.length > 1) {
      sorted = await ref
          .read(smartQueueManagerProvider)
          .scoreAndSort(seed, allTracks);
    } else {
      sorted = List.from(allTracks);
    }

    // Ensure seed is first
    final seedIdx = sorted.indexWhere((t) => t.id == seed.id);
    if (seedIdx > 0) {
      sorted.removeAt(seedIdx);
      sorted.insert(0, seed);
    }

    await playQueue(sorted, startIndex: 0);
  }

  /// Replace the queue with the seed track followed by Jellyfin's Instant Mix
  /// of similar songs. Falls back to playing the single track on
  /// signed-out / demo builds.
  Future<void> playInstantMix(AfTrack seed, {bool wait = false}) async {
    // 1. Play the seed track immediately so the user doesn't wait
    await playQueue([seed], startIndex: 0);

    final backend = ref.read(musicBackendProvider);
    if (backend == null) return;

    // 2. Fetch the mix and backfill
    final future = () async {
      try {
        final localLib = ref.read(localLibraryProvider);
        final skippedIds = await localLib.db
            .getRecentlySkippedTrackIds()
            .catchError((_) => <String>[]);
        final mix = await backend.instantMix(seed.id);

        var queue = <AfTrack>[
          for (final t in mix)
            if (t.id != seed.id && !skippedIds.contains(t.id)) t,
        ];

        if (queue.length < 29) {
          final backfillSeedQueue = <AfTrack>[seed, ...queue];
          final backfilled = await backfillQueue(
            backend,
            backfillSeedQueue,
            ref,
            targetSize: 30,
          );
          queue = backfilled.where((t) => t.id != seed.id).toList();
        }

        if (queue.isNotEmpty) {
          final svc = ref.read(playerServiceProvider);
          // Only append if the active track is still the seed track
          if (svc.currentTrack?.id == seed.id) {
            await svc.appendQueue(
              queue,
              resolveStreamUrl: (t) => resolveStreamUrl(t, ref),
            );
          }
        }
      } on Exception catch (e, stack) {
        afLog(
          'audio',
          'background instantMix/backfill failed',
          error: e,
          stackTrace: stack,
        );
      }
    }();

    if (wait) {
      await future;
    } else {
      unawaited(future);
    }
  }
}

final playActionsProvider = Provider<PlayActions>(PlayActions.new);
