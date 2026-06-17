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

      await expectLater(observer.stream, emits(true));

      controller.add([ConnectivityResult.none]);

      await expectLater(observer.stream, emits(false));

      observer.dispose();
    });

    test('emits true on reconnection after offline', () async {
      final observer = ConnectivityObserver(
        checkConnectivity: () async => [ConnectivityResult.none],
        onConnectivityChanged: () => controller.stream,
      );

      await expectLater(observer.stream, emits(false));

      controller.add([ConnectivityResult.wifi]);

      await expectLater(observer.stream, emits(true));

      observer.dispose();
    });
  });
}
