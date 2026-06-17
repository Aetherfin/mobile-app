import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aetherfin/core/jellyfin/models/items.dart';
import 'package:aetherfin/core/jellyfin/models/server.dart';
import 'package:aetherfin/design_tokens/colors.dart';
import 'package:aetherfin/features/profile/profile_screen.dart';
import 'package:aetherfin/state/providers.dart';
import 'package:aetherfin/state/state_holder.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  ProviderContainer createContainer({
    JellyfinAuth? auth,
    AppMode? mode,
    List<AfTrack> tracks = const [],
    List<AfAlbum> albums = const [],
    List<AfArtist> artists = const [],
  }) {
    return ProviderContainer(
      overrides: [
        currentSpectralProvider.overrideWith((ref) => Spectral.fallback),
        initialAuthProvider.overrideWithValue(auth),
        appModeProvider.overrideWith(
          () => StateHolder<AppMode?>((ref) => mode),
        ),
        musicBackendProvider.overrideWith((ref) => null),
        localTracksProvider.overrideWith((ref) => tracks),
        localAlbumsProvider.overrideWith((ref) => albums),
        localArtistsProvider.overrideWith((ref) => artists),
        allTracksProvider.overrideWith((ref) => tracks),
        allAlbumsProvider.overrideWith((ref) => albums),
        allArtistsProvider.overrideWith((ref) => artists),
        allPlaylistsProvider.overrideWith((ref) => const <AfPlaylist>[]),
        favoriteAlbumsProvider.overrideWith((ref) => const <AfAlbum>[]),
        recentlyAddedAlbumsProvider.overrideWith((ref) => const <AfAlbum>[]),
        recentlyPlayedTracksProvider.overrideWith((ref) => const <AfTrack>[]),
        favoriteTracksProvider.overrideWith((ref) => const <AfTrack>[]),
        allGenresProvider.overrideWith((ref) => const <AfGenre>[]),
        lastfmSessionKeyProvider.overrideWith(
          () => StateHolder<String>((ref) => ''),
        ),
        lastfmUsernameProvider.overrideWith(
          () => StateHolder<String>((ref) => ''),
        ),
      ],
    );
  }

  group('ProfileScreen', () {
    // ProfileScreen contains animations that never settle (e.g. shimmer in
    // AboutSection). Use pump() with fixed duration like HomeScreen tests.
    Future<void> pumpProfile(
      WidgetTester tester,
      ProviderContainer container,
    ) async {
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: ProfileScreen()),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
    }

    testWidgets('renders without crashing', (tester) async {
      final container = createContainer(mode: AppMode.local);
      addTearDown(container.dispose);

      await pumpProfile(tester, container);

      expect(find.byType(ProfileScreen), findsOneWidget);
    });

    testWidgets('shows "Profile" title', (tester) async {
      final container = createContainer(mode: AppMode.local);
      addTearDown(container.dispose);

      await pumpProfile(tester, container);

      expect(find.text('Profile'), findsOneWidget);
    });

    testWidgets('settings button exists', (tester) async {
      final container = createContainer(mode: AppMode.local);
      addTearDown(container.dispose);

      await pumpProfile(tester, container);

      expect(find.byTooltip('Settings'), findsOneWidget);
    });

    testWidgets('displays user name when auth loaded', (tester) async {
      const auth = JellyfinAuth(
        server: JellyfinServer(
          baseUrl: 'http://test:8096',
          name: 'Test Server',
        ),
        userId: 'user-1',
        userName: 'TestUser',
        accessToken: 'token',
      );
      final container = createContainer(auth: auth, mode: AppMode.server);
      addTearDown(container.dispose);

      await pumpProfile(tester, container);

      expect(find.text('TestUser'), findsOneWidget);
    });

    testWidgets('shows library counts when data loaded', (tester) async {
      final container = createContainer(
        mode: AppMode.local,
        tracks: List.generate(
          50,
          (i) => AfTrack(
            id: 't-$i',
            title: 'Track $i',
            artistName: 'Artist',
            albumName: 'Album',
            duration: const Duration(minutes: 3),
          ),
        ),
        albums: List.generate(
          10,
          (i) => AfAlbum(
            id: 'a-$i',
            name: 'Album $i',
            artistName: 'Artist',
            trackCount: 5,
          ),
        ),
      );
      addTearDown(container.dispose);

      await pumpProfile(tester, container);

      // The profile screen shows track and album counts via SplitInfoSection
      expect(find.text('50'), findsWidgets);
      expect(find.text('10'), findsWidgets);
    });

    testWidgets('loading state renders without error', (tester) async {
      final container = createContainer(mode: AppMode.local);
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: ProfileScreen()),
        ),
      );
      // Pump without settling to catch loading states
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.byType(ProfileScreen), findsOneWidget);
    });
  });
}
