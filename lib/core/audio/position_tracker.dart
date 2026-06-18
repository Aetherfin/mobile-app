import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:mpv_audio_kit/mpv_audio_kit.dart' show PlayerApi;

import '../../design_tokens/tokens.dart';
import '../../utils/log.dart';

/// Matches a numeric seconds value with optional sign, decimal portion,
/// and optional unit suffix (s, sec, seconds, ms, milliseconds).
///
/// Valid: "5", "5.0", "5.0s", "5.00 ms", "-1.5", "3,14" (EU locale).
final _secondsRegex = RegExp(
  r'^\s*([+-]?\d+(?:[.,]\d+)?)\s*(?:s(?:ec(?:onds?)?)?|ms|milliseconds)?\s*$',
  caseSensitive: false,
);

/// Stores a snapshot of playback position for elapsed-time extrapolation.
/// Used when mpv's observe_property/getRawPropertyNode for time-pos stalls.
class _PositionAnchor {
  Duration lastKnownPos = Duration.zero;
  DateTime lastUpdateTime = clock.now();
}

/// Manages position polling, extrapolation, and stale detection.
///
/// Polls mpv at 200ms intervals. Falls back to Dart-side elapsed-time
/// extrapolation when mpv returns 0 or when the same non-zero position
/// repeats across several ticks (Samsung One UI freeze workaround).
class AfPositionTracker {
  AfPositionTracker({
    required PlayerApi player,
    required bool Function() shouldAdvancePosition,
  }) : _player = player,
       _shouldAdvancePosition = shouldAdvancePosition;
  final PlayerApi _player;
  final bool Function() _shouldAdvancePosition;

  final StreamController<Duration> _positionController =
      StreamController<Duration>.broadcast();
  Stream<Duration> get positionStream => _positionController.stream;

  final _positionAnchor = _PositionAnchor();
  Timer? _positionPollTimer;
  bool _isSeeking = false;
  Timer? _seekResetTimer;
  Future<void>? _pollChain;

  Duration? _lastRawPolledPos;
  int _staleRawPollTicks = 0;
  static const _rawStaleTolerance = Duration(milliseconds: 50);
  static const _rawStaleAfterTicks = 4;

  bool _disposed = false;

  void start() {
    if (_disposed) return;
    _positionPollTimer?.cancel();
    _positionPollTimer = Timer.periodic(AfDurations.expressive, (_) {
      if (_disposed) return;
      _pollAndEmitPosition();
    });
  }

  void stop() {
    _positionPollTimer?.cancel();
    _positionPollTimer = null;
  }

  bool get isSeeking => _isSeeking;
  Duration get lastKnownPosition => _positionAnchor.lastKnownPos;

  void _emitPosition(Duration pos) {
    _positionController.add(pos);
  }

  void _forceEmit(Duration pos) {
    _positionController.add(pos);
  }

  @visibleForTesting
  void emitPositionForTesting(Duration pos) {
    _positionController.add(pos);
  }

  void onSeek(Duration position) {
    _isSeeking = true;
    final now = clock.now();
    _positionAnchor.lastKnownPos = position;
    _positionAnchor.lastUpdateTime = now;
    _resetRawPositionStaleDetector(position);
    _forceEmit(position);

    _seekResetTimer?.cancel();
    _seekResetTimer = Timer(AfDurations.standard, () {
      if (!_disposed) _isSeeking = false;
    });
  }

  void onTrackChanged() {
    _positionAnchor.lastKnownPos = Duration.zero;
    _positionAnchor.lastUpdateTime = clock.now();
    _onZeroEmit();
  }

  void _onZeroEmit() {
    _forceEmit(Duration.zero);
    _resetRawPositionStaleDetector(Duration.zero);
  }

  void onPlay() {
    _positionAnchor.lastUpdateTime = clock.now();
  }

  void updateKnownPosition(Duration pos) {
    _positionAnchor.lastKnownPos = pos;
    _positionAnchor.lastUpdateTime = clock.now();
  }

  void onPause() {
    _positionAnchor.lastUpdateTime = clock.now();
  }

  void onStop() {
    _positionAnchor.lastKnownPos = Duration.zero;
    _positionAnchor.lastUpdateTime = clock.now();
    _onZeroEmit();
  }

  /// Parses a seconds value from mpv's string property format.
  ///
  /// Handles:
  /// - Plain numbers: "5", "5.0"
  /// - Unit suffixes: "5.0s", "3.00 ms", "1.5 sec", "500ms"
  /// - EU locale: "3,14" (comma decimal)
  /// - Whitespace: "  5.0  "
  ///
  /// Returns the parsed seconds, or `null` if the string can't be parsed.
  // Retained as fallback; getRawPropertyNode is now preferred.
  @visibleForTesting
  static double? parseSeconds(String raw) {
    // Fast path: clean numeric string — handles 99.9% of mpv output.
    final trimmed = raw.trim();
    final fastResult = double.tryParse(trimmed);
    if (fastResult != null) return fastResult;
    // Fallback: unit suffixes, EU locale, whitespace padding.
    final match = _secondsRegex.firstMatch(raw);
    if (match == null) return null;
    final normalized = match.group(1)!.replaceFirst(',', '.');
    return double.tryParse(normalized);
  }

