import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../design_tokens/tokens.dart';
import 'press_scale.dart';

const _navBg = Color(0xB30B0B14);

/// Google-style bottom navigation bar.
///
/// Per §7.7:
///   - 4 destinations only.
///   - 72dp height (excluding gesture inset).
///   - Active tab shows a colored pill background behind icon + label.
///   - Pill slides between tabs with 240ms `easeStandard` animation.
///   - Inactive tabs show icon only; label appears only on the active tab.
class AfBottomNavItem {
  const AfBottomNavItem({
    required this.icon,
    required this.filledIcon,
    required this.label,
  });
  final IconData icon;
  final IconData filledIcon;
  final String label;
}

class AfBottomNav extends ConsumerStatefulWidget {
  const AfBottomNav({
    super.key,
    required this.currentIndex,
    required this.onSelect,
    required this.items,
  });
  final int currentIndex;
  final ValueChanged<int> onSelect;
  final List<AfBottomNavItem> items;

  @override
  ConsumerState<AfBottomNav> createState() => _AfBottomNavState();
}

class _AfBottomNavState extends ConsumerState<AfBottomNav> {
  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom;

    return ClipRRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          decoration: const BoxDecoration(
            color: _navBg,
            border: Border(
              top: BorderSide(color: AfColors.surfaceLow, width: 1),
            ),
          ),
          padding: EdgeInsets.only(bottom: bottomInset),
          child: SizedBox(
            height: AfSpacing.bottomNavHeight,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: List.generate(
                widget.items.length,
                (i) => _buildTab(i, widget.items[i], i == widget.currentIndex),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTab(int index, AfBottomNavItem item, bool active) {
    return PressScale(
      ensureHitTarget: false,
      onTap: () => widget.onSelect(index),
      child: AnimatedContainer(
        duration: AfDurations.standard,
        curve: AfCurves.easeStandard,
        height: 48,
        padding: EdgeInsets.symmetric(horizontal: active ? 16 : 12),
        decoration: BoxDecoration(
          color: active
              ? AfColors.indigo500.withValues(alpha: 0.15)
              : Colors.transparent,
          borderRadius: AfRadii.borderPill,
          border: active
              ? Border.all(
                  color: AfColors.indigo400.withValues(alpha: 0.25),
                  width: 1,
                )
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedSwitcher(
              duration: AfDurations.instant,
              child: Icon(
                active ? item.filledIcon : item.icon,
                key: ValueKey(active),
                size: 24,
                color: active ? AfColors.textPrimary : AfColors.textTertiary,
              ),
            ),
            ClipRect(
              child: AnimatedAlign(
                duration: AfDurations.standard,
                curve: AfCurves.easeStandard,
                alignment: Alignment.centerLeft,
                widthFactor: active ? 1.0 : 0.0,
                child: Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: Text(
                    item.label,
                    maxLines: 1,
                    style: AfTypography.caption.copyWith(
                      color: AfColors.textPrimary,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
