import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aetherfin/core/jellyfin/models/items.dart';
import 'package:aetherfin/design_tokens/colors.dart';
import 'package:aetherfin/features/search/search_screen.dart';
import 'package:aetherfin/state/providers.dart';
import 'package:aetherfin/state/state_holder.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// Creates the minimal provider overrides so SearchScreen renders
  /// in idle state — no backend or database needed.
  ProviderContainer createSearchContainer() {
    return ProviderContainer(
      overrides: [
        // ── Spectral: fallback palette ──
        currentSpectralProvider.overrideWith((ref) => Spectral.fallback),

        // ── App mode: local (for idle grid providers) ──
        appModeProvider.overrideWith(
          () => StateHolder<AppMode?>((ref) => AppMode.local),
        ),

        // ── Backend: null (no server connected) ──
        musicBackendProvider.overrideWith((ref) => null),

        // ── Idle grid data: empty lists ──
        localArtistsProvider.overrideWith((ref) => const <AfArtist>[]),
        localGenresProvider.overrideWith((ref) => const <AfGenre>[]),
        localAlbumsProvider.overrideWith((ref) => const <AfAlbum>[]),
      ],
    );
  }

  group('SearchScreen', () {
    testWidgets('renders without crashing', (tester) async {
      final container = createSearchContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: SearchScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(SearchScreen), findsOneWidget);
    });

    testWidgets('displays "Search" header', (tester) async {
      final container = createSearchContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: SearchScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Search'), findsOneWidget);
    });

    testWidgets('displays search text field', (tester) async {
      final container = createSearchContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: SearchScreen()),
        ),
      );
      await tester.pumpAndSettle();

      // The search field is a TextField with hint text
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('Artists, albums, tracks…'), findsOneWidget);
    });

    testWidgets('search field has autofocus enabled', (tester) async {
      final container = createSearchContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: SearchScreen()),
        ),
      );
      await tester.pumpAndSettle();

      // The TextField is configured with autofocus: true
      final textField = tester.widget<TextField>(find.byType(TextField));
      expect(textField.autofocus, isTrue);
    });

    testWidgets('shows idle state when query is empty', (tester) async {
      final container = createSearchContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: SearchScreen()),
        ),
      );
      await tester.pumpAndSettle();

      // Idle state shows filter pills (Artists, Genres, Albums)
      // and an idle grid. The custom scroll view should be present.
      expect(find.byType(CustomScrollView), findsAtLeastNWidgets(1));
    });
  });
}
