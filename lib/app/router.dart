import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/jellyfin/models/server.dart';
import '../state/providers.dart';
import '../design_tokens/tokens.dart';
import '../features/album/album_screen.dart';
import '../features/artist/artist_screen.dart';
import '../features/cast_picker/cast_picker_screen.dart';
import '../features/home/home_screen.dart';
import '../features/library/library_screen.dart';
import '../features/lyrics/lyrics_screen.dart';
import '../features/now_playing/now_playing_screen.dart';
import '../features/onboarding/all_set_screen.dart';
import '../features/onboarding/library_scope_screen.dart';
import '../features/onboarding/server_discovery_screen.dart';
import '../features/onboarding/sign_in_screen.dart';
import '../features/onboarding/welcome_screen.dart';
import '../features/playlist/playlist_screen.dart';
import '../features/profile/profile_screen.dart';
import '../features/queue/queue_screen.dart';
import '../features/search/search_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/sleep_timer/sleep_timer_screen.dart';
import '../widgets/app_shell.dart';

/// Single source of truth for all in-app navigation.
///
/// Onboarding lives outside the shell so the bottom nav doesn't appear
/// before the user has chosen a library. All four tabs sit inside a
/// [StatefulShellRoute], which preserves each tab's stack across switches
/// (per design spec §11.6).
final routerProvider = Provider<GoRouter>((ref) {
  final rootKey = GlobalKey<NavigatorState>();
  final shellKey = GlobalKey<NavigatorState>();

  // Re-evaluate redirects whenever auth changes so signing in lands you on
  // /home and signing out drops you back at /.
  final refresh = _AuthRefreshListenable();
  ref.listen<JellyfinAuth?>(authProvider, (_, __) => refresh._notify(),
      fireImmediately: false);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    navigatorKey: rootKey,
    initialLocation: '/',
    refreshListenable: refresh,
    redirect: (context, state) {
      final auth = ref.read(authProvider);
      final loc = state.matchedLocation;
      final inOnboarding = loc == '/' || loc.startsWith('/onboarding');
      if (auth != null && inOnboarding) {
        // Already signed in — fast-forward past welcome / discovery.
        return '/home';
      }
      if (auth == null && !inOnboarding) {
        // No credentials — send the user through onboarding before we
        // try to render any post-auth screen (which would 401 anyway).
        return '/';
      }
      return null;
    },
    routes: [
      // Onboarding
      GoRoute(
        path: '/',
        builder: (_, __) => const WelcomeScreen(),
      ),
      GoRoute(
        path: '/onboarding/discover',
        builder: (_, __) => const ServerDiscoveryScreen(),
      ),
      GoRoute(
        path: '/onboarding/sign-in',
        builder: (_, state) =>
            SignInScreen(server: state.extra! as JellyfinServer),
      ),
      GoRoute(
        path: '/onboarding/scope',
        builder: (_, __) => const LibraryScopeScreen(),
      ),
      GoRoute(
        path: '/onboarding/done',
        builder: (_, __) => const AllSetScreen(),
      ),

      // Shell — 4 tabs.
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => AppShell(shell: shell),
        branches: [
          StatefulShellBranch(
            navigatorKey: shellKey,
            routes: [
              GoRoute(
                path: '/home',
                pageBuilder: (_, __) =>
                    const NoTransitionPage(child: HomeScreen()),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/search',
                pageBuilder: (_, __) =>
                    const NoTransitionPage(child: SearchScreen()),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/library',
                pageBuilder: (_, __) =>
                    const NoTransitionPage(child: LibraryScreen()),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/profile',
                pageBuilder: (_, __) =>
                    const NoTransitionPage(child: ProfileScreen()),
              ),
            ],
          ),
        ],
      ),

      // Top-level sheets / overlays (live above the shell).
      GoRoute(
        path: '/now-playing',
        parentNavigatorKey: rootKey,
        pageBuilder: (_, __) => _NowPlayingPage(),
      ),
      GoRoute(
        path: '/lyrics',
        parentNavigatorKey: rootKey,
        builder: (_, __) => const LyricsScreen(),
      ),
      GoRoute(
        path: '/queue',
        parentNavigatorKey: rootKey,
        builder: (_, __) => const QueueScreen(),
      ),
      GoRoute(
        path: '/sleep',
        parentNavigatorKey: rootKey,
        builder: (_, __) => const SleepTimerScreen(),
      ),
      GoRoute(
        path: '/cast',
        parentNavigatorKey: rootKey,
        builder: (_, __) => const CastPickerScreen(),
      ),
      GoRoute(
        path: '/settings',
        parentNavigatorKey: rootKey,
        builder: (_, __) => const SettingsScreen(),
      ),

      // Top-level album / artist routes. We register these above the shell
      // so that `context.push('/album/<id>')` and
      // `context.push('/artist/<id>')` resolve identically regardless of
      // which tab the user is currently on — code in widgets like
      // `library_screen.dart` and `home_screen.dart` pushes the bare path,
      // and previously hit `GoException: no routes for location: /artist/<id>`
      // because the routes were only registered as nested children of each
      // shell branch (e.g. `/home/artist/:id`). Living above the shell also
      // hides the bottom nav while the user is browsing detail screens.
      GoRoute(
        path: '/album/:id',
        parentNavigatorKey: rootKey,
        builder: (_, state) =>
            AlbumScreen(albumId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/artist/:id',
        parentNavigatorKey: rootKey,
        builder: (_, state) =>
            ArtistScreen(artistId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/playlist/:id',
        parentNavigatorKey: rootKey,
        builder: (_, state) =>
            PlaylistScreen(playlistId: state.pathParameters['id']!),
      ),
    ],
  );
});

/// Thin ChangeNotifier we hand to GoRouter so it re-runs `redirect` when
/// auth state flips. We can't pass `authProvider` directly because
/// GoRouter expects a Listenable and Riverpod providers are not Listenables.
class _AuthRefreshListenable extends ChangeNotifier {
  void _notify() => notifyListeners();
}

class _NowPlayingPage extends Page<void> {
  @override
  Route<void> createRoute(BuildContext context) {
    return PageRouteBuilder<void>(
      settings: this,
      transitionDuration: AfDurations.expressive,
      reverseTransitionDuration: AfDurations.expressive,
      pageBuilder: (_, __, ___) => const NowPlayingScreen(),
      transitionsBuilder: (context, animation, _, child) {
        final reduced = MediaQuery.of(context).disableAnimations;
        if (reduced) {
          return FadeTransition(opacity: animation, child: child);
        }
        final curved = CurvedAnimation(
          parent: animation,
          curve: AfCurves.easeEmphasized,
          reverseCurve: AfCurves.easeEmphasized,
        );
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 1),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        );
      },
    );
  }
}
