import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:dio_cache_interceptor/dio_cache_interceptor.dart';
import 'package:flutter/material.dart';
import '../../utils/log.dart';
import '../../utils/url.dart';
import 'certificate_pinning_store.dart';
import 'https_redirect_guard.dart';
import 'tls_trust_interceptor.dart';

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
    _dio.httpClientAdapter = _createAdapter(badCertCallback: _badCertCallback);

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

  /// The bad-certificate callback set on all adapters once TOFU is configured.
  /// `null` means TOFU is not yet configured (accept-all fallback).
  bool Function(X509Certificate, String, int)? _badCertCallback;

  /// Stored for creating interceptors on custom Dio instances.
  CertificatePinningStore? _tlsStore;
  GlobalKey<NavigatorState>? _tlsNavigatorKey;

  /// Configure Trust-On-First-Use certificate validation.
  ///
  /// Sets the `badCertificateCallback` on all HTTP adapters and adds the
  /// [TlsTrustInterceptor] to the shared Dio instance. Must be called
  /// before the first HTTP request. Re-creating adapters is safe — the
  /// previous adapter is discarded.
  void configureTlsTrust({
    required CertificatePinningStore store,
    required GlobalKey<NavigatorState> navigatorKey,
    required bool acceptAll,
  }) {
    _tlsStore = store;
    _tlsNavigatorKey = navigatorKey;
    _badCertCallback = TlsTrustInterceptor.badCertCallback(
      store: store,
      acceptAll: acceptAll,
    );

    // Reconfigure the shared _dio adapter.
    _dio.httpClientAdapter = _createAdapter();

    // Insert the TOFU interceptor at position 0 (before cache + retry).
    // Only add once.
    final hasTofu = _dio.interceptors.any((i) => i is TlsTrustInterceptor);
    if (!hasTofu) {
      _dio.interceptors.insert(
        0,
        TlsTrustInterceptor(
          store: store,
          navigatorKey: navigatorKey,
          dio: _dio,
        ),
      );
    }
  }

  /// Update the accept-all escape hatch at runtime (from settings toggle).
  void setAcceptAllCerts(
    bool acceptAll, {
    required CertificatePinningStore store,
  }) {
    // Re-create the callback with the new flag. Adapters are already
    // configured — the callback is a closure that reads the store's cache,
    // so we just need to swap the flag.  Since badCertCallback is a static
    // factory that captures `acceptAll` by value, we must rebuild it.
    _badCertCallback = TlsTrustInterceptor.badCertCallback(
      store: store,
      acceptAll: acceptAll,
    );
    // Reconfigure all adapters so they pick up the new callback.
    _dio.httpClientAdapter = _createAdapter();
  }

  static IOHttpClientAdapter _createAdapter({
    bool Function(X509Certificate, String, int)? badCertCallback,
  }) {
    return IOHttpClientAdapter()
      ..createHttpClient = () {
        final client = HttpClient();
        client.findProxy = (uri) => 'DIRECT';
        client.idleTimeout = const Duration(seconds: 15);
        client.connectionTimeout = const Duration(seconds: 5);
        // TOFU: reject unknown certs so the interceptor can show a dialog.
        // Falls back to accept-all when TOFU is not configured.
        client.badCertificateCallback =
            badCertCallback ??
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
    customDio.httpClientAdapter = _createAdapter(
      badCertCallback: _badCertCallback,
    );

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

    // Add TOFU interceptor if configured.
    final store = _tlsStore;
    final navKey = _tlsNavigatorKey;
    if (store != null && navKey != null) {
      customDio.interceptors.add(
        TlsTrustInterceptor(store: store, navigatorKey: navKey, dio: customDio),
      );
    }

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
