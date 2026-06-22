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
    _chain = _chain.then((_) async {
      try {
        completer.complete(await action());
      } on Object catch (e, st) {
        afLog('error', 'AfAsyncLock action failed', error: e, stackTrace: st);
        completer.completeError(e, st);
      }
    });
    return completer.future;
  }
}
