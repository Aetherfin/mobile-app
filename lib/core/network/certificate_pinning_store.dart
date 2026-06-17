import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../utils/log.dart';

/// Persists TLS certificate fingerprints per host:port using
/// flutter_secure_storage for Trust-On-First-Use (TOFU) validation.
///
/// On first connection to a server with a self-signed or unknown-CA cert,
/// the user is prompted to accept. The cert's SHA-256 fingerprint is stored.
/// Subsequent connections verify the cert matches the stored fingerprint.
/// If the cert changes (e.g., server rotation), the user is prompted again.
class CertificatePinningStore {
  CertificatePinningStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();
  final FlutterSecureStorage _storage;

  /// In-memory cache for synchronous lookups from `badCertificateCallback`.
  final _cache = <String, String>{};
  bool _initialized = false;

  /// Load persisted fingerprints into memory. Must be called before
  /// the adapter's `badCertificateCallback` can reference this store.
  Future<void> init() async {
    if (_initialized) return;
    try {
      final all = await _storage.readAll();
      for (final entry in all.entries) {
        if (entry.key.startsWith(_prefix)) {
          _cache[entry.key] = entry.value;
        }
      }
    } on Exception catch (e) {
      afLog(
        'error',
        'Failed to load TLS fingerprints from secure storage',
        error: e,
      );
    }
    _initialized = true;
  }

  static const _prefix = 'tls_fp_';
  static String _key(String host, int port) => '$_prefix${host}_$port';

  /// Synchronous lookup for use inside `badCertificateCallback`.
  /// Returns `null` if no fingerprint is stored for this host:port.
  String? getFingerprintSync(String host, int port) => _cache[_key(host, port)];

  /// Persist a certificate fingerprint.
  Future<void> saveFingerprint(
    String host,
    int port,
    String fingerprint,
  ) async {
    await _storage.write(key: _key(host, port), value: fingerprint);
    _cache[_key(host, port)] = fingerprint;
  }

  /// Remove the stored fingerprint for a specific host:port.
  Future<void> clearForHost(String host, int port) async {
    await _storage.delete(key: _key(host, port));
    _cache.remove(_key(host, port));
  }

  /// Remove all stored TLS fingerprints.
  Future<void> clearAll() async {
    final all = await _storage.readAll();
    for (final key in all.keys) {
      if (key.startsWith(_prefix)) {
        await _storage.delete(key: key);
      }
    }
    _cache.removeWhere((k, _) => k.startsWith(_prefix));
  }

  /// Compute SHA-256 fingerprint from an [X509Certificate].
  static String fingerprintOf(X509Certificate cert) {
    final der = _derFromPem(cert.pem);
    return sha256.convert(der).toString();
  }

  static List<int> _derFromPem(String pem) {
    final base64Str = pem
        .replaceAll('-----BEGIN CERTIFICATE-----', '')
        .replaceAll('-----END CERTIFICATE-----', '')
        .replaceAll('\n', '')
        .replaceAll('\r', '')
        .trim();
    return base64.decode(base64Str);
  }
}
