import 'dart:io';

import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import '../../utils/log.dart';
import '../backend/music_backend.dart';
import '../jellyfin/models/items.dart';
import '../jellyfin/models/library.dart';
import 'innertube_client.dart';
import 'youtube_auth.dart';
import 'youtube_home_content.dart';

/// YouTube Music backend using youtube_explode_dart.
///
/// Streams from YouTube/YouTube Music catalog. Does NOT sync with a
/// YouTube Music account library — that's Phase 2. This MVP focuses
/// on search + streaming.
class YouTubeMusicClient implements MusicBackend {
  YouTubeMusicClient({this.auth}) : _yt = YoutubeExplode() {
    if (auth != null) {
      _innertube.setAuth(auth);
    }
  }

  final YouTubeAuthBundle? auth;
  final YoutubeExplode _yt;
  final InnerTubeClient _innertube = InnerTubeClient();

  // Cache the last artist page browse to avoid redundant HTTP calls.
  String? _cachedArtistId;
  List<InnerTubeItem>? _cachedSongs;
  List<InnerTubeItem>? _cachedCarousel;
  String? _cachedArtistName;
  String? _cachedArtistThumb;
  List<List<InnerTubeItem>>? _cachedSections;
  List<String>? _cachedSectionTitles;
  List<String?>? _cachedSectionMoreIds;
  String? _cachedSongsMoreId;

  /// Returns the cached songs section's "more" browse ID if any.
  String? get artistSongsMoreId => _cachedSongsMoreId;

  /// Returns the cached artist page sections with titles and "more" browse IDs.
  /// Each entry is (title, items, moreBrowseId). Only valid after artist() is called.
  List<({String title, List<InnerTubeItem> items, String? moreId})>
  get artistSections {
    if (_cachedSections == null || _cachedSectionTitles == null) return [];
    return List.generate(
      _cachedSections!.length,
      (i) => (
        title: _cachedSectionTitles![i],
        items: _cachedSections![i],
        moreId:
            _cachedSectionMoreIds != null && i < _cachedSectionMoreIds!.length
            ? _cachedSectionMoreIds![i]
            : null,
      ),
    );
  }

  @override
  ServerType get serverType => ServerType.youtubeMusic;

  // ── Helpers ──────────────────────────────────────────────────────────

  AfTrack _videoToTrack(Video video) => AfTrack(
    id: video.id.value,
    title: video.title,
    artistName: video.author,
    albumName: 'YouTube Music',
    duration: video.duration ?? Duration.zero,
    imageUrl: video.thumbnails.highResUrl,
  );

  // ── Library browsing ─────────────────────────────────────────────────

  /// Returns the device's ISO country code (e.g. "ID", "MY", "US").
  String get _countryCode {
    final parts = Platform.localeName.split('_');
    if (parts.length >= 2) {
      final code = parts.last.toUpperCase();
      if (code.length == 2) return code;
    }
    return 'US';
  }

  /// Fetches home page content via InnerTube browse API.
  Future<YouTubeHomeContent> browseHome({
    String? params,
    String? continuation,
  }) async {
    final region = _countryCode;
    afLog(
      'aetherfin:youtube',
      'browseHome: region=$region, params=$params, continuation=$continuation',
    );

    final response = await _innertube.browseHome(
      params: params,
      continuation: continuation,
    );
    if (response == null || response.sections.isEmpty) {
      return YouTubeHomeContent.empty();
    }

    final sections = response.sections
        .map((s) => YouTubeHomeSection(title: s.title, items: s.items))
        .toList();

    afLog(
      'aetherfin:youtube',
      'browseHome: ${sections.length} sections, ${response.chips.length} chips',
    );

    return YouTubeHomeContent(
      sections: sections,
      chips: response.chips,
      region: region,
      continuation: response.continuation,
    );
  }

  @override
  Future<List<AfAlbum>> recentlyAddedAlbums({int limit = 20}) async => [];

  @override
  Future<List<AfTrack>> recentlyPlayed({int limit = 20}) async => [];

  @override
  Future<List<AfTrack>> resumeItems({int limit = 20}) async => [];

  @override
  Future<List<AfArtist>> artists({int limit = 200}) async => [];

