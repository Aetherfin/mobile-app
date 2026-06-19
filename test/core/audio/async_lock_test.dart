import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:aetherfin/core/audio/async_lock.dart';

void main() {
  group('AfAsyncLock', () {
    late AfAsyncLock lock;

    setUp(() {
      lock = AfAsyncLock();
    });

    test('serializes concurrent operations', () async {
      final order = <int>[];
      final completer1 = Completer<void>();
      final completer2 = Completer<void>();

      final f1 = lock.run(() async {
        order.add(1);
        await completer1.future;
        order.add(2);
      });

      final f2 = lock.run(() async {
        order.add(3);
        await completer2.future;
        order.add(4);
      });

      completer1.complete();
      await Future<void>.delayed(Duration.zero);
      completer2.complete();
      await Future.wait([f1, f2]);

      expect(order, [1, 2, 3, 4]);
    });

    test('propagates exceptions from action', () async {
      expect(
        lock.run(() async {
          throw Exception('test error');
        }),
        throwsException,
      );
    });

    test('chain continues after error', () async {
      // First operation fails
      final f1 = lock.run<void>(() async {
        throw Exception('first error');
      });
      await f1.catchError((Object error, StackTrace stack) {});

      // Second operation should still run
      final result = await lock.run(() async {
        return 42;
      });
      expect(result, 42);
    });

    test('returns correct value', () async {
      final result = await lock.run(() async {
        return 'hello';
      });
      expect(result, 'hello');
    });

    test('handles Error types (not just Exception)', () async {
      expect(
        lock.run(() async {
          throw StateError('state error');
        }),
        throwsStateError,
      );
    });

    test('multiple sequential runs execute in order', () async {
      final order = <int>[];

      await lock.run(() async {
        order.add(1);
      });
      await lock.run(() async {
        order.add(2);
      });
      await lock.run(() async {
        order.add(3);
      });

      expect(order, [1, 2, 3]);
    });

    test('does not block unrelated code', () async {
      final order = <int>[];

      // Start a slow operation
      final f1 = lock.run(() async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        order.add(1);
      });

      // Unrelated code should not be blocked
      order.add(0);

      await f1;
      expect(order, [0, 1]);
    });
  });
}
