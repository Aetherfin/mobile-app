import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../utils/log.dart';
import '../../widgets/cert_accept_dialog.dart';
import 'certificate_pinning_store.dart';

/// Dio interceptor implementing Trust-On-First-Use (TOFU) certificate
/// validation.
///
/// Works with the `badCertificateCallback` on the `HttpClient` adapter:
/// 1. The callback rejects unknown certs (returns `false`) and stashes the
///    cert in a pending map keyed by `host:port`.
/// 2. This interceptor's `onError` catches the resulting handshake error,
///    shows a dialog, and either stores the fingerprint + retries, or
///    lets the error propagate.
class TlsTrustInterceptor extends Interceptor {
  TlsTrustInterceptor({
    required CertificatePinningStore store,
    required GlobalKey<NavigatorState> navigatorKey,
    required Dio dio,
  }) : _store = store,
       _navigatorKey = navigatorKey,
       _dio = dio;

  final CertificatePinningStore _store;
  final GlobalKey<NavigatorState> _navigatorKey;
  final Dio _dio;

  /// Pending cert info, keyed by `host:port`.
  /// Populated by [badCertCallback], consumed by [onError].
  static final _pendingCerts = <String, _PendingCert>{};

  /// Factory for the `badCertificateCallback` function.
  ///
  /// The returned function rejects unknown certs (stashing them for the
  /// dialog) and accepts certs whose fingerprint matches the stored value.
  /// When [acceptAll] is `true`, everything is accepted (escape hatch).
  static bool Function(X509Certificate, String, int) badCertCallback({
    required CertificatePinningStore store,
    required bool acceptAll,
  }) {
    return (X509Certificate cert, String host, int port) {
      afLog('http', 'Bad certificate for $host:$port — issuer: ${cert.issuer}');
      if (acceptAll) return true;

      // Check if we already trust this exact fingerprint.
      final stored = store.getFingerprintSync(host, port);
      if (stored != null) {
        final current = CertificatePinningStore.fingerprintOf(cert);
        if (current == stored) {
          return true; // Already trusted and matches.
        }
        // Cert changed — stash for the interceptor to show a warning.
        _pendingCerts['$host:$port'] = _PendingCert(
          cert: cert,
          previousFingerprint: stored,
        );
        return false;
      }

      // First connect — stash for the interceptor to show accept dialog.
      _pendingCerts['$host:$port'] = _PendingCert(cert: cert);
      return false;
    };
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    if (err.type != DioExceptionType.connectionError) {
      handler.next(err);
      return;
    }

    // Only handle TLS handshake failures.
    final error = err.error;
    if (error is! HandshakeException && error is! TlsException) {
      handler.next(err);
      return;
    }

    final host = err.requestOptions.uri.host;
    final port = err.requestOptions.uri.port;
    final key = '$host:$port';

    final pending = _pendingCerts.remove(key);
    if (pending == null) {
      handler.next(err);
      return;
    }

    final navigator = _navigatorKey.currentState;
    if (navigator == null) {
      afLog('http', 'No navigator available for cert dialog');
      handler.next(err);
      return;
    }

    final context = navigator.context;
    if (!context.mounted) {
      handler.next(err);
      return;
    }

    final accepted = await showCertAcceptDialog(
      context: context,
      cert: pending.cert,
      host: host,
      port: port,
      previousFingerprint: pending.previousFingerprint,
    );

    if (!accepted) {
      afLog('http', 'User rejected certificate for $host:$port');
      handler.next(err);
      return;
    }

    // Store the new fingerprint and retry the original request.
    final fingerprint = CertificatePinningStore.fingerprintOf(pending.cert);
    await _store.saveFingerprint(host, port, fingerprint);
    afLog('http', 'Stored TLS fingerprint for $host:$port');

    try {
      final response = await _dio.fetch(err.requestOptions);
      handler.resolve(response);
    } on DioException catch (retryErr) {
      afLog(
        'http',
        'Retry after cert accept failed for $host:$port',
        error: retryErr,
      );
      handler.next(retryErr);
    }
  }
}

/// Stashed cert info waiting for user decision via dialog.
class _PendingCert {
  _PendingCert({required this.cert, this.previousFingerprint});
  final X509Certificate cert;
  final String? previousFingerprint;
}