  @override
  Future<List<AfPlaylist>> playlists({int limit = 200}) async {
    try {
      final infos = await _innertube.browsePlaylists();
      return infos
          .take(limit)
          .map(
            (info) => AfPlaylist(
              id: info.id.isNotEmpty ? info.id : info.browseId,
              name: info.title,
              trackCount: info.trackCount ?? 0,
              imageUrl: info.imageUrl,
            ),
          )
          .toList();
    } on Exception catch (e) {
      afLog('youtube', 'Failed to get playlists', error: e);
      return [];
    }
  }

  @override
  Future<List<AfAlbum>> allAlbums({
    int limit = 500,
    int startIndex = 0,
  }) async => [];

  @override
  Future<List<AfTrack>> allTracks({
    int limit = 1000,
    int startIndex = 0,
  }) async => [];

  @override
  Future<List<AfGenre>> genres({int limit = 200}) async => [];

  @override
  Future<List<AfAlbum>> favoriteAlbums({int limit = 30}) async => [];

  @override
  Future<List<AfTrack>> favoriteTracks({int limit = 500}) async => [];

  // ── Detail views ─────────────────────────────────────────────────────

  @override
  Future<({AfAlbum album, List<AfTrack> tracks})?> album(String id) async {
    try {
      var browseId = id;
      if (!browseId.startsWith('VL') &&
          (browseId.startsWith('PL') ||
           browseId.startsWith('OL') ||
           browseId.startsWith('RD'))) {
        browseId = 'VL$browseId';
      }
      final result = await _innertube.browsePlaylistWithMetadata(browseId);
      if (result == null || result.tracks.isEmpty) return null;

      final tracks = result.tracks
          .map(
            (item) => AfTrack(
              id: item.videoId ?? item.id,
              title: item.title,
              artistName: item.subtitle,
              artistId: item.artistId,
              albumName: result.albumTitle ?? 'YouTube Music',
              imageUrl: item.thumbnailUrl,
            ),
          )
          .toList();

      final album = AfAlbum(
        id: id,
        name: result.albumTitle ?? 'Album',
        artistName: result.albumArtist ?? '',
        trackCount: tracks.length,
        imageUrl:
            result.albumArtUrl ??
            (tracks.isNotEmpty ? tracks.first.imageUrl : ''),
      );
      return (album: album, tracks: tracks);
    } on Exception catch (e) {
      afLog('youtube', 'Failed to get album', error: e);
      return null;
    }
  }

  Future<bool> _fetchArtistPage(String artistId) async {
    if (_cachedArtistId == artistId && _cachedArtistName != null) return true;
    _cachedArtistId = artistId;
    final page = await _innertube.browseArtistPage(artistId);
    if (page == null) {
      _cachedArtistName = null;
      return false;
    }
    _cachedArtistName = page.name;
    _cachedArtistThumb = page.thumbUrl;
    _cachedSongs = page.songs;
    _cachedCarousel = page.carouselItems;
    _cachedSongsMoreId = null;
    for (final s in page.sections) {
      if (s.isSongSection) {
        _cachedSongsMoreId = s.moreBrowseId;
        break;
      }
    }
    final nonSongSections = page.sections.where((s) => !s.isSongSection).toList();
    _cachedSections = nonSongSections.map((s) => s.items).toList();
    _cachedSectionTitles = nonSongSections.map((s) => s.title).toList();
    _cachedSectionMoreIds = nonSongSections.map((s) => s.moreBrowseId).toList();
    return true;
  }

  @override
  Future<AfArtist?> artist(String id) async {
    try {
      if (!await _fetchArtistPage(id)) return null;
      return AfArtist(
        id: id,
        name: _cachedArtistName!,
        imageUrl: _cachedArtistThumb ?? '',
      );
    } on Exception catch (e) {
      afLog('youtube', 'Failed to get artist', error: e);
      return null;
    }
  }

  @override
  Future<List<AfTrack>> artistTopTracks(
    String artistId, {
    int limit = 100,
  }) async {
    try {
      if (!await _fetchArtistPage(artistId)) return [];
      return _cachedSongs!
          .take(limit)
          .map(
            (item) => AfTrack(
              id: item.videoId ?? item.id,
              title: item.title,
              artistName: item.subtitle,
              artistId: item.artistId,
              albumName: 'YouTube Music',
              imageUrl: item.thumbnailUrl,
            ),
          )
          .toList();
    } on Exception catch (e) {
      afLog('youtube', 'artistTopTracks failed', error: e);
      return [];
    }
  }

