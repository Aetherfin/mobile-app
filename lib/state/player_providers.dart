import 'dart:async' show unawaited, Timer, StreamSubscription;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mpv_audio_kit/mpv_audio_kit.dart'
    show Device, AudioParams, Loop, MpvPlayerError, FftFrame;

import '../design_tokens/tokens.dart';
import '../core/audio/active_queue_store.dart';
import '../core/audio/af_loop_mode.dart';
import '../core/audio/jellyfin_playback_reporter.dart';
import '../core/audio/lastfm_playback_reporter.dart';
import '../core/lyrics/lyrics_preload_manager.dart';
import '../core/audio/player_service.dart';
import '../core/audio/shuffle_mode.dart';
import '../core/backend/music_backend.dart';
import '../core/jellyfin/models/items.dart';
import '../core/local/local_db_tracks.dart';
import '../core/youtube/youtube_music_client.dart';
import 'app_mode_providers.dart';
import 'state_holder.dart';
import 'local_library_providers.dart';
import 'music_backend_providers.dart';
import 'settings_providers.dart';
import 'favorite_providers.dart';
import '../utils/log.dart';
import 'search_providers.dart';
import 'smart_queue_providers.dart';
import '../home_widget/home_widget_manager.dart';

/// Holds disposables accumulated during [wirePlayerService] wiring so each
/// extracted function can register resources that are torn down together.
class _WireDisposables {
  Timer? saveQueueDebounce;
  Timer? activeQueuePeriodicTimer;
  int saveLoopGen = 0; // ponytail: generation counter, cancels stale loops
  StreamSubscription<List<AfTrack>>? queueSub;
  StreamSubscription<AfTrack?>? trackSub;
  StreamSubscription<MpvPlayerError>? errorSub;
  StreamSubscription<bool>? bufferingSub;
  StreamSubscription<bool>? pausedForCacheSub;
  StreamSubscription<bool>? queueSavingPlayingSub;
  StreamSubscription<bool>? infraPlayingSub;
  ProviderSubscription<void>? backendListenSub;
  JellyfinPlaybackReporter? reporter;
  LastFmPlaybackReporter? lastfmReporter;
  ActiveQueueStore? activeQueueStore;

  Future<void> dispose() async {
    saveQueueDebounce?.cancel();
    activeQueuePeriodicTimer?.cancel();
    await queueSub?.cancel();
    await trackSub?.cancel();
    await errorSub?.cancel();
    await bufferingSub?.cancel();
    await pausedForCacheSub?.cancel();
    await queueSavingPlayingSub?.cancel();
    await infraPlayingSub?.cancel();
    backendListenSub?.close();
    await reporter?.dispose();
    await lastfmReporter?.dispose();
  }
}

void wirePlayerService(Ref ref, AfPlayerService svc) {
  final d = _WireDisposables();
  _wireQueueLoading(ref, svc, d);
  _wireQueueSaving(ref, svc, d);
  _wireServiceCallbacks(ref, svc);
  _wireInfrastructure(ref, svc, d);

  ref.onDispose(() async {
    await d.dispose();
    await svc.dispose();
  });
}

// ── Queue loading ──────────────────────────────────────────────────────────

