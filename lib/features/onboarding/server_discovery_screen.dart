import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/jellyfin/client.dart';
import '../../core/jellyfin/discovery.dart';
import '../../core/jellyfin/models/server.dart';
import '../../core/local/app_mode_store.dart';
import '../../core/subsonic/client.dart';
import '../../design_tokens/tokens.dart';
import '../../state/providers.dart';
import '../../utils/log.dart';
import '../../widgets/af_loading_indicator.dart';
import '../../widgets/press_scale.dart';
import '../../widgets/skeleton.dart';
import '../../widgets/stagger_reveal.dart';

/// LAN/URL server discovery screen.
///
/// Scans for Jellyfin/Navidrome servers via mDNS with shimmer loading
/// skeletons, shows discovered server cards with status indicators,
/// and provides manual URL input.
class ServerDiscoveryScreen extends ConsumerStatefulWidget {
  const ServerDiscoveryScreen({super.key});

  @override
  ConsumerState<ServerDiscoveryScreen> createState() =>
      _ServerDiscoveryScreenState();
}

class _ServerDiscoveryScreenState extends ConsumerState<ServerDiscoveryScreen> {
  StreamSubscription<JellyfinServer>? _sub;
  Timer? _scanTimeout;
  final _manualController = TextEditingController(text: 'http://');
  bool _scanning = true;
  String? _manualError;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _startScan();
  }

  @override
  void dispose() {
    _scanTimeout?.cancel();
    _sub?.cancel();
    _manualController.dispose();
    super.dispose();
  }

  void _startScan() {
    setState(() => _scanning = true);
    ref.read(discoveredServersProvider.notifier).set(const []);
    _sub?.cancel();
    _sub = JellyfinDiscovery(clientVersion: ref.read(aetherfinVersionProvider))
        .scan()
        .listen(
          (s) {
            final current = ref.read(discoveredServersProvider);
            if (!current.contains(s)) {
              ref.read(discoveredServersProvider.notifier).set([...current, s]);
            }
          },
          onError: (_) {},
          onDone: () => mounted ? setState(() => _scanning = false) : null,
        );
    _scanTimeout = Timer(const Duration(seconds: 6), () {
      if (mounted) setState(() => _scanning = false);
    });
  }

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

  Future<void> _useManual() async {
    final raw = _manualController.text.trim();
    if (raw.isEmpty) return;
    final urlError = _validateServerUrl(raw);
    if (urlError != null) {
      setState(() => _manualError = urlError);
      return;
    }
    final uri = Uri.tryParse(raw)!;
    setState(() {
      _manualError = null;
      _busy = true;
    });

    // Preserve any base path the user pasted (e.g. https://media.example.com/jellyfin),
    // and strip a trailing slash so we don't construct doubled slashes
    // when Dio joins relative paths.
    final basePath = uri.path.replaceAll(RegExp(r'/+$'), '');
    final server = JellyfinServer(
      baseUrl:
          '${uri.scheme}://${uri.host}'
          '${uri.hasPort ? ':${uri.port}' : ''}'
          '$basePath',
      name: uri.host,
      isLocal: false,
    );

    // Try Jellyfin first, then Navidrome/Subsonic
    final jellyfinClient = JellyfinClient(
      server: server,
      deviceId: ref.read(deviceIdProvider),
      clientVersion: ref.read(aetherfinVersionProvider),
    );
    try {
      final resolved = await jellyfinClient.publicInfo();
      if (!mounted) return;
      setState(() => _busy = false);
      _continueWith(resolved);
      return;
    } catch (e, stack) {
      afLog(
        'error',
        'Jellyfin publicInfo probe failed, trying Subsonic',
        error: e,
        stackTrace: stack,
      );
    } finally {
      jellyfinClient.close();
    }

    // Probe Subsonic ping.view — Navidrome responds with a Subsonic
    // API envelope even on bad credentials, confirming the server type.
    try {
      final testClient = SubsonicClient(
        server: server,
        username: '',
        password: '',
        clientVersion: ref.read(aetherfinVersionProvider),
      );
      try {
        await testClient.ping();
      } on SubsonicApiError {
        // Expected — wrong/empty creds but the Subsonic envelope arrived
      }
      testClient.close();
      if (!mounted) return;
      setState(() => _busy = false);
      _continueWith(
        server.copyWith(name: 'Navidrome', isReachable: true),
        serverType: ServerType.subsonic,
      );
    } on Exception catch (e, stack) {
      afLog('error', 'server discovery failed', error: e, stackTrace: stack);
      if (!mounted) return;
      setState(() {
        _manualError =
            'Couldn\'t reach ${server.baseUrl}. '
            'Make sure the server is running and accessible from your device.';
        _busy = false;
      });
    }
  }

  void _continueWith(
    JellyfinServer s, {
    ServerType serverType = ServerType.jellyfin,
  }) {
    ref.read(discoveredServersProvider.notifier).set([s]);
    context.push(
      '/onboarding/sign-in',
      extra: (server: s, serverType: serverType),
    );
  }

  @override
  Widget build(BuildContext context) {
    final servers = ref.watch(discoveredServersProvider);
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(LucideIcons.arrowLeft),
          tooltip: 'Back',
          onPressed: () async {
            // Reset mode on back — user wants to re-decide at the
            // WelcomeScreen. This also prevents stale redirects on
            // app restart after going back.
            await AppModeStore.clear();
            if (context.mounted) {
              ref.read(appModeProvider.notifier).set(null);
              // null triggers resetRouterMode() in main.dart's modeSub,
              // clearing the router's _appMode and _localOnboardingCompleted.
              //
              // Use go('/') instead of pop() to avoid redirect race:
              // notifyAuthChanged() from modeSub fires synchronously and
              // causes GoRouter to re-evaluate the redirect mid-pop,
              // resulting in a "reload" of the same screen.
              context.go('/');
            }
          },
        ),
        title: Text('Find your server', style: AfTypography.titleMedium),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AfSpacing.gutterGenerous,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Text(
                  'Step 2 of 5',
                  style: AfTypography.caption.copyWith(
                    color: AfColors.textTertiary,
                  ),
                ),
              ),
              const SizedBox(height: AfSpacing.s8),
              Text(
                _scanning
                    ? 'Scanning your network for servers…'
                    : 'Pick a server, or enter its address.',
                style: AfTypography.bodyMedium.copyWith(
                  color: AfColors.textSecondary,
                ),
              ),
              const SizedBox(height: AfSpacing.s24),

              // Scanning skeleton
              if (_scanning && servers.isEmpty) const _ScanSkeleton(),

              // Discovered server cards
              if (servers.isNotEmpty)
                StaggerReveal(
                  children: [
                    for (final s in servers) ...[
                      _ServerCard(server: s, onTap: () => _continueWith(s)),
                      const SizedBox(height: AfSpacing.s12),
                    ],
                  ],
                ),

              if (!_scanning && servers.isEmpty)
                Text(
                  'No servers found. Make sure your server (Jellyfin '
                  'or Navidrome) is running and on the same Wi-Fi, then '
                  'enter its URL below.',
                  style: AfTypography.bodyMedium.copyWith(
                    color: AfColors.textTertiary,
                  ),
                ),
              const Spacer(),
              const Divider(color: AfColors.surfaceHigh),
              const SizedBox(height: AfSpacing.s16),
              Text(
                'Or enter manually',
                style: AfTypography.label.copyWith(
                  color: AfColors.textTertiary,
                ),
              ),
              const SizedBox(height: AfSpacing.s8),
              TextField(
                controller: _manualController,
                autofocus: true,
                keyboardType: TextInputType.url,
                autocorrect: false,
                style: AfTypography.bodyLarge,
                decoration: InputDecoration(
                  labelText: 'Server URL',
                  hintText: 'http://192.168.1.10:8096',
                  errorText: _manualError,
                ),
                onSubmitted: (_) => _busy ? null : _useManual(),
              ),
              const SizedBox(height: AfSpacing.s12),
              ElevatedButton(
                onPressed: _busy ? null : _useManual,
                child: _busy
                    ? const AfLoadingIndicator(size: 18, strokeWidth: 2.5)
                    : const Text('Connect'),
              ),
              const SizedBox(height: AfSpacing.s24),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shimmer skeleton shown during mDNS scan.
