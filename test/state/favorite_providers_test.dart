import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:aetherfin/core/backend/music_backend.dart';
import 'package:aetherfin/core/jellyfin/models/items.dart';
import 'package:aetherfin/state/favorite_providers.dart';
import 'package:aetherfin/state/library_providers.dart';
import 'package:aetherfin/state/music_backend_providers.dart';
import 'package:aetherfin/state/settings_providers.dart';
import 'package:aetherfin/state/state_holder.dart';

// ── Mocks ────────────────────────────────────────────────────────────────────

class MockMusicBackend extends Mock implements MusicBackend {}

// ── Helpers ──────────────────────────────────────────────────────────────────

AfTrack _fakeTrack({
  String id = 'track-1',
  String title = 'Test Track',
  String artistName = 'Test Artist',
  String albumName = 'Test Album',
  bool isFavorite = false,
}) => AfTrack(
  id: id,
  title: title,
  artistName: artistName,
  albumName: albumName,
  isFavorite: isFavorite,
);

/// Creates a container with common overrides for favorite provider tests.
///
/// [backend] is optional — pass null to simulate signed-out / demo mode.
/// [favoriteIds] overrides favoriteIdsProvider directly so isFavoriteProvider
/// resolves without hitting a real backend or relying on autoDispose chains.
ProviderContainer _createContainer({
  MusicBackend? backend,
  Set<String> favoriteIds = const {},
}) {
  final overrides = [
    musicBackendProvider.overrideWithValue(backend),
    lastfmApiKeyProvider.overrideWith(() => StateHolder<String>((ref) => '')),
    lastfmSessionKeyProvider.overrideWith(
      () => StateHolder<String>((ref) => ''),
    ),
    favoriteIdsProvider.overrideWith((ref) => favoriteIds),
  ];
  return ProviderContainer(overrides: overrides);
}

// ── Tests ────────────────────────────────────────────────────────────────────

void main() {
  setUpAll(() {
    registerFallbackValue(_fakeTrack());
  });

  group('trackFavoriteOverridesProvider', () {
    test('initial state is empty map', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(trackFavoriteOverridesProvider), isEmpty);
    });
  });

  group('trackFavoriteOverrideProvider', () {
    test('initial state is null for any track ID', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(trackFavoriteOverrideProvider('track-1')), isNull);
      expect(container.read(trackFavoriteOverrideProvider('track-99')), isNull);
    });

    test('can set and read override per track', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(trackFavoriteOverrideProvider('track-1').notifier).state =
          true;
      container.read(trackFavoriteOverrideProvider('track-2').notifier).state =
          false;

      expect(container.read(trackFavoriteOverrideProvider('track-1')), true);
      expect(container.read(trackFavoriteOverrideProvider('track-2')), false);
      // track-3 is independent
      expect(container.read(trackFavoriteOverrideProvider('track-3')), isNull);
    });
  });

  group('isFavoriteProvider', () {
    test('returns override when present (true)', () {
      final container = _createContainer(backend: null);
      addTearDown(container.dispose);

      container.read(trackFavoriteOverrideProvider('t1').notifier).state = true;

      expect(container.read(isFavoriteProvider('t1')), true);
    });

    test('returns override when present (false)', () {
      final container = _createContainer(backend: null, favoriteIds: {'t1'});
      addTearDown(container.dispose);

      // Without override, t1 would be favorite (in favoriteIds)
      expect(container.read(isFavoriteProvider('t1')), true);

      // Override to false
      container.read(trackFavoriteOverrideProvider('t1').notifier).state =
          false;
      expect(container.read(isFavoriteProvider('t1')), false);
    });

    test('falls back to favoriteIdsProvider when no override', () {
      final container = _createContainer(
        backend: null,
        favoriteIds: {'t1', 't2'},
      );
      addTearDown(container.dispose);

      expect(container.read(isFavoriteProvider('t1')), true);
      expect(container.read(isFavoriteProvider('t2')), true);
      expect(container.read(isFavoriteProvider('t3')), false);
    });
  });

  group('favoriteToggleProvider', () {
    test('toggles from non-favorite to favorite (optimistic update)', () async {
      final mockBackend = MockMusicBackend();
      when(
        () => mockBackend.setFavorite(any(), any()),
      ).thenAnswer((_) async {});

      final container = _createContainer(backend: mockBackend, favoriteIds: {});
      addTearDown(container.dispose);

      final track = _fakeTrack(id: 'toggle-1', isFavorite: false);
      expect(container.read(isFavoriteProvider('toggle-1')), false);

      final toggle = container.read(favoriteToggleProvider);
      await toggle(track);

      expect(container.read(isFavoriteProvider('toggle-1')), true);
      verify(() => mockBackend.setFavorite('toggle-1', true)).called(1);
    });

    test('toggles from favorite to non-favorite', () async {
      final mockBackend = MockMusicBackend();
      when(
        () => mockBackend.setFavorite(any(), any()),
      ).thenAnswer((_) async {});

      final container = _createContainer(
        backend: mockBackend,
        favoriteIds: {'toggle-2'},
      );
      addTearDown(container.dispose);

      expect(container.read(isFavoriteProvider('toggle-2')), true);

      final toggle = container.read(favoriteToggleProvider);
      await toggle(_fakeTrack(id: 'toggle-2', isFavorite: true));

      expect(container.read(isFavoriteProvider('toggle-2')), false);
      verify(() => mockBackend.setFavorite('toggle-2', false)).called(1);
    });

    test('rolls back optimistic update on backend error', () async {
      final mockBackend = MockMusicBackend();
      when(
        () => mockBackend.setFavorite(any(), any()),
      ).thenThrow(Exception('network error'));

      final container = _createContainer(backend: mockBackend, favoriteIds: {});
      addTearDown(container.dispose);

      final track = _fakeTrack(id: 'fail-1', isFavorite: false);
      expect(container.read(isFavoriteProvider('fail-1')), false);

      final toggle = container.read(favoriteToggleProvider);

      // Should throw but the override should be rolled back
      unawaited(expectLater(toggle(track), throwsA(isA<Exception>())));

      // After error, the optimistic override should be rolled back to false
      await Future<void>.delayed(Duration.zero);
      expect(container.read(trackFavoriteOverrideProvider('fail-1')), false);
      // isFavorite falls back to original (not favorite)
      expect(container.read(isFavoriteProvider('fail-1')), false);
    });

    test(
      'toggles without backend (demo/signed-out mode) skips API call',
      () async {
        final container = _createContainer(backend: null);
        addTearDown(container.dispose);

        final track = _fakeTrack(id: 'demo-1', isFavorite: false);
        final toggle = container.read(favoriteToggleProvider);
        await toggle(track);

        // Optimistic override applied
        expect(container.read(isFavoriteProvider('demo-1')), true);
      },
    );
  });
}
