import 'dart:ui';

import 'package:animate_do/animate_do.dart';
import 'package:flutter/material.dart';

import '../design_tokens/tokens.dart';

/// Shows a blurred dialog pushed as a real route on the root navigator.
///
/// Both `child` and `builder` patterns are supported. In both cases,
/// `Navigator.pop(context, result)` inside the child tree correctly
/// dismisses the dialog and completes the future.
Future<T?> showBlurDialog<T>({
  required BuildContext context,
  Widget? child,
  Widget Function(BuildContext context, void Function([T? result]) dismiss)?
  builder,
  bool barrierDismissible = true,
}) {
  assert(child != null || builder != null, 'Provide child or builder');

  final reduced = MediaQuery.of(context).disableAnimations;

  return Navigator.of(context, rootNavigator: true).push<T>(
    PageRouteBuilder<T>(
      opaque: false,
      barrierDismissible: barrierDismissible,
      barrierColor: Colors.transparent,
      transitionDuration: reduced ? Duration.zero : AfDurations.quick,
      reverseTransitionDuration: reduced ? Duration.zero : AfDurations.bounce,
      pageBuilder: (context, animation, secondaryAnimation) {
        return _BlurDialogOverlay<T>(
          animation: animation,
          barrierDismissible: barrierDismissible,
          reduced: reduced,
          child: builder != null
              ? builder(context, ([T? result]) {
                  Navigator.of(context).pop(result);
                })
              : child!,
        );
      },
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        return child;
      },
    ),
  );
}

// ── Overlay widget ─────────────────────────────────────────────────────────

class _BlurDialogOverlay<T> extends StatelessWidget {
  const _BlurDialogOverlay({
    required this.child,
    required this.barrierDismissible,
    required this.animation,
    required this.reduced,
  });

  final Widget child;
  final bool barrierDismissible;
  final Animation<double> animation;
  final bool reduced;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        final t = animation.value;
        final blurSigma = lerpDouble(1, 24, t)!;
        final opacity = AfCurves.easeOut.transform(t).clamp(0.001, 0.999);

        return Material(
          type: MaterialType.transparency,
          child: Semantics(
            label: 'Dismiss dialog',
            button: true,
            onTap: barrierDismissible
                ? () => Navigator.of(context).pop()
                : null,
            child: GestureDetector(
              onTap: barrierDismissible
                  ? () => Navigator.of(context).pop()
                  : null,
              behavior: HitTestBehavior.opaque,
              child: Stack(
                children: [
                  // ── Blur layer (driven by route animation) ──
                  Positioned.fill(
                    child: BackdropFilter(
                      filter: ImageFilter.blur(
                        sigmaX: blurSigma,
                        sigmaY: blurSigma,
                      ),
                      child: Container(
                        color: AfColors.surfaceScrim.withValues(
                          alpha: opacity * 0.25,
                        ),
                      ),
                    ),
                  ),
                  // ── Dialog content (animate_do on mount) ──
                  Center(
                    child: ZoomIn(
                      duration: AfDurations.quick,
                      curve: AfCurves.easeEmphasized,
                      from: 0.92,
                      animate: !reduced,
                      child: FadeIn(
                        duration: AfDurations.quick,
                        curve: AfCurves.easeEmphasized,
                        animate: !reduced,
                        child: GestureDetector(
                          onTap: () {},
                          child: FocusScope(
                            autofocus: true,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: AfSpacing.s24,
                              ),
                              child: Container(
                                padding: const EdgeInsets.all(AfSpacing.s16),
                                decoration: BoxDecoration(
                                  color: AfColors.surfaceRaised.withValues(
                                    alpha: 0.85,
                                  ),
                                  borderRadius: AfRadii.borderLg,
                                  border: Border.all(
                                    color: AfColors.glassBorderEmphasis,
                                    width: 0.5,
                                  ),
                                ),
                                child: ListTileTheme(
                                  tileColor: Colors.transparent,
                                  child: child,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
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
