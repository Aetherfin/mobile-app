import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app/app.dart';
import 'core/audio/player_service.dart';
import 'core/jellyfin/auth_storage.dart';
import 'core/jellyfin/models/server.dart';
import 'design_tokens/tokens.dart';
import 'state/providers.dart';

/// Plain-prefs key for the fallback device ID used when the encrypted
/// secure-storage keystore can't be reached. Persisting the fallback
/// means even a permanently-broken keystore looks like the SAME device
/// across launches instead of a fresh one (which would create a stale
/// Jellyfin session per launch and trip the 500-on-AuthenticateByName
/// described in CLAUDE.md §5.1).
const _fallbackDeviceIdKey = 'aetherfin.deviceId.fallback.v1';

/// Boot breadcrumb — every checkpoint prefixes with this so a single
/// `adb logcat | grep aetherfin:boot` shows the full startup trace.
void _boot(String message) {
  // ignore: avoid_print
  print('aetherfin:boot $message');
}



Future<void> main() async {
  _boot('main() entered');
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    _boot('WidgetsFlutterBinding.ensureInitialized OK');

    // Surface framework errors to Logcat (always) AND keep a visible
    // breadcrumb on screen via [_RootErrorWidget]. Without this a single
    // thrown exception can leave the user staring at an empty surface.
    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      // ignore: avoid_print
      print('aetherfin:error FlutterError: ${details.exceptionAsString()}');
      if (details.stack != null) {
        // ignore: avoid_print
        print('aetherfin:error stack: ${details.stack}');
      }
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      // ignore: avoid_print
      print('aetherfin:error PlatformDispatcher: $error');
      // ignore: avoid_print
      print('aetherfin:error stack: $stack');
      return true;
    };
    ErrorWidget.builder = (details) => _RootErrorWidget(details: details);
    _boot('error handlers installed');

    // Load the stable per-install device ID + the persisted auth blob
    // before mounting the app so every Jellyfin request uses the same
    // identifier from the very first frame, AND so the router can
    // immediately route an already-signed-in user past the welcome screen
    // to /home. Two sub-100 ms keystore reads — we await them in parallel
    // so they don't stack. If either fails (corrupt keystore, etc.) we
    // fall back gracefully rather than blocking the user.
    final storage = AuthStorage();
    String deviceId;
    JellyfinAuth? initialAuth;
    try {
      final results = await Future.wait([
        storage.loadOrCreateDeviceId(),
        storage.load(),
      ]);
      deviceId = results[0] as String;
      initialAuth = results[1] as JellyfinAuth?;
      _boot('device id loaded (len=${deviceId.length}); '
          'auth ${initialAuth != null ? "restored for ${initialAuth.userName}" : "absent"}');
    } catch (e, stack) {
      // ignore: avoid_print
      print('aetherfin:error device id / auth load failed: $e');
      // ignore: avoid_print
      print('aetherfin:error stack: $stack');
      // Last-ditch fallback so onboarding can still proceed. Persist
      // the fallback ID to plain shared_preferences so it survives the
      // next launch even when secure_storage stays broken — otherwise
      // Jellyfin sees a new device on every launch and accumulates
      // stale sessions (the known cause of `AuthenticateByName` 500s).
      deviceId = await _loadOrCreateFallbackDeviceId();
      initialAuth = null;
    }

    // Construct THE one and only audio handler up front so the exact
    // same instance is shared between Riverpod (via
    // `playerServiceProvider` override) and `AudioService.init` below.
    // Previously the override created one service and `_warmUpAudio()`
    // created a second orphaned one — lock-screen controls flapped
    // against a dead handler and never drove playback.
    final handler = AfPlayerService();

    // Launch the UI immediately — audio init runs in the background AFTER
    // the first frame.
    _boot('calling runApp');
    runApp(
      ProviderScope(
        overrides: [
          deviceIdProvider.overrideWithValue(deviceId),
          initialAuthProvider.overrideWithValue(initialAuth),
          playerServiceProvider.overrideWith((ref) {
            // Apply the same Riverpod-side wiring the default factory
            // would have applied (currentTrack forwarding + Jellyfin
            // session reporter), but on the singleton `handler` so the
            // OS-integrated handler IS the one the UI sees.
            wirePlayerService(ref, handler);
            return handler;
          }),
        ],
        child: const AetherfinApp(),
      ),
    );
    _boot('runApp returned');

    // Schedule audio_service init AFTER the first frame is painted so we
    // are 100% sure the UI is alive before we touch the OS. If init fails
    // (e.g. on a stripped-down device), we log + carry on; the app still
    // works without lock-screen controls.
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _boot('first frame painted — kicking AudioService init');
      unawaited(_warmUpAudio(handler));
    });
  }, (error, stack) {
    // ignore: avoid_print
    print('aetherfin:error zoned uncaught: $error');
    // ignore: avoid_print
    print('aetherfin:error stack: $stack');
  });
}

