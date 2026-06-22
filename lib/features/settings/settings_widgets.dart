import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../design_tokens/tokens.dart';
import '../../state/providers.dart';
import '../../widgets/press_scale.dart';

class SettingsLabel extends StatelessWidget {
  const SettingsLabel(this.label, {super.key});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AfSpacing.s16,
        0,
        AfSpacing.s4,
        AfSpacing.s8,
      ),
      child: Text(
        label,
        style: AfTypography.bodySmall.copyWith(
          color: AfColors.textTertiary,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

class SettingsGroup extends StatelessWidget {
  const SettingsGroup({required this.children, super.key});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: const BoxDecoration(
        color: AfColors.surfaceRaised,
        borderRadius: AfRadii.borderLg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (int i = 0; i < children.length; i++) ...[
            children[i],
            if (i < children.length - 1)
              const Divider(
                height: 0,
                thickness: 0.5,
                indent: 60,
                color: AfColors.surfaceHigh,
              ),
          ],
        ],
      ),
    );
  }
}

class SettingsTile extends ConsumerWidget {
  const SettingsTile({
    super.key,
    required this.icon,
    this.iconColor,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.danger = false,
  });
  final IconData icon;
  final Color? iconColor;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool danger;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spectral = ref.watch(
      currentSpectralProvider.select((s) => s.primary),
    );
    final effectiveIconColor = danger
        ? AfColors.semanticError
        : (iconColor ?? spectral);
    return Semantics(
      label: title,
      button: true,
      child: PressScale(
        onTap: onTap,
        ensureHitTarget: true,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: AfSpacing.minHitTarget),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AfSpacing.s16,
              vertical: AfSpacing.s12,
            ),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: const BoxDecoration(
                    color: AfColors.surfaceHigh,
                    borderRadius: AfRadii.borderSm,
                  ),
                  child: Icon(icon, size: 16, color: effectiveIconColor),
                ),
                const SizedBox(width: AfSpacing.s12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        style: AfTypography.bodyMedium.copyWith(
                          color: danger
                              ? AfColors.semanticError
                              : AfColors.textPrimary,
                        ),
                      ),
                      if (subtitle != null)
                        Padding(
                          padding: const EdgeInsets.only(top: AfSpacing.s2),
                          child: Text(
                            subtitle!,
                            style: AfTypography.bodySmall.copyWith(
                              color: AfColors.textTertiary,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                if (trailing != null) ...[
                  const SizedBox(width: AfSpacing.s8),
                  trailing!,
                ] else if (onTap != null) ...[
                  const SizedBox(width: AfSpacing.s8),
                  const Icon(
                    LucideIcons.chevronRight,
                    size: 16,
                    color: AfColors.textDisabled,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class SettingsSwitchTile extends ConsumerWidget {
  const SettingsSwitchTile({
    super.key,
    required this.icon,
    this.iconColor,
    required this.title,
    this.subtitle,
    required this.value,
    required this.onChanged,
  });
  final IconData icon;
  final Color? iconColor;
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spectral = ref.watch(
      currentSpectralProvider.select((s) => s.primary),
    );
    final effectiveIconColor = iconColor ?? spectral;
    return Semantics(
      label: title,
      toggled: value,
      button: true,
      child: PressScale(
        onTap: () => onChanged(!value),
        ensureHitTarget: true,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: AfSpacing.minHitTarget),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AfSpacing.s16,
              vertical: AfSpacing.s12,
            ),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: const BoxDecoration(
                    color: AfColors.surfaceHigh,
                    borderRadius: AfRadii.borderSm,
                  ),
                  child: Icon(icon, size: 16, color: effectiveIconColor),
                ),
                const SizedBox(width: AfSpacing.s12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(title, style: AfTypography.bodyMedium),
                      if (subtitle != null)
                        Padding(
                          padding: const EdgeInsets.only(top: AfSpacing.s2),
                          child: Text(
                            subtitle!,
                            style: AfTypography.bodySmall.copyWith(
                              color: AfColors.textTertiary,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: AfSpacing.s8),
                Switch.adaptive(
                  value: value,
                  onChanged: onChanged,
                  activeThumbColor: AfColors.textOnPrimary,
                  activeTrackColor: spectral,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Collapsible Section ──────────────────────────────────────────────────────

/// A collapsible section for the settings screen.
///
/// Renders a tappable header with title, chevron indicator, and optional
/// trailing widget. The child content animates open/closed using the
/// standard Aetherfin motion tokens.
class AfCollapsibleSection extends StatefulWidget {
  const AfCollapsibleSection({
    super.key,
    required this.title,
    required this.child,
    this.initiallyExpanded = true,
    this.trailing,
  });

  final String title;
  final Widget child;
  final bool initiallyExpanded;
  final Widget? trailing;

  @override
  State<AfCollapsibleSection> createState() => _AfCollapsibleSectionState();
}

class _AfCollapsibleSectionState extends State<AfCollapsibleSection>
    with SingleTickerProviderStateMixin {
  late bool _expanded;
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _expanded = widget.initiallyExpanded;
    _controller = AnimationController(
      vsync: this,
      duration: AfDurations.standard,
    );
    _animation = CurvedAnimation(
      parent: _controller,
      curve: AfCurves.easeStandard,
    );
    if (_expanded) {
      _controller.value = 1;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() {
      _expanded = !_expanded;
      if (_expanded) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Header ─────────────────────────────────────────────────────
        PressScale(
          onTap: _toggle,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AfSpacing.s16,
              vertical: AfSpacing.s12,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.title.toUpperCase(),
                    style: AfTypography.label.copyWith(
                      color: AfColors.textSecondary,
                    ),
                  ),
                ),
                if (widget.trailing != null) ...[
                  widget.trailing!,
                  const SizedBox(width: AfSpacing.s8),
                ],
                AnimatedRotation(
                  turns: _expanded ? 0.5 : 0,
                  duration: AfDurations.standard,
                  curve: AfCurves.easeStandard,
                  child: const Icon(
                    LucideIcons.chevronDown,
                    size: 16,
                    color: AfColors.textTertiary,
                  ),
                ),
              ],
            ),
          ),
        ),
        // ── Collapsible content ────────────────────────────────────────
        ClipRect(
          child: AnimatedBuilder(
            animation: _animation,
            builder: (context, child) {
              return Align(
                alignment: Alignment.topCenter,
                heightFactor: _animation.value,
                child: child,
              );
            },
            child: widget.child,
          ),
        ),
        // ── Bottom divider ─────────────────────────────────────────────
        const Divider(height: 1, thickness: 0.5, color: AfColors.surfaceHigh),
      ],
    );
  }
}

// ── Option Tile ──────────────────────────────────────────────────────────────

class OptionTile extends ConsumerWidget {
  const OptionTile({
    super.key,
    required this.label,
    this.subtitle,
    required this.isActive,
    required this.onTap,
  });
  final String label;
  final String? subtitle;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spectral = ref.watch(
      currentSpectralProvider.select((s) => s.primary),
    );
    return Semantics(
      label: label,
      button: true,
      child: PressScale(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AfSpacing.gutterGenerous,
            vertical: AfSpacing.s12,
          ),
          child: Row(
            children: [
              Container(
                width: 3,
                height: subtitle != null ? 28 : 20,
                decoration: BoxDecoration(
                  color: isActive ? spectral : AfColors.transparent,
                  borderRadius: AfRadii.borderXs,
                ),
              ),
              const SizedBox(width: AfSpacing.s12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      style: AfTypography.bodyMedium.copyWith(
                        color: isActive ? spectral : AfColors.textPrimary,
                        fontWeight: isActive
                            ? FontWeight.w600
                            : FontWeight.w400,
                      ),
                    ),
                    if (subtitle != null)
                      Padding(
                        padding: const EdgeInsets.only(top: AfSpacing.s2),
                        child: Text(
                          subtitle!,
                          style: AfTypography.bodySmall.copyWith(
                            color: AfColors.textTertiary,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