  Future<Duration> getRawPosition() async {
    try {
      final node = await _player.getRawPropertyNode('time-pos');
      if (node == null) return Duration.zero;
      final seconds = (node is num)
          ? node.toDouble()
          : double.tryParse('$node') ?? 0.0;
      if (seconds < 0) return Duration.zero;
      return Duration(milliseconds: (seconds * 1000).round());
    } on Exception catch (e, stack) {
      afLog('audio', 'getRawPosition failed', error: e, stackTrace: stack);
      return Duration.zero;
    }
  }

  Future<Duration> getRawDuration() async {
    try {
      final node = await _player.getRawPropertyNode('duration');
      if (node == null) return Duration.zero;
      final seconds = (node is num)
          ? node.toDouble()
          : double.tryParse('$node') ?? 0.0;
      if (seconds <= 0) return Duration.zero;
      return Duration(milliseconds: (seconds * 1000).round());
    } on Exception catch (e, stack) {
      afLog('audio', 'getRawDuration failed', error: e, stackTrace: stack);
      return Duration.zero;
    }
  }

  void _resetRawPositionStaleDetector([Duration? seed]) {
    _lastRawPolledPos = seed;
    _staleRawPollTicks = 0;
  }

  bool _isRawPositionStale(Duration rawPos) {
    final previous = _lastRawPolledPos;
    _lastRawPolledPos = rawPos;

    if (previous == null) {
      _staleRawPollTicks = 0;
      return false;
    }

    final deltaMs = (rawPos - previous).inMilliseconds.abs();
    if (deltaMs <= _rawStaleTolerance.inMilliseconds) {
      _staleRawPollTicks++;
    } else {
      _staleRawPollTicks = 0;
    }

    return _staleRawPollTicks >= _rawStaleAfterTicks;
  }

  void _emitExtrapolatedPosition() {
    final now = clock.now();
    final dur = _player.state.duration;
    if (dur > Duration.zero && _positionAnchor.lastKnownPos >= dur) {
      _positionAnchor.lastKnownPos = dur;
      _emitPosition(dur);
      return;
    }
    final elapsed = now.difference(_positionAnchor.lastUpdateTime);
    final speed = _player.state.rate;
    final extrapolated =
        _positionAnchor.lastKnownPos +
        Duration(milliseconds: (elapsed.inMilliseconds * speed).round());
    final durCap = dur > Duration.zero ? dur : const Duration(hours: 1);
    final capped = extrapolated > durCap ? durCap : extrapolated;
    _positionAnchor.lastKnownPos = capped;
    _positionAnchor.lastUpdateTime = now;
    _emitPosition(capped);
  }

  Future<void> _pollAndEmitPosition() async {
    if (_isSeeking) return;
    // Skip poll when nothing is advancing — no need to hit the
    // MethodChannel for getRawPropertyNode('time-pos').  UI reads from
    // positionStreamProvider which holds the last emitted value.
    if (!_player.state.playing && !_shouldAdvancePosition()) {
      _emitPosition(_positionAnchor.lastKnownPos);
      return;
    }
    // If a poll is already in-flight, skip this tick silently.
    // The next tick (500ms later) will get a fresh raw read instead
    // of falling back to extrapolation which can drift.
    if (_pollChain != null) return;

    _pollChain = _executePoll();
    try {
      await _pollChain;
    } finally {
      _pollChain = null;
    }
  }

  Future<void> _executePoll() async {
    try {
      final rawPos = await getRawPosition();
      final now = clock.now();
      // Use the service-level advancement check as the single source of
      // truth — it verifies a valid track is active and not at queue end.
      // Do NOT fall back to _player.state.playing here: after stop(), mpv
      // may still report playing=true (stale property) while no track is
      // active, causing the position to keep extrapolating past the end.
      final shouldAdvance = _shouldAdvancePosition();

      if (rawPos > Duration.zero) {
        final behind =
            rawPos.inMilliseconds + 1000 <
            _positionAnchor.lastKnownPos.inMilliseconds;
        final rawBehindAnchor = shouldAdvance && behind;
        final rawStale =
            shouldAdvance && (_isRawPositionStale(rawPos) || rawBehindAnchor);

        if (!rawStale && (!behind || shouldAdvance)) {
          _positionAnchor.lastKnownPos = rawPos;
          _positionAnchor.lastUpdateTime = now;
          _emitPosition(rawPos);
          return;
        }

        if (_staleRawPollTicks == _rawStaleAfterTicks || rawBehindAnchor) {
          afLog(
            'audio',
            'raw time-pos stale at ${rawPos.inMilliseconds}ms; using extrapolated position',
          );
        }
      }

      if (shouldAdvance) {
        _emitExtrapolatedPosition();
      } else if (rawPos == Duration.zero) {
        _resetRawPositionStaleDetector(Duration.zero);
      }
    } on Exception catch (e, stack) {
      afLog('audio', '_executePoll failed', error: e, stackTrace: stack);
      // Poll failed silently — next tick will retry.
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _positionPollTimer?.cancel();
    _seekResetTimer?.cancel();
    _positionController.close();
  }
}
