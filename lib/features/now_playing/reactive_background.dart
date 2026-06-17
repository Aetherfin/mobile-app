import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../design_tokens/tokens.dart';
import '../../state/providers.dart';
import '../../utils/oklch.dart';
import 'backgrounds/backgrounds.dart';

/// Animated background that transitions between spectral-derived colors.
///
/// Watches [currentSpectralProvider] and [playerBackgroundStyleProvider]
/// to render the appropriate background style. Uses [AnimatedSwitcher]
/// for smooth crossfade transitions when the style changes.
///
/// The spectral energy color is animated independently so artwork transitions
/// feel smooth regardless of which background style is active.
class ReactiveBackground extends ConsumerStatefulWidget {
  const ReactiveBackground({super.key, required this.child});
  final Widget child;

  @override
  ConsumerState<ReactiveBackground> createState() => _ReactiveBackgroundState();
}

class _ReactiveBackgroundState extends ConsumerState<ReactiveBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late Animation<Color?> _colorAnimation;
  Color _current = AfColors.surfaceCanvas;
  Color _target = AfColors.surfaceCanvas;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: AfDurations.expressive,
    );
    _colorAnimation = ColorTween(begin: _current, end: _current).animate(
      CurvedAnimation(parent: _controller, curve: AfCurves.easeStandard),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final spectral = ref.watch(currentSpectralProvider);
    final energy = spectral.energy;

    final oklch = srgbToOklch(energy);
    final target = OklchColor(0.35, 0.12, oklch.h).toColor();

    // ponytail: mutation in build() — safe because guarded by `target != _target`.
    // Runs exactly once per spectral change. Alternatives (ref.listen in initState,
    // addPostFrameCallback) either don't work in ConsumerState or add frame delay.
    if (target != _target) {
      _target = target;
      _current = _colorAnimation.value ?? _current;
      _colorAnimation = ColorTween(begin: _current, end: target).animate(
        CurvedAnimation(parent: _controller, curve: AfCurves.easeStandard),
      );
      _controller
        ..reset()
        ..forward();
      _current = target;
    }

    final luminance = target.computeLuminance();
    final overlayStyle = SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: luminance > 0.5
          ? Brightness.dark
          : Brightness.light,
      statusBarBrightness: luminance > 0.5 ? Brightness.light : Brightness.dark,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarIconBrightness: luminance > 0.5
          ? Brightness.dark
          : Brightness.light,
      systemNavigationBarDividerColor: Colors.transparent,
    );

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlayStyle,
      child: AnimatedBuilder(
        animation: _colorAnimation,
        builder: (context, _) =>
            GlowBackground(energy: energy, child: widget.child),
      ),
    );
  }
}
