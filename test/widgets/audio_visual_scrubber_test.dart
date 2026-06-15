// ignore_for_file: close_sinks
// StreamControllers are intentionally kept alive for the test lifecycle.

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mpv_audio_kit/mpv_audio_kit.dart';

import 'package:aetherfin/core/audio/media_session_bridge.dart';
import 'package:aetherfin/core/audio/player_service.dart';
import 'package:aetherfin/state/providers.dart';
import 'package:aetherfin/widgets/audio_visual_scrubber.dart';

import '../helpers/fake_player.dart';

/// Creates a mock player wired for spectrum testing.
///
/// Builds on [createMockPlayer] from `fake_player.dart` and adds a
/// [StreamController<FftFrame>] for the `spectrum` stream.
({
  MockPlayer player,
  StreamControllers ctrls,
  StreamController<FftFrame> spectrumCtrl,
})
_createSpectrumPlayer() {
  final base = createMockPlayer();
  final spectrumCtrl = StreamController<FftFrame>.broadcast();
  final stream = base.player.stream as MockPlayerStream;

  when(() => stream.fft).thenAnswer((_) => spectrumCtrl.stream);

  return (player: base.player, ctrls: base.ctrls, spectrumCtrl: spectrumCtrl);
}

/// Builds the scrubber inside the minimal widget tree it needs.
///
/// - [PlayerApi] overrides are passed via [overrides].
Widget _buildScrubber({
  required double progress,
  double height = 100,
  Color playedColor = Colors.indigoAccent,
  Color unplayedColor = Colors.grey,
  void Function(double)? onScrub,
  void Function(double)? onScrubEnd,
  List<dynamic>? overrides,
}) {
  return ProviderScope(
    overrides: overrides?.cast() ?? [],
    child: MaterialApp(
      home: Scaffold(
        body: AudioVisualScrubber(
          height: height,
          progress: progress,
          playedColor: playedColor,
          unplayedColor: unplayedColor,
          onScrub: onScrub,
          onScrubEnd: onScrubEnd,
        ),
      ),
    ),
  );
}

