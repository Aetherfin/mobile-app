import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/backend/music_backend.dart';
import '../core/jellyfin/models/items.dart';
import '../utils/log.dart';
import 'local_library_providers.dart';
import 'music_backend_providers.dart';
import 'settings_providers.dart';
import 'smart_queue_providers.dart';

final radioGeneratorProvider = Provider<RadioGenerator>((ref) {
  return RadioGenerator(ref);
});

class RadioGenerator {
  RadioGenerator(this.ref);
  final Ref ref;

  /// Generates a radio queue seeded by a single track using the smart
  /// queue scoring algorithm (same as Songs/Library screens).
  ///
  /// Returns the seed followed by the top 50 scored tracks. The queue is
  /// auto-expandable via [SmartQueueManager.refillBuffer] when the end is
  /// near (wired through [AfPlayerService.onGetSimilarTracks]).
  Future<List<AfTrack>> generateTrackRadio(AfTrack seed) async {
    final backend = ref.read(musicBackendProvider);
    if (backend == null) return [seed];

    final sq = ref.read(smartQueueManagerProvider);

    if (backend.serverType != ServerType.local) {
      try {
        // Fetch a pool of candidates from the server's similarity endpoint
        final mix = await backend.instantMix(seed.id, limit: 150);
        if (mix.isNotEmpty) {
          final sorted = await sq.scoreAndSort(seed, mix);
          final withoutSeed = sorted.where((t) => t.id != seed.id).toList();
          return [seed, ...withoutSeed.take(50)];
        }
      } catch (e, stack) {
        afLog(
          'error',
          'Server-side similarity scoring failed, falling back to local',
          error: e,
          stackTrace: stack,
        );
      }
    }

    final allTracks = await _fetchAllTracks(backend);
    if (allTracks.length <= 1) return [seed];

    final sorted = await sq.scoreAndSort(seed, allTracks);
    final withoutSeed = sorted.where((t) => t.id != seed.id).toList();
    // Cap at 50 so the queue doesn't overwhelm the player on large
    // libraries.  RefillBuffer handles expanding when near the end.
    final limited = withoutSeed.take(50).toList();
    return [seed, ...limited];
  }

  Future<List<AfTrack>> _fetchAllTracks(MusicBackend backend) async {
    try {
      if (backend.serverType == ServerType.local) {
        return await ref.read(localTracksProvider.future);
      }
      return await backend.allTracks(limit: 5000);
    } catch (e, stack) {
      afLog(
        'error',
        'Fetch all tracks for radio failed',
        error: e,
        stackTrace: stack,
      );
      return [];
    }
  }

  /// Generates a radio queue seeded by an artist name.
  Future<List<AfTrack>> generateArtistRadio(
    String artistName,
    String? artistId,
  ) async {
    final client = ref.read(lastFmClientProvider);
    final backend = ref.read(musicBackendProvider);
    if (backend == null) return const [];

    // 1. Try Last.fm to get similar artists
    if (client != null) {
      try {
        final similarArtists = await client.getSimilarArtists(
          artistName: artistName,
          limit: 15,
        );

        if (similarArtists.isNotEmpty) {
          final resolved = await _resolveArtistsTracks(backend, similarArtists);
          if (resolved.isNotEmpty) {
            return resolved;
          }
        }
      } on Exception catch (e) {
        afLog('radio', 'Similar artists fallback failed', error: e);
      }
    }

    // 2. Fallback to artist top tracks or general artist query search
    try {
      if (artistId != null) {
        final top = await backend.artistTopTracks(artistId, limit: 20);
        if (top.isNotEmpty) return top;
      } else {
        final results = await backend.search(artistName);
        if (results.tracks.isNotEmpty) return results.tracks;
      }
    } on Exception catch (e) {
      afLog('radio', 'Artist top tracks fallback failed', error: e);
    }

    return const [];
  }

  /// Resolve 1-2 tracks for each similar artist name.
  Future<List<AfTrack>> _resolveArtistsTracks(
    MusicBackend backend,
    List<String> artistNames,
  ) async {
    final resolved = <AfTrack>[];

    // Process in batches of 4
    const batchSize = 4;
    for (var i = 0; i < artistNames.length; i += batchSize) {
      final batch = artistNames.skip(i).take(batchSize);
      final futures = batch.map((name) async {
        try {
          if (backend.serverType == ServerType.local) {
            final db = ref.read(localLibraryProvider).db;
            final tracks = await db.tracksByArtist(name);
            return tracks.take(2).toList();
          } else {
            final results = await backend.search(name);
            final artistTracks = results.tracks
                .where((t) => t.artistName.toLowerCase() == name.toLowerCase())
                .take(2)
                .toList();
            if (artistTracks.isNotEmpty) return artistTracks;

            return results.tracks
                .where(
                  (t) =>
                      t.artistName.toLowerCase().contains(name.toLowerCase()),
                )
                .take(2)
                .toList();
          }
        } on Exception catch (e) {
          afLog('radio', 'Artist track resolution failed for batch', error: e);
        }
        return <AfTrack>[];
      });

      final results = await Future.wait(futures);
      for (final list in results) {
        resolved.addAll(list);
      }

      if (resolved.length >= 20) break;
    }

    return resolved;
  }
}
