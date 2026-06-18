import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../design_tokens/tokens.dart';
import '../widgets/af_dialog.dart';

/// Dialog shown when connecting to a server whose TLS certificate is not
/// signed by a trusted CA (self-signed, local CA, etc.).
///
/// Two variants:
/// - **First connect:** user is asked to accept the certificate.
/// - **Certificate changed:** the stored fingerprint no longer matches —
///   user sees both the old and new certificate details.
Future<bool> showCertAcceptDialog({
  required BuildContext context,
  required X509Certificate cert,
  required String host,
  required int port,
  String? previousFingerprint,
}) async {
  final result = await showBlurDialog<bool>(
    context: context,
    barrierDismissible: false,
    child: _CertAcceptContent(
      cert: cert,
      host: host,
      port: port,
      previousFingerprint: previousFingerprint,
    ),
  );
  return result ?? false;
}

class _CertAcceptContent extends StatelessWidget {
  const _CertAcceptContent({
    required this.cert,
    required this.host,
    required this.port,
    this.previousFingerprint,
  });

  final X509Certificate cert;
  final String host;
  final int port;
  final String? previousFingerprint;

  bool get _isChanged => previousFingerprint != null;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Title ──────────────────────────────────────────────────────
        Row(
          children: [
            Icon(
              _isChanged ? LucideIcons.alertTriangle : LucideIcons.shield,
              size: 20,
              color: _isChanged
                  ? AfColors.semanticWarning
                  : AfColors.semanticInfo,
            ),
            const SizedBox(width: AfSpacing.s8),
            Expanded(
              child: Text(
                _isChanged ? 'Certificate changed' : 'Accept certificate?',
                style: AfTypography.titleMedium,
              ),
            ),
          ],
        ),
        const SizedBox(height: AfSpacing.s12),

        Text(
          _isChanged
              ? 'The certificate for $host:$port has changed since it was '
                    'first accepted. This could be a normal rotation or a '
                    'security concern.'
              : '$host:$port is using a certificate not signed by a '
                    'trusted Certificate Authority. This is common for '
                    'self-hosted servers.',
          style: AfTypography.bodySmall.copyWith(color: AfColors.textTertiary),
        ),
        const SizedBox(height: AfSpacing.s16),

        // ── Certificate details ───────────────────────────────────────
        Container(
          padding: const EdgeInsets.all(AfSpacing.s12),
          decoration: const BoxDecoration(
            color: AfColors.surfaceHigh,
            borderRadius: AfRadii.borderMd,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _infoRow('Subject', cert.subject),
              _infoRow('Issuer', cert.issuer),
              const SizedBox(height: AfSpacing.s8),
              Text(
                'SHA-256 fingerprint',
                style: AfTypography.caption.copyWith(
                  color: AfColors.textTertiary,
                ),
              ),
              const SizedBox(height: AfSpacing.s2),
              SelectableText(
                _formatFingerprint(cert),
                style: AfTypography.monoSmall.copyWith(
                  color: AfColors.textSecondary,
                ),
              ),
            ],
          ),
        ),

        // ── Previous fingerprint (changed cert) ───────────────────────
        if (_isChanged) ...[
          const SizedBox(height: AfSpacing.s12),
          Container(
            padding: const EdgeInsets.all(AfSpacing.s12),
            decoration: const BoxDecoration(
              color: AfColors.surfaceHigh,
              borderRadius: AfRadii.borderMd,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Previous fingerprint',
                  style: AfTypography.caption.copyWith(
                    color: AfColors.textTertiary,
                  ),
                ),
                const SizedBox(height: AfSpacing.s2),
                SelectableText(
                  previousFingerprint!,
                  style: AfTypography.monoSmall.copyWith(
                    color: AfColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],

        const SizedBox(height: AfSpacing.s24),

        // ── Actions ───────────────────────────────────────────────────
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: () => context.pop(false),
              child: const Text('Reject'),
            ),
            const SizedBox(width: AfSpacing.s8),
            Focus(
              autofocus: true,
              child: ElevatedButton(
                onPressed: () => context.pop(true),
                child: Text(_isChanged ? 'Accept new cert' : 'Accept'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  static Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AfSpacing.s4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: AfTypography.caption.copyWith(color: AfColors.textTertiary),
          ),
          SelectableText(
            value,
            style: AfTypography.bodySmall.copyWith(
              color: AfColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  static String _formatFingerprint(X509Certificate cert) {
    final der = _derFromPem(cert.pem);
    final hexParts = <String>[];
    for (var i = 0; i < der.length && i < 32; i++) {
      hexParts.add(der[i].toRadixString(16).padLeft(2, '0'));
    }
    return hexParts.join(':');
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
