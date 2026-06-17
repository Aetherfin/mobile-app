import 'package:dio/dio.dart';

import '../../utils/log.dart';
import '../../utils/url.dart';

/// Dio interceptor that blocks HTTPS→HTTP redirects, which could indicate
/// a MITM attack on shared networks.
///
/// Usage:
/// ```dart
/// dio.interceptors.add(HttpsRedirectGuard());
/// ```
class HttpsRedirectGuard extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (options.uri.scheme == 'https') {
      options.extra['_originalScheme'] = 'https';
    }
    handler.next(options);
  }

  @override
  void onResponse(
    Response<dynamic> response,
    ResponseInterceptorHandler handler,
  ) {
    final originalScheme = response.requestOptions.extra['_originalScheme'];
    if (originalScheme == 'https' &&
        response.requestOptions.uri.scheme == 'http') {
      afLog(
        'http',
        'HTTPS→HTTP redirect blocked: ${redactSensitiveQueryParams(response.requestOptions.uri)}',
      );
      handler.reject(
        DioException(
          requestOptions: response.requestOptions,
          response: response,
          type: DioExceptionType.badResponse,
          error: 'HTTPS to HTTP redirect detected — possible MITM',
        ),
      );
      return;
    }
    handler.next(response);
  }
}
