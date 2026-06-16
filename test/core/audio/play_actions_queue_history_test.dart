import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/native.dart';
import 'package:aetherfin/core/audio/play_actions.dart';
import 'package:aetherfin/core/audio/player_service.dart';
import 'package:aetherfin/core/local/app_database.dart';
import 'package:aetherfin/core/local/queue_history_repository.dart';
import 'package:aetherfin/state/providers.dart';
import 'package:aetherfin/state/state_holder.dart';
import 'package:aetherfin/core/jellyfin/models/items.dart';

class MockPlayerService extends Mock implements AfPlayerService {}

void main() {
  setUpAll(() {
    registerFallbackValue(
      const AfTrack(id: '', title: '', artistName: '', albumName: ''),
    );
  });

  group('PlayActions Queue History Save', () {
    test('playQueue saves to history repository', () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      final repo = QueueHistoryRepository(db);
      final mockSvc = MockPlayerService();

      when(() => mockSvc.isShuffleEnabled).thenReturn(false);
      when(
        () => mockSvc.playQueue(
          any(),
          startIndex: any(named: 'startIndex'),
          resolveStreamUrl: any(named: 'resolveStreamUrl'),
          streamHeaders: any(named: 'streamHeaders'),
        ),
      ).thenAnswer((_) async {});

      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          queueHistoryRepositoryProvider.overrideWithValue(repo),
          playerServiceProvider.overrideWithValue(mockSvc),
          appModeProvider.overrideWith(
            () => StateHolder<AppMode?>((ref) => AppMode.local),
          ),
          initialAuthProvider.overrideWithValue(null),
        ],
      );
      addTearDown(() {
        container.dispose();
        db.close();
      });

      final actions = container.read(playActionsProvider);

      const tracks = [
        AfTrack(
          id: 'track-1',
          title: 'Track 1',
          artistName: 'Artist 1',
          albumName: 'Album 1',
          duration: Duration(seconds: 120),
        ),
      ];

      await actions.playQueue(tracks);

      final recent = await repo.loadRecent(limit: 10);
      expect(recent.length, equals(1));
      expect(recent[0].trackIds, equals(['track-1']));
      expect(recent[0].sourceLabel, equals('Album: Album 1'));
    });
  });
}