Future<void> _wireQueueLoading(
  Ref ref,
  AfPlayerService svc,
  _WireDisposables d,
) async {
  Future<void> loadSavedQueue() async {
    final backend = ref.read(musicBackendProvider);
    if (backend == null) return;

    // Try backend first (returns full AfTrack objects).
    try {
      final saved = await backend.getPlayQueue();
      if (saved != null && saved.tracks.isNotEmpty) {
        afLog(
          'audio',
          'Loaded saved queue from backend: count=${saved.tracks.length} current=${saved.currentIndex}',
        );
        await svc.playQueue(
          saved.tracks,
          startIndex: saved.currentIndex,
          resolveStreamUrl: (track) => backend.trackStreamUrl(track.id),
        );
        if (saved.position > Duration.zero) {
          await svc.seek(saved.position);
        }
        await svc.pause();
        return;
      }
    } on Exception catch (e, stack) {
      afLog(
        'audio',
        'Failed to load saved queue from backend',
        error: e,
        stackTrace: stack,
      );
    }

    // Fallback: try restoring from local ActiveQueueStore.
    // This provides track IDs only — full object resolution requires
    // a backend tracksByIds endpoint (out of scope for this batch).
    try {
      final store = ActiveQueueStore();
      final local = await store.restore();
      if (local != null && local.trackIds.isNotEmpty) {
        afLog(
          'audio',
          'Found saved queue in ActiveQueueStore: '
              'count=${local.trackIds.length} '
              'currentIndex=${local.currentIndex} '
              'shuffle=${local.shuffleEnabled}',
        );
        // Track IDs are available in local.trackIds for future
        // resolution. Cannot play without backend tracksByIds support.
      }
    } on Exception catch (e, stack) {
      afLog(
        'audio',
        'Failed to restore active queue from local store',
        error: e,
        stackTrace: stack,
      );
    }
  }

  // Load initially if backend is already available
  if (ref.read(musicBackendProvider) != null) {
    unawaited(loadSavedQueue());
  }

  // Load saved queue when the user signs in later
  d.backendListenSub = ref.listen<MusicBackend?>(musicBackendProvider, (
    prev,
    next,
  ) {
    if (prev == null && next != null) {
      unawaited(loadSavedQueue());
    }
  });
}

// ── Queue saving ───────────────────────────────────────────────────────────

void _wireQueueSaving(Ref ref, AfPlayerService svc, _WireDisposables d) {
  void triggerSaveQueue() {
    d.saveQueueDebounce?.cancel();
    d.saveQueueDebounce = Timer(AfDurations.shimmer, () async {
      final backend = ref.read(musicBackendProvider);
      if (backend == null) return;

      final tracks = svc.currentQueue;
      if (tracks.isEmpty) return;

      final trackIds = tracks.map((t) => t.id).toList();
      final currentIndex = svc.currentIndex;
      final position = svc.position;

      try {
        await backend.savePlayQueue(
          trackIds,
          currentIndex: currentIndex >= 0 ? currentIndex : 0,
          position: position,
        );
      } on Exception catch (e) {
        afLog('audio', 'Failed to save play queue', error: e);
      }
    });
  }

  // Periodic save to ActiveQueueStore every 10 seconds while playing.
  // Uses a serialized async loop instead of Timer.periodic to prevent
  // overlapping saves (CLAUDE.md §15 item #35).
  Future<void> activeQueueSaveLoop(int gen) async {
    while (true) {
      await Future<void>.delayed(const Duration(seconds: 10));
      // Stop if timer was cancelled or a new loop started (play/pause race).
      if (d.activeQueuePeriodicTimer == null || gen != d.saveLoopGen) return;
      if (!svc.isPlaying) return; // exit — re-created on next play
      final tracks = svc.currentQueue;
      if (tracks.isEmpty) continue;

      final store = d.activeQueueStore ?? ActiveQueueStore();
      d.activeQueueStore = store;

      try {
        await store.save(
          trackIds: tracks.map((t) => t.id).toList(),
          currentIndex: svc.currentIndex >= 0 ? svc.currentIndex : 0,
          position: svc.position,
          shuffleEnabled: svc.isShuffleEnabled,
        );
      } on Exception catch (e) {
        afLog('audio', 'Failed to save active queue', error: e);
      }
    }
  }

  void startActiveQueuePeriodicTimer() {
    d.activeQueuePeriodicTimer?.cancel();
    d.activeQueuePeriodicTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) {},
    ); // non-null sentinel — actual work done by _activeQueueSaveLoop
    d.saveLoopGen++;
    unawaited(activeQueueSaveLoop(d.saveLoopGen));
  }

  // Start/stop the periodic timer based on playback state.
  d.queueSavingPlayingSub = svc.playingStream.listen((playing) {
    if (playing) {
      startActiveQueuePeriodicTimer();
    } else {
      d.activeQueuePeriodicTimer?.cancel();
      d.activeQueuePeriodicTimer = null;
    }
  });

  d.queueSub = svc.queueStream.listen((_) => triggerSaveQueue());
  d.trackSub = svc.currentTrackStream.listen((_) => triggerSaveQueue());
}

