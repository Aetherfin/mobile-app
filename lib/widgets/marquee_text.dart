import 'package:flutter/material.dart';

import '../design_tokens/tokens.dart';

/// Auto-scrolling marquee text that animates when content overflows.
///
/// Measures text width via [LayoutBuilder], then scrolls a duplicated
/// text row at [speedPxPerSec] when the content exceeds the available
/// width. Pauses briefly at each edge before repeating.
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

  /// Cache text measurement to avoid TextPainter allocation on every build.
  String _cachedText = '';
  TextStyle? _cachedStyle;
  double _cachedTextWidth = 0;

  double _measureTextWidth(String text, TextStyle style) {
    if (text == _cachedText && style == _cachedStyle) {
      return _cachedTextWidth;
    }
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      maxLines: 1,
      textDirection: TextDirection.ltr,
    )..layout();
    _cachedText = text;
    _cachedStyle = style;
    _cachedTextWidth = tp.width;
    return _cachedTextWidth;
  }

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
      _cachedText = '';
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        final textWidth = _measureTextWidth(widget.text, widget.style);

        if (textWidth <= maxWidth) {
          if (_shouldScroll) {
            _controller.stop();
            _controller.value = 0;
            _shouldScroll = false;
          }
          return Text(widget.text, maxLines: 1, style: widget.style);
        }

        if (!_shouldScroll) {
          _shouldScroll = true;
          _offset = textWidth + 32.0;
          final durationMs = (_offset / widget.speedPxPerSec * 1000)
              .round()
              .clamp(widget.minDurationMs, widget.maxDurationMs);
          _controller.duration = Duration(milliseconds: durationMs);
          _controller.repeat();
        }

        final totalWidth = _offset + textWidth;
        final lineHeight =
            (widget.style.fontSize ?? 14) * (widget.style.height ?? 1.4);
        return RepaintBoundary(
          child: ClipRect(
            child: SizedBox(
              width: maxWidth,
              height: lineHeight,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  AnimatedBuilder(
                    animation: _controller,
                    builder: (context, _) {
                      return Transform.translate(
                        offset: Offset(-_offset * _controller.value, 0),
                        child: OverflowBox(
                          alignment: Alignment.centerLeft,
                          minWidth: totalWidth,
                          maxWidth: totalWidth,
                          minHeight: lineHeight,
                          maxHeight: lineHeight,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                widget.text,
                                maxLines: 1,
                                style: widget.style,
                              ),
                              const SizedBox(width: AfSpacing.s32),
                              Text(
                                widget.text,
                                maxLines: 1,
                                style: widget.style,
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
