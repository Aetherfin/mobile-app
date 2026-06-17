import 'dart:async';

import '../../utils/log.dart';
import '../jellyfin/models/items.dart';
import '../lastfm/lastfm_client.dart';
import 'player_service.dart';

/// Pushes Now Playing updates and Scrobbles to Last.fm.
///
/// Listens to [AfPlayerService.currentTrackStream]. When a track starts,
/// we update "Now Playing". Monitors listened duration every 15 seconds
/// and scrobbles as soon as the threshold is met (rather than waiting
/// for track change).
///
/// Threshold (per Last.fm guidelines):
/// - Track must be > 30 seconds long
/// - AND played for >= 50% duration or >= 4 minutes (whichever first)
class LastFmPlaybackReporter {
  LastFmPlaybackReporter(
    this._player,
    this._clientGetter,
    this._enabledGetter,
  ) {
    _trackSub = _player.currentTrackStream.listen(_onTrackChanged);
    _scrobbleCheckTimer = Timer.periodic(
      const Duration(seconds: 15),
      (_) => _checkScrobbleMidPlayback(),
    );
  }

  final AfPlayerService _player;
  final LastFmClient? Function() _clientGetter;
  final bool Function() _enabledGetter;

  StreamSubscription<AfTrack?>? _trackSub;
  Timer? _scrobbleCheckTimer;
  AfTrack? _lastReportedTrack;
  final Set<String> _scrobbledTrackIds = {};
  bool _disposed = false;

  /// Returns true when the Last.fm scrobble threshold is met.
  bool _isThresholdMet(Duration listened, Duration duration) {
    return duration >= const Duration(seconds: 30) &&
        ((duration > Duration.zero && listened >= duration * 0.5) ||
            listened >= const Duration(minutes: 4));
  }

  /// Build the Unix timestamp (seconds since epoch) for when the track
  /// started playing, based on the current time minus listened duration.
  int _scrobbleTimestamp(Duration listened) =>
      DateTime.now().millisecondsSinceEpoch ~/ 1000 - listened.inSeconds;

  /// Submit a scrobble to Last.fm, fire-and-forget.
  void _submitScrobble(LastFmClient client, AfTrack track, Duration listened) {
    unawaited(
      client.scrobble(
        artist: track.artistName,
        track: track.title,
        album: track.albumName,
        duration: track.duration,
        timestamp: _scrobbleTimestamp(listened),
      ),
    );
  }

  /// Periodic check — scrobble early if threshold is met mid-playback.
  void _checkScrobbleMidPlayback() {
    if (_disposed) return;
    final client = _clientGetter();
    final enabled = _enabledGetter();
    final track = _lastReportedTrack;
    if (client == null || !enabled || track == null) return;
    if (_scrobbledTrackIds.contains(track.id)) return;

    final listened = _player.listenedDuration;
    if (_isThresholdMet(listened, track.duration)) {
      _scrobbledTrackIds.add(track.id);
      _submitScrobble(client, track, listened);
      afLog(
        'data',
        'Last.fm early scrobble: "${track.title}" '
            'at ${listened.inSeconds}s / ${track.duration.inSeconds}s',
      );
    }
  }

  Future<void> _onTrackChanged(AfTrack? track) async {
    if (_disposed) return;
    final client = _clientGetter();
    final enabled = _enabledGetter();

    if (client == null || !enabled) {
      _lastReportedTrack = track;
      return;
    }

    final previousTrack = _lastReportedTrack;

    // 1. Scrobble previous track if threshold met and not already sent
    //    by the mid-playback timer.
    if (previousTrack != null && previousTrack.id != track?.id) {
      if (!_scrobbledTrackIds.contains(previousTrack.id)) {
        final listened = _player.listenedDuration;
        if (_isThresholdMet(listened, previousTrack.duration)) {
          _submitScrobble(client, previousTrack, listened);
          _scrobbledTrackIds.add(previousTrack.id);
        } else {
          afLog(
            'data',
            'Last.fm track "${previousTrack.title}" skipped scrobble '
                '(listened: ${listened.inSeconds}s, duration: ${previousTrack.duration.inSeconds}s)',
          );
        }
      }
    }

    // 2. Scrobble last track when queue ends, then clean up
    if (track == null) {
      if (previousTrack != null &&
          !_scrobbledTrackIds.contains(previousTrack.id)) {
        final listened = _player.listenedDuration;
        if (_isThresholdMet(listened, previousTrack.duration)) {
          _submitScrobble(client, previousTrack, listened);
          _scrobbledTrackIds.add(previousTrack.id);
        }
      }
      _lastReportedTrack = null;
      _scrobbledTrackIds.clear();
      return;
    }

    if (track.id == previousTrack?.id) return;
    _lastReportedTrack = track;
    _scrobbledTrackIds.clear();

    // Send Now Playing update
    unawaited(
      client.updateNowPlaying(
        artist: track.artistName,
        track: track.title,
        album: track.albumName,
        duration: track.duration,
      ),
    );
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _scrobbleCheckTimer?.cancel();
    await _trackSub?.cancel();

    // Try scrobbling the final track upon disposal
    final track = _lastReportedTrack;
    try {
      final client = _clientGetter();
      final enabled = _enabledGetter();

      if (track != null &&
          client != null &&
          enabled &&
          !_scrobbledTrackIds.contains(track.id)) {
        final listened = _player.listenedDuration;
        if (_isThresholdMet(listened, track.duration)) {
          try {
            await client.scrobble(
              artist: track.artistName,
              track: track.title,
              album: track.albumName,
              duration: track.duration,
              timestamp: _scrobbleTimestamp(listened),
            );
          } on Exception catch (e, stack) {
            afLog(
              'error',
              'Last.fm final scrobble on dispose failed',
              error: e,
              stackTrace: stack,
            );
          }
        }
      }
    } catch (_) {
      // Ignored: container is likely already disposed.
    }
  }
}