// ── Service callbacks ──────────────────────────────────────────────────────

void _wireServiceCallbacks(Ref ref, AfPlayerService svc) {
  AfTrack? prevTrack;
  bool wasSkip = false;
  LyricsPreloadManager? preloader;

  svc.onTrackSkipped = (oldTrack) {
    wasSkip = true;
    final sq = ref.read(smartQueueManagerProvider);
    final pos = ref.read(positionStreamProvider);
    final dur = oldTrack.duration;
    final completion = dur > Duration.zero
        ? (pos.inMilliseconds / dur.inMilliseconds).clamp(0.0, 1.0).toDouble()
        : 0.0;
    unawaited(
      sq.recordPlayback(oldTrack, completionRate: completion, isSkipped: true),
    );
  };

  svc.onTrackChanged = (track) {
    // Smart queue feedback for prev track
    if (prevTrack != null &&
        track != null &&
        track.id != prevTrack!.id &&
        !wasSkip) {
      final sq = ref.read(smartQueueManagerProvider);
      final pos = ref.read(positionStreamProvider);
      final dur = prevTrack!.duration;
      final completion = dur > Duration.zero
          ? (pos.inMilliseconds / dur.inMilliseconds).clamp(0.0, 1.0).toDouble()
          : 0.0;
      unawaited(
        sq.recordPlayback(
          prevTrack!,
          completionRate: completion,
          isSkipped: false,
        ),
      );
      unawaited(
        sq.recordTransition(prevTrack!, track, completionRate: completion),
      );
    }
    prevTrack = track;
    wasSkip = false;

    // Refill smart queue buffer
    if (track != null && ref.read(smartQueueEnabledProvider)) {
      final sq = ref.read(smartQueueManagerProvider);
      unawaited(sq.refillBuffer(track));
    }

    ref.read(currentTrackProvider.notifier).set(track);
    ref
        .read(currentArtworkUriProvider.notifier)
        .set(track != null ? svc.currentArtworkUri : null);

    // Update Android home screen widget on track change.
    HomeWidgetManager.update(
      title: track?.title ?? 'Not Playing',
      artist: track?.artistName ?? '',
      playing: svc.isPlaying,
      isFavorite: track?.isFavorite ?? false,
      artPath: _getArtPath(svc.currentArtworkUri),
    );
    ref.read(positionStreamProvider.notifier).set(Duration.zero);
    ref
        .read(durationStreamProvider.notifier)
        .set(
          (track != null && track.duration > Duration.zero)
              ? track.duration
              : Duration.zero,
        );
    ref.read(abLoopAProvider.notifier).set(null);
    ref.read(abLoopBProvider.notifier).set(null);

    // Preload lyrics for upcoming tracks (fire-and-forget)
    if (track != null && track.duration > Duration.zero) {
      final backend = ref.read(musicBackendProvider);
      if (backend != null) {
        preloader ??= LyricsPreloadManager(
          backend: backend,
          onCachedResult: (trackId, result) async {
            ref
                .read(lyricsCacheProvider.notifier)
                .update((prev) => {...prev, trackId: result});
          },
        );
        final queue = svc.currentQueue;
        final currentIdx = svc.currentIndex;
        preloader!.preloadNext(queue: queue, currentIndex: currentIdx);
      }
    }
  };

  svc.onArtworkUpdated = (artUri) {
    ref.read(currentArtworkUriProvider.notifier).set(artUri);
    // Refresh home widget artwork.
    final track = ref.read(currentTrackProvider);
    HomeWidgetManager.update(
      title: track?.title ?? 'Not Playing',
      artist: track?.artistName ?? '',
      playing: svc.isPlaying,
      isFavorite: track?.isFavorite ?? false,
      artPath: _getArtPath(artUri),
    );
  };

  svc.onMpvLoadedTrackChanged = (trackId) {
    ref.read(mpvLoadedTrackIdProvider.notifier).set(trackId);
  };

  svc.onToggleFavorite = () async {
    final track = ref.read(currentTrackProvider);
    if (track != null) {
      try {
        await ref.read(favoriteToggleProvider)(track);
      } on Exception catch (e) {
        afLog('audio', 'Favorite toggle from notification failed', error: e);
      }
      // Refresh home widget after favorite toggle.
      final updatedTrack = ref.read(currentTrackProvider);
      unawaited(
        HomeWidgetManager.update(
          title: updatedTrack?.title ?? 'Not Playing',
          artist: updatedTrack?.artistName ?? '',
          playing: svc.isPlaying,
          isFavorite: updatedTrack?.isFavorite ?? false,
          artPath: _getArtPath(ref.read(currentArtworkUriProvider)),
        ),
      );
    }
  };

  svc.onForNtimesChanged = (enabled) {
    ref.read(forNtimesModeProvider.notifier).set(enabled);
  };

  svc.onTrackCompleted = (track) async {
    final enabled = ref.read(offlineCacheEnabledProvider);
    if (!enabled) return;
    final mode = ref.read(appModeProvider);
    if (mode == AppMode.local) return;
    final backend = ref.read(musicBackendProvider);
    if (backend == null) return;

    // YouTube Music: resolve actual stream URL for caching.
    String url;
    if (backend is YouTubeMusicClient) {
      try {
        url = await backend.resolveStreamUrl(track.id);
      } on Exception catch (e) {
        afLog('audio', 'YouTube stream resolve failed for cache', error: e);
        return;
      }
    } else {
      final maxBitrate = ref.read(maxBitrateProvider);
      url = backend.trackStreamUrl(
        track.id,
        maxBitrateKbps: maxBitrate == 0 ? null : maxBitrate,
      );
    }

    final cache = ref.read(offlineCacheServiceProvider);
    unawaited(cache.cacheTrack(track.id, url, headers: backend.authHeaders));
  };

  svc.onGetSimilarTracks = (lastTrack) async {
    final sqEnabled = ref.read(smartQueueEnabledProvider);
    if (!sqEnabled) return const <AfTrack>[];

    final sq = ref.read(smartQueueManagerProvider);
    final existingIds = svc.currentQueue.map((t) => t.id).toSet();

    if (sq.isBufferLow) {
      await sq.refillBuffer(lastTrack);
    }

    final bufferTracks = sq
        .dequeueBatch(20)
        .where((t) => !existingIds.contains(t.id))
        .toList();
    if (bufferTracks.isNotEmpty) {
      unawaited(sq.refillBuffer(lastTrack));
      return bufferTracks.take(20).toList();
    }
    return const <AfTrack>[];
  };

  // Wire permanent cover art saving: when mpv extracts embedded cover art,
  // save it to the permanent cache and update the DB so artwork appears
  // in library views (not just Now Playing).
  svc.artworkManager.onPermanentCoverSaved = (trackId, coverPath) async {
    try {
      final db = ref.read(appDatabaseProvider);
      final repo = TrackRepository(db);
      await repo.updateCoverPath(trackId, coverPath);
      afLog('audio', 'DB cover_path updated for $trackId');
    } on Exception catch (e) {
      afLog('audio', 'Failed to update DB cover_path', error: e);
    }
  };
}

