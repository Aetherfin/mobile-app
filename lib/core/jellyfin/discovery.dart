import 'dart:async';
import 'dart:convert' show base64UrlEncode;
import 'dart:io';
import 'dart:math' show Random;

import 'package:async/async.dart' show StreamGroup;
import 'package:multicast_dns/multicast_dns.dart';

import '../../utils/log.dart';
import 'client.dart';
import 'models/server.dart';

/// Scans the local network for Jellyfin servers via mDNS.
///
/// Jellyfin advertises itself on `_jellyfin._tcp.local` (HTTP) and
/// `_jellyfin-server._tcp.local` (server-API). We listen on both.
class JellyfinDiscovery {
  JellyfinDiscovery({required this.clientVersion});
  static const _httpService = '_jellyfin._tcp.local';
  static const _serverService = '_jellyfin-server._tcp.local';

  /// Aetherfin app version sent on the discovery probe `User-Agent`. The
  /// probe never authenticates so this is purely cosmetic in server access
  /// logs, but threading the real version through keeps every outbound
  /// HTTP byte stamped consistently and prevents a `Aetherfin/0.0.0` from
  /// leaking into an admin's nginx logs.
  final String clientVersion;

  /// Yields servers as they are resolved. The stream completes after
  /// [timeout] elapses; cancel the subscription early to stop scanning.
  Stream<JellyfinServer> scan({
    Duration timeout = const Duration(seconds: 6),
  }) async* {
    final client = MDnsClient(
      rawDatagramSocketFactory:
          (
            dynamic host,
            int port, {
            bool reuseAddress = true,
            bool reusePort = false,
            int ttl = 1,
          }) {
            return RawDatagramSocket.bind(
              host,
              port,
              reuseAddress: reuseAddress,
              reusePort: false, // Android disallows reusePort
              ttl: ttl,
            );
          },
    );
    try {
      await client.start();
      final seen = <String>{};
      final completer = Completer<void>();
      Timer(timeout, () {
        if (!completer.isCompleted) completer.complete();
      });

      Stream<JellyfinServer> resolveOne(String service) async* {
        final ptrStream = client.lookup<PtrResourceRecord>(
          ResourceRecordQuery.serverPointer(service),
          timeout: timeout,
        );
        await for (final ptr in ptrStream) {
          if (completer.isCompleted) break;
          final srvStream = client.lookup<SrvResourceRecord>(
            ResourceRecordQuery.service(ptr.domainName),
            timeout: timeout,
          );
          await for (final srv in srvStream) {
            if (completer.isCompleted) break;
            final ipStream = client.lookup<IPAddressResourceRecord>(
              ResourceRecordQuery.addressIPv4(srv.target),
              timeout: timeout,
            );
            await for (final ip in ipStream) {
              if (completer.isCompleted) break;
              final addr = ip.address.address;
              final port = srv.port;
              // Most home Jellyfin installs are plain-HTTP on the LAN,
              // but some users front them with a reverse proxy on the
              // same host. Probe HTTPS first (no cost when it 404s
              // fast) so encrypted servers don't get downgraded to
              // HTTP just because mDNS advertises the bare port.
              final url = await _resolveBaseUrl(addr, port, clientVersion);
              if (seen.add(url)) {
                yield JellyfinServer(
                  baseUrl: url,
                  name: ptr.domainName.split('.').first,
                  isLocal: true,
                );
              }
            }
          }
        }
      }

      yield* StreamGroup.merge([
        resolveOne(_httpService),
        resolveOne(_serverService),
      ]);
    } finally {
      client.stop();
    }
  }

  /// Pick the best scheme for the discovered host/port pair.
  ///
  /// We probe `https://host:port/System/Info/Public` with a short
  /// connect timeout. Anything that completes (200 / 401 / 404 — all
  /// count) means the port speaks TLS, so we keep https. On any TLS
  /// handshake failure, refusal, or timeout we fall back to plain http
  /// which is what mDNS advertises by default.
  static Future<String> _resolveBaseUrl(
    String addr,
    int port,
    String clientVersion,
  ) async {
    final https = 'https://$addr:$port';
    try {
      final probe = JellyfinClient(
        server: JellyfinServer(baseUrl: https, name: addr, isLocal: true),
        clientVersion: clientVersion,
        // CLAUDE.md §5 forbids reusing static DeviceId values — Jellyfin
        // keys session/device records on this string and a probe sharing
        // an ID with another install (or with our own persisted ID) can
        // poison those records. The probe never authenticates, so we use
        // a throwaway random ID per call rather than the real
        // per-install ID.
        deviceId: _ephemeralDeviceId(),
      );
      try {
        await probe.publicInfo().timeout(const Duration(seconds: 2));
        return https;
      } finally {
        probe.close();
      }
    } catch (e, stack) {
      afLog(
        'error',
        'HTTPS probe failed for $addr:$port, falling back to HTTP',
        error: e,
        stackTrace: stack,
      );
      return 'http://$addr:$port';
    }
  }

  /// 16 random bytes, base64url-encoded, prefixed so a server admin
  /// reading the audit log can immediately tell this came from a
  /// discovery probe (not a real authenticated session).
  static String _ephemeralDeviceId() {
    final bytes = List<int>.generate(16, (_) => _rng.nextInt(256));
    return 'aetherfin-probe-${base64UrlEncode(bytes).replaceAll('=', '')}';
  }

  static final Random _rng = Random.secure();
}
