import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart' show LoopMode;

import '../core/audio/jellyfin_playback_reporter.dart';
import '../core/audio/player_service.dart';
import '../core/audio/spectral_extractor.dart';
import '../core/demo/demo_library.dart';
import '../core/jellyfin/auth_storage.dart';
import '../core/jellyfin/client.dart';
import '../core/jellyfin/models/items.dart';
import '../core/jellyfin/models/server.dart';
import '../core/lyrics/lrc_parser.dart';
import '../design_tokens/colors.dart';

/// Compact one-liner for the `aetherfin:data` trace category.
///
/// Every place that resolves data the UI will render goes through this
/// helper so an `adb logcat -s flutter | grep aetherfin:data` output
/// shows exactly which feature served live Jellyfin data vs. demo data
/// vs. still-mocked data. Used by reviewers to spot regressions where a
/// screen silently slips back onto `DemoLibrary` after sign-in.
void _logData(
  String feature, {
  required String source,
  String? extra,
}) {
  final detail = extra == null || extra.isEmpty ? '' : ' $extra';
  // ignore: avoid_print
  print('aetherfin:data $feature source=$source$detail');
}

/// ─────────────────────────────────────────────────────────────────────────
/// Auth
/// ─────────────────────────────────────────────────────────────────────────

final authStorageProvider = Provider<AuthStorage>((ref) => AuthStorage());

/// Stable per-install device ID used in the Jellyfin Authorization header.
/// Overridden at app startup in `main.dart` with the value loaded from
/// `AuthStorage.loadOrCreateDeviceId()`. Throws if accessed before that
/// override is applied — a loud failure is preferable to silently sending
/// the literal string "uninitialized" to Jellyfin.
final deviceIdProvider = Provider<String>((ref) {
  throw StateError(
    'deviceIdProvider was read before being overridden in main(). '
    'This is a bug — ProviderScope must override it with the value '
    'returned by AuthStorage.loadOrCreateDeviceId().',
  );
});

/// Auth blob loaded synchronously from secure storage at app startup.
/// Overridden in `main.dart` so that [authProvider]'s initial state is
/// the persisted auth (if any) — never `null` followed by an async
/// hydrate() that would race with a sign-in `save()` and clobber it.
final initialAuthProvider = Provider<JellyfinAuth?>((ref) {
  throw StateError(
    'initialAuthProvider was read before being overridden in main(). '
    'This is a bug — ProviderScope must override it with the value '
    'returned by AuthStorage.load() (or null when no auth is stored).',
  );
});

final authProvider = StateNotifierProvider<AuthNotifier, JellyfinAuth?>((ref) {
  return AuthNotifier(
    ref.watch(authStorageProvider),
    initial: ref.watch(initialAuthProvider),
  );
});

class AuthNotifier extends StateNotifier<JellyfinAuth?> {
  final AuthStorage _storage;
  AuthNotifier(this._storage, {JellyfinAuth? initial}) : super(initial);

  /// Persist [auth] FIRST, then flip in-memory state.
  ///
  /// Previously we set `state = auth` before the storage write — if the
  /// keystore was full / corrupted the user looked signed in but the
  /// next app launch would silently kick them back to onboarding. By
  /// failing loudly here the sign-in screen surfaces the error instead,
  /// and a successful flip implies the secret already hit disk.
  Future<void> save(JellyfinAuth auth) async {
    await _storage.save(auth);
    state = auth;
  }

  Future<void> clear() async {
    // The Jellyfin client provider listens to this state and tears
    // itself down (HTTP cache + connection pool) via `ref.onDispose`
    // when `state` flips to null.
    state = null;
    await _storage.clear();
  }
}

/// ─────────────────────────────────────────────────────────────────────────
/// Jellyfin client (null when no auth — UI uses demo data in that case)
/// ─────────────────────────────────────────────────────────────────────────

final jellyfinClientProvider = Provider<JellyfinClient?>((ref) {
  final auth = ref.watch(authProvider);
  if (auth == null) {
    _logData('jellyfinClient', source: 'demo', extra: '(signed out)');
    return null;
  }
  _logData('jellyfinClient',
      source: 'live',
      extra: 'server=${auth.server.baseUrl} user=${auth.userName}');
  final client = JellyfinClient(
    server: auth.server,
    deviceId: ref.watch(deviceIdProvider),
    accessToken: auth.accessToken,
    userId: auth.userId,
  );
  // When auth flips (sign-out, account switch) the provider rebuilds —
  // tear down the old client so its HTTP cache + connection pool don't
  // leak across accounts.
  ref.onDispose(client.close);
  return client;
});

