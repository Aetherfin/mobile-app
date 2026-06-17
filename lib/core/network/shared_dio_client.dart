import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:dio_cache_interceptor/dio_cache_interceptor.dart';
import '../../utils/log.dart';
import '../../utils/url.dart';
import 'https_redirect_guard.dart';

/// Shared Dio client with connection pooling and caching for all HTTP requests.
///
/// This singleton provides a centralized, optimized HTTP client that can be reused
/// across all backend implementations (Jellyfin, Subsonic, Navidrome) to:
/// - Enable connection pooling (reduces TCP/TLS handshake overhead)
/// - Share cache storage across all clients
/// - Provide consistent timeout and retry configuration
/// - Reduce memory overhead from multiple Dio instances
class SharedDioClient {
  SharedDioClient._internal()
    : _cacheStore = MemCacheStore(
        maxSize: 20 * 1024 * 1024, // 20MB
        maxEntrySize: 1 * 1024 * 1024, // 1MB per entry
      ),
      _dio = Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 5),
          sendTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 15),
          // Enable following redirects
          followRedirects: true,
          // Maximum number of redirects
          maxRedirects: 5,
        ),
      ) {
    // Configure connection pooling via HttpClientAdapter
    _dio.httpClientAdapter = _createAdapter();

    // Configure caching with LRU eviction
    _dio.interceptors.add(
      DioCacheInterceptor(
        options: CacheOptions(
          store: _cacheStore,
          policy: CachePolicy.request,
          maxStale: const Duration(minutes: 5),
          priority: CachePriority.normal,
        ),
      ),
    );

    // Add retry interceptor for transient failures
    _dio.interceptors.add(_RetryInterceptor(_dio));
  }

  /// Factory constructor returns the singleton instance
  factory SharedDioClient() => _instance;

  static final SharedDioClient _instance = SharedDioClient._internal();

  final Dio _dio;
  final MemCacheStore _cacheStore;

  static IOHttpClientAdapter _createAdapter() {
    return IOHttpClientAdapter()
      ..createHttpClient = () {
        final client = HttpClient();
        client.findProxy = (uri) => 'DIRECT';
        client.idleTimeout = const Duration(seconds: 15);
        client.connectionTimeout = const Duration(seconds: 5);
        // Defense-in-depth: log bad certificates but allow connection.
        // Self-hosted servers (Jellyfin/Navidrome) frequently use self-signed
        // or local-CA certs — rejecting them would break the primary use case.
        client.badCertificateCallback =
            (X509Certificate cert, String host, int port) {
              afLog(
                'http',
                'Bad certificate for $host:$port — issuer: ${cert.issuer}',
              );
              return true; // Allow (self-hosted servers use self-signed certs)
            };
        return client;
      };
  }

  /// Returns the shared Dio instance
  Dio get dio => _dio;

  /// Returns the cache store for direct access (e.g., manual cache clearing)
  MemCacheStore get cacheStore => _cacheStore;

  /// Creates a Dio instance with its own adapter so that [Dio.close]
  /// on one backend client does not kill the adapter used by another.
  /// Includes a short-lived cache for read-only GET requests and retry
  /// for transient failures on idempotent methods only.
  Dio createWithOptions(BaseOptions options) {
    final customDio = Dio(options);
    customDio.httpClientAdapter = _createAdapter();

    // HTTPS redirect guard — prevent scheme downgrade from HTTPS to HTTP
    // which could indicate a MITM attack on shared networks.
    customDio.interceptors.add(HttpsRedirectGuard());

    // Short-lived cache (30s) for GET requests — reduces redundant navigation
    // refetches without stale data risk.
    customDio.interceptors.add(
      DioCacheInterceptor(
        options: CacheOptions(
          store: _cacheStore,
          policy: CachePolicy.forceCache,
          maxStale: const Duration(seconds: 30),
          priority: CachePriority.normal,
          hitCacheOnErrorExcept: [401, 403],
        ),
      ),
    );

    customDio.interceptors.add(_RetryInterceptor(customDio));
    return customDio;
  }

  /// Clears all cached responses
  void clearCache() {
    _cacheStore.clean();
  }

  /// Closes the Dio client and cleans up resources
  void close() {
    _dio.close(force: true);
    _cacheStore.close();
  }
}

/// Retry interceptor for transient HTTP failures.
///
/// Retries on connection timeouts, connection errors, and server errors
/// (500, 502, 503, 504) with exponential backoff: 1s, 2s, 4s. Max 3 retries.
class _RetryInterceptor extends Interceptor {
  _RetryInterceptor(this._dio);
  final Dio _dio;
  static const _maxRetries = 3;
  static const _retryDelays = [
    Duration(seconds: 1),
    Duration(seconds: 2),
    Duration(seconds: 4),
  ];

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    if (_shouldRetry(err)) {
      final method = err.requestOptions.method.toUpperCase();
      // Only retry idempotent methods — POST/PUT/DELETE can cause duplicate
      // side effects (double-favorite, double-scrobble, etc.).
      if (method != 'GET' && method != 'HEAD') {
        handler.next(err);
        return;
      }
      final retryCount = (err.requestOptions.extra['_retryCount'] as int?) ?? 0;
      if (retryCount < _maxRetries) {
        unawaited(_retry(err, handler, retryCount));
        return;
      }
    }
    handler.next(err);
  }

  Future<void> _retry(
    DioException err,
    ErrorInterceptorHandler handler,
    int retryCount,
  ) async {
    final delay = _retryDelays[retryCount];
    afLog(
      'http',
      'Retrying ${err.requestOptions.method} ${redactSensitiveQueryParams(err.requestOptions.uri)} '
          '(attempt ${retryCount + 1}/$_maxRetries) after ${delay.inSeconds}s',
    );
    await Future.delayed(delay);
    final options = err.requestOptions;
    options.extra['_retryCount'] = retryCount + 1;
    try {
      final response = await _dio.fetch(options);
      handler.resolve(response);
    } catch (retryErr) {
      afLog('http', 'Retry ${retryCount + 1}/$_maxRetries failed: $retryErr');
      if (retryErr is DioException && _shouldRetry(retryErr)) {
        final nextCount = retryCount + 1;
        if (nextCount < _maxRetries) {
          unawaited(_retry(retryErr, handler, nextCount));
          return;
        }
      }
      handler.next(retryErr as DioException);
    }
  }

  bool _shouldRetry(DioException err) {
    if (err.type == DioExceptionType.connectionTimeout ||
        err.type == DioExceptionType.connectionError ||
        err.type == DioExceptionType.receiveTimeout) {
      return true;
    }
    if (err.response != null) {
      final statusCode = err.response!.statusCode;
      if (statusCode == 500 ||
          statusCode == 502 ||
          statusCode == 503 ||
          statusCode == 504) {
        return true;
      }
    }
    return false;
  }
}
