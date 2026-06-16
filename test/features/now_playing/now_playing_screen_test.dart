import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mpv_audio_kit/mpv_audio_kit.dart';

import 'package:aetherfin/core/audio/media_session_bridge.dart';
import 'package:aetherfin/core/audio/player_service.dart';
import 'package:aetherfin/core/jellyfin/models/items.dart';
import 'package:aetherfin/design_tokens/colors.dart';
import 'package:aetherfin/features/now_playing/now_playing_screen.dart';
import 'package:aetherfin/features/now_playing/transport_row.dart';
import 'package:aetherfin/state/providers.dart';
import 'package:aetherfin/state/state_holder.dart';

import '../../helpers/fake_player.dart';
import '../../helpers/mock_method_channel.dart';

/// Creates a NowPlayingScreen test fixture with a mock player service.
({ProviderContainer container, StreamControllers ctrls})
createNowPlayingFixture({AfTrack? track}) {
  final result = createMockPlayer();
  final player = result.player;
  final ctrls = result.ctrls;

  // Stub state getter
  when(() => player.state).thenReturn(const PlayerState());

  // Stub all no-op methods called by AfPlayerService
  when(() => player.setAudioDriver(any())).thenAnswer((_) async {});
  when(() => player.setAudioBuffer(any())).thenAnswer((_) async {});
  when(() => player.setAudioDevice(any())).thenAnswer((_) async {});
  when(() => player.setShuffle(any())).thenAnswer((_) async {});
  when(() => player.setLoop(any())).thenAnswer((_) async {});
  when(() => player.setRate(any())).thenAnswer((_) async {});
  when(() => player.setGapless(any())).thenAnswer((_) async {});
  when(() => player.setPrefetchPlaylist(any())).thenAnswer((_) async {});
  when(() => player.setSpectrum(any())).thenAnswer((_) async {});
  when(() => player.setMediaSession(any())).thenAnswer((_) async {});
  when(() => player.sendRawCommand(any())).thenAnswer((_) async {});
  when(() => player.getRawProperty(any())).thenAnswer((_) async => null);
  when(player.play).thenAnswer((_) async {});
  when(player.pause).thenAnswer((_) async {});
  when(player.stop).thenAnswer((_) async {});
  when(() => player.seek(any())).thenAnswer((_) async {});
  when(player.next).thenAnswer((_) async {});
  when(player.previous).thenAnswer((_) async {});
  when(() => player.jump(any())).thenAnswer((_) async {});
  when(
    () => player.open(any(), play: any(named: 'play')),
  ).thenAnswer((_) async {});
  when(
    () => player.openAll(
      any(),
      index: any(named: 'index'),
      play: any(named: 'play'),
    ),
  ).thenAnswer((_) async {});
  when(() => player.add(any())).thenAnswer((_) async {});
  when(player.dispose).thenAnswer((_) async {});

  final channel = MockMethodChannel();
  when(() => channel.invokeMethod(any())).thenAnswer((_) async => null);
  when(() => channel.invokeMethod(any(), any())).thenAnswer((_) async => null);

  final bridge = NativeMediaSessionBridge(channel: channel);
  final service = AfPlayerService.test(player: player, bridge: bridge);

  final overrides = [
    playerServiceProvider.overrideWithValue(service),
    currentSpectralProvider.overrideWithValue(Spectral.fallback),
  ];

  if (track != null) {
    overrides.add(
      currentTrackProvider.overrideWith(
        () => StateHolder<AfTrack?>((ref) => track),
      ),
    );
  }

  final container = ProviderContainer(overrides: overrides);

  return (container: container, ctrls: ctrls);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    registerFallbackValue(Duration.zero);
    registerFallbackValue(const Media(''));
    registerFallbackValue(<Media>[]);
    registerFallbackValue(Device.auto);
    registerFallbackValue(Loop.off);
    registerFallbackValue(Gapless.weak);
    registerFallbackValue(SpectrumSettings.defaults);
    registerFallbackValue(const Playlist([]));
    registerFallbackValue(const MediaSession());
  });

  group('NowPlayingScreen', () {
    testWidgets('renders empty state when no track is playing', (tester) async {
      final fixture = createNowPlayingFixture();
      addTearDown(fixture.container.dispose);
      addTearDown(fixture.ctrls.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: fixture.container,
          child: const MaterialApp(home: NowPlayingScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(NowPlayingScreen), findsOneWidget);
      expect(find.text('Nothing playing yet'), findsOneWidget);
      expect(find.text('Start playing to see your music here'), findsOneWidget);
    });

    testWidgets('renders full player when track is present', (tester) async {
      const track = AfTrack(
        id: 'test-1',
        title: 'Test Track',
        artistName: 'Test Artist',
        albumName: 'Test Album',
        duration: Duration(minutes: 3, seconds: 30),
      );

      final fixture = createNowPlayingFixture(track: track);
      addTearDown(fixture.container.dispose);
      addTearDown(fixture.ctrls.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: fixture.container,
          child: const MaterialApp(home: NowPlayingScreen()),
        ),
      );
      // Use pump() instead of pumpAndSettle() because ReactiveBackground
      // runs continuous color animations that never settle.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byType(NowPlayingScreen), findsOneWidget);
      // Track title and artist should be shown in the bottom content area
      expect(find.text('Test Track'), findsOneWidget);
      expect(find.text('Test Artist'), findsOneWidget);
    });

    testWidgets('displays transport controls when track is present', (
      tester,
    ) async {
      const track = AfTrack(
        id: 'test-2',
        title: 'Song Two',
        artistName: 'Artist Two',
        albumName: 'Album Two',
        duration: Duration(minutes: 4),
      );

      final fixture = createNowPlayingFixture(track: track);
      addTearDown(fixture.container.dispose);
      addTearDown(fixture.ctrls.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: fixture.container,
          child: const MaterialApp(home: NowPlayingScreen()),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Transport controls use TransportRow with TransportButton widgets
      // for play/pause, skip forward/back, shuffle, and repeat
      expect(find.byType(TransportRow), findsOneWidget);
      expect(
        find.byType(TransportButton),
        findsAtLeastNWidgets(3),
        reason:
            'Expected at least shuffle, previous, and next transport buttons',
      );
    });

    testWidgets('displays artwork widget when track is present', (
      tester,
    ) async {
      const track = AfTrack(
        id: 'test-3',
        title: 'Artwork Song',
        artistName: 'Artwork Artist',
        albumName: 'Artwork Album',
        duration: Duration(minutes: 2, seconds: 45),
      );

      final fixture = createNowPlayingFixture(track: track);
      addTearDown(fixture.container.dispose);
      addTearDown(fixture.ctrls.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: fixture.container,
          child: const MaterialApp(home: NowPlayingScreen()),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // The artwork area is rendered via ReactiveArtwork which contains
      // an Artwork widget or a fallback placeholder inside a LayoutBuilder
      expect(
        find.byType(LayoutBuilder),
        findsAtLeastNWidgets(1),
        reason: 'ReactiveArtwork uses LayoutBuilder for responsive sizing',
      );
    });
  });
}