/// ─────────────────────────────────────────────────────────────────────────
/// Audio player (singleton handler)
/// ─────────────────────────────────────────────────────────────────────────

/// Wires Riverpod-side side-effects onto an [AfPlayerService] instance:
///   1. Forwards `onTrackChanged` to `currentTrackProvider` so the UI
///      re-renders on queue advance / manual skip / lock-screen action.
///   2. Instantiates the [JellyfinPlaybackReporter] (Sessions/Playing*
///      lifecycle) bound to the same service.
///   3. Registers disposal so both the reporter and the service shut
///      down when the ProviderScope is torn down.
///
/// Pulled out as a free function so `main.dart` can hand the *same*
/// service instance to `AudioService.init` (for lock-screen controls)
/// and to the provider tree — without duplicating the wiring logic
/// across the default factory and the override.
void wirePlayerService(Ref ref, AfPlayerService svc) {
  svc.onTrackChanged = (track) {
    ref.read(currentTrackProvider.notifier).state = track;
  };
  final reporter = JellyfinPlaybackReporter(
    svc,
    () => ref.read(jellyfinClientProvider),
  );
  ref.onDispose(() async {
    await reporter.dispose();
    await svc.dispose();
  });
}

final playerServiceProvider = Provider<AfPlayerService>((ref) {
  final svc = AfPlayerService();
  wirePlayerService(ref, svc);
  return svc;
});

/// Live queue exposed by the player. The Queue screen watches this so
/// reorder / skip / play-new-album immediately re-render — no more
/// snapshotting `DemoLibrary.tracks` into local state.
final playerQueueProvider = StreamProvider.autoDispose<List<AfTrack>>((ref) {
  final svc = ref.watch(playerServiceProvider);
  // ignore: avoid_print
  // Emit the current snapshot first so a freshly mounted Queue screen
  // doesn't render an empty list while waiting for the next stream tick.
  return Stream<List<AfTrack>>.multi((controller) {
    controller.add(svc.currentQueue);
    final sub = svc.queueStream.listen(controller.add);
    controller.onCancel = sub.cancel;
  });
});

/// Stream of position from the single player. Per non-negotiable §4.3,
/// every UI consumer (ring, waveform, lyric scroll, time labels) listens
/// to THIS stream — never a private timer.
final positionStreamProvider = StreamProvider.autoDispose<Duration>((ref) {
  final svc = ref.watch(playerServiceProvider);
  return svc.positionStream;
});

final playingStreamProvider = StreamProvider.autoDispose<bool>((ref) {
  final svc = ref.watch(playerServiceProvider);
  return svc.playingStream;
});

/// Live shuffle flag — drives the shuffle icon's active tint in
/// Now Playing / Queue. Seeded with the player's current value so the
/// first frame matches reality without waiting for the next emit.
final shuffleModeProvider = StreamProvider.autoDispose<bool>((ref) {
  final svc = ref.watch(playerServiceProvider);
  return Stream<bool>.multi((controller) {
    controller.add(svc.isShuffleEnabled);
    final sub = svc.shuffleModeStream.listen(controller.add);
    controller.onCancel = sub.cancel;
  });
});

/// Live loop mode — drives the repeat icon (off / all / one) in
/// Now Playing.
final loopModeProvider = StreamProvider.autoDispose<LoopMode>((ref) {
  final svc = ref.watch(playerServiceProvider);
  return Stream<LoopMode>.multi((controller) {
    controller.add(svc.loopMode);
    final sub = svc.loopModeStream.listen(controller.add);
    controller.onCancel = sub.cancel;
  });
});

/// Live playback speed multiplier — drives the Speed sheet's checkmark.
final playbackSpeedProvider = StreamProvider.autoDispose<double>((ref) {
  final svc = ref.watch(playerServiceProvider);
  return Stream<double>.multi((controller) {
    controller.add(svc.speed);
    final sub = svc.speedStream.listen(controller.add);
    controller.onCancel = sub.cancel;
  });
});

