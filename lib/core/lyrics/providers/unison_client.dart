import 'package:dio/dio.dart';

import '../../../utils/log.dart';
import '../../network/shared_dio_client.dart';

/// Client for fetching lyrics from the Unison API.
///
/// Unison is an open-source music player. Its public API provides
/// lyrics from multiple backends aggregated through a free proxy.
///
/// No API key required. Returns null on any failure.
class UnisonClient {
  UnisonClient({Dio? dio})
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

  /// Fetches synced or plain lyrics for a track from Unison API.
  /// Returns null if not found or on error.
  Future<({String? synced, String? plain})?> fetchLyrics({
    required String trackName,
    required String artistName,
    required String albumName,
    required Duration duration,
  }) async {
    if (trackName.isEmpty || artistName.isEmpty) return null;

    try {
      // Use URL-encoded query for the search
      final uri = Uri.parse('https://api.unison.moe/lyrics');
      final requestUri = uri.replace(
        queryParameters: {
          'title': trackName,
          'artist': artistName,
          if (albumName.isNotEmpty) 'album': albumName,
        },
      );

      afLog('lyrics', 'Unison: fetching lyrics for "$trackName"');

      final response = await _dio.get<Map<String, dynamic>>(
        requestUri.toString(),
      );

      final data = response.data;
      if (data == null) {
        afLog('lyrics', 'Unison: response is null');
        return null;
      }

      // Unison returns LRC content directly in the response
      final synced = data['synced'] as String?;
      final plain = data['plain'] as String?;

      if (synced != null && synced.trim().isNotEmpty) {
        afLog('lyrics', 'Unison: synced lyrics found. ${synced.length} chars');
        return (synced: synced.trim(), plain: null);
      }

      if (plain != null && plain.trim().isNotEmpty) {
        afLog('lyrics', 'Unison: plain lyrics found. ${plain.length} chars');
        return (synced: null, plain: plain.trim());
      }

      afLog('lyrics', 'Unison: no lyrics content');
    } on DioException catch (e) {
      // 404 means no lyrics found — not an error
      if (e.response?.statusCode == 404) {
        afLog('lyrics', 'Unison: no lyrics available (404)');
      } else {
        afLog(
          'lyrics',
          'Unison: HTTP error',
          error: e,
          stackTrace: e.stackTrace,
        );
      }
    } on Exception catch (e, stack) {
      afLog('lyrics', 'Unison: fetch failed', error: e, stackTrace: stack);
    }
    return null;
  }
}