  @override
  Future<List<AfAlbum>> artistAlbums(String artistId, {int limit = 100}) async {
    try {
      if (!await _fetchArtistPage(artistId)) return [];

      String? moreId;
      if (_cachedSectionTitles != null && _cachedSectionMoreIds != null) {
        for (var i = 0; i < _cachedSectionTitles!.length; i++) {
          final t = _cachedSectionTitles![i].toLowerCase();
          if (t.contains('album') || t.contains('single') || t.contains('ep')) {
            moreId = _cachedSectionMoreIds![i];
            if (moreId != null) break;
          }
        }
      }

      final List<InnerTubeItem> items;
      if (moreId != null) {
        items = await _innertube.browsePlaylist(moreId);
      } else {
        items = _cachedCarousel ?? [];
      }

      return items
          .where((item) => item.type == InnerTubeItemType.album)
          .take(limit)
          .map((item) => AfAlbum(
                id: item.id,
                name: item.title,
                artistName: item.subtitle,
                trackCount: 0,
                imageUrl: item.thumbnailUrl,
              ))
          .toList();
    } on Exception catch (e) {
      afLog('youtube', 'artistAlbums failed', error: e);
      return [];
    }
  }

  @override
  Future<AfTrackDetails?> trackDetails(String id) async {
    try {
      final video = await _yt.videos.get(id);
      return AfTrackDetails(track: _videoToTrack(video));
    } on Exception catch (e) {
      afLog('youtube', 'Failed to get track details', error: e);
      return null;
    }
  }

  @override
  Future<List<AfAlbum>> albumsByGenre(String genre, {int limit = 200}) async =>
      [];

  @override
  Future<({AfPlaylist playlist, List<AfTrack> tracks})?> playlist(
    String id,
  ) async {
    try {
      final browseId = id.startsWith('VL') ? id : 'VL$id';
      final innerTubeItems = await _innertube.browsePlaylist(browseId);
      if (innerTubeItems.isEmpty) return null;

      final tracks = innerTubeItems
          .map(
            (item) => AfTrack(
              id: item.videoId ?? item.id,
              title: item.title,
              artistName: item.subtitle,
              artistId: item.artistId,
              albumName: 'YouTube Music',
              imageUrl: item.thumbnailUrl,
            ),
          )
          .toList();

      final playlist = AfPlaylist(
        id: id,
        name: '', // Title from playlist list
        trackCount: tracks.length,
      );
      return (playlist: playlist, tracks: tracks);
    } on Exception catch (e) {
      afLog('youtube', 'Failed to get playlist', error: e);
      return null;
    }
  }

  // ── Search ───────────────────────────────────────────────────────────

  @override
  Future<
    ({
      List<AfTrack> tracks,
      List<AfAlbum> albums,
      List<AfArtist> artists,
      List<AfPlaylist> playlists,
    })
  >
  search(String query) async {
    try {
      final results = await _yt.search.search(query);
      final tracks = <AfTrack>[];
      for (final result in results) {
        tracks.add(_videoToTrack(result));
      }
      return (
        tracks: tracks,
        albums: <AfAlbum>[],
        artists: <AfArtist>[],
        playlists: <AfPlaylist>[],
      );
    } on Exception catch (e) {
      afLog('youtube', 'Search failed', error: e);
      return (
        tracks: <AfTrack>[],
        albums: <AfAlbum>[],
        artists: <AfArtist>[],
        playlists: <AfPlaylist>[],
      );
    }
  }

  // ── Favorites ────────────────────────────────────────────────────────

  @override
  Future<void> setFavorite(String itemId, bool isFavorite) async {
    afLog(
      'aetherfin:youtube',
      'setFavorite not yet implemented: $itemId -> $isFavorite',
    );
  }

  // ── Playlists ────────────────────────────────────────────────────────

  @override
  Future<void> addToPlaylist(String playlistId, List<String> trackIds) async {
    afLog('aetherfin:youtube', 'addToPlaylist not yet implemented');
  }

  @override
  Future<String?> createPlaylist(String name, List<String> trackIds) async {
    afLog('aetherfin:youtube', 'createPlaylist not yet implemented');
    return null;
  }

  @override
  Future<void> removeFromPlaylist(
    String playlistId,
    List<String> entryIds,
  ) async {
    afLog('aetherfin:youtube', 'removeFromPlaylist not yet implemented');
  }

  @override
  Future<void> movePlaylistItem(
    String playlistId,
    String itemId,
    int newIndex,
  ) async {
    afLog('aetherfin:youtube', 'movePlaylistItem not yet implemented');
  }

