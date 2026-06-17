import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/audio/player_settings_store.dart';
import '../../../core/lastfm/lastfm_client.dart';
import '../../../design_tokens/tokens.dart';
import '../../../state/providers.dart';
import '../../../utils/log.dart';
import '../../../widgets/af_dialog.dart';
import '../../../widgets/press_scale.dart';

void showLastFmApiConfigDialog(BuildContext context, WidgetRef ref) {
  final apiKeyController = TextEditingController(
    text: ref.read(lastfmApiKeyProvider),
  );
  final apiSecretController = TextEditingController(
    text: ref.read(lastfmApiSecretProvider),
  );
  final spectral = ref.watch(currentSpectralProvider.select((s) => s.primary));

  showBlurDialog(
    context: context,
    builder: (context, dismiss) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Last.fm API Credentials', style: AfTypography.titleMedium),
        const SizedBox(height: AfSpacing.s12),
        Text(
          'To enable Last.fm scrobbling, you need your own API credentials.',
          style: AfTypography.bodyMedium,
        ),
        const SizedBox(height: AfSpacing.s8),
        PressScale(
          onTap: () => launchUrl(
            Uri.parse('https://www.last.fm/api/account/create'),
            mode: LaunchMode.externalApplication,
          ),
          child: InkWell(
            child: Text(
              'Create a developer account and register your API key at last.fm/api/account/create',
              style: AfTypography.bodySmall.copyWith(
                color: spectral,
                decoration: TextDecoration.underline,
              ),
            ),
          ),
        ),
        const SizedBox(height: AfSpacing.s16),
        TextField(
          decoration: const InputDecoration(
            labelText: 'Last.fm Username (optional)',
            hintText: 'Your Last.fm username',
            border: OutlineInputBorder(
              borderRadius: AfRadii.borderSm,
              borderSide: BorderSide(color: AfColors.surfaceHigh),
            ),
          ),
          style: AfTypography.bodyMedium,
        ),
        const SizedBox(height: AfSpacing.s12),
        TextField(
          controller: apiSecretController,
          decoration: const InputDecoration(
            labelText: 'API Secret',
            border: OutlineInputBorder(
              borderRadius: AfRadii.borderSm,
              borderSide: BorderSide(color: AfColors.surfaceHigh),
            ),
          ),
          style: AfTypography.bodyMedium,
        ),
        const SizedBox(height: AfSpacing.s24),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(onPressed: () => dismiss(), child: const Text('Cancel')),
            TextButton(
              onPressed: () {
                final key = apiKeyController.text.trim();
                final secret = apiSecretController.text.trim();
                ref.read(lastfmApiKeyProvider.notifier).set(key);
                ref.read(lastfmApiSecretProvider.notifier).set(secret);
                unawaited(PlayerSettingsStore.saveLastFmApiKey(key));
                unawaited(PlayerSettingsStore.saveLastFmApiSecret(secret));
                dismiss();
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ],
    ),
  );
}

void showLastFmLoginDialog(BuildContext context, WidgetRef ref) {
  showBlurDialog(
    context: context,
    builder: (context, dismiss) => _LastFmBrowserAuthDialog(dismiss: dismiss),
  );
}

/// Browser-based Last.fm auth dialog.
///
/// Flow:
/// 1. Get token via [LastFmClient.getToken].
/// 2. Open browser for user to authorize at `last.fm/api/auth`.
/// 3. Poll [LastFmClient.getSession] until user authorizes.
/// 4. Save session key.
class _LastFmBrowserAuthDialog extends ConsumerStatefulWidget {
  const _LastFmBrowserAuthDialog({required this.dismiss});
  final VoidCallback dismiss;
  @override
  ConsumerState<_LastFmBrowserAuthDialog> createState() =>
      _LastFmBrowserAuthDialogState();
}

