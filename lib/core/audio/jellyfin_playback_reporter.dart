import 'dart:async';

import 'package:drift/drift.dart';

import '../../utils/log.dart';
import '../backend/music_backend.dart';
import '../jellyfin/models/items.dart';
import '../local/app_database.dart';
import 'player_service.dart';

/// Pushes playback-session lifecycle events from [AfPlayerService] to the
/// Jellyfin or Subsonic/Navidrome server so the "Now Playing" widgets,
/// listening history, and activity feed all reflect what's actually playing.
///
/// Wired up in `playerServiceProvider` so the player itself stays
/// Riverpod-free. [clientGetter] is a *lazy* lookup (called on every
/// emit) so when auth flips and `jellyfinClientProvider` rebuilds with a
/// new `JellyfinClient` or `NavidromeClient`, the reporter automatically
/// targets the new server without any re-subscription dance.
///
/// Endpoints used (per the Jellyfin REST conventions Finamp + the web
/// client agree on):
///   • `POST /Sessions/Playing`           — first emit for a new track
///   • `POST /Sessions/Playing/Progress`  — every 10s while playing,
///                                          and once on each pause / resume
///   • `POST /Sessions/Playing/Stopped`   — when the queue advances, the
///                                          player stops, or the reporter
///                                          is disposed
class JellyfinPlaybackReporter {
  JellyfinPlaybackReporter(this._player, this._clientGetter, this._db) {
    _trackSub = _player.currentTrackStream.listen(_onTrackChanged);
    _playingSub = _player.playingStream.listen(_onPlayingChanged);
  }
  final AfPlayerService _player;
  final MusicBackend? Function() _clientGetter;
  final AppDatabase _db;

  static const _progressInterval = Duration(seconds: 10);

  StreamSubscription<AfTrack?>? _trackSub;
  StreamSubscription<bool>? _playingSub;
  AfTrack? _lastReportedTrack;
  bool _disposed = false;
  // dispose() must NOT send a `Stopped` ping when the reporter is being
  // torn down purely because the ProviderScope rebuilt around a still-
  // playing track — otherwise Jellyfin's activity feed flips to "stopped"
  // while audio keeps coming out the speaker. Set to false on every
  // intentional teardown (audio service stops, sign-out, app close).
  bool _shouldStopOnDispose = false;

  Future<void> _onTrackChanged(AfTrack? track) async {
    if (_disposed) return;
    final client = _clientGetter();
    final previousTrack = _lastReportedTrack;

    // Stop the progress timer before sending playbackStop to prevent
    // the old loop from reporting progress for the previous track
    // after the stop has been sent.
    _stopProgressTimer();

    if (previousTrack != null && previousTrack.id != track?.id) {
      final position = _player.position;
      final listened = _player.listenedDuration;
      final duration = previousTrack.duration;
      final isThresholdMet =
          duration > Duration.zero && listened >= duration * 0.75;
      final isScrobble =
          isThresholdMet || listened >= const Duration(minutes: 4);

      final isSkip =
          !isScrobble &&
          listened >= const Duration(seconds: 2) &&
          (listened < const Duration(seconds: 30) ||
              (duration > Duration.zero && listened < duration * 0.35));

      if (isScrobble) {
        unawaited(
          _db
              .into(_db.playbackHistory)
              .insert(
                PlaybackHistoryCompanion.insert(
                  trackId: previousTrack.id,
                  playedAt: DateTime.now().millisecondsSinceEpoch,
                  title: Value(previousTrack.title),
                  artist: Value(previousTrack.artistName),
                  album: Value(previousTrack.albumName),
                  durationMs: Value(previousTrack.duration.inMilliseconds),
                  imageUrl: Value(previousTrack.imageUrl),
                  skipped: const Value(false),
                ),
              )
              .catchError((Object e) {
                afLog(
                  'playback-reporter',
                  'Failed to insert playback history',
                  error: e,
                );
                return 0;
              }),
        );
        afLog('data', 'Logged play history track=${previousTrack.id}');
      } else if (isSkip) {
        unawaited(
          _db
              .into(_db.playbackHistory)
              .insert(
                PlaybackHistoryCompanion.insert(
                  trackId: previousTrack.id,
                  playedAt: DateTime.now().millisecondsSinceEpoch,
                  title: Value(previousTrack.title),
                  artist: Value(previousTrack.artistName),
                  album: Value(previousTrack.albumName),
                  durationMs: Value(previousTrack.duration.inMilliseconds),
                  imageUrl: Value(previousTrack.imageUrl),
                  skipped: const Value(true),
                ),
              )
              .catchError((Object e) {
                afLog(
                  'playback-reporter',
                  'Failed to insert skip history',
                  error: e,
                );
                return 0;
              }),
        );
        afLog('data', 'Logged skip history track=${previousTrack.id}');
      }

      if (client != null) {
        try {
          await client
              .reportPlaybackStop(
                previousTrack.id,
                position,
                submission: isScrobble,
              )
              .timeout(const Duration(seconds: 5));
          if (_disposed) return;
          // Re-check after the await: a concurrent _onTrackChanged(null)
          // may have cleared _lastReportedTrack, invalidating our context.
          if (_lastReportedTrack?.id != previousTrack.id) return;
          afLog(
            'data',
            'playbackStop source=live track=${previousTrack.id} '
                'positionMs=${position.inMilliseconds} listenedMs=${listened.inMilliseconds} scrobble=$isScrobble',
          );
        } on Exception catch (e, stack) {
          afLog(
            'error',
            'reportPlaybackStop failed',
            error: e,
            stackTrace: stack,
          );
        }
      }
    }

    if (track == null) {
      _lastReportedTrack = null;
      return;
    }
    if (track.id == previousTrack?.id) return;
    if (_disposed) return;

    _lastReportedTrack = track;
    if (client == null) {
      afLog('data', 'playbackStart source=demo track=${track.id} (signed out)');
      return;
    }
    try {
      await client
          .reportPlaybackStart(track.id)
          .timeout(const Duration(seconds: 5));
      if (_disposed) return;
      afLog('data', 'playbackStart source=live track=${track.id}');
      _startProgressTimer();
    } on Exception catch (e, stack) {
      afLog('error', 'reportPlaybackStart failed', error: e, stackTrace: stack);
    }
  }

