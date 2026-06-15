import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../design_tokens/tokens.dart';
import '../state/providers.dart';
import '../utils/time_format.dart';
import 'scrubber_notifiers.dart';
import 'scrubber_painters.dart';

class AudioVisualScrubber extends ConsumerStatefulWidget {
  const AudioVisualScrubber({
    super.key,
    this.height = 120,
    required this.progress,
    this.playedColor = AfColors.indigo300,
    this.unplayedColor = AfColors.textTertiary,
    this.onScrub,
    this.onScrubEnd,
  });
  final double height;
  final double progress;
  final Color playedColor;
  final Color unplayedColor;
  final ValueChanged<double>? onScrub;
  final ValueChanged<double>? onScrubEnd;

  @override
  ConsumerState<AudioVisualScrubber> createState() =>
      _AudioVisualScrubberState();
}

class _AudioVisualScrubberState extends ConsumerState<AudioVisualScrubber>
    with SingleTickerProviderStateMixin {
  late final ScrubBlockNotifier _fftNotifier;
  late final ScrubProgressNotifier _scrubNotifier;
  late final AnimationController _ticker;
  Timer? _silenceTimer;
  Animation<double>? _overlayAnim;
  late final AppLifecycleListener _lifecycle;

  bool _isAppBackground = false;

  bool get _isObscured => (_overlayAnim?.value ?? 0.0) > 0.0;
  bool get _shouldRender => mounted && !_isObscured && !_isAppBackground;

  @override
  void initState() {
    super.initState();
    _fftNotifier = ScrubBlockNotifier();
    _scrubNotifier = ScrubProgressNotifier(progress: widget.progress);

    _lifecycle = AppLifecycleListener(
      onPause: () {
        _isAppBackground = true;
        _ticker.stop();
      },
      onResume: () {
        _isAppBackground = false;
        if (_fftNotifier.hasEnergy) _ticker.repeat();
      },
    );

    // Ticker drives repaints at vsync (60 fps). Stream events just update
    // data; the ticker ensures frame-aligned rendering so the visualizer
    // doesn't stutter from async stream timing misalignment.
    _ticker =
        AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 16),
        )..addListener(() {
          if (mounted) _fftNotifier.flush();
        });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Listen through shared fftFrameProvider instead of a direct
      // spectrumStream subscription — both visualizer and artwork pulse
      // share one mpv stream.
      final reduced = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
      ref.listenManual(fftFrameProvider, (prev, next) {
        if (!_shouldRender) return;
        final frame = next.valueOrNull;
        if (frame == null) return;
        _fftNotifier.ingest(frame.bands);
        if (reduced) {
          // Static render: flush directly, no ticker, no fade/decay.
          _fftNotifier.flush();
        } else {
          _silenceTimer?.cancel();
          if (!_ticker.isAnimating) _ticker.repeat();
          _silenceTimer = Timer(const Duration(milliseconds: 300), () {
            if (mounted && _shouldRender) {
              _fftNotifier.startFadeOut();
            }
          });
        }
      });
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    // Detect when another route (Queue, Lyrics, etc.) covers this screen.
    if (_overlayAnim != route?.secondaryAnimation) {
      _overlayAnim?.removeListener(_onVisibilityChange);
      _overlayAnim = route?.secondaryAnimation;
      _overlayAnim?.addListener(_onVisibilityChange);
    }
  }

  void _onVisibilityChange() {
    if (_isObscured) {
      _ticker.stop();
    } else if (_fftNotifier.totalEnergy > 0.001) {
      _ticker.repeat();
    }
  }

  @override
  void dispose() {
    _overlayAnim?.removeListener(_onVisibilityChange);
    _lifecycle.dispose();
    _silenceTimer?.cancel();
    _ticker.dispose();
    _fftNotifier.dispose();
    _scrubNotifier.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant AudioVisualScrubber old) {
    super.didUpdateWidget(old);
    _scrubNotifier.update(widget.progress);
  }

  double _toProgress(double dx) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || box.size.width <= 0) return 0;
    return (dx / box.size.width).clamp(0.0, 1.0);
  }

  void _handleDragUpdate(DragUpdateDetails d) {
    _scrubNotifier.setDrag(true, _toProgress(d.localPosition.dx));
    widget.onScrub?.call(_scrubNotifier.dragProgress);
  }

  void _handleDragEnd(DragEndDetails _) {
    widget.onScrubEnd?.call(_scrubNotifier.dragProgress);
    _scrubNotifier.setDrag(false, _scrubNotifier.dragProgress);
  }

  @override
  Widget build(BuildContext context) {
    // Use ref.read() instead of ref.watch() to avoid rebuilding this
    // 240-line widget tree on every position tick (~200ms). The parent
    // ReactiveProgress already watches position and passes `progress`.
    // These values are only needed for Semantics accessibility strings
    // and the seekBy callbacks — freshness within ~200ms is acceptable.
    final position = ref.read(positionStreamProvider);
    final duration = ref.read(durationStreamProvider);
    final valueStr =
        '${formatTrackDuration(position)} of ${formatTrackDuration(duration)}';

    void seekBy(Duration offset) {
      // Read fresh values at interaction time for accurate seek.
      final pos = ref.read(positionStreamProvider);
      final dur = ref.read(durationStreamProvider);
      final newMs = (pos + offset).inMilliseconds;
      final clampedMs = newMs.clamp(0, dur.inMilliseconds);
      final p = dur.inMilliseconds > 0 ? clampedMs / dur.inMilliseconds : 0.0;
      widget.onScrub?.call(p);
      widget.onScrubEnd?.call(p);
    }

    final fwd = position + const Duration(seconds: 10);
    final bwd = position - const Duration(seconds: 10);
    final increasedStr =
        '${formatTrackDuration(Duration(milliseconds: fwd.inMilliseconds.clamp(0, duration.inMilliseconds)))} of ${formatTrackDuration(duration)}';
    final decreasedStr =
        '${formatTrackDuration(Duration(milliseconds: bwd.inMilliseconds.clamp(0, duration.inMilliseconds)))} of ${formatTrackDuration(duration)}';

    return Semantics(
      label: 'Scrubber',
      value: valueStr,
      increasedValue: increasedStr,
      decreasedValue: decreasedStr,
      onIncrease: () => seekBy(const Duration(seconds: 10)),
      onDecrease: () => seekBy(const Duration(seconds: -10)),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragStart: (d) {
          HapticFeedback.selectionClick();
          _handleDragUpdate(
            DragUpdateDetails(
              globalPosition: d.globalPosition,
              localPosition: d.localPosition,
            ),
          );
        },
        onHorizontalDragUpdate: _handleDragUpdate,
        onHorizontalDragEnd: _handleDragEnd,
        onTapDown: (d) {
          HapticFeedback.selectionClick();
          final p = _toProgress(d.localPosition.dx);
          widget.onScrub?.call(p);
          widget.onScrubEnd?.call(p);
        },
        child: SizedBox(
          height: widget.height,
          width: double.infinity,
          child: Stack(
            fit: StackFit.expand,
            children: [
              ExcludeSemantics(
                child: RepaintBoundary(
                  child: CustomPaint(
                    painter: ScrubCombinedBarPainter(
                      fftNotifier: _fftNotifier,
                      scrubNotifier: _scrubNotifier,
                      playedColor: widget.playedColor,
                      unplayedColor: widget.unplayedColor,
                    ),
                  ),
                ),
              ),
              ExcludeSemantics(
                child: RepaintBoundary(
                  child: CustomPaint(
                    painter: ScrubOverlayPainter(
                      notifier: _scrubNotifier,
                      playedColor: widget.playedColor,
                      unplayedColor: widget.unplayedColor,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
