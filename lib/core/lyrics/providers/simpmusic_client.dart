import 'package:dio/dio.dart';

import '../../../utils/log.dart';
import '../../network/shared_dio_client.dart';

/// Client for fetching lyrics from the SimpMusic API.
///
/// SimpMusic is an open-source Flutter music player. Its public API
/// aggregates multiple Chinese music platform backends and returns
/// LRC-format lyrics.
///
/// No API key required. Returns null on any failure.
class SimpMusicClient {
  SimpMusicClient({Dio? dio})
    : _dio =
          dio ??
          SharedDioClient().createWithOptions(
            BaseOptions(
              connectTimeout: const Duration(seconds: 5),
              sendTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 15),
              headers: {
                'User-Agent':
                    'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36',
              },
            ),
          );

  final Dio _dio;

  /// Fetches synced or plain lyrics for a track from SimpMusic API.
  /// Returns null if not found or on error.
  Future<({String? synced, String? plain})?> fetchLyrics({
    required String trackName,
    required String artistName,
    required String albumName,
    required Duration duration,
  }) async {
    if (trackName.isEmpty || artistName.isEmpty) return null;

    try {
      final query = '$trackName $artistName';
      afLog('lyrics', 'SimpMusic: searching "$query"');

      // SimpMusic API uses a multi-backend proxy.
      // Search for the track first
      final searchResponse = await _dio.get<Map<String, dynamic>>(
        'https://music-api.toscl.com/search',
        queryParameters: {'keywords': query, 'type': 'song', 'limit': 5},
      );

      final searchData = searchResponse.data;
      if (searchData == null || searchData['code'] != 200) {
        afLog('lyrics', 'SimpMusic: search failed or no results');
        return null;
      }

      final result = searchData['result'] as Map<String, dynamic>?;
      final songs = result?['songs'] as List<dynamic>?;
      if (songs == null || songs.isEmpty) {
        afLog('lyrics', 'SimpMusic: no songs found');
        return null;
      }

      final firstSong = songs.first as Map<String, dynamic>;
      final songId = firstSong['id'];

      if (songId == null) {
        afLog('lyrics', 'SimpMusic: song ID is null');
        return null;
      }

      afLog('lyrics', 'SimpMusic: found song ID=$songId');

      // Fetch lyrics by song ID
      final lyricsResponse = await _dio.get<Map<String, dynamic>>(
        'https://music-api.toscl.com/lyric',
        queryParameters: {'id': songId},
      );

      final lyricsData = lyricsResponse.data;
      if (lyricsData == null || lyricsData['code'] != 200) {
        afLog('lyrics', 'SimpMusic: lyrics fetch failed');
        return null;
      }

      final lyricResult = lyricsData['result'] as Map<String, dynamic>?;
      // Try synced (lrc) first, fall back to plain text
      final lrc = lyricResult?['lrc'] as Map<String, dynamic>?;
      final lrcText = lrc?['lyric'] as String?;
      final plain = lyricResult?['plain'] as String?;

      if (lrcText != null && lrcText.trim().isNotEmpty) {
        afLog(
          'lyrics',
          'SimpMusic: synced lyrics found. ${lrcText.length} chars',
        );
        return (synced: lrcText.trim(), plain: null);
      }

      if (plain != null && plain.trim().isNotEmpty) {
        afLog('lyrics', 'SimpMusic: plain lyrics found. ${plain.length} chars');
        return (synced: null, plain: plain.trim());
      }

      afLog('lyrics', 'SimpMusic: no lyrics content');
    } on Exception catch (e, stack) {
      afLog('lyrics', 'SimpMusic: fetch failed', error: e, stackTrace: stack);
    }
    return null;
  }
}