class _ScanSkeleton extends StatelessWidget {
  const _ScanSkeleton();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(3, (_) {
        return Padding(
          padding: const EdgeInsets.only(bottom: AfSpacing.s12),
          child: ShimmerWrap(
            child: Container(
              padding: const EdgeInsets.all(AfSpacing.s16),
              decoration: const BoxDecoration(
                color: AfColors.surfaceRaised,
                borderRadius: AfRadii.borderLg,
              ),
              child: const Row(
                children: [
                  SkeletonCircle(size: 40),
                  SizedBox(width: AfSpacing.s16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SkeletonBar(width: 120, height: 16),
                        SizedBox(height: AfSpacing.s4),
                        SkeletonBar(width: 200, height: 12),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }),
    );
  }
}

class _ServerCard extends ConsumerWidget {
  const _ServerCard({required this.server, required this.onTap});
  final JellyfinServer server;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spectral = ref.watch(
      currentSpectralProvider.select((s) => s.primary),
    );
    return PressScale(
      ensureHitTarget: false,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(AfSpacing.s16),
        decoration: BoxDecoration(
          color: AfColors.surfaceRaised,
          borderRadius: AfRadii.borderLg,
          border: Border.all(color: AfColors.surfaceHigh, width: 1),
        ),
        child: Row(
          children: [
            // Status indicator
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: spectral.withValues(alpha: 0.15),
                borderRadius: AfRadii.borderMd,
              ),
              child: Icon(LucideIcons.server, color: spectral, size: 24),
            ),
            const SizedBox(width: AfSpacing.s16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(server.name, style: AfTypography.titleSmall),
                  const SizedBox(height: AfSpacing.s2),
                  Text(
                    server.baseUrl,
                    style: AfTypography.bodySmall.copyWith(
                      color: AfColors.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
            // Reachable status dot
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: server.isReachable
                    ? AfColors.semanticSuccess
                    : AfColors.textTertiary,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: AfSpacing.s8),
            const Icon(LucideIcons.chevronRight, color: AfColors.textTertiary),
          ],
        ),
      ),
    );
  }
}
