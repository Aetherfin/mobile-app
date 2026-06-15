import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/backend/music_backend.dart';
import '../core/jellyfin/models/items.dart';
import '../utils/log.dart';
import 'library_providers.dart';
import 'local_library_providers.dart';
import 'music_backend_providers.dart';
import 'settings_providers.dart';

/// Provider exposing favorite syncing action.
final lastFmSyncProvider = Provider<Future<({int toApp, int toLastFm})> Function()>((
  ref,
) {
  return () async {
    final client = ref.read(lastFmClientProvider);
    final sessionKey = ref.read(lastfmSessionKeyProvider);
    final username = ref.read(lastfmUsernameProvider);
    final backend = ref.read(musicBackendProvider);

    if (client == null ||
        sessionKey.isEmpty ||
        username.isEmpty ||
        backend == null) {
      throw StateError(
        'Last.fm integration or audio library is not connected.',
      );
    }

    afLog('data', 'Starting Last.fm favorite synchronization');

    // 1. Fetch loved tracks from Last.fm
    final lovedLastFm = await client.getLovedTracks(
      username: username,
      limit: 200,
    );

    // 2. Fetch favorite tracks from Backend
    final appFavorites = await backend.favoriteTracks(limit: 500);

    final backendKeys = appFavorites
        .map(
          (t) =>
              '${t.artistName.toLowerCase().trim()}::${t.title.toLowerCase().trim()}',
        )
        .toSet();

    final lastFmKeys = lovedLastFm
        .map(
          (t) =>
              '${t.artist.toLowerCase().trim()}::${t.title.toLowerCase().trim()}',
        )
        .toSet();

    int toApp = 0;
    int toLastFm = 0;

    // --- Sync: Last.fm -> App ---
    final missingInApp = lovedLastFm.where((t) {
      final key =
          '${t.artist.toLowerCase().trim()}::${t.title.toLowerCase().trim()}';
      return !backendKeys.contains(key);
    }).toList();

    // Limit syncing searches in one run to protect backend rate limits.
    // Process in batches of 5 concurrent searches to reduce sync time
    // from ~30 sequential calls to ~6 parallel batches.
    const batchSize = 5;
    final limitAppSync = missingInApp.take(30).toList();
    final resolvedTracks = <AfTrack>[];

    for (var i = 0; i < limitAppSync.length; i += batchSize) {
      final batch = limitAppSync.sublist(
        i,
        i + batchSize > limitAppSync.length
            ? limitAppSync.length
            : i + batchSize,
      );
      final results = await Future.wait(
        batch.map((item) async {
          try {
            if (backend.serverType == ServerType.local) {
              final db = ref.read(localLibraryProvider).db;
              return await db.searchTrackByArtistAndTitle(
                item.artist,
                item.title,
              );
            } else {
              final searchResults = await backend.search(
                '${item.artist} ${item.title}',
              );
              for (final t in searchResults.tracks) {
                if (t.title.toLowerCase() == item.title.toLowerCase() &&
                    t.artistName.toLowerCase() == item.artist.toLowerCase()) {
                  return t;
                }
              }
              for (final t in searchResults.tracks) {
                if (t.title.toLowerCase().contains(item.title.toLowerCase()) &&
                    t.artistName.toLowerCase().contains(
                      item.artist.toLowerCase(),
                    )) {
                  return t;
                }
              }
              return null;
            }
          } on Exception catch (e) {
            afLog(
              'error',
              'Failed to resolve track ${item.artist} - ${item.title}',
              error: e,
            );
            return null;
          }
        }),
        eagerError: false,
      );
      resolvedTracks.addAll(results.whereType<AfTrack>());
      await Future.delayed(const Duration(milliseconds: 200));
    }

    // Set favorites sequentially to respect backend rate limits.
    for (final track in resolvedTracks) {
      try {
        await backend.setFavorite(track.id, true);
        toApp++;
      } on Exception catch (e) {
        afLog(
          'error',
          'Failed to favorite track ${track.artistName} - ${track.title}',
          error: e,
        );
      }
    }

    // --- Sync: App -> Last.fm ---
    final missingInLastFm = appFavorites.where((t) {
      final key =
          '${t.artistName.toLowerCase().trim()}::${t.title.toLowerCase().trim()}';
      return !lastFmKeys.contains(key);
    }).toList();

    final limitLastFmSync = missingInLastFm.take(30);
    for (final item in limitLastFmSync) {
      try {
        await client.love(artist: item.artistName, track: item.title);
        toLastFm++;
      } on Exception catch (e) {
        afLog(
          'error',
          'Failed to love track ${item.artistName} - ${item.title} on Last.fm',
          error: e,
        );
      }
    }

    if (toApp > 0 || toLastFm > 0) {
      ref.invalidate(favoriteTracksProvider);
      ref.invalidate(favoriteIdsProvider);
    }

    return (toApp: toApp, toLastFm: toLastFm);
  };
});