class _LastFmBrowserAuthDialogState
    extends ConsumerState<_LastFmBrowserAuthDialog> {
  bool _loading = true;
  String? _token;
  bool _waiting = false;
  String? _username;
  String? _error;
  Timer? _pollTimer;
  String _apiKey = '';
  String _apiSecret = '';

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _startAuth() async {
    _apiKey = ref.read(lastfmApiKeyProvider);
    _apiSecret = ref.read(lastfmApiSecretProvider);
    if (_apiKey.isEmpty || _apiSecret.isEmpty) {
      setState(() {
        _loading = false;
        _error = 'API credentials are missing. Set them first.';
      });
      return;
    }

    try {
      final client = LastFmClient(apiKey: _apiKey, apiSecret: _apiSecret);
      final token = await client.getToken();

      final url = client.authPageUrl(token);
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);

      setState(() {
        _loading = false;
        _token = token;
        _waiting = true;
      });

      _startPolling(client, token);
    } on Exception catch (e) {
      setState(() {
        _loading = false;
        _error = e.toString().replaceAll('Exception: ', '');
      });
    }
  }

  void _startPolling(LastFmClient client, String token) {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
      if (!mounted) return;
      try {
        final sessionKey = await client.getSession(token);
        _pollTimer?.cancel();
        if (!mounted) return;

        ref.read(lastfmSessionKeyProvider.notifier).set(sessionKey);
        // Recreate client with session key so verifySession can use it
        final verifiedClient = LastFmClient(
          apiKey: _apiKey,
          apiSecret: _apiSecret,
          sessionKey: sessionKey,
        );
        final verifiedName = await verifiedClient.verifySession();
        if (!mounted) return;
        final username = verifiedName.isNotEmpty
            ? verifiedName
            : (_username ?? 'Last.fm');
        ref.read(lastfmUsernameProvider.notifier).set(username);
        unawaited(PlayerSettingsStore.saveLastFmSessionKey(sessionKey));
        unawaited(PlayerSettingsStore.saveLastFmUsername(username));

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Connected to Last.fm as $username!')),
        );
        widget.dismiss();
      } on Exception catch (e) {
        afLog('settings', 'Last.fm OAuth polling failed', error: e);
      }
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _startAuth());
  }

  void _checkAgain() {
    if (_token == null) return;
    final apiKey = ref.read(lastfmApiKeyProvider);
    final apiSecret = ref.read(lastfmApiSecretProvider);
    if (apiKey.isEmpty || apiSecret.isEmpty) return;
    final client = LastFmClient(apiKey: apiKey, apiSecret: apiSecret);
    _startPolling(client, _token!);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Link Last.fm Account', style: AfTypography.titleMedium),
        const SizedBox(height: AfSpacing.s12),
        if (_loading) ...[
          const Center(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: AfSpacing.s24),
              child: CircularProgressIndicator(),
            ),
          ),
        ] else if (_error != null) ...[
          Text(
            _error!,
            style: AfTypography.bodyMediumSmall.copyWith(
              color: AfColors.semanticError,
            ),
          ),
          const SizedBox(height: AfSpacing.s16),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => widget.dismiss(),
                child: const Text('Close'),
              ),
              const SizedBox(width: AfSpacing.s8),
              TextButton(
                onPressed: () {
                  setState(() {
                    _error = null;
                    _loading = true;
                  });
                  _startAuth();
                },
                child: const Text('Retry'),
              ),
            ],
          ),
        ] else if (_waiting) ...[
          Text(
            'Authorize Aetherfin in your browser, then come back here.',
            style: AfTypography.bodyMedium,
          ),
          const SizedBox(height: AfSpacing.s8),
          Row(
            children: [
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: AfSpacing.s12),
              Expanded(
                child: Text(
                  'Waiting for authorization…',
                  style: AfTypography.bodySmall.copyWith(
                    color: AfColors.textTertiary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AfSpacing.s16),
          if (_username != null)
            Padding(
              padding: const EdgeInsets.only(bottom: AfSpacing.s8),
              child: TextField(
                decoration: const InputDecoration(
                  labelText: 'Last.fm Username (optional)',
                  hintText: 'Your Last.fm username',
                  border: OutlineInputBorder(
                    borderRadius: AfRadii.borderSm,
                    borderSide: BorderSide(color: AfColors.surfaceHigh),
                  ),
                ),
                style: AfTypography.bodyMedium,
                autocorrect: false,
                onChanged: (v) => _username = v.trim(),
              ),
            ),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () {
                  _pollTimer?.cancel();
                  widget.dismiss();
                },
                child: const Text('Cancel'),
              ),
              const SizedBox(width: AfSpacing.s8),
              TextButton(
                onPressed: () {
                  _pollTimer?.cancel();
                  _checkAgain();
                },
                child: const Text('Check Again'),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

Future<void> showLastFmSignOutDialog(
  BuildContext context,
  WidgetRef ref,
) async {
  final confirmed = await showBlurDialog<bool>(
    context: context,
    builder: (context, dismiss) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Disconnect Last.fm?', style: AfTypography.titleMedium),
        const SizedBox(height: AfSpacing.s12),
        Text(
          'You will be signed out from Last.fm, and tracks will no longer be scrobbled.',
          style: AfTypography.bodyMedium,
        ),
        const SizedBox(height: AfSpacing.s24),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: () => dismiss(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => dismiss(true),
              child: Text(
                'Disconnect',
                style: AfTypography.bodyMedium.copyWith(
                  color: AfColors.semanticError,
                ),
              ),
            ),
          ],
        ),
      ],
    ),
  );

  if (confirmed == true) {
    ref.read(lastfmSessionKeyProvider.notifier).set('');
    ref.read(lastfmUsernameProvider.notifier).set('');
    unawaited(PlayerSettingsStore.saveLastFmSessionKey(''));
    unawaited(PlayerSettingsStore.saveLastFmUsername(''));

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Disconnected from Last.fm.')),
      );
    }
  }
}