/// Currently-playing track (changes when the player advances within
/// the queue). Null when no playback has been started this session.
final currentTrackProvider = StateProvider<AfTrack?>((ref) => null);

/// Imperative helper to toggle a track's favorite state.
///
/// Optimistically flips the in-memory `currentTrackProvider.isFavorite`
/// so the heart fills/empties on the next frame, then POSTs/DELETEs
/// `/Users/{id}/FavoriteItems/{trackId}`. On HTTP failure we revert.
///
/// Signed-out (no client) → updates the local state only; the next sign-in
/// will resync against the server's user-data on the next track fetch.
final favoriteToggleProvider = Provider<Future<void> Function(AfTrack)>((ref) {
  return (AfTrack track) async {
    final client = ref.read(jellyfinClientProvider);
    final next = !track.isFavorite;
    final updated = track.copyWith(isFavorite: next);
    // Optimistic UI: update currentTrackProvider if this is the playing
    // track. (Album / Track tiles read isFavorite from their own
    // FutureProvider snapshots which will refresh next time their
    // provider re-runs.)
    final current = ref.read(currentTrackProvider);
    if (current?.id == track.id) {
      ref.read(currentTrackProvider.notifier).state = updated;
    }
    if (client == null) {
      _logData('favoriteToggle',
          source: 'demo',
          extra: '(signed out) id=${track.id} isFavorite=$next');
      return;
    }
    try {
      await client.setFavorite(track.id, next);
      _logData('favoriteToggle',
          source: 'live',
          extra: 'id=${track.id} isFavorite=$next');
    } catch (e) {
      // ignore: avoid_print
      print('aetherfin:error favoriteToggle failed: $e');
      // Revert optimistic flip on server error.
      if (current?.id == track.id) {
        ref.read(currentTrackProvider.notifier).state = track;
      }
      rethrow;
    }
  };
});

/// True the moment any playback has been started this session — drives
/// whether the floating mini-player is rendered.
final hasActivePlaybackProvider = Provider<bool>((ref) {
  return ref.watch(currentTrackProvider) != null;
});

/// ─────────────────────────────────────────────────────────────────────────
/// Spectral accent — Riverpod family keyed by track ID. Uses image-based
/// extraction when an artwork URL is available, otherwise falls back to
/// the indigo default.
/// ─────────────────────────────────────────────────────────────────────────

final spectralExtractorProvider =
    Provider<SpectralExtractor>((ref) => SpectralExtractor());

final spectralProvider =
    FutureProvider.autoDispose.family<Spectral, AfTrack?>((ref, track) async {
  if (track?.imageUrl == null) return Spectral.fallback;
  // Hand the same Authorization header to PaletteGenerator that the
  // CachedNetworkImage widgets use — once the token moved out of the
  // URL query string (review S2), unauthed artwork fetches would 401
  // and the player UI would flicker back to fallback indigo.
  final client = ref.watch(jellyfinClientProvider);
  final headers = client?.authHeaders;
  try {
    return await ref
        .watch(spectralExtractorProvider)
        .fromImageUrl(track!.imageUrl!, headers: headers);
  } catch (_) {
    return Spectral.fallback;
  }
});

/// Currently-resolved spectral triple for the currently-playing track.
final currentSpectralProvider = Provider<Spectral>((ref) {
  final track = ref.watch(currentTrackProvider);
  final async = ref.watch(spectralProvider(track));
  return async.maybeWhen(data: (s) => s, orElse: () => Spectral.fallback);
});

/// ─────────────────────────────────────────────────────────────────────────
/// Library (demo backed for v1; swaps to live Jellyfin when authed)
/// ─────────────────────────────────────────────────────────────────────────

/// Recently added albums. When authenticated, hits Jellyfin's `Latest`
/// endpoint; when not, falls back to the bundled demo library so the
/// onboarding "All set" preview still has something to render.
final recentlyAddedAlbumsProvider =
    FutureProvider.autoDispose<List<AfAlbum>>((ref) async {
  final client = ref.watch(jellyfinClientProvider);
  if (client == null) {
    _logData('recentlyAddedAlbums',
        source: 'demo', extra: '(signed out)');
    return DemoLibrary.albums;
  }
  final res = await client.recentlyAddedAlbums();
  _logData('recentlyAddedAlbums', source: 'live', extra: 'count=${res.length}');
  return res;
});

