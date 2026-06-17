import 'package:dio/dio.dart';

import 'url.dart';

/// Render [e] as a one-line user-facing string with sensitive auth query
/// parameters redacted.
///
/// Why this exists: most failure paths in the app eventually surface a
/// `SnackBar(content: Text('Failed: $e'))` or similar. When `e` is a
/// [DioException], `e.toString()` includes the full request URI — and
/// our request URIs embed credentials as query params (`api_key=…` for
/// Jellyfin, `t=…&s=…&u=…` for Subsonic). Without redaction those tokens
/// land on screen, in screen-recordings, and in user-submitted bug
/// reports.
///
/// The redaction list lives in [redactSensitiveQueryParams]. The path,
/// host, status code, and non-sensitive params stay visible so the
/// message remains useful for debugging.
String displayError(Object e, {String? prefix}) {
  final body = _render(e);
  return prefix == null ? body : '$prefix: $body';
}

String _render(Object e) {
  if (e is DioException) {
    final url = redactSensitiveQueryParams(e.requestOptions.uri);
    final status = e.response?.statusCode;
    if (status != null) return 'HTTP $status from $url';
    final msg = e.message ?? e.error?.toString();
    final summary = '${e.type.name} from $url';
    return msg == null || msg.isEmpty ? summary : '$summary: $msg';
  }
  // Non-Dio errors — redact in case the toString contains sensitive data
  // (e.g. URLs with embedded auth tokens from nested exceptions).
  return redactSensitiveQueryParams(e.toString());
}
