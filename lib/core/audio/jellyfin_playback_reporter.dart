import 'dart:async';

import '../jellyfin/client.dart';
import '../jellyfin/models/items.dart';
import 'player_service.dart';

/// Pushes playback-session lifecycle events from [AfPlayerService] to the
/// Jellyfin server so the "Now Playing" widgets, listening history, and
/// activity feed all reflect what's actually playing.
///
/// Wired up in `playerServiceProvider` so the player itself stays
/// Riverpod-free. [clientGetter] is a *lazy* lookup (called on every
/// emit) so when auth flips and `jellyfinClientProvider` rebuilds with a
/// new `JellyfinClient`, the reporter automatically targets the new
/// server without any re-subscription dance.
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
  final AfPlayerService _player;
  final JellyfinClient? Function() _clientGetter;

  static const _progressInterval = Duration(seconds: 10);

  StreamSubscription<AfTrack?>? _trackSub;
  StreamSubscription<bool>? _playingSub;
  Timer? _progressTimer;
  String? _lastReportedTrackId;
  // dispose() must NOT send a `Stopped` ping when the reporter is being
  // torn down purely because the ProviderScope rebuilt around a still-
  // playing track — otherwise Jellyfin's activity feed flips to "stopped"
  // while audio keeps coming out the speaker. Set to false on every
  // intentional teardown (audio service stops, sign-out, app close).
  bool _shouldStopOnDispose = false;

  JellyfinPlaybackReporter(this._player, this._clientGetter) {
    _trackSub = _player.currentTrackStream.listen(_onTrackChanged);
    _playingSub = _player.playingStream.listen(_onPlayingChanged);
  }

  Future<void> _onTrackChanged(AfTrack? track) async {
    final client = _clientGetter();
    final previousId = _lastReportedTrackId;

    if (previousId != null && previousId != track?.id) {
      // Send the stop for the outgoing track before we open a session
      // for the incoming one — Jellyfin keys the active session by the
      // last reported start, and overlapping sessions confuse the
      // activity feed.
      final position = _player.position;
      if (client != null) {
        try {
          await client.reportPlaybackStop(previousId, position);
          // ignore: avoid_print
          print('aetherfin:data playbackStop source=live track=$previousId '
              'positionMs=${position.inMilliseconds}');
        } catch (e, stack) {
          // ignore: avoid_print
          print('aetherfin:error reportPlaybackStop failed: $e');
          // ignore: avoid_print
          print('aetherfin:error stack: $stack');
        }
      }
    }

    if (track == null) {
      _lastReportedTrackId = null;
      _stopProgressTimer();
      return;
    }
    if (track.id == previousId) return;

    _lastReportedTrackId = track.id;
    if (client == null) {
      // ignore: avoid_print
      print('aetherfin:data playbackStart source=demo track=${track.id} '
          '(no JellyfinClient; signed out)');
      _stopProgressTimer();
      return;
    }
    try {
      await client.reportPlaybackStart(track.id);
      // ignore: avoid_print
      print('aetherfin:data playbackStart source=live track=${track.id} '
          'title="${track.title}"');
      _startProgressTimer();
    } catch (e, stack) {
      // ignore: avoid_print
      print('aetherfin:error reportPlaybackStart failed: $e');
      // ignore: avoid_print
      print('aetherfin:error stack: $stack');
    }
  }

  Future<void> _onPlayingChanged(bool isPlaying) async {
    final trackId = _lastReportedTrackId;
    if (trackId == null) return;
    final client = _clientGetter();
    if (client == null) return;
    final position = _player.position;
    try {
      await client.reportProgress(
        trackId,
        position,
        isPaused: !isPlaying,
      );
      // ignore: avoid_print
      print('aetherfin:data playbackProgress source=live track=$trackId '
          'positionMs=${position.inMilliseconds} paused=${!isPlaying}');
    } catch (e, stack) {
      // ignore: avoid_print
      print('aetherfin:error reportProgress (transition) failed: $e');
      // ignore: avoid_print
      print('aetherfin:error stack: $stack');
    }
    if (isPlaying) {
      _startProgressTimer();
    } else {
      _stopProgressTimer();
    }
  }

  void _startProgressTimer() {
    _stopProgressTimer();
    _progressTimer = Timer.periodic(_progressInterval, (_) async {
      final trackId = _lastReportedTrackId;
      if (trackId == null) return;
      final client = _clientGetter();
      if (client == null) return;
      final position = _player.position;
      try {
        await client.reportProgress(trackId, position);
        // ignore: avoid_print
        print('aetherfin:data playbackProgress source=live track=$trackId '
            'positionMs=${position.inMilliseconds} (tick)');
      } catch (e, stack) {
        // ignore: avoid_print
        print('aetherfin:error reportProgress (tick) failed: $e');
        // ignore: avoid_print
        print('aetherfin:error stack: $stack');
      }
    });
  }

  void _stopProgressTimer() {
    _progressTimer?.cancel();
    _progressTimer = null;
  }

  Future<void> dispose() async {
    await _trackSub?.cancel();
    await _playingSub?.cancel();
    _stopProgressTimer();
    final trackId = _lastReportedTrackId;
    if (trackId == null) return;
    // Only emit a Stopped on dispose if it was explicitly requested
    // (sign-out, audio handler tear-down) — a Riverpod scope rebuild
    // around a still-playing track must NOT flip the activity feed.
    if (!_shouldStopOnDispose) return;
    final client = _clientGetter();
    if (client == null) return;
    final position = _player.position;
    try {
      await client.reportPlaybackStop(trackId, position);
      // ignore: avoid_print
      print('aetherfin:data playbackStop source=live track=$trackId '
          'positionMs=${position.inMilliseconds} (reporter disposed)');
    } catch (e, stack) {
      // ignore: avoid_print
      print('aetherfin:error reportPlaybackStop (dispose) failed: $e');
      // ignore: avoid_print
      print('aetherfin:error stack: $stack');
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
