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

      unawaited(expectLater(toggle(track), throwsA(isA<Exception>())));

      await Future<void>.delayed(Duration.zero);
      expect(container.read(trackFavoriteOverrideProvider('fail-1')), false);
      expect(container.read(isFavoriteProvider('fail-1')), false);
    });

    test('toggles without backend (demo mode) skips API call', () async {
      final container = _createContainer(backend: null);
      addTearDown(container.dispose);

      final track = _fakeTrack(id: 'demo-1', isFavorite: false);
      final toggle = container.read(favoriteToggleProvider);
      await toggle(track);

      expect(container.read(isFavoriteProvider('demo-1')), true);
    });
  });
}