final recentlyPlayedTracksProvider =
    FutureProvider.autoDispose<List<AfTrack>>((ref) async {
  final client = ref.watch(jellyfinClientProvider);
  if (client == null) {
    _logData('recentlyPlayedTracks',
        source: 'demo', extra: '(signed out)');
    return DemoLibrary.tracks.take(10).toList();
  }
  final res = await client.recentlyPlayed();
  _logData('recentlyPlayedTracks',
      source: 'live', extra: 'count=${res.length}');
  return res;
});

final allArtistsProvider =
    FutureProvider.autoDispose<List<AfArtist>>((ref) async {
  final client = ref.watch(jellyfinClientProvider);
  if (client == null) {
    _logData('allArtists', source: 'demo', extra: '(signed out)');
    return DemoLibrary.artists;
  }
  final res = await client.artists();
  _logData('allArtists', source: 'live', extra: 'count=${res.length}');
  return res;
});

final allPlaylistsProvider =
    FutureProvider.autoDispose<List<AfPlaylist>>((ref) async {
  final client = ref.watch(jellyfinClientProvider);
  if (client == null) {
    _logData('allPlaylists', source: 'demo', extra: '(signed out)');
    return DemoLibrary.playlists;
  }
  final res = await client.playlists();
  _logData('allPlaylists', source: 'live', extra: 'count=${res.length}');
  return res;
});

/// User's favourite (heart-flagged) albums. Powers the Profile screen's
/// "Pinned" row. Previously the row was hard-coded with four demo album
/// names; now it shows real favourites, falling back to the most
/// recently added albums when the user hasn't hearted anything yet so
/// the row is never empty.
final favoriteAlbumsProvider =
    FutureProvider.autoDispose<List<AfAlbum>>((ref) async {
  final client = ref.watch(jellyfinClientProvider);
  if (client == null) {
    _logData('favoriteAlbums', source: 'demo', extra: '(signed out)');
    return DemoLibrary.albums.take(4).toList();
  }
  final res = await client.favoriteAlbums();
  _logData('favoriteAlbums', source: 'live', extra: 'count=${res.length}');
  return res;
});

/// Every album in the library (sorted alphabetically). Used by the
/// Library tab's Albums grid — the previous wiring used
/// `recentlyAddedAlbums` (top-20 newest) so the grid looked permanently
/// underpopulated.
final allAlbumsProvider =
    FutureProvider.autoDispose<List<AfAlbum>>((ref) async {
  final client = ref.watch(jellyfinClientProvider);
  if (client == null) {
    _logData('allAlbums', source: 'demo', extra: '(signed out)');
    return DemoLibrary.albums;
  }
  final res = await client.allAlbums();
  _logData('allAlbums', source: 'live', extra: 'count=${res.length}');
  return res;
});

/// Every track in the library (sorted alphabetically). Used by the
/// Library tab's Songs list, which previously used
/// `recentlyPlayedTracks` (filter=IsPlayed, limit=20) and so missed
/// every unplayed song.
final allTracksProvider =
    FutureProvider.autoDispose<List<AfTrack>>((ref) async {
  final client = ref.watch(jellyfinClientProvider);
  if (client == null) {
    _logData('allTracks', source: 'demo', extra: '(signed out)');
    return DemoLibrary.tracks;
  }
  final res = await client.allTracks();
  _logData('allTracks', source: 'live', extra: 'count=${res.length}');
  return res;
});

/// Playlist + its ordered tracks. Powers the Playlist detail screen.
final playlistDetailProvider = FutureProvider.autoDispose
    .family<({AfPlaylist playlist, List<AfTrack> tracks})?, String>(
        (ref, id) async {
  final client = ref.watch(jellyfinClientProvider);
  if (client == null) {
    _logData('playlistDetail',
        source: 'demo', extra: 'id=$id (signed out)');
    return null;
  }
  final res = await client.playlist(id);
  _logData('playlistDetail',
      source: 'live',
      extra: 'id=$id tracks=${res?.tracks.length ?? 0}');
  return res;
});