  @override
  Future<void> deletePlaylist(String playlistId) async {
    afLog('aetherfin:youtube', 'deletePlaylist not yet implemented');
  }

  @override
  Future<void> renamePlaylist(String playlistId, String newName) async {
    afLog('aetherfin:youtube', 'renamePlaylist not yet implemented');
  }

  // ── Similar songs ────────────────────────────────────────────────────

  @override
  Future<List<AfTrack>> instantMix(String seedId, {int limit = 50}) async {
    try {
      final video = await _yt.videos.get(seedId);
      final related = await _yt.videos.getRelatedVideos(video);
      if (related == null) return [];
      return related.take(limit).map(_videoToTrack).toList();
    } on Exception catch (e) {
      afLog('youtube', 'instantMix failed', error: e);
      return [];
    }
  }

  // ── Lyrics ───────────────────────────────────────────────────────────

  @override
  Future<String?> lyrics(String trackId) async => null;

  // ── Streaming ────────────────────────────────────────────────────────

  @override
  String trackStreamUrl(String trackId, {int? maxBitrateKbps}) {
    return 'https://youtube.com/watch?v=$trackId';
  }

  /// Resolves the actual audio stream URL for a YouTube video.
  Future<String> resolveStreamUrl(String videoId) async {
    try {
      afLog('aetherfin:youtube', 'getManifest for: $videoId');
      var manifest = await _yt.videos.streams.getManifest(
        VideoId(videoId),
        ytClients: [YoutubeApiClient.androidVr],
      );
      if (manifest.muxed.isEmpty && manifest.audioOnly.isEmpty) {
        afLog('aetherfin:youtube', 'androidVr manifest empty, trying default fallback for $videoId');
        manifest = await _yt.videos.streams.getManifest(
          VideoId(videoId),
        );
      }
      afLog(
        'aetherfin:youtube',
        'manifest OK: audioOnly=${manifest.audioOnly.length} muxed=${manifest.muxed.length}',
      );

      // Prefer audio-only streams to save bandwidth and speed up initial loading.
      if (manifest.audioOnly.isNotEmpty) {
        final best = manifest.audioOnly.withHighestBitrate();
        final url = best.url.toString();
        afLog(
          'aetherfin:youtube',
          'Using audioOnly: ${best.container} bitrate=${best.bitrate} url=${url.substring(0, 80)}',
        );
        return url;
      }

      // Fallback: muxed (audio+video in one file).
      if (manifest.muxed.isNotEmpty) {
        final best = manifest.muxed.withHighestBitrate();
        final url = best.url.toString();
        afLog(
          'aetherfin:youtube',
          'Using muxed: ${best.container} bitrate=${best.bitrate} url=${url.substring(0, 80)}',
        );
        return url;
      }

      throw StateError('No streams available for $videoId');
    } on Exception catch (e) {
      afLog('youtube', 'resolveStreamUrl failed for $videoId', error: e);
      rethrow;
    }
  }

  // ── Playback reporting ───────────────────────────────────────────────

  @override
  Future<void> reportPlaybackStart(String trackId) async {}

  @override
  Future<void> reportProgress(
    String trackId,
    Duration position, {
    bool isPaused = false,
  }) async {}

  @override
  Future<void> reportPlaybackStop(
    String trackId,
    Duration position, {
    bool submission = true,
  }) async {}

  // ── Play queue sync ──────────────────────────────────────────────────

  @override
  Future<void> savePlayQueue(
    List<String> trackIds, {
    int? currentIndex,
    Duration? position,
  }) async {}

  @override
  Future<({List<AfTrack> tracks, int currentIndex, Duration position})?>
  getPlayQueue() async => null;

  // ── User views ───────────────────────────────────────────────────────

  @override
  Future<List<LibraryView>> userViews() async => [];

  // ── User avatar ──────────────────────────────────────────────────────

  @override
  Future<void> uploadUserAvatar(List<int> bytes, String mimeType) async {}

  @override
  Future<void> deleteUserAvatar() async {}

  // ── Auth headers ─────────────────────────────────────────────────────

  @override
  Map<String, String> get authHeaders => {
    'User-Agent': 'Aetherfin/0.3.5 (Android)',
  };

  // ── Lifecycle ────────────────────────────────────────────────────────

  @override
  void clearCache() {}

  @override
  void close() {
    _yt.close();
  }
}
