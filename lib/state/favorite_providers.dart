import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../core/jellyfin/models/items.dart';
import '../utils/log.dart';
import 'library_providers.dart';
import 'music_backend_providers.dart';
import 'settings_providers.dart';

void _logData(String feature, {required String source, String? extra}) {
  final detail = extra == null || extra.isEmpty ? '' : ' $extra';
  afLog('data', '$feature source=$source$detail');
}

/// Map-based track favorite overrides for optimistic UI updates.
///
/// Holds a `Map<String, bool>` of track id → overridden favorite state.
/// Widgets that display a heart for any track watch this provider via
/// `.select((map) => map[id] ?? ...)` so only the specific heart rebuilds.
/// The `.family` variant below is kept for granular access from providers
/// that need to watch a single track's override without rebuilding on
/// other tracks' toggles.
final trackFavoriteOverridesProvider = StateProvider<Map<String, bool>>(
  (ref) => const {},
);

/// Per-track favorite override for optimistic UI updates.
///
/// Each track gets its own state (null = no override, true/false = override).
/// Using `.family` means only the specific track's watchers rebuild on toggle,
/// instead of every track in the library.
final trackFavoriteOverrideProvider = StateProvider.family<bool?, String>(
  (ref, trackId) => null,
);

/// Derives the favorite state for a specific track by merging per-track
/// overrides (from optimistic UI) with the server/library favorite IDs.
final isFavoriteProvider = Provider.family<bool, String>((ref, trackId) {
  final override = ref.watch(trackFavoriteOverrideProvider(trackId));
  if (override != null) return override;
  final favIds = ref.watch(favoriteIdsProvider);
  return favIds.contains(trackId);
});

final favoriteToggleProvider = Provider<Future<void> Function(AfTrack)>((ref) {
  /// Serializer: any previous in-flight toggle must resolve before the
  /// next one starts. Without this, rapid double-taps create a race
  /// between optimistic overrides and backend responses — the earlier
  /// toggle's error-handler can restore a stale value, and two
  /// concurrent `setFavorite` calls can leave the server in the
  /// opposite state from what the override map shows.
  Future<void>? pending;

  return (AfTrack track) async {
    while (pending != null) {
      try {
        await pending!;
      } on Exception catch (e, stack) {
        afLog(
          'error',
          'Previous favorite toggle failed, proceeding',
          error: e,
          stackTrace: stack,
        );
      }
    }

    final backend = ref.read(musicBackendProvider);
    final override = ref.read(trackFavoriteOverrideProvider(track.id));
    final wasFavorite = override ?? track.isFavorite;
    final next = !wasFavorite;
    ref.read(trackFavoriteOverrideProvider(track.id).notifier).state = next;

    if (backend == null) {
      _logData(
        'favoriteToggle',
        source: 'demo',
        extra: '(signed out) id=${track.id} isFavorite=$next',
      );
      return;
    }

    pending = (() async {
      try {
        await backend.setFavorite(track.id, next);
        _logData(
          'favoriteToggle',
          source: 'live',
          extra: 'id=${track.id} isFavorite=$next',
        );

        // Sync to Last.fm if account is linked
        final lastFmClient = ref.read(lastFmClientProvider);
        final sessionKey = ref.read(lastfmSessionKeyProvider);
        if (lastFmClient != null && sessionKey.isNotEmpty) {
          try {
            if (next) {
              await lastFmClient.love(
                artist: track.artistName,
                track: track.title,
              );
            } else {
              await lastFmClient.unlove(
                artist: track.artistName,
                track: track.title,
              );
            }
          } on Exception catch (e, stack) {
            afLog(
              'error',
              'Last.fm love/unlove failed during toggle',
              error: e,
              stackTrace: stack,
            );
          }
        }

        ref.invalidate(favoriteAlbumsProvider);
        ref.invalidate(favoriteTracksProvider);
        ref.invalidate(recentlyPlayedTracksProvider);
      } on Exception catch (e, stack) {
        afLog('error', 'favoriteToggle failed', error: e, stackTrace: stack);
        ref.read(trackFavoriteOverrideProvider(track.id).notifier).state =
            wasFavorite;
        rethrow;
      }
    })();

    try {
      await pending!;
    } finally {
      pending = null;
    }
  };
});