/// Instant Mix — server-side similar-tracks generator keyed on a seed
/// track / album / artist ID. Used to start a "radio" from the currently
/// playing song and to extend the queue with related songs (the feature
/// the user requested).
final instantMixProvider = FutureProvider.autoDispose
    .family<List<AfTrack>, String>((ref, seedId) async {
  final client = ref.watch(jellyfinClientProvider);
  if (client == null) {
    _logData('instantMix',
        source: 'demo', extra: 'seedId=$seedId (signed out)');
    return const <AfTrack>[];
  }
  final res = await client.instantMix(seedId);
  _logData('instantMix',
      source: 'live', extra: 'seedId=$seedId count=${res.length}');
  return res;
});

/// Music genres. Jellyfin returns these without colors so we cycle through
/// a small palette to keep the chip row colourful.
final allGenresProvider =
    FutureProvider.autoDispose<List<AfGenre>>((ref) async {
  final client = ref.watch(jellyfinClientProvider);
  if (client == null) {
    _logData('allGenres', source: 'demo', extra: '(signed out)');
    return DemoLibrary.genres;
  }
  final res = await client.genres();
  _logData('allGenres', source: 'live', extra: 'count=${res.length}');
  return res;
});

final albumDetailProvider = FutureProvider.autoDispose
    .family<({AfAlbum album, List<AfTrack> tracks})?, String>((ref, id) async {
  final client = ref.watch(jellyfinClientProvider);
  if (client != null) {
    final res = await client.album(id);
    _logData('albumDetail',
        source: 'live',
        extra: 'id=$id tracks=${res?.tracks.length ?? 0}');
    return res;
  }
  final album = DemoLibrary.albumById(id);
  if (album == null) {
    _logData('albumDetail',
        source: 'demo', extra: 'id=$id (not found)');
    return null;
  }
  _logData('albumDetail',
      source: 'demo',
      extra: 'id=$id tracks=${DemoLibrary.tracksByAlbum(id).length}');
  return (album: album, tracks: DemoLibrary.tracksByAlbum(id));
});

final artistDetailProvider =
    FutureProvider.autoDispose.family<AfArtist?, String>((ref, id) async {
  final client = ref.watch(jellyfinClientProvider);
  if (client != null) {
    final res = await client.artist(id);
    _logData('artistDetail',
        source: 'live', extra: 'id=$id found=${res != null}');
    return res;
  }
  final res = DemoLibrary.artistById(id);
  _logData('artistDetail',
      source: 'demo', extra: 'id=$id found=${res != null}');
  return res;
});

/// Albums credited to a given artist. Used by the Artist screen's albums
/// rail — replaces the previous DemoLibrary `.where(byName)` filter
/// (which only ever showed demo albums even when signed in).
final artistAlbumsProvider = FutureProvider.autoDispose
    .family<List<AfAlbum>, String>((ref, artistId) async {
  final client = ref.watch(jellyfinClientProvider);
  if (client == null) {
    final artist = DemoLibrary.artistById(artistId);
    final res = artist == null
        ? const <AfAlbum>[]
        : DemoLibrary.albums.where((a) => a.artistName == artist.name).toList();
    _logData('artistAlbums',
        source: 'demo', extra: 'artistId=$artistId count=${res.length}');
    return res;
  }
  final res = await client.artistAlbums(artistId);
  _logData('artistAlbums',
      source: 'live', extra: 'artistId=$artistId count=${res.length}');
  return res;
});

/// Top tracks for an artist (highest play count, falling back to
/// alphabetical on fresh libraries). Replaces the previous DemoLibrary
/// `.where(byName).take(5)` filter on the Artist screen.
final artistTopTracksProvider = FutureProvider.autoDispose
    .family<List<AfTrack>, String>((ref, artistId) async {
  final client = ref.watch(jellyfinClientProvider);
  if (client == null) {
    final artist = DemoLibrary.artistById(artistId);
    final res = artist == null
        ? const <AfTrack>[]
        : DemoLibrary.tracks
            .where((t) => t.artistName == artist.name)
            .take(5)
            .toList();
    _logData('artistTopTracks',
        source: 'demo', extra: 'artistId=$artistId count=${res.length}');
    return res;
  }
  final res = await client.artistTopTracks(artistId, limit: 5);
  _logData('artistTopTracks',
      source: 'live', extra: 'artistId=$artistId count=${res.length}');
  return res;
});

