import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../design_tokens/tokens.dart';
import 'player_providers.dart';
import 'spectral_providers.dart';

/// Animated spectral value — updates every frame during transitions.
/// Read via [ValueListenableBuilder] in the widget tree.
final ValueNotifier<Spectral> animatedSpectral = ValueNotifier<Spectral>(
  Spectral.fallback,
);

/// Watches [currentSpectralProvider] and animates color transitions.
/// Wrap [MaterialApp] with this widget.
class AnimatedSpectralScope extends ConsumerStatefulWidget {
  const AnimatedSpectralScope({required this.child, super.key});
  final Widget child;

  @override
  ConsumerState<AnimatedSpectralScope> createState() =>
      _AnimatedSpectralScopeState();
}

class _AnimatedSpectralScopeState extends ConsumerState<AnimatedSpectralScope>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  Spectral _from = Spectral.fallback;
  Spectral _to = Spectral.fallback;
  Spectral _current = Spectral.fallback;

  /// Tracks whether a new spectral extraction is in progress.
  /// When the image URL changes, spectralFromUrlProvider returns
  /// AsyncLoading and currentSpectralProvider falls back to _lastSpectral.
  /// If _lastSpectral == _to (e.g. previous extraction failed), the animation
  /// would not trigger without this flag.
  bool _isExtracting = false;
  String? _lastImageUrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: AfDurations.spectral);
    _ctrl.addListener(() {
      _current = _lerpSpectral(_from, _to, _ctrl.value);
      animatedSpectral.value = _current;
    });

    // Listen for image URL changes on the track provider.
    // When URL changes, mark extraction as in-progress so the animation
    // triggers even if the spectral value temporarily matches _to.
    ref.listenManual<String?>(currentTrackProvider.select((t) => t?.imageUrl), (
      prev,
      next,
    ) {
      if (next != _lastImageUrl) {
        _lastImageUrl = next;
        _isExtracting = true;
      }
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final next = ref.watch(currentSpectralProvider);
    if (next != _to || _isExtracting) {
      _from = _current;
      _to = next;
      _ctrl.forward(from: 0);
      _isExtracting = false;
    }
    return widget.child;
  }
}

/// Linearly interpolates color fields in [Spectral].
///
/// 12 fields are lerped every frame (primary, secondary, energy, shadow,
/// surfaceCanvas, glow, muted, surfaceBase, surfaceRaised, textPrimary,
/// textSecondary, textOnPrimary). The remaining 7 fields (link, warning,
/// surfaceLow, surfaceHigh, surfaceMax, textTertiary, textDisabled) snap
/// at endpoints only. ~0.03ms extra per frame over previous 5-field lerp.
Spectral _lerpSpectral(Spectral a, Spectral b, double t) {
  if (t == 0) return a;
  if (t == 1) return b;
  return Spectral(
    // ── Lerp every frame (12 fields) ──
    primary: Color.lerp(a.primary, b.primary, t)!,
    secondary: Color.lerp(a.secondary, b.secondary, t)!,
    energy: Color.lerp(a.energy, b.energy, t)!,
    shadow: Color.lerp(a.shadow, b.shadow, t)!,
    surfaceCanvas: Color.lerp(a.surfaceCanvas, b.surfaceCanvas, t)!,
    glow: Color.lerp(a.glow, b.glow, t)!,
    muted: Color.lerp(a.muted, b.muted, t)!,
    surfaceBase: Color.lerp(a.surfaceBase, b.surfaceBase, t)!,
    surfaceRaised: Color.lerp(a.surfaceRaised, b.surfaceRaised, t)!,
    textPrimary: Color.lerp(a.textPrimary, b.textPrimary, t)!,
    textSecondary: Color.lerp(a.textSecondary, b.textSecondary, t)!,
    textOnPrimary: Color.lerp(a.textOnPrimary, b.textOnPrimary, t)!,
    // ── Snap at endpoints (7 fields) ──
    link: a.link,
    warning: a.warning,
    surfaceLow: a.surfaceLow,
    surfaceHigh: a.surfaceHigh,
    surfaceMax: a.surfaceMax,
    textTertiary: a.textTertiary,
    textDisabled: a.textDisabled,
  );
}