// ── Infrastructure ─────────────────────────────────────────────────────────

void _wireInfrastructure(Ref ref, AfPlayerService svc, _WireDisposables d) {
  _startPositionPolling(ref, svc);

  d.errorSub = svc.errorStream.listen((error) {
    ref.read(playbackErrorProvider.notifier).set(error);
  });

  void updateBuffering() {
    ref
        .read(playerIsBufferingProvider.notifier)
        .set(svc.isBuffering || svc.isPausedForCache);
  }

  d.bufferingSub = svc.bufferingStream.listen((_) => updateBuffering());
  d.pausedForCacheSub = svc.pausedForCacheStream.listen(
    (_) => updateBuffering(),
  );

  // Update home widget when play/pause state changes.
  d.infraPlayingSub = svc.playingStream.listen((playing) {
    final track = ref.read(currentTrackProvider);
    HomeWidgetManager.update(
      title: track?.title ?? 'Not Playing',
      artist: track?.artistName ?? '',
      playing: playing,
      isFavorite: track?.isFavorite ?? false,
      artPath: _getArtPath(ref.read(currentArtworkUriProvider)),
    );
  });

  d.reporter = JellyfinPlaybackReporter(
    svc,
    () => ref.read(musicBackendProvider),
    ref.read(appDatabaseProvider),
  );

  d.lastfmReporter = LastFmPlaybackReporter(
    svc,
    () => ref.read(lastFmClientProvider),
    () => ref.read(lastfmScrobbleEnabledProvider),
  );

  unawaited(svc.configureSpectrum());

  ref.listen<MusicBackend?>(musicBackendProvider, (prev, next) {
    if (prev != null && next == null) {
      d.reporter?.requestStopOnDispose();
      unawaited(d.reporter?.dispose());
      d.reporter = null;
    }
  });
}

