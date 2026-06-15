import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aetherfin/core/network/connectivity_observer.dart';

void main() {
  group('ConnectivityObserver', () {
    late StreamController<List<ConnectivityResult>> controller;

    setUp(() {
      controller = StreamController<List<ConnectivityResult>>.broadcast();
    });

    tearDown(() {
      controller.close();
    });

    test('emits online on initial check when wifi is available', () async {
      final observer = ConnectivityObserver(
        checkConnectivity: () async => [ConnectivityResult.wifi],
        onConnectivityChanged: () => controller.stream,
      );

      await expectLater(observer.stream, emits(true));

      observer.dispose();
    });

    test('emits offline on initial check when none', () async {
      final observer = ConnectivityObserver(
        checkConnectivity: () async => [ConnectivityResult.none],
        onConnectivityChanged: () => controller.stream,
      );

      await expectLater(observer.stream, emits(false));

      observer.dispose();
    });

    test('emits false on connectivity lost', () async {
      final observer = ConnectivityObserver(
        checkConnectivity: () async => [ConnectivityResult.wifi],
        onConnectivityChanged: () => controller.stream,
      );

      // Wait for initial check
      await expectLater(observer.stream, emits(true));

      // Simulate going offline
      controller.add([ConnectivityResult.none]);

      await expectLater(observer.stream, emits(false));

      observer.dispose();
    });

    test('emits true on reconnection after offline', () async {
      final observer = ConnectivityObserver(
        checkConnectivity: () async => [ConnectivityResult.none],
        onConnectivityChanged: () => controller.stream,
      );

      // Wait for initial check
      await expectLater(observer.stream, emits(false));

      // Simulate coming back online
      controller.add([ConnectivityResult.wifi]);

      await expectLater(observer.stream, emits(true));

      observer.dispose();
    });

    test('does not emit duplicate consecutive values', () async {
      final values = <bool>[];
      final observer = ConnectivityObserver(
        checkConnectivity: () async => [ConnectivityResult.wifi],
        onConnectivityChanged: () => controller.stream,
      );

      observer.stream.listen(values.add);

      // Give time for initial check
      await Future.microtask(() {});

      // Same state should not emit again
      controller.add([ConnectivityResult.mobile]);

      await Future.microtask(() {});
      controller.add([ConnectivityResult.wifi]);

      await Future.microtask(() {});

      expect(values, [true]);
      // Note: initial online + same-state transitions = no duplicates

      observer.dispose();
    });

    test('isOnline getter returns current state', () async {
      final observer = ConnectivityObserver(
        checkConnectivity: () async => [ConnectivityResult.wifi],
        onConnectivityChanged: () => controller.stream,
      );

      // Wait for initial check
      await Future.microtask(() {});
      expect(observer.isOnline, isTrue);

      controller.add([ConnectivityResult.none]);
      await Future.microtask(() {});
      expect(observer.isOnline, isFalse);

      controller.add([ConnectivityResult.wifi]);
      await Future.microtask(() {});
      expect(observer.isOnline, isTrue);

      observer.dispose();
    });

    test('handles checkConnectivity error by assuming online', () async {
      final observer = ConnectivityObserver(
        checkConnectivity: () async => throw Exception('no platform'),
        onConnectivityChanged: () => controller.stream,
      );

      await expectLater(observer.stream, emits(true));

      observer.dispose();
    });

    test('dispose stops listening and closes stream', () async {
      final observer = ConnectivityObserver(
        checkConnectivity: () async => [ConnectivityResult.wifi],
        onConnectivityChanged: () => controller.stream,
      );

      await Future.microtask(() {});
      observer.dispose();

      // This should not cause errors
      controller.add([ConnectivityResult.none]);
      // No crash = success
    });
  });
}
