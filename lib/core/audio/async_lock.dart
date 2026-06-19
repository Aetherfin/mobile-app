import 'dart:async';

import '../../utils/log.dart';

/// A simple async mutual-exclusion lock.
///
/// Queues asynchronous actions so they execute one at a time.
/// Used to serialize queue mutations that must not interleave
/// (e.g., openAll, skip, completed handler).
class AfAsyncLock {
  Future<void> _chain = Future<void>.value();

  Future<T> run<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    _chain = _chain
        .then((_) async {
          try {
            final result = await action();
            completer.complete(result);
          } on Object catch (e, st) {
            completer.completeError(e, st);
          }
        })
        .catchError((Object error, StackTrace stack) {
          afLog(
            'error',
            'AfAsyncLock chain error',
            error: error,
            stackTrace: stack,
          );
          if (!completer.isCompleted) {
            completer.completeError(error, stack);
          }
          Error.throwWithStackTrace(error, stack);
        });
    return completer.future;
  }
}
