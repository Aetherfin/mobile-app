import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';

import '../../utils/log.dart';

/// Wraps [connectivity_plus] to emit a `bool` stream of online/offline state.
///
/// - `true` = device has at least one active network connection.
/// - `false` = device is offline (no connectivity at all).
///
/// The stream never emits duplicate consecutive values — only fires on
/// actual state transitions.
///
/// Call [dispose] when no longer needed.
class ConnectivityObserver {
  ConnectivityObserver({
    Future<List<ConnectivityResult>> Function()? checkConnectivity,
    Stream<List<ConnectivityResult>> Function()? onConnectivityChanged,
  }) : _checkConnectivity =
           checkConnectivity ?? (() => Connectivity().checkConnectivity()),
       _onConnectivityChanged =
           onConnectivityChanged ??
           (() => Connectivity().onConnectivityChanged) {
    _init();
  }

  final Future<List<ConnectivityResult>> Function() _checkConnectivity;
  final Stream<List<ConnectivityResult>> Function() _onConnectivityChanged;
  StreamSubscription<List<ConnectivityResult>>? _sub;
  bool _lastOnline = true;
  bool _disposed = false;

  /// Broadcast stream of online/offline state.
  ///
  /// - `true` = online
  /// - `false` = offline
  /// - First event is the initial state from `checkConnectivity()`.
  /// - Subsequent events fire only on actual transitions.
  final StreamController<bool> _controller = StreamController<bool>.broadcast();

  Stream<bool> get stream => _controller.stream;

  Future<void> _init() async {
    if (_disposed) return;
    try {
      final result = await _checkConnectivity();
      _lastOnline = !_allNone(result);
      if (!_disposed) {
        _controller.add(_lastOnline);
      }
    } catch (e) {
      afLog('http', 'Connectivity check failed', error: e);
      // Assume online by default.
      _lastOnline = true;
      if (!_disposed) {
        _controller.add(true);
      }
    }

    if (_disposed) return;
    _sub = _onConnectivityChanged().listen(_onChanged);
  }

  void _onChanged(List<ConnectivityResult> results) {
    if (_disposed) return;
    final online = !_allNone(results);
    if (online != _lastOnline) {
      _lastOnline = online;
      _controller.add(online);
    }
  }

  /// Returns `true` when all results are [ConnectivityResult.none].
  static bool _allNone(List<ConnectivityResult> results) {
    return results.every((r) => r == ConnectivityResult.none);
  }

  /// Whether the device is currently online.
  bool get isOnline => _lastOnline;

  /// Stops listening and releases resources.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _sub?.cancel();
    _sub = null;
    _controller.close();
  }
}
