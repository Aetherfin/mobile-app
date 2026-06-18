import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';

import '../design_tokens/tokens.dart';

/// Global back-button coordinator for blur bottom sheets.
///
/// Bottom sheets are inserted via [OverlayEntry] (not a Navigator route), so
/// the system back gesture bypasses the sheet and pops the route below it
/// (e.g. Now Playing). To fix this without converting to a Navigator route,
/// sheets register a dismiss callback here, and the root [PopScope] in
/// `app.dart` consults [blurSheetCount] to decide whether to pop the route
/// or trigger the topmost sheet's dismiss.
final ValueNotifier<int> blurSheetCount = ValueNotifier<int>(0);
final ValueNotifier<VoidCallback?> blurSheetDismiss =
    ValueNotifier<VoidCallback?>(null);

/// Saves the focus node to restore when the current sheet dismisses.
FocusNode? _previousFocus;

/// Shows a blurred bottom sheet that renders in the current route's overlay.
Future<T?> showBlurBottomSheet<T>({
  required BuildContext context,
  Widget? child,
  Widget Function(BuildContext context, void Function([T? result]) dismiss)?
  builder,
  bool isDismissible = true,
  bool isScrollControlled = true,
  bool enableDrag = true,
  double topRadius = AfRadii.xl,
}) {
  assert(child != null || builder != null, 'Provide child or builder');
  final overlay = Navigator.of(context, rootNavigator: true).overlay;
  if (overlay == null) return Future.value(null);

  // Save current focus for restoration when sheet dismisses.
  _previousFocus = WidgetsBinding.instance.focusManager.primaryFocus;

  final completer = Completer<T?>();
  late OverlayEntry entry;

  blurSheetCount.value++;
  void onDismiss([T? result]) {
    if (completer.isCompleted) return;
    blurSheetCount.value--;
    if (blurSheetDismiss.value == _dismissTop) blurSheetDismiss.value = null;
    entry.remove();
    completer.complete(result);

    // Restore focus to the widget that was focused before the sheet opened.
    final prev = _previousFocus;
    _previousFocus = null;
    if (prev != null && prev.canRequestFocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (prev.canRequestFocus) prev.requestFocus();
      });
    }
  }

  blurSheetDismiss.value = onDismiss;

  entry = OverlayEntry(
    builder: (context) => _BlurBottomSheetOverlay<T>(
      builder: builder != null
          ? (context) => builder(context, onDismiss)
          : (context) => child!,
      isDismissible: isDismissible,
      enableDrag: enableDrag,
      topRadius: topRadius,
      onDismiss: onDismiss,
    ),
  );

  overlay.insert(entry);
  return completer.future;
}

void _dismissTop() {
  blurSheetDismiss.value?.call();
}

class _BlurBottomSheetOverlay<T> extends StatefulWidget {
  const _BlurBottomSheetOverlay({
    required this.builder,
    required this.isDismissible,
    required this.enableDrag,
    required this.topRadius,
    required this.onDismiss,
  });

  final WidgetBuilder builder;
  final bool isDismissible;
  final bool enableDrag;
  final double topRadius;
  final void Function(T?) onDismiss;

  @override
  State<_BlurBottomSheetOverlay<T>> createState() =>
      _BlurBottomSheetOverlayState<T>();
}

class _BlurBottomSheetOverlayState<T> extends State<_BlurBottomSheetOverlay<T>>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _slideAnim;
  late final Animation<double> _fadeAnim;
  late final Animation<double> _blurAnim;
  bool _dismissed = false;
  bool _didAnimate = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: AfDurations.expressive,
      reverseDuration: AfDurations.bounce,
    );
    _slideAnim = Tween<double>(
      begin: 1.0,
      end: 0.0,
    ).animate(CurvedAnimation(parent: _ctrl, curve: AfCurves.springPresent));
    _fadeAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _ctrl,
        curve: AfCurves.springPresent,
        reverseCurve: AfCurves.springDismiss,
      ),
    );
    _blurAnim = Tween<double>(begin: 1, end: 24).animate(
      CurvedAnimation(
        parent: _ctrl,
        curve: AfCurves.springPresent,
        reverseCurve: AfCurves.springDismiss,
      ),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_didAnimate) return;
    _didAnimate = true;
    if (MediaQuery.of(context).disableAnimations) {
      _ctrl.value = 1.0; // instant show, no blur/slide
    } else {
      _ctrl.forward();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _dismiss([T? result]) {
    if (_dismissed) return;
    _dismissed = true;
    _ctrl.reverse().then((_) => widget.onDismiss(result));
  }

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.of(context).viewInsets;

    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        final slideOffset = _slideAnim.value;
        final opacity = _fadeAnim.value.clamp(0.001, 0.999);
        final blurSigma = _blurAnim.value;

        return Material(
          type: MaterialType.transparency,
          child: GestureDetector(
            onTap: widget.isDismissible ? _dismiss : null,
            behavior: HitTestBehavior.opaque,
            child: Stack(
              children: [
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
                Align(
                  alignment: Alignment.bottomCenter,
                  child: Transform.translate(
                    offset: Offset(0, slideOffset * 400),
                    child: Opacity(
                      opacity: opacity,
                      child: GestureDetector(
                        onVerticalDragEnd: widget.enableDrag
                            ? (details) {
                                final vy = details.primaryVelocity ?? 0;
                                if (vy > 300 || (vy > 0 && slideOffset > 0.3)) {
                                  _dismiss();
                                }
                              }
                            : null,
                        child: Padding(
                          padding: EdgeInsets.only(bottom: viewInsets.bottom),
                          child: ClipRRect(
                            // ponytail: dynamic topRadius, no matching AfRadii token
                            borderRadius: BorderRadius.vertical(
                              top: Radius.circular(widget.topRadius),
                            ),
                            child: Container(
                              decoration: BoxDecoration(
                                color: AfColors.surfaceBase.withValues(
                                  alpha: 0.85,
                                ),
                                // ponytail: dynamic topRadius, no matching AfRadii token
                                borderRadius: BorderRadius.vertical(
                                  top: Radius.circular(widget.topRadius),
                                ),
                                border: const Border(
                                  top: BorderSide(
                                    color: AfColors.glassBorderEmphasis,
                                    width: 0.5,
                                  ),
                                ),
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const SizedBox(height: AfSpacing.s12),
                                  Semantics(
                                    label: 'Drag to dismiss',
                                    child: Container(
                                      width: AfSpacing.s40,
                                      height: AfSpacing.s4,
                                      decoration: BoxDecoration(
                                        color: AfColors.textTertiary.withValues(
                                          alpha: 0.4,
                                        ),
                                        borderRadius: AfRadii.borderXs,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: AfSpacing.s12),
                                  FocusScope(
                                    autofocus: true,
                                    child: ListTileTheme(
                                      tileColor: Colors.transparent,
                                      child: widget.builder(context),
                                    ),
                                  ),
                                ],
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
        );
      },
    );
  }
}
