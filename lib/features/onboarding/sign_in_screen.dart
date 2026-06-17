import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/jellyfin/client.dart';
import '../../core/jellyfin/models/server.dart';
import '../../core/subsonic/client.dart';
import '../../design_tokens/tokens.dart';
import '../../widgets/af_loading_indicator.dart';
import '../../state/providers.dart';
import '../../utils/display_error.dart';
import '../../utils/log.dart';
import '../../utils/url.dart';
import '../../widgets/server_pill.dart';
import '../../widgets/stagger_reveal.dart';

/// Server sign-in form.
///
/// Shows server URL, username/password fields, sign-in button with
/// accentPrimary styling, error handling, and cleartext HTTP warning.
class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({
    super.key,
    required this.server,
    this.serverType = ServerType.jellyfin,
  });
  final JellyfinServer server;
  final ServerType serverType;

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  final _user = TextEditingController();
  final _pass = TextEditingController();
  bool _useToken = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _user.dispose();
    _pass.dispose();
    super.dispose();
  }

  bool get _isSubsonic => widget.serverType == ServerType.subsonic;

  String? _validateServerUrl(String url) {
    if (url.isEmpty) return 'Server URL is required';
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme || !uri.hasAuthority) {
      return 'Invalid URL format';
    }
    final scheme = uri.scheme.toLowerCase();
    if (scheme != 'http' && scheme != 'https') {
      return 'URL must use http:// or https://';
    }
    return null;
  }

  Future<void> _submit() async {
    final urlError = _validateServerUrl(widget.server.baseUrl);
    if (urlError != null) {
      setState(() {
        _error = urlError;
        _busy = false;
      });
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final JellyfinAuth auth;
      if (_isSubsonic) {
        auth = await _authenticateSubsonic();
      } else if (_useToken) {
        final client = JellyfinClient(
          server: widget.server,
          deviceId: ref.read(deviceIdProvider),
          clientVersion: ref.read(aetherfinVersionProvider),
        );
        auth = await client.authenticateWithApiKey(
          username: _user.text.trim(),
          apiKey: _pass.text.trim(),
        );
      } else {
        final client = JellyfinClient(
          server: widget.server,
          deviceId: ref.read(deviceIdProvider),
          clientVersion: ref.read(aetherfinVersionProvider),
        );
        auth = await client.authenticate(
          username: _user.text.trim(),
          password: _pass.text,
        );
      }
      await ref.read(authProvider.notifier).save(auth);
      if (!mounted) return;
      context.go('/onboarding/scope');
    } on Exception catch (e, stack) {
      afLog('error', 'sign-in failed', error: e, stackTrace: stack);
      if (e is DioException) {
        // Redact `t`, `s`, `api_key`, etc. before emitting the URL — for
        // Subsonic the request URI includes the salted MD5 token as a
        // query param, and we don't want it in a logcat capture or a
        // user-submitted bug report.
        afLog(
          'error',
          'url: ${redactSensitiveQueryParams(e.requestOptions.uri)}',
        );
        afLog('error', 'status: ${e.response?.statusCode}');
        // Body + response headers can include cookies, server-side error
        // messages, and full HTML 500 pages — only emit them in debug
        // builds so a release-build logcat capture stays sanitized.
        if (kDebugMode) {
          afLog('error', 'body: ${e.response?.data}');
          afLog('error', 'headers: ${e.response?.headers.map}');
        }
      }
      if (!mounted) return;
      setState(() {
        _error = _humanizeError(e);
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Authenticate against a Subsonic/Navidrome server.
  Future<JellyfinAuth> _authenticateSubsonic() async {
    final username = _user.text.trim();
    final password = _pass.text;
    final client = SubsonicClient(
      server: widget.server,
      username: username,
      password: password,
      clientVersion: ref.read(aetherfinVersionProvider),
    );
    try {
      // ping verifies the credentials are valid
      await client.ping();
      return JellyfinAuth(
        server: widget.server,
        userId: username,
        userName: username,
        accessToken: password,
        serverType: ServerType.subsonic,
      );
    } finally {
      client.close();
    }
  }

  /// Translate raw exception text into something the user can act on.
  /// Falls back to the full exception string so we never hide what's wrong
  /// behind a generic 'check your username' message.
  String _humanizeError(Object e) {
    if (e is SubsonicApiError) {
      // Subsonic error codes: 40 = wrong password, 10 = missing param,
      // etc. Show a user-friendly message instead of the raw toString().
      return e.code == 40
          ? 'Wrong username or password.'
          : 'Server error: ${e.message}';
    }
    if (e is DioException) {
      final status = e.response?.statusCode;
      // Use the redacted URL in the visible error message — Subsonic
      // ping URLs carry the user's salted MD5 token (`t`) and salt
      // (`s`) as query params, and the message ends up on screen.
      final url = redactSensitiveQueryParams(e.requestOptions.uri);
      if (status == 401 || status == 403) {
        return 'Wrong username or password (HTTP $status from $url).';
      }
      if (status != null) {
        // Trim body to first 240 chars so a giant HTML 500 page doesn't
        // swamp the input field's helper text. We ONLY show the body in
        // debug builds because a misconfigured Jellyfin's 5xx page can
        // contain stack traces, DB connection strings, and internal
        // file paths that we don't want pasted into the user-facing
        // password field error in release. Full body is always in logcat
        // (gated below) for debugging.
        if (kDebugMode) {
          final raw = e.response?.data?.toString() ?? '';
          final body = raw.length > 240 ? '${raw.substring(0, 240)}…' : raw;
          return 'HTTP $status from $url\n'
              '${body.isNotEmpty ? body : "(no body)"}';
        }
        return 'HTTP $status from $url. Check Jellyfin server logs.';
      }
      switch (e.type) {
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.sendTimeout:
        case DioExceptionType.receiveTimeout:
          return 'Connection timed out reaching ${widget.server.baseUrl}.';
        case DioExceptionType.connectionError:
          return 'Could not reach ${widget.server.baseUrl}. ${e.message ?? ""}';
        case DioExceptionType.badCertificate:
          return 'TLS certificate rejected for ${widget.server.baseUrl}.';
        default:
          return '${e.type.name}: ${e.message ?? e.error ?? "unknown"}';
      }
    }
    return displayError(e);
  }

  /// Aetherfin sends every byte (including the access token) over plain HTTP
  /// when the user picked an `http://` server. We surface a warning banner so
  /// the user understands the risk before pasting credentials — the Jellyfin
  /// design assumption is "trusted LAN" but users routinely try this on cafe
  /// Wi-Fi and over WAN with no TLS terminator in front.
  bool get _isCleartext =>
      widget.server.baseUrl.toLowerCase().startsWith('http://');

  @override
  Widget build(BuildContext context) {
    final spectral = ref.watch(
      currentSpectralProvider.select((s) => s.primary),
    );
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(LucideIcons.arrowLeft),
          tooltip: 'Back',
          onPressed: () => context.pop(),
        ),
        title: Text('Sign in', style: AfTypography.titleMedium),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: AfSpacing.s16),
            child: Center(
              child: ServerPill(
                state: ServerPillState.connectedOther,
                label: widget.server.name,
              ),
            ),
          ),
        ],
      ),
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(
            horizontal: AfSpacing.gutterGenerous,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Text(
                  'Step 3 of 5',
                  style: AfTypography.caption.copyWith(
                    color: AfColors.textTertiary,
                  ),
                ),
              ),
              StaggerReveal(
                children: [
                  const SizedBox(height: AfSpacing.s16),
                  if (_isCleartext)
                    _CleartextWarning(baseUrl: widget.server.baseUrl),
                  if (_isCleartext) const SizedBox(height: AfSpacing.s16),
                  Text(
                    _isSubsonic
                        ? 'Enter your Navidrome username and password.'
                        : _useToken
                        ? 'Paste a Jellyfin API token. Find these under '
                              'Dashboard → API Keys on your server.'
                        : 'Enter your Jellyfin username and password.',
                    style: AfTypography.bodyMedium.copyWith(
                      color: AfColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: AfSpacing.s24),
                  TextField(
                    controller: _user,
                    autofocus: true,
                    autocorrect: false,
                    textCapitalization: TextCapitalization.none,
                    decoration: const InputDecoration(
                      labelText: 'Username',
                      hintText: 'Username',
                    ),
                  ),
                  const SizedBox(height: AfSpacing.s12),
                  TextField(
                    controller: _pass,
                    obscureText: true,
                    autocorrect: false,
                    decoration: InputDecoration(
                      labelText: _useToken ? 'API token' : 'Password',
                      hintText: _useToken ? 'API token' : 'Password',
                      errorText: _error,
                    ),
                    onSubmitted: (_) => _busy ? null : _submit(),
                  ),
                  const SizedBox(height: AfSpacing.s12),
                  if (!_isSubsonic)
                    Row(
                      children: [
                        Switch.adaptive(
                          value: _useToken,
                          onChanged: (v) => setState(() => _useToken = v),
                          activeThumbColor: spectral,
                        ),
                        const SizedBox(width: AfSpacing.s8),
                        Expanded(
                          child: Text(
                            'Use API token instead',
                            style: AfTypography.bodyMedium,
                          ),
                        ),
                      ],
                    ),
                  const SizedBox(height: AfSpacing.s32),
                  ElevatedButton(
                    onPressed: _busy ? null : _submit,
                    child: _busy
                        ? const AfLoadingIndicator(size: 18, strokeWidth: 2.5)
                        : const Text('Sign in'),
                  ),
                  const SizedBox(height: AfSpacing.s24),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Inline banner shown when the chosen server URL uses `http://`. Cleartext
/// is on by default in the network security config (some self-hosters can't
/// terminate TLS), but the user should know what they're agreeing to before
/// the access token rides over the wire in plain.
class _CleartextWarning extends ConsumerWidget {
  const _CleartextWarning({required this.baseUrl});
  final String baseUrl;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spectral = ref.watch(
      currentSpectralProvider.select((s) => s.warning),
    );
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AfSpacing.s12,
        vertical: AfSpacing.s8,
      ),
      decoration: BoxDecoration(
        color: spectral.withValues(alpha: 0.12),
        borderRadius: AfRadii.borderMd,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(LucideIcons.lockOpen, size: 18, color: spectral),
          const SizedBox(width: AfSpacing.s8),
          Expanded(
            child: Text(
              'This server uses plain HTTP. Your username, password, '
              'and access token will be sent unencrypted to $baseUrl. '
              'Only sign in on a trusted network.',
              style: AfTypography.bodySmall.copyWith(
                color: AfColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