/// ─────────────────────────────────────────────────────────────────────────
/// Search & lyrics (live)
/// ─────────────────────────────────────────────────────────────────────────

/// Server-side search results. Hits `/Users/{id}/Items?searchTerm=`
/// (NOT `/Search/Hints` — see CLAUDE.md §10 footgun #3) and bucketises
/// the BaseItemDto stream into tracks/albums/artists for the screen.
typedef SearchResults = ({
  List<AfTrack> tracks,
  List<AfAlbum> albums,
  List<AfArtist> artists,
  List<AfPlaylist> playlists,
});

final searchProvider = FutureProvider.autoDispose
    .family<SearchResults, String>((ref, raw) async {
  final query = raw.trim();
  if (query.isEmpty) {
    _logData('search', source: 'live', extra: 'query="" (empty)');
    return (
      tracks: const <AfTrack>[],
      albums: const <AfAlbum>[],
      artists: const <AfArtist>[],
      playlists: const <AfPlaylist>[],
    );
  }
  final client = ref.watch(jellyfinClientProvider);
  if (client == null) {
    final tracks = DemoLibrary.tracks
        .where((t) =>
            t.title.toLowerCase().contains(query.toLowerCase()) ||
            t.artistName.toLowerCase().contains(query.toLowerCase()) ||
            t.albumName.toLowerCase().contains(query.toLowerCase()))
        .toList(growable: false);
    final albums = DemoLibrary.albums
        .where((a) =>
            a.name.toLowerCase().contains(query.toLowerCase()) ||
            a.artistName.toLowerCase().contains(query.toLowerCase()))
        .toList(growable: false);
    final artists = DemoLibrary.artists
        .where((a) => a.name.toLowerCase().contains(query.toLowerCase()))
        .toList(growable: false);
    _logData('search',
        source: 'demo',
        extra: 'query="$query" tracks=${tracks.length} '
            'albums=${albums.length} artists=${artists.length}');
    return (
      tracks: tracks,
      albums: albums,
      artists: artists,
      playlists: const <AfPlaylist>[],
    );
  }
  final res = await client.search(query);
  _logData('search',
      source: 'live',
      extra: 'query="$query" tracks=${res.tracks.length} '
          'albums=${res.albums.length} artists=${res.artists.length} '
          'playlists=${res.playlists.length}');
  return (
    tracks: res.tracks,
    albums: res.albums,
    artists: res.artists,
    playlists: res.playlists,
  );
});

/// Time-synced lyrics for a track. Returns `null` when the server has
/// none and the UI should render the "no lyrics" empty state. Parses
/// the raw LRC payload from `/Audio/{id}/Lyrics` into our [Lrc] type so
/// the screen doesn't have to know about LRC syntax.
final lyricsProvider =
    FutureProvider.autoDispose.family<Lrc?, String>((ref, trackId) async {
  final client = ref.watch(jellyfinClientProvider);
  if (client == null) {
    _logData('lyrics',
        source: 'demo', extra: 'trackId=$trackId (signed out)');
    return null;
  }
  final raw = await client.lyrics(trackId);
  if (raw == null || raw.isEmpty) {
    _logData('lyrics',
        source: 'live', extra: 'trackId=$trackId result=none');
    return null;
  }
  final parsed = parseLrc(raw);
  _logData('lyrics',
      source: 'live',
      extra: 'trackId=$trackId lines=${parsed.lines.length}');
  return parsed;
});

/// ─────────────────────────────────────────────────────────────────────────
/// Settings
/// ─────────────────────────────────────────────────────────────────────────

final showNavLabelsProvider = StateProvider<bool>((ref) => false);

final reducedMotionProvider = Provider.autoDispose<bool>((ref) {
  // Re-evaluated whenever MediaQuery changes — UIs read this via
  // MediaQuery.disableAnimations OR via this provider in non-widget code.
  return false;
});

/// ─────────────────────────────────────────────────────────────────────────
/// Server discovery results (used by the onboarding flow)
/// ─────────────────────────────────────────────────────────────────────────

final discoveredServersProvider =
    StateProvider<List<JellyfinServer>>((ref) => const []);