/// Read or generate the persistent fallback device ID.
///
/// Only used when `flutter_secure_storage` is unreachable (corrupt
/// keystore, brand-new device with no biometric setup, etc.). The ID
/// lives in plain `shared_preferences` — not as secure as the encrypted
/// store, but it's just a random opaque token (not a credential) and
/// having it survive launches is far more important than hiding it.
Future<String> _loadOrCreateFallbackDeviceId() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(_fallbackDeviceIdKey);
    if (existing != null && existing.isNotEmpty) {
      _boot('fallback device id reused (len=${existing.length})');
      return existing;
    }
    final fresh =
        'aetherfin-fallback-${DateTime.now().microsecondsSinceEpoch}';
    await prefs.setString(_fallbackDeviceIdKey, fresh);
    _boot('fallback device id generated (len=${fresh.length})');
    return fresh;
  } catch (e, stack) {
    // ignore: avoid_print
    print('aetherfin:error fallback device id load failed: $e');
    // ignore: avoid_print
    print('aetherfin:error stack: $stack');
    // shared_preferences itself is unavailable — pick a per-launch ID
    // so the rest of the app still functions, even if Jellyfin sees a
    // new device every time. This branch is essentially unreachable on
    // a normal Android device.
    return 'aetherfin-fallback-${DateTime.now().microsecondsSinceEpoch}';
  }
}

Future<void> _warmUpAudio(AfPlayerService handler) async {
  try {
    _boot('AudioService.init starting');
    await AudioService.init(
      builder: () => handler,
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'dev.aetherfin.audio',
        androidNotificationChannelName: 'Aetherfin playback',
        androidNotificationOngoing: true,
        androidStopForegroundOnPause: true,
        notificationColor: Color(0xFF332C7A),
      ),
    );
    _boot('AudioService.init OK');
  } catch (e, stack) {
    // ignore: avoid_print
    print('aetherfin:error AudioService.init failed: $e');
    // ignore: avoid_print
    print('aetherfin:error stack: $stack');
    // Don't rethrow — the UI must keep working even without OS audio
    // integration. The mini-player + Now Playing will still drive playback
    // via the in-app handler that was already wired through ProviderScope.
  }
}

/// Last-line-of-defense error widget so the user always sees *something*
/// (with the actual exception text) instead of a gray rectangle when a
/// build throws.
class _RootErrorWidget extends StatelessWidget {
  final FlutterErrorDetails details;
  const _RootErrorWidget({required this.details});

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: ColoredBox(
        color: AfColors.surfaceCanvas,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text(
                  'Aetherfin hit a snag',
                  style: TextStyle(
                    color: AfColors.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                Flexible(
                  child: SingleChildScrollView(
                    child: Text(
                      details.exceptionAsString(),
                      style: const TextStyle(
                        color: AfColors.textSecondary,
                        fontSize: 13,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  kReleaseMode
                      ? 'Tap Restart on Android to retry.'
                      : 'Hot reload to retry.',
                  style: const TextStyle(
                    color: AfColors.textTertiary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
