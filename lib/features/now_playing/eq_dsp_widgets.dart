import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../design_tokens/tokens.dart';
import '../../state/providers.dart';

// ─── Section Label ──────────────────────────────────────────────────────────

Widget eqSectionLabel(String title) => Padding(
  padding: const EdgeInsets.fromLTRB(
    AfSpacing.s4,
    0,
    AfSpacing.s4,
    AfSpacing.s8,
  ),
  child: Text(
    title,
    style: AfTypography.bodySmall.copyWith(
      color: AfColors.textTertiary,
      fontWeight: FontWeight.w500,
    ),
  ),
);

// ─── Card ───────────────────────────────────────────────────────────────────

Widget eqCard(List<Widget> children) => Material(
  color: AfColors.surfaceBase,
  borderRadius: AfRadii.borderLg,
  clipBehavior: Clip.antiAlias,
  child: Padding(
    padding: const EdgeInsets.all(AfSpacing.s16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: children,
    ),
  ),
);

// ─── Master Banner ──────────────────────────────────────────────────────────

/// Prominent DSP master toggle banner with gradient bg and glow.
class EqMasterBanner extends ConsumerWidget {
  const EqMasterBanner({
    super.key,
    required this.enabled,
    required this.onChanged,
  });

  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spectral = ref.watch(
      currentSpectralProvider.select(
        (s) => (primary: s.primary, secondary: s.secondary, muted: s.muted),
      ),
    );
    return AnimatedContainer(
      duration: AfDurations.standard,
      curve: AfCurves.easeStandard,
      decoration: BoxDecoration(
        gradient: enabled
            ? LinearGradient(
                colors: [spectral.muted, AfColors.surfaceLow],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
            : null,
        color: enabled ? null : AfColors.surfaceLow,
        borderRadius: AfRadii.borderLg,
      ),
      padding: const EdgeInsets.all(AfSpacing.s16),
      child: Row(
        children: [
          // Glowing icon circle
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: enabled
                  ? spectral.secondary.withValues(alpha: 0.3)
                  : AfColors.surfaceHigh,
              boxShadow: enabled
                  ? [
                      BoxShadow(
                        color: spectral.primary.withValues(alpha: 0.4),
                        blurRadius: 8,
                      ),
                    ]
                  : null,
            ),
            child: Icon(
              LucideIcons.audioWaveform,
              size: AfIconSizes.sm,
              color: enabled ? spectral.primary : AfColors.textTertiary,
            ),
          ),
          const SizedBox(width: AfSpacing.s12),
          // Title + subtitle
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  enabled ? 'DSP Processing Active' : 'DSP Bypassed',
                  style: AfTypography.bodyMedium.copyWith(
                    color: AfColors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: AfSpacing.s2),
                Text(
                  enabled
                      ? 'All effects are processing audio'
                      : 'Audio passes through unprocessed',
                  style: AfTypography.bodySmall.copyWith(
                    color: enabled ? spectral.primary : AfColors.textTertiary,
                  ),
                ),
              ],
            ),
          ),
          // Custom pill toggle 52x30
          Semantics(
            toggled: enabled,
            label: 'DSP processing: ${enabled ? "on" : "off"}',
            child: GestureDetector(
              onTap: () => onChanged(!enabled),
              behavior: HitTestBehavior.opaque,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                child: AnimatedContainer(
                  duration: AfDurations.quick,
                  curve: AfCurves.easeStandard,
                  width: 52,
                  height: 30,
                  decoration: BoxDecoration(
                    color: enabled ? spectral.primary : AfColors.surfaceHigh,
                    borderRadius: AfRadii.borderPill,
                    boxShadow: enabled
                        ? [
                            BoxShadow(
                              color: spectral.primary.withValues(alpha: 0.4),
                              blurRadius: 8,
                            ),
                          ]
                        : null,
                  ),
                  child: AnimatedAlign(
                    duration: AfDurations.quick,
                    alignment: enabled
                        ? Alignment.centerRight
                        : Alignment.centerLeft,
                    curve: AfCurves.easeStandard,
                    child: Container(
                      width: 26,
                      height: 26,
                      margin: const EdgeInsets.symmetric(
                        horizontal: AfSpacing.s2,
                      ),
                      decoration: const BoxDecoration(
                        color: AfColors.textPrimary,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Accordion Section ──────────────────────────────────────────────────────

/// Single-open accordion container with header, badge, chevron, animated content.
class EqAccordionSection extends ConsumerWidget {
  const EqAccordionSection({
    super.key,
    required this.label,
    required this.isOpen,
    required this.onTap,
    required this.child,
    this.badgeCount,
  });

  final String label;
  final bool isOpen;
  final VoidCallback onTap;
  final Widget child;
  final int? badgeCount;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spectral = ref.watch(
      currentSpectralProvider.select(
        (s) => (primary: s.primary, secondary: s.secondary),
      ),
    );
    return AnimatedContainer(
      duration: AfDurations.standard,
      curve: AfCurves.easeStandard,
      decoration: BoxDecoration(
        color: isOpen ? AfColors.surfaceBase : AfColors.surfaceLow,
        borderRadius: AfRadii.borderLg,
        border: Border.all(
          color: isOpen
              ? spectral.secondary.withValues(alpha: 0.4)
              : AfColors.surfaceHigh,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Semantics(
            button: true,
            expanded: isOpen,
            label: '$label section',
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onTap,
              child: Focus(
                onKeyEvent: (node, event) {
                  if (event is KeyDownEvent &&
                      (event.logicalKey == LogicalKeyboardKey.enter ||
                          event.logicalKey == LogicalKeyboardKey.space)) {
                    onTap();
                    return KeyEventResult.handled;
                  }
                  return KeyEventResult.ignored;
                },
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    minHeight: AfSpacing.minHitTarget,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AfSpacing.s16,
                      vertical: AfSpacing.s12,
                    ),
                    child: Row(
                      children: [
                        Text(
                          label,
                          style: AfTypography.label.copyWith(
                            color: isOpen
                                ? spectral.primary
                                : AfColors.textSecondary,
                          ),
                        ),
                        if (badgeCount != null) ...[
                          const SizedBox(width: AfSpacing.s8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AfSpacing.s8,
                              vertical: AfSpacing.s2,
                            ),
                            decoration: BoxDecoration(
                              color: spectral.secondary.withValues(alpha: 0.3),
                              borderRadius: AfRadii.borderPill,
                            ),
                            child: Text(
                              '$badgeCount',
                              style: AfTypography.overline.copyWith(
                                color: spectral.primary,
                              ),
                            ),
                          ),
                        ],
                        const Spacer(),
                        AnimatedRotation(
                          turns: isOpen ? 0.5 : 0,
                          duration: AfDurations.standard,
                          curve: AfCurves.easeStandard,
                          child: const Icon(
                            LucideIcons.chevronDown,
                            size: AfIconSizes.md,
                            color: AfColors.textTertiary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          // Content with animated cross-fade
          AnimatedCrossFade(
            firstChild: const SizedBox(width: double.infinity),
            secondChild: Padding(
              padding: const EdgeInsets.fromLTRB(
                AfSpacing.s16,
                0,
                AfSpacing.s16,
                AfSpacing.s16,
              ),
              child: child,
            ),
            crossFadeState: isOpen
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: AfDurations.standard,
          ),
        ],
      ),
    );
  }
}

// ─── Compact Effect Toggle ──────────────────────────────────────────────────

/// Compact toggle row: title + subtitle column + custom pill toggle.
class EqEffectToggle extends ConsumerWidget {
  const EqEffectToggle({
    super.key,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spectral = ref.watch(
      currentSpectralProvider.select((s) => s.secondary),
    );
    return Semantics(
      toggled: value,
      label: '$title: ${value ? "on" : "off"}',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onChanged(!value),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AfSpacing.s8),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(title, style: AfTypography.bodyMedium),
                    const SizedBox(height: AfSpacing.s2),
                    Text(
                      subtitle,
                      style: AfTypography.bodySmall.copyWith(
                        color: AfColors.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AfSpacing.s8),
              // Custom pill toggle 48x28 (meets 48dp hit target with padding)
              AnimatedContainer(
                duration: AfDurations.quick,
                curve: AfCurves.easeStandard,
                width: 48,
                height: 28,
                decoration: BoxDecoration(
                  color: value ? spectral : AfColors.surfaceHigh,
                  borderRadius: AfRadii.borderPill,
                ),
                child: AnimatedAlign(
                  duration: AfDurations.quick,
                  alignment: value
                      ? Alignment.centerRight
                      : Alignment.centerLeft,
                  curve: AfCurves.easeStandard,
                  child: Container(
                    width: 24,
                    height: 24,
                    margin: const EdgeInsets.symmetric(
                      horizontal: AfSpacing.s2,
                    ),
                    decoration: const BoxDecoration(
                      color: AfColors.textPrimary,
                      shape: BoxShape.circle,
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

// ─── Animated Toggle Tile ───────────────────────────────────────────────────

Widget eqToggleTile(
  String title,
  String subtitle,
  bool value,
  ValueChanged<bool> onChanged, {
  bool enabled = true,
}) {
  return EqEffectToggle(
    title: title,
    subtitle: subtitle,
    value: value,
    onChanged: enabled ? onChanged : (_) {},
  );
}

// ─── Slider Row ─────────────────────────────────────────────────────────────

/// Custom slider with label, value display and optional suffix.
class EqSliderRow extends ConsumerWidget {
  const EqSliderRow({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.onChanged,
    required this.onChangeEnd,
    this.suffix,
    this.precision = 0,
    this.enabled = true,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final ValueChanged<double> onChanged;
  final VoidCallback onChangeEnd;
  final String? suffix;
  final int precision;
  final bool enabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spectral = ref.watch(
      currentSpectralProvider.select((s) => s.primary),
    );
    final display = value >= 0 && suffix == 'dB'
        ? '+${value.toStringAsFixed(precision)}'
        : value.toStringAsFixed(precision);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            SizedBox(
              width: 72,
              child: Text(label, style: AfTypography.bodyMedium),
            ),
            const Spacer(),
            Text(
              suffix != null ? '$display $suffix' : display,
              style: AfTypography.mono.copyWith(color: spectral),
            ),
          ],
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 2,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
          ),
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: divisions,
            activeColor: spectral,
            onChanged: enabled ? onChanged : null,
            onChangeEnd: enabled ? (_) => onChangeEnd() : null,
          ),
        ),
      ],
    );
  }
}

/// Backward-compatible alias.
Widget eqSliderRow(
  String label,
  double value,
  double min,
  double max,
  int divisions,
  ValueChanged<double> onChanged,
  VoidCallback onChangeEnd, {
  String? suffix,
  int precision = 0,
  bool enabled = true,
}) {
  return EqSliderRow(
    label: label,
    value: value,
    min: min,
    max: max,
    divisions: divisions,
    onChanged: onChanged,
    onChangeEnd: onChangeEnd,
    suffix: suffix,
    precision: precision,
    enabled: enabled,
  );
}

// ─── Text Field Row ─────────────────────────────────────────────────────────

/// Validates pipe-separated numeric input (e.g. "40|60" or "0.4|0.32").
String? _validatePipeSeparatedNumbers(String? value) {
  if (value == null || value.trim().isEmpty) return null;
  final parts = value.split('|');
  for (final part in parts) {
    if (double.tryParse(part.trim()) == null) {
      return 'Enter numbers separated by |';
    }
  }
  return null;
}

Widget eqTextFieldRow(
  BuildContext context,
  String label,
  String value,
  String hint,
  ValueChanged<String> onSubmitted, {
  bool numericPipe = false,
}) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: AfSpacing.s4),
    child: Row(
      children: [
        // ponytail: 96 is closest AfSpacing token
        SizedBox(width: 96, child: Text(label, style: AfTypography.bodySmall)),
        const SizedBox(width: AfSpacing.s8),
        Expanded(
          child: TextFormField(
            initialValue: value,
            // ponytail: no matching AfTypography token for 13px mono
            style: AfTypography.monoMedium,
            validator: numericPipe ? _validatePipeSeparatedNumbers : null,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            decoration: InputDecoration(
              labelText: label,
              hintText: hint,
              // ponytail: 12px mono hint — caption is 12dp
              hintStyle: AfTypography.caption.copyWith(
                color: AfColors.textTertiary,
              ),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: AfSpacing.s8,
                vertical: AfSpacing.s8,
              ),
              border: const OutlineInputBorder(
                borderRadius: AfRadii.borderSm,
                borderSide: BorderSide(color: AfColors.surfaceHigh),
              ),
              enabledBorder: const OutlineInputBorder(
                borderRadius: AfRadii.borderSm,
                borderSide: BorderSide(color: AfColors.surfaceHigh),
              ),
              errorBorder: const OutlineInputBorder(
                borderRadius: AfRadii.borderSm,
                borderSide: BorderSide(color: AfColors.semanticError),
              ),
              focusedErrorBorder: const OutlineInputBorder(
                borderRadius: AfRadii.borderSm,
                borderSide: BorderSide(color: AfColors.semanticError),
              ),
            ),
            onFieldSubmitted: onSubmitted,
            onTapOutside: (_) => FocusScope.of(context).unfocus(),
          ),
        ),
      ],
    ),
  );
}

// ─── Animated Content Reveal ────────────────────────────────────────────────

/// Wraps [child] in an animated size + fade transition.
/// Used to smoothly reveal sub-settings when an effect is toggled on.
class EqExpandableContent extends StatefulWidget {
  const EqExpandableContent({
    super.key,
    required this.visible,
    required this.child,
  });

  final bool visible;
  final Widget child;

  @override
  State<EqExpandableContent> createState() => _EqExpandableContentState();
}

class _EqExpandableContentState extends State<EqExpandableContent>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _heightFactor;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: AfDurations.standard);
    _heightFactor = _ctrl.drive(Tween<double>(begin: 0, end: 1));
    _opacity = _ctrl.drive(Tween<double>(begin: 0, end: 1));
    if (widget.visible) {
      _ctrl.value = 1;
    }
  }

  @override
  void didUpdateWidget(EqExpandableContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.visible != oldWidget.visible) {
      if (widget.visible) {
        _ctrl.forward();
      } else {
        _ctrl.reverse();
      }
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduced = MediaQuery.disableAnimationsOf(context);
    if (reduced) {
      return widget.visible ? widget.child : const SizedBox.shrink();
    }
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, child) => ClipRect(
        child: Align(
          alignment: Alignment.topCenter,
          heightFactor: _heightFactor.value,
          child: Opacity(
            opacity: _opacity.value.clamp(0.001, 0.999),
            child: child,
          ),
        ),
      ),
      child: widget.child,
    );
  }
}

// ─── EQ Band Vertical Bar ───────────────────────────────────────────────────

/// A single vertical EQ band bar with animated gain height.
class EqBandBar extends ConsumerWidget {
  const EqBandBar({
    super.key,
    required this.label,
    required this.gain,
    required this.min,
    required this.max,
    required this.onChanged,
    required this.onChangeEnd,
  });

  final String label;
  final double gain;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;
  final VoidCallback onChangeEnd;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spectral = ref.watch(
      currentSpectralProvider.select(
        (s) => (primary: s.primary, secondary: s.secondary),
      ),
    );
    final reduced = MediaQuery.disableAnimationsOf(context);
    // Normalize gain to 0..1 for display (0 = min, 1 = max).
    final t = ((gain - min) / (max - min)).clamp(0.0, 1.0);
    // 0.5 = flat (unity), below = cut, above = boost.
    final isFlat = (gain - 1.0).abs() < 0.05;
    final gainDb = ((gain - 1) * 12).toStringAsFixed(0);

    return Semantics(
      label: 'Frequency band $label, gain $gainDb dB',
      value: isFlat ? 'flat' : (gain > 1 ? 'boost' : 'cut'),
      child: GestureDetector(
        onVerticalDragUpdate: (details) {
          final box = context.findRenderObject() as RenderBox?;
          if (box == null) return;
          final height = box.size.height;
          // Invert: drag up = increase gain.
          final delta = -details.delta.dy / height * (max - min);
          onChanged((gain + delta).clamp(min, max));
        },
        onVerticalDragEnd: (_) => onChangeEnd(),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Gain value label.
            Text(
              gain >= 1.0
                  ? '+${((gain - 1) * 12).toStringAsFixed(0)}'
                  : ((gain - 1) * 12).toStringAsFixed(0),
              style: AfTypography.overline.copyWith(
                color: isFlat ? AfColors.textTertiary : spectral.primary,
              ),
            ),
            const SizedBox(height: AfSpacing.s2),
            // Bar container.
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final totalH = constraints.maxHeight;
                  // Fill height: how far from center the bar reaches.
                  final fillFrac = (t - 0.5).abs() * 2;

                  return AnimatedContainer(
                    duration: reduced ? Duration.zero : AfDurations.quick,
                    curve: AfCurves.easeStandard,
                    decoration: BoxDecoration(
                      color: isFlat
                          ? AfColors.surfaceHigh
                          : spectral.secondary.withValues(alpha: 0.6),
                      borderRadius: AfRadii.borderXs,
                    ),
                    child: Align(
                      alignment: Alignment(0, 1 - t * 2),
                      child: Container(
                        height: totalH * 0.08 + totalH * 0.45 * fillFrac,
                        decoration: BoxDecoration(
                          color: isFlat
                              ? AfColors.surfaceHigh
                              : spectral.primary,
                          borderRadius: AfRadii.borderXs,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: AfSpacing.s2),
            // Frequency label.
            Text(
              label,
              style: AfTypography.overline.copyWith(
                color: AfColors.textTertiary,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

// ─── EQ Band Slider (horizontal, for detailed editing) ──────────────────────

/// A single horizontal EQ band slider with animated value.
class EqBandSlider extends ConsumerWidget {
  const EqBandSlider({
    super.key,
    required this.bandKey,
    required this.freq,
    required this.gain,
    required this.onChanged,
    required this.onChangeEnd,
  });

  final String bandKey;
  final String freq;
  final double gain;
  final ValueChanged<double> onChanged;
  final VoidCallback onChangeEnd;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spectral = ref.watch(
      currentSpectralProvider.select((s) => s.primary),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AfSpacing.s2),
      child: Row(
        children: [
          SizedBox(
            width: 58,
            child: Text(
              freq,
              style: AfTypography.caption.copyWith(
                color: AfColors.textTertiary,
              ),
            ),
          ),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 2,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
              ),
              child: Slider(
                key: ValueKey(bandKey),
                value: gain.clamp(0.0, 4.0),
                min: 0,
                max: 4,
                divisions: 40,
                activeColor: spectral,
                onChanged: onChanged,
                onChangeEnd: (_) => onChangeEnd(),
              ),
            ),
          ),
          SizedBox(
            width: 36,
            child: Text(
              gain.toStringAsFixed(1),
              textAlign: TextAlign.right,
              style: AfTypography.caption.copyWith(
                color: AfColors.textTertiary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Scroll Absorb Overlay ──────────────────────────────────────────────────

/// Manages scroll-active state to prevent phantom touch events on
/// Slider/Switch/ChoiceChip widgets during scroll momentum.
class ScrollAbsorbController extends ValueNotifier<bool> {
  ScrollAbsorbController() : super(false);

  void markActive() {
    if (!value) value = true;
  }

  void markInactive() {
    if (value) value = false;
  }
}

/// Wraps a [ListView] and manages scroll-absorb state.
class ScrollAbsorbNotification extends StatefulWidget {
  const ScrollAbsorbNotification({
    super.key,
    required this.controller,
    required this.child,
  });

  final ScrollAbsorbController controller;
  final Widget child;

  @override
  State<ScrollAbsorbNotification> createState() =>
      _ScrollAbsorbNotificationState();
}

class _ScrollAbsorbNotificationState extends State<ScrollAbsorbNotification> {
  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification is ScrollStartNotification) {
          widget.controller.markActive();
        } else if (notification is ScrollEndNotification ||
            (notification is UserScrollNotification &&
                notification.direction == ScrollDirection.idle)) {
          widget.controller.markInactive();
        }
        return false;
      },
      child: NotificationListener<OverscrollIndicatorNotification>(
        onNotification: (notification) {
          notification.disallowIndicator();
          return true;
        },
        child: widget.child,
      ),
    );
  }
}