final playerServiceProvider = Provider<AfPlayerService>((ref) {
  final svc = AfPlayerService();
  wirePlayerService(ref, svc);
  return svc;
});

final playerQueueProvider = StreamProvider.autoDispose<List<AfTrack>>((ref) {
  final svc = ref.watch(playerServiceProvider);
  return Stream<List<AfTrack>>.multi((controller) {
    controller.add(svc.currentQueue);
    final sub = svc.queueStream.listen(controller.add);
    controller.onCancel = sub.cancel;
  });
});

final positionStreamProvider =
    NotifierProvider<StateHolder<Duration>, Duration>(
      () => StateHolder<Duration>((ref) => Duration.zero),
    );
final durationStreamProvider =
    NotifierProvider<StateHolder<Duration>, Duration>(
      () => StateHolder<Duration>((ref) => Duration.zero),
    );
final playbackErrorProvider =
    NotifierProvider<StateHolder<MpvPlayerError?>, MpvPlayerError?>(
      () => StateHolder<MpvPlayerError?>((ref) => null),
    );
final abLoopAProvider = NotifierProvider<StateHolder<Duration?>, Duration?>(
  () => StateHolder<Duration?>((ref) => null),
);
final abLoopBProvider = NotifierProvider<StateHolder<Duration?>, Duration?>(
  () => StateHolder<Duration?>((ref) => null),
);

/// Bridges [AfPlayerService] position/duration streams into Riverpod
/// providers and handles EOF state reset.
void _startPositionPolling(Ref ref, AfPlayerService svc) {
  var disposed = false;

  ref.onDispose(() {
    disposed = true;
  });

  Duration? lastWrittenPosition;
  Duration? pendingPosition;
  Timer? positionThrottleTimer;

  // Throttled flush: writes the latest pending position and arms a 200 ms
  // cooldown timer. Subsequent events during the window store their value
  // but don't write, so only the latest position is ever emitted.
  void flushPendingPosition() {
    if (disposed) return;
    final pos = pendingPosition;
    if (pos == null || pos == lastWrittenPosition) {
      pendingPosition = null;
      return;
    }
    lastWrittenPosition = pos;
    ref.read(positionStreamProvider.notifier).set(pos);
    pendingPosition = null;
    positionThrottleTimer = Timer(
      AfDurations.quick, // 200→180ms, closest token
      flushPendingPosition,
    );
  }

  final posSub = svc.positionStream.listen((pos) {
    if (disposed) return;
    pendingPosition = pos;
    // If no timer is active, flush immediately (first event or after cooldown).
    if (!(positionThrottleTimer?.isActive ?? false)) {
      flushPendingPosition();
    }
  });

  final durSub = svc.durationStream.listen((dur) {
    if (dur > Duration.zero) {
      final current = ref.read(durationStreamProvider);
      if (dur != current) {
        ref.read(durationStreamProvider.notifier).set(dur);
      }
    }
  });

  // Duration poll loop — recursive Future.delayed instead of
  // Timer.periodic so the async callback never overlaps with itself.
  // Timer.periodic does NOT await the callback; if getRawDuration()
  // takes longer than 250 ms the ticks pile up, causing redundant
  // state writes and wasted work.
  int loopGeneration = 0;
  bool loopRunning = false;

  Future<void> runDurationPollLoop() async {
    final gen = loopGeneration;
    while (loopRunning && gen == loopGeneration) {
      await Future.delayed(AfDurations.ambient); // 1000→1200ms, closest token
      if (!loopRunning || gen != loopGeneration || disposed) break;

      final rawDur = await svc.getRawDuration();
      if (!loopRunning || gen != loopGeneration || disposed) return;

      if (rawDur > Duration.zero) {
        if (disposed) return;
        final current = ref.read(durationStreamProvider);
        if (rawDur != current) {
          ref.read(durationStreamProvider.notifier).set(rawDur);
        }
      } else {
        // Don't fallback to metadata duration while mpv is still
        // buffering — the real duration isn't known yet and the
        // progress bar would move prematurely.
        if (svc.isBuffering || svc.isPausedForCache) continue;
        final track = ref.read(currentTrackProvider);
        if (track != null && track.duration > Duration.zero) {
          if (disposed) return;
          ref.read(durationStreamProvider.notifier).set(track.duration);
        }
      }
    }
  }

  void cancelTimer() {
    loopRunning = false;
  }

  void ensureTimer() {
    if (disposed || loopRunning) return;
    loopGeneration++;
    loopRunning = true;
    runDurationPollLoop();
  }

  ensureTimer();

  ref.listen(currentTrackProvider, (prev, next) {
    if (prev != null && next == null) {
      cancelTimer();
    } else if (prev == null && next != null) {
      ensureTimer();
    }
    if (next != null && prev?.isFavorite != next.isFavorite) {
      svc.updateTrackFavorite(next.id, next.isFavorite);
    }
  });

  ref.onDispose(() {
    cancelTimer();
    positionThrottleTimer?.cancel();
    unawaited(posSub.cancel());
    unawaited(durSub.cancel());
  });
}

