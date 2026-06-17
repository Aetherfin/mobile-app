import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mpv_audio_kit/mpv_audio_kit.dart';

import 'package:aetherfin/core/audio/media_session_bridge.dart';
import 'package:aetherfin/core/audio/player_service.dart';
import 'package:aetherfin/design_tokens/colors.dart';
import 'package:aetherfin/features/cast_picker/cast_picker_screen.dart';
import 'package:aetherfin/state/providers.dart';

import '../../helpers/fake_player.dart';
import '../../helpers/mock_method_channel.dart';

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

  ({AfPlayerService service, StreamControllers ctrls}) createCastFixture({
    List<Device> devices = const [],
    Device? activeDevice,
  }) {
    final result = createMockPlayer();
    final player = result.player;
    final ctrls = result.ctrls;

    when(() => player.state).thenReturn(
      PlayerState(
        audioDevices: devices,
        audioDevice: activeDevice ?? Device.auto,
      ),
    );

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
    when(
      () => channel.invokeMethod(any(), any()),
    ).thenAnswer((_) async => null);

    final bridge = NativeMediaSessionBridge(channel: channel);
    final service = AfPlayerService.test(player: player, bridge: bridge);

    return (service: service, ctrls: ctrls);
  }

  group('CastPickerScreen', () {
    testWidgets('renders without crashing', (tester) async {
      final fixture = createCastFixture();
      addTearDown(fixture.ctrls.dispose);

      final container = ProviderContainer(
        overrides: [
          playerServiceProvider.overrideWithValue(fixture.service),
          currentSpectralProvider.overrideWithValue(Spectral.fallback),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: CastPickerScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(CastPickerScreen), findsOneWidget);
    });

    testWidgets('displays "Output" title', (tester) async {
      final fixture = createCastFixture();
      addTearDown(fixture.ctrls.dispose);

      final container = ProviderContainer(
        overrides: [
          playerServiceProvider.overrideWithValue(fixture.service),
          currentSpectralProvider.overrideWithValue(Spectral.fallback),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: CastPickerScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Output'), findsOneWidget);
    });

    testWidgets('shows empty state when no devices', (tester) async {
      final fixture = createCastFixture(devices: const []);
      addTearDown(fixture.ctrls.dispose);

      final container = ProviderContainer(
        overrides: [
          playerServiceProvider.overrideWithValue(fixture.service),
          currentSpectralProvider.overrideWithValue(Spectral.fallback),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: CastPickerScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('No audio devices found.\nStart playback first.'),
        findsOneWidget,
      );
    });

    testWidgets('lists devices with names', (tester) async {
      const device1 = Device(
        name: 'bt-headphones',
        description: 'Sony WH-1000XM5',
      );
      const device2 = Device(name: 'speaker', description: 'JBL Charge 5');
      final fixture = createCastFixture(devices: [device1, device2]);
      addTearDown(fixture.ctrls.dispose);

      final container = ProviderContainer(
        overrides: [
          playerServiceProvider.overrideWithValue(fixture.service),
          currentSpectralProvider.overrideWithValue(Spectral.fallback),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: CastPickerScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Sony WH-1000XM5'), findsOneWidget);
      expect(find.text('JBL Charge 5'), findsOneWidget);
    });

    testWidgets('active device shows checkmark', (tester) async {
      const activeDevice = Device(name: 'speaker', description: 'JBL');
      const otherDevice = Device(name: 'phone', description: 'Built-in');
      final fixture = createCastFixture(
        devices: [activeDevice, otherDevice],
        activeDevice: activeDevice,
      );
      addTearDown(fixture.ctrls.dispose);

      final container = ProviderContainer(
        overrides: [
          playerServiceProvider.overrideWithValue(fixture.service),
          currentSpectralProvider.overrideWithValue(Spectral.fallback),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: CastPickerScreen()),
        ),
      );
      await tester.pumpAndSettle();

      // Only one checkmark icon for the active device
      expect(find.byIcon(LucideIcons.check), findsOneWidget);
    });
  });
}
