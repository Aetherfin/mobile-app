import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../design_tokens/tokens.dart';
import '../state/providers.dart';
import 'press_scale.dart';

/// Custom bottom navigation bar — Dark Moody edition.
///
/// Four tabs: Home, Library, Playlists, Profile.
///   - True black background (AfColors.surfaceCanvas) with subtle top border.
///   - Active tab: warm amber accent pill background.
///   - Icons: Lucide icons, warm inactive color (textTertiary), white active.
///   - Height: 64dp.
///   - Animated pill slides between tabs with easeStandard.
///   - Inactive: icon only; Active: icon + label.
class AfBottomNavItem {
  const AfBottomNavItem({required this.icon, required this.label});
  final IconData icon;
  final String label;
}

class AfBottomNav extends ConsumerStatefulWidget {
  const AfBottomNav({
    super.key,
    required this.currentIndex,
    required this.onSelect,
    required this.items,
    this.accentColor,
  });
  final int currentIndex;
  final ValueChanged<int> onSelect;
  final List<AfBottomNavItem> items;

  /// Pill accent color for the active tab. Defaults to warm amber.
  final Color? accentColor;

  @override
  ConsumerState<AfBottomNav> createState() => _AfBottomNavState();
}

class _AfBottomNavState extends ConsumerState<AfBottomNav>
    with TickerProviderStateMixin {
  static const double _pillAlpha = 0.22;

  late final AnimationController _springCtrl;
  late final Animation<double> _springAnim;

  @override
  void initState() {
    super.initState();
    _springCtrl = AnimationController(
      vsync: this,
      duration: AfDurations.standard,
    );
    _springAnim = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.2), weight: 40),
      TweenSequenceItem(tween: Tween(begin: 1.2, end: 1.0), weight: 60),
    ]).animate(CurvedAnimation(parent: _springCtrl, curve: AfCurves.easeOut));
  }

  @override
  void dispose() {
    _springCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom;
    final Color accent =
        widget.accentColor ??
        ref.watch(currentSpectralProvider.select((s) => s.primary));

    return Container(
      decoration: const BoxDecoration(
        color: AfColors.surfaceCanvas,
        border: Border(
          top: BorderSide(color: AfColors.glassBorderEmphasis, width: 1),
        ),
      ),
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SizedBox(
        height: AfSpacing.bottomNavHeight,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: List.generate(
            widget.items.length,
            (i) =>
                _buildTab(i, widget.items[i], i == widget.currentIndex, accent),
          ),
        ),
      ),
    );
  }

  Widget _buildTab(int index, AfBottomNavItem item, bool active, Color accent) {
    return Semantics(
      selected: active,
      button: true,
      label: item.label,
      child: FocusPressScale(
        ensureHitTarget: false,
        onTap: () {
          widget.onSelect(index);
          HapticFeedback.mediumImpact();
          _springCtrl.forward(from: 0);
        },
        child: Transform.scale(
          scale: active ? _springAnim.value : 1.0,
          child: AnimatedContainer(
            duration: AfDurations.quick,
            curve: AfCurves.easeStandard,
            height: AfSpacing.minHitTarget,
            padding: EdgeInsets.symmetric(
              horizontal: active ? AfSpacing.s16 : AfSpacing.s12,
            ),
            decoration: BoxDecoration(
              color: active
                  ? accent.withValues(alpha: _pillAlpha)
                  : Colors.transparent,
              borderRadius: AfRadii.borderPill,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedSwitcher(
                  duration: AfDurations.instant,
                  child: Icon(
                    item.icon,
                    key: ValueKey(active),
                    size: AfIconSizes.md,
                    color: active ? accent : AfColors.textTertiary,
                  ),
                ),
                ClipRect(
                  child: AnimatedAlign(
                    duration: AfDurations.quick,
                    curve: AfCurves.easeStandard,
                    alignment: Alignment.centerLeft,
                    widthFactor: active ? 1.0 : 0.0,
                    child: Padding(
                      padding: const EdgeInsets.only(left: AfSpacing.s4),
                      child: Text(
                        item.label,
                        maxLines: 1,
                        style: AfTypography.caption.copyWith(
                          color: accent,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
