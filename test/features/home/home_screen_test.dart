import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aetherfin/core/jellyfin/models/items.dart';
import 'package:aetherfin/design_tokens/colors.dart';
import 'package:aetherfin/features/home/home_screen.dart';
import 'package:aetherfin/state/providers.dart';
import 'package:aetherfin/state/state_holder.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// Creates the minimal provider overrides so HomeScreen renders in
  /// local mode with empty library data — no backend or database needed.
  ProviderContainer createHomeContainer() {
    return ProviderContainer(
      overrides: [
        // ── App mode: local (avoids YouTube branch) ──
        appModeProvider.overrideWith(
          () => StateHolder<AppMode?>((ref) => AppMode.local),
        ),

        // ── Spectral: fallback palette ──
        currentSpectralProvider.overrideWith((ref) => Spectral.fallback),

        // ── Backend: null (no server connected) ──
        musicBackendProvider.overrideWith((ref) => null),

        // ── Library data: empty lists ──
        recentlyAddedAlbumsProvider.overrideWith((ref) => const <AfAlbum>[]),
        localTracksProvider.overrideWith((ref) => const <AfTrack>[]),
        localArtistsProvider.overrideWith((ref) => const <AfArtist>[]),
        localGenresProvider.overrideWith((ref) => const <AfGenre>[]),
        localAlbumsProvider.overrideWith((ref) => const <AfAlbum>[]),
        lostMemoriesProvider.overrideWith((ref) => const <AfTrack>[]),
      ],
    );
  }

  group('HomeScreen', () {
    // Use pump() with fixed duration instead of pumpAndSettle() for
    // controlled frame advancement.

    Future<void> pumpHome(
      WidgetTester tester,
      ProviderContainer container,
    ) async {
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: HomeScreen()),
        ),
      );
      // Pump a few frames to let async providers resolve and build.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
    }

    testWidgets('renders without crashing', (tester) async {
      final container = createHomeContainer();
      addTearDown(container.dispose);
      await pumpHome(tester, container);
      expect(find.byType(HomeScreen), findsOneWidget);
    });

    testWidgets('displays "Listen" header', (tester) async {
      final container = createHomeContainer();
      addTearDown(container.dispose);
      await pumpHome(tester, container);
      expect(find.text('Listen'), findsOneWidget);
    });

    testWidgets('renders hero carousel section (empty state)', (tester) async {
      final container = createHomeContainer();
      addTearDown(container.dispose);
      await pumpHome(tester, container);
      // When recentlyAddedAlbumsProvider returns empty data, the carousel
      // renders as a SizedBox.shrink(). The CustomScrollView and its slivers
      // should still be present.
      expect(find.byType(CustomScrollView), findsOneWidget);
    });

    testWidgets('renders Recently Played section header', (tester) async {
      final container = createHomeContainer();
      addTearDown(container.dispose);
      await pumpHome(tester, container);
      expect(find.text('Recently played'), findsOneWidget);
    });

    testWidgets('renders RefreshIndicator for pull-to-refresh', (tester) async {
      final container = createHomeContainer();
      addTearDown(container.dispose);
      await pumpHome(tester, container);
      expect(find.byType(RefreshIndicator), findsOneWidget);
    });
  });
}