final playingStreamProvider = StreamProvider.autoDispose<bool>((ref) {
  final svc = ref.watch(playerServiceProvider);
  return svc.playingStream;
});

final shuffleModeProvider = StreamProvider.autoDispose<ShuffleMode>((ref) {
  final svc = ref.watch(playerServiceProvider);
  return Stream<ShuffleMode>.multi((controller) {
    controller.add(
      svc.isShuffleEnabled
          ? (svc.isTailShuffle ? ShuffleMode.tail : ShuffleMode.all)
          : ShuffleMode.off,
    );
    final sub = svc.shuffleModeStream.listen((enabled) {
      controller.add(
        enabled
            ? (svc.isTailShuffle ? ShuffleMode.tail : ShuffleMode.all)
            : ShuffleMode.off,
      );
    });
    controller.onCancel = sub.cancel;
  });
});

AfLoopMode _loopToAfLoopMode(Loop loop) {
  switch (loop) {
    case Loop.off:
      return AfLoopMode.off;
    case Loop.file:
      return AfLoopMode.file;
    case Loop.playlist:
      return AfLoopMode.playlist;
  }
}

final loopModeProvider = StreamProvider.autoDispose<AfLoopMode>((ref) {
  final svc = ref.watch(playerServiceProvider);
  final forNtimesActive = ref.watch(forNtimesModeProvider);
  if (forNtimesActive) {
    return Stream.value(AfLoopMode.forNtimes);
  }
  return Stream<AfLoopMode>.multi((controller) {
    controller.add(_loopToAfLoopMode(svc.loopMode));
    final sub = svc.loopModeStream.listen((loop) {
      controller.add(_loopToAfLoopMode(loop));
    });
    controller.onCancel = sub.cancel;
  });
});

final playbackSpeedProvider = StreamProvider.autoDispose<double>((ref) {
  final svc = ref.watch(playerServiceProvider);
  return Stream<double>.multi((controller) {
    controller.add(svc.speed);
    final sub = svc.speedStream.listen(controller.add);
    controller.onCancel = sub.cancel;
  });
});

final audioDeviceProvider = StreamProvider.autoDispose<Device?>((ref) {
  final svc = ref.watch(playerServiceProvider);
  return svc.audioDeviceStream.map((d) => d as Device?);
});

final audioDevicesProvider = StreamProvider.autoDispose<List<Device>>((ref) {
  final svc = ref.watch(playerServiceProvider);
  return svc.audioDevicesStream;
});

