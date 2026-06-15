import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/network/connectivity_observer.dart';
import '../design_tokens/colors.dart';
import '../design_tokens/spacing.dart';
import '../state/animated_spectral.dart';
import '../utils/log.dart';
import 'router.dart';
import 'theme.dart';

/// Root widget. Uses [appRouter] directly — a module-level singleton that
/// is never recreated. This prevents go_router's internal
/// [StatefulNavigationShell] from receiving a new key on auth state changes,
/// which was the cause of the recurring "Duplicate GlobalKey" crash.
///
/// Auth redirects are handled by [_authRefresh] inside router.dart, which
/// is notified by a [ProviderContainer] listener wired in main.dart.
class AetherfinApp extends ConsumerWidget {
  const AetherfinApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    afLog('boot', 'AetherfinApp.build');
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
    );

    return AnimatedSpectralScope(child: _AetherfinRouter());
  }
}

class _AetherfinRouter extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Spectral>(
      valueListenable: animatedSpectral,
      builder: (context, spectral, _) {
        final theme = buildNocturneThemeFromSpectral(spectral);
        return MaterialApp.router(
          title: 'Aetherfin',
          debugShowCheckedModeBanner: false,
          themeMode: ThemeMode.dark,
          darkTheme: theme,
          theme: theme,
          routerConfig: appRouter,
          builder: (context, child) {
            final mq = MediaQuery.of(context);
            // Clamp text scaler to prevent accessibility blowout on large fonts.
            // Range 0.85–1.3 preserves readability while preventing layout overflow.
            // Scaled typography variants (AfTypography.*Scaled) handle this gracefully.
            final clamped = mq.textScaler.clamp(
              minScaleFactor: 0.85,
              maxScaleFactor: 1.3,
            );
            return MediaQuery(
              data: mq.copyWith(textScaler: clamped),
              child: _ConnectivityBanner(
                child: child ?? const SizedBox.shrink(),
              ),
            );
          },
        );
      },
    );
  }
}

/// Monitors network connectivity and shows a top SnackBar when offline.
///
/// Auto-dismisses on reconnection. Skips display during onboarding routes.
class _ConnectivityBanner extends StatefulWidget {
  const _ConnectivityBanner({required this.child});

  final Widget child;

  @override
  State<_ConnectivityBanner> createState() => _ConnectivityBannerState();
}

class _ConnectivityBannerState extends State<_ConnectivityBanner> {
  ConnectivityObserver? _observer;
  StreamSubscription<bool>? _sub;

  @override
  void initState() {
    super.initState();
    _observer = ConnectivityObserver();
    _sub = _observer!.stream.listen(_onConnectivityChanged);
  }

  void _onConnectivityChanged(bool online) {
    if (!mounted) return;

    final loc = GoRouterState.of(context).matchedLocation;
    // Skip during onboarding
    if (loc == '/' || loc.startsWith('/onboarding')) return;

    final messenger = ScaffoldMessenger.of(context);
    if (online) {
      messenger.hideCurrentSnackBar();
    } else {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(_offlineSnackBar());
    }
  }

  SnackBar _offlineSnackBar() {
    return SnackBar(
      content: const Row(
        children: [
          Icon(LucideIcons.wifiOff, color: Colors.white, size: 20),
          SizedBox(width: AfSpacing.s8),
          Expanded(child: Text('No internet connection')),
        ],
      ),
      backgroundColor: AfColors.semanticOffline,
      behavior: SnackBarBehavior.floating,
      margin: EdgeInsets.only(
        left: AfSpacing.s16,
        right: AfSpacing.s16,
        top: MediaQuery.of(context).padding.top + AfSpacing.s8,
      ),
      // Position banner at the top
      dismissDirection: DismissDirection.up,
      duration: const Duration(seconds: 5),
    );
  }

  @override
  void dispose() {
    _sub?.cancel();
    _observer?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
