import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'state_holder.dart';

import 'local_library_providers.dart';
import 'settings_providers.dart';

/// Active period selected in the profile dashboard.
/// Last.fm expects: '7day' | '1month' | '3month' | '6month' | '12month' | 'overall'
final statsPeriodProvider = NotifierProvider<StateHolder<String>, String>(
  () => StateHolder<String>((ref) => '7day'),
);

/// Active stats tab: 'songs' | 'artists' | 'albums'
final statsTabProvider = NotifierProvider<StateHolder<String>, String>(
  () => StateHolder<String>((ref) => 'songs'),
);

/// Provider for user's top tracks chart.
final topTracksProvider =
    FutureProvider.autoDispose<
      List<({String artist, String title, int playCount, String? imageUrl})>
    >((ref) async {
      final client = ref.watch(lastFmClientProvider);
      final sessionKey = ref.watch(lastfmSessionKeyProvider);
      final username = ref.watch(lastfmUsernameProvider);
      final period = ref.watch(statsPeriodProvider);

      if (client != null && sessionKey.isNotEmpty && username.isNotEmpty) {
        final lastfmTracks = await client.getTopTracks(
          username: username,
          period: period,
          limit: 15,
        );
        return lastfmTracks
            .map(
              (t) => (
                artist: t.artist,
                title: t.title,
                playCount: t.playCount,
                imageUrl: null as String?,
              ),
            )
            .toList();
      } else {
        final db = ref.watch(localLibraryProvider).db;
        return db.getTopTracksFromHistory(limit: 15);
      }
    });

/// Provider for user's top artists chart.
final topArtistsProvider =
    FutureProvider.autoDispose<List<({String artist, int playCount})>>((
      ref,
    ) async {
      final client = ref.watch(lastFmClientProvider);
      final sessionKey = ref.watch(lastfmSessionKeyProvider);
      final username = ref.watch(lastfmUsernameProvider);
      final period = ref.watch(statsPeriodProvider);

      if (client != null && sessionKey.isNotEmpty && username.isNotEmpty) {
        return client.getTopArtists(
          username: username,
          period: period,
          limit: 15,
        );
      } else {
        final db = ref.watch(localLibraryProvider).db;
        return db.getTopArtistsFromHistory(limit: 15);
      }
    });

/// Provider for user's top albums chart.
final topAlbumsProvider =
    FutureProvider.autoDispose<
      List<({String artist, String album, int playCount, String? imageUrl})>
    >((ref) async {
      final client = ref.watch(lastFmClientProvider);
      final sessionKey = ref.watch(lastfmSessionKeyProvider);
      final username = ref.watch(lastfmUsernameProvider);
      final period = ref.watch(statsPeriodProvider);

      if (client != null && sessionKey.isNotEmpty && username.isNotEmpty) {
        return client.getTopAlbums(
          username: username,
          period: period,
          limit: 15,
        );
      } else {
        final db = ref.watch(localLibraryProvider).db;
        return db.getTopAlbumsFromHistory(limit: 15);
      }
    });
