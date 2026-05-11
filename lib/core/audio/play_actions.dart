import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/providers.dart';
import '../jellyfin/models/items.dart';

/// Cross-cutting "Play" entry points used by every screen so that we
/// don't replicate the wiring (and so the spectral provider always
/// updates first — per spec §3.4).
class PlayActions {
  final Ref ref;
  PlayActions(this.ref);

  /// Replace the queue with [tracks] and start playback at [startIndex].
  Future<void> playQueue(
    List<AfTrack> tracks, {
    int startIndex = 0,
  }) async {
    if (tracks.isEmpty) return;
    final svc = ref.read(playerServiceProvider);
    final client = ref.read(jellyfinClientProvider);

    String resolveStreamUrl(AfTrack t) {
      // When connected to Jellyfin, ask the server for a transcode-aware URL.
      if (client != null) {
        return client.trackStreamUrl(t.id, maxBitrateKbps: 320);
      }
      // Demo mode — no real stream URLs. The audio service will simply
      // surface buffering, which is the honest UX for "no server configured".
      return 'about:blank';
    }

    ref.read(currentTrackProvider.notifier).state = tracks[startIndex];
    if (client != null) {
      try {
        await svc.playQueue(
          tracks,
          startIndex: startIndex,
          resolveStreamUrl: resolveStreamUrl,
        );
      } catch (e, stack) {
        // Leave the queue staged so the mini-player keeps the track
        // visible, but log loudly so a logcat capture shows the cause
        // (`aetherfin:audio` lines from player_service already cover
        // setAudioSource/play failures; this catches anything thrown
        // before/around them).
        // ignore: avoid_print
        print('aetherfin:audio playQueue failed: $e');
        // ignore: avoid_print
        print('aetherfin:audio stack: $stack');
      }
    }
  }

  Future<void> playAlbum(List<AfTrack> tracks) => playQueue(tracks);

  Future<void> playSingle(AfTrack track) =>
      playQueue([track], startIndex: 0);
}

final playActionsProvider = Provider<PlayActions>((ref) => PlayActions(ref));
