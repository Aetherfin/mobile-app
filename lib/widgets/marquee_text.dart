import 'package:flutter/material.dart';

import '../design_tokens/tokens.dart';

/// Auto-scrolling marquee text that animates when content overflows.
///
/// Measures text width once via [LayoutBuilder], then scrolls a duplicated
/// text row at [speedPxPerSec] when the content exceeds the available width.
/// After the initial measurement, the animation runs without [LayoutBuilder]
/// to avoid unnecessary tree rebuilds from parent state changes.
class MarqueeText extends StatefulWidget {
  const MarqueeText({
    super.key,
    required this.text,
    required this.style,
    this.speedPxPerSec = 30.0,
    this.minDurationMs = 4000,
    this.maxDurationMs = 20000,
  });

  final String text;
  final TextStyle style;

  /// Pixels per second for scroll speed calculation.
  final double speedPxPerSec;

  /// Minimum animation duration in milliseconds.
  final int minDurationMs;

  /// Maximum animation duration in milliseconds.
  final int maxDurationMs;

  @override
  State<MarqueeText> createState() => MarqueeTextState();
}

class MarqueeTextState extends State<MarqueeText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  double _offset = 0.0;
  bool _shouldScroll = false;

  /// Measured values — set once after LayoutBuilder, then reused.
  double _availableWidth = 0;
  double _textWidth = 0;
  double _totalWidth = 0;
  double _lineHeight = 0;
  bool _measured = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this);
  }

  @override
  void didUpdateWidget(covariant MarqueeText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) {
      _controller.stop();
      _controller.value = 0;
      _shouldScroll = false;
      _measured = false;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_measured) {
      return LayoutBuilder(
        builder: (context, constraints) {
          // Defer measurement to post-frame so the layout is settled.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            _measure(constraints.maxWidth);
          });
          return Text(widget.text, maxLines: 1, style: widget.style);
        },
      );
    }

    if (!_shouldScroll) {
      return Text(widget.text, maxLines: 1, style: widget.style);
    }

    // Respect reduced motion — fall back to truncated static text.
    if (MediaQuery.disableAnimationsOf(context)) {
      return Text(
        widget.text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: widget.style,
      );
    }

    // Animation path — no LayoutBuilder, no parent rebuild overhead.
    return RepaintBoundary(
      child: ClipRect(
        child: SizedBox(
          width: _availableWidth,
          height: _lineHeight,
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              return Transform.translate(
                offset: Offset(-_offset * _controller.value, 0),
                child: OverflowBox(
                  alignment: Alignment.centerLeft,
                  minWidth: _totalWidth,
                  maxWidth: _totalWidth,
                  minHeight: _lineHeight,
                  maxHeight: _lineHeight,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: _textWidth,
                        child: Text(
                          widget.text,
                          maxLines: 1,
                          style: widget.style,
                        ),
                      ),
                      const SizedBox(width: AfSpacing.s32),
                      SizedBox(
                        width: _textWidth,
                        child: Text(
                          widget.text,
                          maxLines: 1,
                          style: widget.style,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  void _measure(double maxWidth) {
    final tp = TextPainter(
      text: TextSpan(text: widget.text, style: widget.style),
      maxLines: 1,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: maxWidth);

    _availableWidth = maxWidth;
    _textWidth = tp.width;
    _lineHeight = (widget.style.fontSize ?? 14) * (widget.style.height ?? 1.4);

    if (!tp.didExceedMaxLines) {
      _measured = true;
      if (mounted) setState(() {});
      return;
    }

    // Text overflows — configure scroll.
    _shouldScroll = true;
    _offset = _textWidth + 32.0;
    _totalWidth = _offset + _textWidth;
    final durationMs = (_offset / widget.speedPxPerSec * 1000).round().clamp(
      widget.minDurationMs,
      widget.maxDurationMs,
    );
    _controller.duration = Duration(milliseconds: durationMs);
    _controller.repeat();

    _measured = true;
    if (mounted) setState(() {});
  }
}
