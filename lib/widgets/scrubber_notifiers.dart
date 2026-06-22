import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

class ScrubProgressNotifier extends ChangeNotifier {
  ScrubProgressNotifier({required double progress}) : _progress = progress;
  double _progress;
  bool _dragging = false;
  double _dragProgress = 0.0;

  double get displayProgress =>
      _dragging ? _dragProgress : _progress.clamp(0.0, 1.0);
  bool get dragging => _dragging;
  double get dragProgress => _dragProgress;

  void update(double progress) {
    _progress = progress;
    notifyListeners();
  }

  void setDrag(bool dragging, double progress) {
    _dragging = dragging;
    _dragProgress = progress;
    notifyListeners();
  }
}

class ScrubBlockNotifier extends ChangeNotifier {
  static const int bins = 64;
  static const int _lutSize = 1024;

  static final Float32List _pow10Lut = Float32List(_lutSize);
  static bool _lutReady = false;

  static void _initLut() {
    if (_lutReady) return;
    for (var i = 0; i < _lutSize; i++) {
      _pow10Lut[i] = math.pow(i / (_lutSize - 1), 2.0).toDouble();
    }
    _lutReady = true;
  }

  final Float32List smoothed = Float32List(bins);

  double totalEnergy = 0.0;
  bool _fadingOut = false;
  bool _dirty = false;

  bool get needsTicker => _fadingOut || totalEnergy > 0.0 || _dirty;

  // ── Transition buffer ──────────────────────────────────────────────
  static const int _transitionCapacity = 20; // ~150ms at 8ms emit interval
  final List<Float32List> _transitionBuffer = List<Float32List>.generate(
    _transitionCapacity,
    (_) => Float32List(bins),
  );
  int _transitionBufferIndex = 0;
  bool _fadingIn = false;
  int _fadeStep = 0;
  int _fadeTotal = 0;
  int _fadeOutFrames = 0;

  bool get hasEnergy => totalEnergy > 0.001;

  /// Updates bar data from engine bands. Does NOT call notifyListeners —
  /// the ticker calls flush() on vsync to trigger the repaint at a
  /// steady frame rate regardless of stream event timing.
  void ingest(Float32List bands) {
    _fadingOut = false;
    if (bands.isEmpty) return;
    if (!_lutReady) _initLut();

    // Copy raw frame into transition buffer (circular).
    // Use setAll instead of sublist to avoid allocation on every frame.
    final buf = _transitionBuffer[_transitionBufferIndex % _transitionCapacity];
    final int srcLen = bands.length;
    final int copyLen = srcLen < bins ? srcLen : bins;
    buf.setRange(0, copyLen, bands);
    if (copyLen < bins) {
      buf.fillRange(copyLen, bins, 0.0);
    }
    _transitionBufferIndex++;

    double energy = 0.0;
    final int n = srcLen < bins ? srcLen : bins;
    for (var i = 0; i < n; i++) {
      final idx = (bands[i].clamp(0.0, 1.0) * (_lutSize - 1)).round();
      smoothed[i] = _pow10Lut[idx];
      energy += smoothed[i];
    }
    for (var i = n; i < bins; i++) {
      smoothed[i] = 0.0;
    }

    // Handle fade-in blending.
    if (_fadingIn) {
      _fadeStep++;
      if (_fadeStep >= _fadeTotal) {
        _fadingIn = false;
      } else {
        final blendFactor = _fadeStep / _fadeTotal;
        for (var i = 0; i < n; i++) {
          final idx = (bands[i].clamp(0.0, 1.0) * (_lutSize - 1)).round();
          final liveV = _pow10Lut[idx];
          smoothed[i] = liveV * blendFactor;
        }
        energy = smoothed.take(n).fold(0.0, (a, b) => a + b);
        totalEnergy = energy / bins;
        _dirty = true;
        return;
      }
    }

    totalEnergy = energy / bins;
    _dirty = true;
  }

  /// Called by the ticker on every vsync. Fires notifyListeners only if
  /// data changed since last flush — guarantees frame-aligned repaints
  /// at a steady 60 fps regardless of stream event timing.
  void flush() {
    if (_fadingOut) {
      _tickFadeOut();
      return;
    }
    if (_dirty) {
      _dirty = false;
      notifyListeners();
    }
  }

  /// Start the fade-out animation (called when audio goes silent).
  void startFadeOut() {
    _fadingOut = true;
    _fadingIn = false;
    _dirty = false;
    _fadeOutFrames = 0;
  }

  void _tickFadeOut() {
    if (_fadeOutFrames < _transitionCapacity) {
      final k = _fadeOutFrames;
      final bufferFrame =
          _transitionBuffer[(_transitionBufferIndex + k) % _transitionCapacity];
      final fadeFactor = 1.0 - (k / _transitionCapacity);
      double energy = 0.0;
      for (var i = 0; i < bins; i++) {
        smoothed[i] = bufferFrame[i] * fadeFactor;
        energy += smoothed[i];
      }
      totalEnergy = energy / bins;
      notifyListeners();
      _fadeOutFrames++;
    } else {
      for (var i = 0; i < bins; i++) {
        smoothed[i] = 0.0;
      }
      totalEnergy = 0.0;
      notifyListeners();
      _fadingOut = false;
      _fadingIn = true;
      _fadeStep = 0;
      _fadeTotal = 6; // ~50ms at 8ms emit
    }
  }

  void clearTarget() {
    for (var i = 0; i < bins; i++) {
      smoothed[i] = 0.0;
    }
    totalEnergy = 0.0;
    notifyListeners();
  }
}