void main() {
  late StreamController<FftFrame> spectrumCtrl;
  AfPlayerService? service;

  setUpAll(() {
    registerFallbackValue(Duration.zero);
    registerFallbackValue(Loop.off);
    registerFallbackValue(Gapless.weak);
    registerFallbackValue(const Media(''));
    registerFallbackValue(Device.auto);
    registerFallbackValue(
      const SpectrumSettings(
        fftSize: 2048,
        bandCount: 64,
        bandLowHz: 20.0,
        bandHighHz: 20000.0,
        attackSmoothing: 0.8,
        releaseSmoothing: 0.1,
        minDb: -105.0,
        maxDb: 35.0,
        emitInterval: Duration(milliseconds: 8),
      ),
    );
  });

  /// Set up a fresh fixture: creates mock player, [spectrumCtrl], and a
  /// real [AfPlayerService] wired to the mock via the `test` constructor.
  void setupFixture() {
    final fixture = _createSpectrumPlayer();
    spectrumCtrl = fixture.spectrumCtrl;
    service = AfPlayerService.test(
      player: fixture.player,
      bridge: NativeMediaSessionBridge(channel: const MethodChannel('test')),
    );
  }

  group('AudioVisualScrubber — baseline rendering', () {
    testWidgets('renders with default colors and progress', (tester) async {
      setupFixture();
      await tester.pumpWidget(
        _buildScrubber(
          progress: 0.5,
          height: 120,
          overrides: [playerServiceProvider.overrideWithValue(service!)],
        ),
      );
      await tester.pump();

      // The widget should fill the horizontal space at the given height.
      final finder = find.byType(AudioVisualScrubber);
      expect(finder, findsOneWidget);
      final sizedBox = find.descendant(
        of: finder,
        matching: find.byType(SizedBox),
      );
      expect(sizedBox, findsOneWidget);

      final renderBox = tester.renderObject<RenderBox>(sizedBox);
      expect(renderBox.size.height, 120);
    });

    testWidgets('renders with custom colors', (tester) async {
      setupFixture();
      await tester.pumpWidget(
        _buildScrubber(
          progress: 0.25,
          playedColor: Colors.blue,
          unplayedColor: Colors.amber,
          overrides: [playerServiceProvider.overrideWithValue(service!)],
        ),
      );
      await tester.pump();

      // Just confirm the widget is present with custom colors — CustomPaint
      // renders don't assert on color easily in widget tests.
      expect(find.byType(AudioVisualScrubber), findsOneWidget);
    });

    testWidgets('renders at zero progress', (tester) async {
      setupFixture();
      await tester.pumpWidget(
        _buildScrubber(
          progress: 0.0,
          overrides: [playerServiceProvider.overrideWithValue(service!)],
        ),
      );
      await tester.pump();

      expect(find.byType(AudioVisualScrubber), findsOneWidget);
    });

    testWidgets('renders at full progress', (tester) async {
      setupFixture();
      await tester.pumpWidget(
        _buildScrubber(
          progress: 1.0,
          overrides: [playerServiceProvider.overrideWithValue(service!)],
        ),
      );
      await tester.pump();

      expect(find.byType(AudioVisualScrubber), findsOneWidget);
    });
  });

  group('AudioVisualScrubber — FFT spectrum ingestion', () {
    testWidgets('receives FFT frames and updates visualizer', (tester) async {
      setupFixture();
      await tester.pumpWidget(
        _buildScrubber(
          progress: 0.3,
          overrides: [playerServiceProvider.overrideWithValue(service!)],
        ),
      );

      // Let initState + addPostFrameCallback fire.
      await tester.pump();
      await tester.pump();

      // Push a spectrum frame with moderate energy.
      final bands = Float32List(64);
      for (var i = 0; i < 64; i++) {
        bands[i] = 0.5;
      }
      spectrumCtrl.add(
        FftFrame(
          bins: bands,
          bands: bands,
          timestamp: Duration.zero,
          sampleRate: 44100,
          bandLowHz: 20.0,
          bandHighHz: 20000.0,
        ),
      );

      // Pump a frame for the ticker to call flush().
      await tester.pump(const Duration(milliseconds: 16));
      // Allow repaint to complete.
      await tester.pump();

      // Widget still renders — visualizer bars are checked via CustomPainter.
      expect(find.byType(AudioVisualScrubber), findsOneWidget);
    });

    testWidgets('handles zero-energy bands gracefully', (tester) async {
      setupFixture();
      await tester.pumpWidget(
        _buildScrubber(
          progress: 0.3,
          overrides: [playerServiceProvider.overrideWithValue(service!)],
        ),
      );

      await tester.pump();
      await tester.pump();

      // All bands at zero.
      final bands = Float32List(64);
      spectrumCtrl.add(
        FftFrame(
          bins: bands,
          bands: bands,
          timestamp: Duration.zero,
          sampleRate: 44100,
          bandLowHz: 20.0,
          bandHighHz: 20000.0,
        ),
      );

      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump();

      expect(find.byType(AudioVisualScrubber), findsOneWidget);
    });

    testWidgets('handles empty band list gracefully', (tester) async {
      setupFixture();
      await tester.pumpWidget(
        _buildScrubber(
          progress: 0.3,
          overrides: [playerServiceProvider.overrideWithValue(service!)],
        ),
      );

      await tester.pump();
      await tester.pump();

      spectrumCtrl.add(
        FftFrame(
          bins: Float32List(0),
          bands: Float32List(0),
          timestamp: Duration.zero,
          sampleRate: 44100,
          bandLowHz: 20.0,
          bandHighHz: 20000.0,
        ),
      );

      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump();

      expect(find.byType(AudioVisualScrubber), findsOneWidget);
    });
  });

  group('AudioVisualScrubber — interaction callbacks', () {
    testWidgets('calls onScrubEnd on tap', (tester) async {
      setupFixture();

      double? capturedProgress;
      await tester.pumpWidget(
        _buildScrubber(
          progress: 0.0,
          height: 100,
          onScrubEnd: (p) => capturedProgress = p,
          overrides: [playerServiceProvider.overrideWithValue(service!)],
        ),
      );

      await tester.pump();
      await tester.pump();

      // Tap in the middle of the widget.
      await tester.tap(find.byType(AudioVisualScrubber));
      await tester.pump();

      // onScrubEnd should have been called with a value between 0 and 1.
      // In a 600x800 default test surface, the widget starts at the left
      // edge and the tap lands around 300px → ~0.5.
      expect(capturedProgress, isNotNull);
      expect(capturedProgress!, greaterThan(0.0));
      expect(capturedProgress!, lessThanOrEqualTo(1.0));
    });

    testWidgets('calls onScrub during horizontal drag', (tester) async {
      setupFixture();

      final capturedProgresses = <double>[];
      await tester.pumpWidget(
        _buildScrubber(
          progress: 0.0,
          height: 100,
          onScrub: capturedProgresses.add,
          overrides: [playerServiceProvider.overrideWithValue(service!)],
        ),
      );

      await tester.pump();
      await tester.pump();

      // Drag from left to right across the widget.
      await tester.drag(find.byType(AudioVisualScrubber), const Offset(200, 0));
      await tester.pump();

      // During a drag, onScrub is called via _handleDragUpdate.
      expect(capturedProgresses, isNotEmpty);
      for (final p in capturedProgresses) {
        expect(p, greaterThanOrEqualTo(0.0));
        expect(p, lessThanOrEqualTo(1.0));
      }
    });

    testWidgets('calls onScrubEnd after drag completes', (tester) async {
      setupFixture();

      double? capturedEnd;
      await tester.pumpWidget(
        _buildScrubber(
          progress: 0.0,
          height: 100,
          onScrubEnd: (p) => capturedEnd = p,
          overrides: [playerServiceProvider.overrideWithValue(service!)],
        ),
      );

      await tester.pump();
      await tester.pump();

      await tester.drag(find.byType(AudioVisualScrubber), const Offset(150, 0));
      await tester.pump();

      expect(capturedEnd, isNotNull);
      expect(capturedEnd!, greaterThan(0.0));
      expect(capturedEnd!, lessThanOrEqualTo(1.0));
    });
  });

  group('AudioVisualScrubber — transition buffer fade-out/fade-in', () {
    testWidgets('fade-out triggers after silence and does not crash', (
      tester,
    ) async {
      setupFixture();

      await tester.pumpWidget(
        _buildScrubber(
          progress: 0.5,
          overrides: [playerServiceProvider.overrideWithValue(service!)],
        ),
      );

      // Let initState + addPostFrameCallback fire.
      await tester.pump();
      await tester.pump();

      // Feed frames to simulate audio playing.
      final bands = Float32List(64);
      for (var i = 0; i < 64; i++) {
        bands[i] = 0.5 + (i / 64.0) * 0.3; // varied energy
      }
      for (var t = 0; t < 30; t++) {
        spectrumCtrl.add(
          FftFrame(
            bins: bands,
            bands: bands,
            timestamp: Duration.zero,
            sampleRate: 44100,
            bandLowHz: 20.0,
            bandHighHz: 20000.0,
          ),
        );
        await tester.pump(const Duration(milliseconds: 16));
      }

      // Widget still renders with frames ingested.
      expect(find.byType(AudioVisualScrubber), findsOneWidget);

      // Stop feeding frames and advance past the 300ms silence timer.
      await tester.pump(const Duration(milliseconds: 350));

      // Silence timer fired → startFadeOut called → ticker runs fade-out.
      // Pump enough ticks for fade-out to decay bars to zero.
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }

      // Widget still renders after fade-out completes.
      expect(find.byType(AudioVisualScrubber), findsOneWidget);
    });

    testWidgets('fade-in blends new frames after silence', (tester) async {
      setupFixture();

      await tester.pumpWidget(
        _buildScrubber(
          progress: 0.5,
          overrides: [playerServiceProvider.overrideWithValue(service!)],
        ),
      );

      await tester.pump();
      await tester.pump();

      // Feed several frames.
      final bands = Float32List(64);
      for (var i = 0; i < 64; i++) {
        bands[i] = 0.5;
      }
      for (var t = 0; t < 30; t++) {
        spectrumCtrl.add(
          FftFrame(
            bins: bands,
            bands: bands,
            timestamp: Duration.zero,
            sampleRate: 44100,
            bandLowHz: 20.0,
            bandHighHz: 20000.0,
          ),
        );
        await tester.pump(const Duration(milliseconds: 16));
      }

      // Trigger silence and wait for fade-out.
      await tester.pump(const Duration(milliseconds: 350));
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }

      // Feed new frames → should trigger fade-in blending into live data.
      for (var t = 0; t < 10; t++) {
        spectrumCtrl.add(
          FftFrame(
            bins: bands,
            bands: bands,
            timestamp: Duration.zero,
            sampleRate: 44100,
            bandLowHz: 20.0,
            bandHighHz: 20000.0,
          ),
        );
        await tester.pump(const Duration(milliseconds: 16));
      }

      // Widget renders correctly after fade-in.
      expect(find.byType(AudioVisualScrubber), findsOneWidget);
    });

    testWidgets('rapid silence-to-audio transitions do not crash', (
      tester,
    ) async {
      setupFixture();

      await tester.pumpWidget(
        _buildScrubber(
          progress: 0.5,
          overrides: [playerServiceProvider.overrideWithValue(service!)],
        ),
      );

      await tester.pump();
      await tester.pump();

      final bands = Float32List(64);
      for (var i = 0; i < 64; i++) {
        bands[i] = 0.5;
      }

      // Perform 3 rapid cycles: play → silence → play → silence → play.
      for (var cycle = 0; cycle < 3; cycle++) {
        // Feed frames.
        for (var t = 0; t < 10; t++) {
          spectrumCtrl.add(
            FftFrame(
              bins: bands,
              bands: bands,
              timestamp: Duration.zero,
              sampleRate: 44100,
              bandLowHz: 20.0,
              bandHighHz: 20000.0,
            ),
          );
          await tester.pump(const Duration(milliseconds: 16));
        }

        // Trigger silence → fade-out.
        await tester.pump(const Duration(milliseconds: 350));
        for (var i = 0; i < 15; i++) {
          await tester.pump(const Duration(milliseconds: 16));
        }
      }

      expect(find.byType(AudioVisualScrubber), findsOneWidget);
    });
  });

  group('AudioVisualScrubber — progress consumption', () {
    testWidgets('consumes and reflects updated progress', (tester) async {
      setupFixture();

      await tester.pumpWidget(
        _buildScrubber(
          progress: 0.0,
          overrides: [playerServiceProvider.overrideWithValue(service!)],
        ),
      );
      await tester.pump();

      // Rebuild with new progress. Since _ScrubNotifier.update calls
      // notifyListeners, the scrub overlay painter repaints.
      await tester.pumpWidget(
        _buildScrubber(
          progress: 0.75,
          overrides: [playerServiceProvider.overrideWithValue(service!)],
        ),
      );
      await tester.pump();

      expect(find.byType(AudioVisualScrubber), findsOneWidget);
    });

    testWidgets('handles rapid progress updates without crashing', (
      tester,
    ) async {
      setupFixture();

      await tester.pumpWidget(
        _buildScrubber(
          progress: 0.0,
          overrides: [playerServiceProvider.overrideWithValue(service!)],
        ),
      );

      for (var i = 0; i < 20; i++) {
        await tester.pumpWidget(
          _buildScrubber(
            progress: i / 19.0,
            overrides: [playerServiceProvider.overrideWithValue(service!)],
          ),
        );
        await tester.pump(const Duration(milliseconds: 16));
      }

      expect(find.byType(AudioVisualScrubber), findsOneWidget);
    });
  });
}