final audioExclusiveProvider = StreamProvider.autoDispose<bool>((ref) {
  final svc = ref.watch(playerServiceProvider);
  return svc.audioExclusiveStream;
});

final audioOutParamsProvider = StreamProvider.autoDispose<AudioParams?>((ref) {
  final svc = ref.watch(playerServiceProvider);
  return svc.audioOutParamsStream.map((p) => p as AudioParams?);
});

final audioStreamSilenceProvider = StreamProvider.autoDispose<bool>((ref) {
  final svc = ref.watch(playerServiceProvider);
  return svc.audioStreamSilenceStream;
});

final audioCachePauseInitialProvider = StreamProvider.autoDispose<bool>((ref) {
  final svc = ref.watch(playerServiceProvider);
  return svc.cacheStream.map((c) => c.pauseInitial);
});

final currentTrackProvider = NotifierProvider<StateHolder<AfTrack?>, AfTrack?>(
  () => StateHolder<AfTrack?>((ref) => null),
);
final currentArtworkUriProvider = NotifierProvider<StateHolder<Uri?>, Uri?>(
  () => StateHolder<Uri?>((ref) => null),
);
final mpvLoadedTrackIdProvider =
    NotifierProvider<StateHolder<String?>, String?>(
      () => StateHolder<String?>((ref) => null),
    );

final playerIsBufferingProvider = NotifierProvider<StateHolder<bool>, bool>(
  () => StateHolder<bool>((ref) {
    final svc = ref.watch(playerServiceProvider);
    return svc.isBuffering || svc.isPausedForCache;
  }),
);

final isBufferingProvider = Provider<bool>((ref) {
  final currentTrack = ref.watch(currentTrackProvider);
  if (currentTrack == null) return false;

  final loadedTrackId = ref.watch(mpvLoadedTrackIdProvider);
  if (currentTrack.id != loadedTrackId) {
    return true;
  }

  return ref.watch(playerIsBufferingProvider);
});

final ntimesCountProvider = NotifierProvider<StateHolder<int>, int>(
  () => StateHolder<int>((ref) => 2),
);

/// The current N value for forNtimes repeat mode. Defaults to 2.
final repeatCountProvider = NotifierProvider<StateHolder<int>, int>(
  () => StateHolder<int>((ref) => 2),
);

/// Whether forNtimes loop mode is currently active.
final forNtimesModeProvider = NotifierProvider<StateHolder<bool>, bool>(
  () => StateHolder<bool>((ref) => false),
);

final hasActivePlaybackProvider = Provider<bool>((ref) {
  return ref.watch(currentTrackProvider) != null;
});

/// Shared FFT frame provider — wraps the player's spectrum stream.
/// ponytail: removed .asBroadcastStream() — StreamProvider already manages
/// a single subscription. The extra broadcast wrapper buffered unread events
/// when now-playing was obscured, leaking memory.
final fftFrameProvider = StreamProvider.autoDispose<FftFrame?>((ref) {
  final svc = ref.watch(playerServiceProvider);
  return svc.spectrumStream.map((f) => f as FftFrame?);
});

/// Sub-bass energy derived from the first 7 post-DC FFT bands.
/// Used by the artwork pulse for kick-drum transient detection.
// ponytail: not gated on NowPlaying visibility — the only consumer
// (reactive_artwork) already autoDisposes when obscured, and the
// 7-band iteration at 120fps is negligible CPU. Adding an
// isNowPlayingVisible provider would require architectural changes
// across the widget tree for ~0.1ms/frame savings.
final bassEnergyProvider = Provider.autoDispose<double>((ref) {
  final frame = ref.watch(fftFrameProvider).value;
  if (frame == null || frame.bands.isEmpty) return 0.0;
  final int hi = frame.bands.length < 7 ? frame.bands.length : 7;
  double max = 0.0;
  for (var i = 1; i < hi; i++) {
    final v = frame.bands[i].abs();
    if (v > max) max = v;
  }
  return max;
});

String? _getArtPath(Uri? uri) {
  return uri != null && uri.isScheme('file') ? uri.toFilePath() : null;
}
