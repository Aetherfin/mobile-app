/// Structured logging helpers built on `dart:developer.log`.
///
/// The codebase historically used bare `print('aetherfin:<category> ...')`
/// calls so any developer could grep `logcat` for a specific subsystem. That
/// works but requires `// ignore: avoid_print` on every site, and release
/// builds emit the same chatty output that debug builds do.
///
/// `dart:developer.log` is the recommended replacement:
///   * It's filterable by `name:` in Flutter DevTools and `adb logcat`.
///   * It accepts `error` and `stackTrace` parameters so exception traces are
///     attached to a single event rather than printed across multiple lines.
///   * It's compiled out by the Dart VM in profile/release builds the same
///     way `print` is (i.e. you still see it on a debug device), so the
///     trace-on-a-real-device debugging workflow is preserved.
///
/// Migration rule: every prior `print('aetherfin:<category> <msg>')` becomes
/// `afLog('<category>', '<msg>')`. Error sites that previously printed both
/// the exception and the stack as two lines should pass them in once:
/// `afLog('error', 'foo failed', error: e, stackTrace: stack)`.
library;

import 'dart:async' show unawaited;
import 'dart:developer' as developer;

/// Emit a structured log line tagged `aetherfin:<category>`. The `category`
/// argument matches the categories documented in CLAUDE.md §7
/// (`boot`, `http`, `audio`, `data`, `live_update`, `error`, …).
void afLog(
  String category,
  String message, {
  Object? error,
  StackTrace? stackTrace,
}) {
  developer.log(
    message,
    name: 'aetherfin:$category',
    error: error,
    stackTrace: stackTrace,
  );
}

/// Fire-and-forget wrapper that catches and logs errors.
/// Use instead of `unawaited()` for async operations where errors
/// should be logged but not propagated.
void safeFireAndForget(Future<void> Function() operation, {String? label}) {
  unawaited(
    (() async {
      try {
        await operation();
      } catch (e, stack) {
        afLog(
          'error',
          label ?? 'Fire-and-forget failed',
          error: e,
          stackTrace: stack,
        );
      }
    })(),
  );
}

/// Log a data-provenance event tagged `aetherfin:data`.
///
/// Usage:
/// ```dart
/// logData('allAlbums', source: 'live', extra: 'count=${res.length}');
/// ```
/// Produces: `aetherfin:data allAlbums source=live count=42`
void logData(String feature, {required String source, String? extra}) {
  final detail = extra == null || extra.isEmpty ? '' : ' $extra';
  afLog('data', '$feature source=$source$detail');
}
