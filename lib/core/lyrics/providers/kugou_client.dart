import 'dart:convert' show base64Decode, utf8;

import 'package:dio/dio.dart';

import '../../../utils/log.dart';
import '../../network/shared_dio_client.dart';

/// Client for fetching lyrics from KuGou Music (kugou.com).
///
/// Uses free public APIs:
/// 1. Search for song → get hash + song ID
/// 2. Search lyrics index → get candidate ID + accesskey
/// 3. Download LRC → base64-decoded LRC content
///
/// No API key required. Returns null on any failure.
class KuGouClient {
  KuGouClient({Dio? dio})
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
                'Referer': 'https://www.kugou.com',
              },
            ),
          );

  final Dio _dio;

  /// Fetches synced or plain lyrics for a track from KuGou.
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
      afLog('lyrics', 'KuGou: searching "$query"');

      // Step 1: Search for song to get hash
      final searchResponse = await _dio.get<Map<String, dynamic>>(
        'https://mobilecdn.kugou.com/api/v3/search/song',
        queryParameters: {
          'format': 'json',
          'keyword': query,
          'page': 1,
          'pagesize': 5,
        },
      );

      final searchData = searchResponse.data;
      if (searchData == null || searchData['status'] != 200) {
        afLog('lyrics', 'KuGou: search failed or no results');
        return null;
      }

      final data = searchData['data'] as Map<String, dynamic>?;
      final info = data?['info'] as List<dynamic>?;
      if (info == null || info.isEmpty) {
        afLog('lyrics', 'KuGou: no songs found');
        return null;
      }

      final firstSong = info.first as Map<String, dynamic>?;
      final hash = firstSong?['hash'] as String?;
      final songName = firstSong?['songname'] as String? ?? trackName;

      if (hash == null || hash.isEmpty) {
        afLog('lyrics', 'KuGou: song hash is null');
        return null;
      }

      afLog('lyrics', 'KuGou: found hash=$hash for "$songName"');

      // Step 2: Search lyrics index
      final durationMs = duration.inMilliseconds;
      final lyricsSearchResponse = await _dio.get<Map<String, dynamic>>(
        'https://lyrics.kugou.com/search',
        queryParameters: {
          'ver': 1,
          'man': 'yes',
          'client': 'pc',
          'keyword': '$songName $artistName',
          'duration': durationMs.toString(),
          'hash': hash,
        },
      );

      final lyricsSearchData = lyricsSearchResponse.data;
      if (lyricsSearchData == null) {
        afLog('lyrics', 'KuGou: lyrics search response null');
        return null;
      }

      final candidates = lyricsSearchData['candidates'] as List<dynamic>?;
      if (candidates == null || candidates.isEmpty) {
        afLog('lyrics', 'KuGou: no lyrics candidates found');
        return null;
      }

      // Pick best candidate
      final best = candidates.first as Map<String, dynamic>;
      final lrcId = best['id'] as String?;
      final accessKey = best['accesskey'] as String?;

      if (lrcId == null || accessKey == null) {
        afLog('lyrics', 'KuGou: lyrics candidate missing id or accesskey');
        return null;
      }

      // Step 3: Download the LRC content
      final lrcResponse = await _dio.get<Map<String, dynamic>>(
        'https://lyrics.kugou.com/download',
        queryParameters: {
          'ver': 1,
          'client': 'pc',
          'id': lrcId,
          'accesskey': accessKey,
          'fmt': 'lrc',
        },
      );

      final lrcData = lrcResponse.data;
      if (lrcData == null || lrcData['status'] != 200) {
        afLog('lyrics', 'KuGou: lyrics download failed');
        return null;
      }

      final content = lrcData['content'] as String?;
      if (content == null || content.isEmpty) {
        afLog('lyrics', 'KuGou: lyrics content empty');
        return null;
      }

      // KuGou returns LRC as base64 encoded content
      final decoded = utf8.decode(base64Decode(content));
      if (decoded.trim().isEmpty) {
        afLog('lyrics', 'KuGou: decoded lyrics empty');
        return null;
      }

      afLog('lyrics', 'KuGou: lyrics found. ${decoded.length} chars');
      return (synced: decoded.trim(), plain: null);
    } on Exception catch (e, stack) {
      afLog('lyrics', 'KuGou: fetch failed', error: e, stackTrace: stack);
    }
    return null;
  }
}