  Future<void> _onPlayingChanged(bool isPlaying) async {
    if (_disposed) return;
    final track = _lastReportedTrack;
    if (track == null) return;
    final trackId = track.id;
    final client = _clientGetter();
    if (client == null) return;
    final position = _player.position;
    try {
      await client
          .reportProgress(trackId, position, isPaused: !isPlaying)
          .timeout(const Duration(seconds: 5));
      afLog(
        'data',
        'playbackProgress source=live track=$trackId '
            'positionMs=${position.inMilliseconds} paused=${!isPlaying}',
      );
    } on Exception catch (e, stack) {
      afLog(
        'error',
        'reportProgress (transition) failed',
        error: e,
        stackTrace: stack,
      );
    }
    if (isPlaying) {
      _startProgressTimer();
    } else {
      _stopProgressTimer();
    }
  }

  void _startProgressTimer() {
    _stopProgressTimer();
    // Use a serialized loop instead of Timer.periodic to prevent concurrent
    // network calls. Timer.periodic does NOT await the callback — if the
    // server is slow, multiple in-flight requests pile up and stale progress
    // can arrive after newer progress, regressing backend state.
    //
    // The generation counter is what isolates restarts: a rapid
    // pause/resume within the 10s interval used to leave the previous
    // loop's `Future.delayed` still pending. When `_stopProgressTimer`
    // flips `_progressRunning` to false the old loop is sleeping, and by
    // the time it wakes a new `_startProgressTimer` has already flipped
    // it back to true — so the old loop kept ticking alongside the new
    // one. Bumping `_loopGeneration` per start lets every loop notice it
    // is no longer the active one regardless of the shared bool's value.
    _loopGeneration++;
    _progressRunning = true;
    _runProgressLoop(_loopGeneration);
  }

  bool _progressRunning = false;
  int _loopGeneration = 0;

  Future<void> _runProgressLoop(int generation) async {
    while (_progressRunning && generation == _loopGeneration) {
      await Future.delayed(_progressInterval);
      if (!_progressRunning || generation != _loopGeneration) break;
      final track = _lastReportedTrack;
      if (track == null) break;
      final trackId = track.id;
      final client = _clientGetter();
      if (client == null) break;
      final position = _player.position;
      try {
        await client
            .reportProgress(trackId, position)
            .timeout(const Duration(seconds: 5));
        afLog(
          'data',
          'playbackProgress source=live track=$trackId '
              'positionMs=${position.inMilliseconds} (tick)',
        );
      } on Exception catch (e, stack) {
        afLog(
          'error',
          'reportProgress (tick) failed',
          error: e,
          stackTrace: stack,
        );
        // Continue loop — a single failed tick shouldn't stop reporting.
      }
    }
  }

  void _stopProgressTimer() {
    _progressRunning = false;
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _trackSub?.cancel();
    await _playingSub?.cancel();
    _stopProgressTimer();
    final track = _lastReportedTrack;
    if (track == null) return;
    if (!_shouldStopOnDispose) return;
    try {
      final client = _clientGetter();
      if (client == null) return;
      final position = _player.position;
      final listened = _player.listenedDuration;
      final duration = track.duration;
      final isScrobble =
          duration > Duration.zero && listened >= duration * 0.75 ||
          listened >= const Duration(minutes: 4);

      if (isScrobble) {
        unawaited(
          _db
              .into(_db.playbackHistory)
              .insert(
                PlaybackHistoryCompanion.insert(
                  trackId: track.id,
                  playedAt: DateTime.now().millisecondsSinceEpoch,
                  title: Value(track.title),
                  artist: Value(track.artistName),
                  album: Value(track.albumName),
                  durationMs: Value(track.duration.inMilliseconds),
                  imageUrl: Value(track.imageUrl),
                  skipped: const Value(false),
                ),
              )
              .catchError((Object e) {
                afLog(
                  'playback-reporter',
                  'Failed to insert playback history (dispose)',
                  error: e,
                );
                return 0;
              }),
        );
        afLog('data', 'Logged play history (dispose) track=${track.id}');
      }

      try {
        await client
            .reportPlaybackStop(track.id, position, submission: isScrobble)
            .timeout(const Duration(seconds: 5));
        afLog(
          'data',
          'playbackStop source=live track=${track.id} '
              'positionMs=${position.inMilliseconds} listenedMs=${listened.inMilliseconds} scrobble=$isScrobble (reporter disposed)',
        );
      } on Exception catch (e, stack) {
        afLog(
          'error',
          'reportPlaybackStop (dispose) failed',
          error: e,
          stackTrace: stack,
        );
      }
    } catch (_) {
      // Ignored: container is likely already disposed.
    }
  }

  /// Call before [dispose] when the caller WANTS a final Stopped ping
  /// to be sent (sign-out, app close, queue cleared). Default is to
  /// keep the active session open so the activity feed isn't trashed
  /// by spurious teardowns.
  void requestStopOnDispose() {
    _shouldStopOnDispose = true;
  }
}
