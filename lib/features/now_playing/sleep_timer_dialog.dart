import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../design_tokens/tokens.dart';
import '../../state/providers.dart';
import '../sleep_timer/sleep_timer_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Sleep timer dialog content
// ─────────────────────────────────────────────────────────────────────────────

class SleepTimerDialogContent extends ConsumerStatefulWidget {
  const SleepTimerDialogContent({super.key, this.dismiss});
  final VoidCallback? dismiss;

  @override
  ConsumerState<SleepTimerDialogContent> createState() =>
      SleepTimerDialogContentState();
}

class SleepTimerDialogContentState
    extends ConsumerState<SleepTimerDialogContent> {
  static const _presets = [5, 10, 15, 30, 45, 60];
  int? _selectedMinutes;
  bool _showCustomInput = false;
  final _customController = TextEditingController();

  @override
  void initState() {
    super.initState();
    final activeTimer = ref.read(sleepTimerProvider);
    if (activeTimer != null) {
      final remaining = activeTimer.difference(DateTime.now());
      final isEndOfTrack = remaining.inMinutes > 120;
      if (isEndOfTrack) {
        _selectedMinutes = 0;
      } else {
        final mins = remaining.inMinutes;
        final closest = _presets.cast<int?>().firstWhere(
          (p) => (p! - mins).abs() <= 2,
          orElse: () => null,
        );
        _selectedMinutes = closest ?? mins;
      }
    }
  }

  @override
  void dispose() {
    _customController.dispose();
    super.dispose();
  }

  void _setTimer() {
    if (_selectedMinutes == null) return;
    if (_selectedMinutes == 0) {
      ref.read(sleepTimerProvider.notifier).state = DateTime.now().add(
        const Duration(days: 1),
      );
      ref.read(sleepTimerRemainingProvider.notifier).state = null;
    } else {
      final target = DateTime.now().add(Duration(minutes: _selectedMinutes!));
      ref.read(sleepTimerProvider.notifier).state = target;
      ref.read(sleepTimerRemainingProvider.notifier).state = Duration(
        minutes: _selectedMinutes!,
      );
    }
    if (widget.dismiss != null) {
      widget.dismiss!();
    } else {
      context.pop();
    }
  }

  void _cancelTimer() {
    ref.read(sleepTimerProvider.notifier).state = null;
    ref.read(sleepTimerRemainingProvider.notifier).state = null;
    if (widget.dismiss != null) {
      widget.dismiss!();
    } else {
      context.pop();
    }
  }

  void _applyCustom() {
    final text = _customController.text.trim();
    final mins = int.tryParse(text);
    if (mins == null || mins <= 0) return;
    setState(() {
      _selectedMinutes = mins;
      _showCustomInput = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final activeTimer = ref.watch(sleepTimerProvider);
    final isActive = activeTimer != null;
    final spectral = ref.watch(
      currentSpectralProvider.select((s) => s.primary),
    );

    return Padding(
      padding: const EdgeInsets.all(AfSpacing.gutterGenerous),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Sleep timer', style: AfTypography.titleSmall),
          const SizedBox(height: AfSpacing.s16),
          if (isActive) ...[
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AfSpacing.s12,
                vertical: AfSpacing.s8,
              ),
              decoration: BoxDecoration(
                color: spectral.withValues(alpha: 0.15),
                borderRadius: AfRadii.borderMd,
              ),
              child: Row(
                children: [
                  Icon(LucideIcons.moon, color: spectral, size: 18),
                  const SizedBox(width: AfSpacing.s8),
                  Expanded(
                    child: Text(
                      'Timer active',
                      style: AfTypography.bodySmall.copyWith(color: spectral),
                    ),
                  ),
                  TextButton(
                    onPressed: _cancelTimer,
                    child: Text(
                      'Cancel',
                      style: AfTypography.bodySmall.copyWith(
                        color: AfColors.semanticError,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AfSpacing.s16),
          ],
          Wrap(
            spacing: AfSpacing.s8,
            runSpacing: AfSpacing.s8,
            children: [
              for (final m in _presets)
                ChoiceChip(
                  label: Text('$m min'),
                  selected: _selectedMinutes == m,
                  onSelected: (_) => setState(() {
                    _selectedMinutes = m;
                    _showCustomInput = false;
                  }),
                  selectedColor: spectral,
                  backgroundColor: AfColors.surfaceRaised,
                  labelStyle: AfTypography.bodySmall.copyWith(
                    color: _selectedMinutes == m
                        ? AfColors.surfaceCanvas
                        : AfColors.textPrimary,
                  ),
                ),
              ChoiceChip(
                label: const Text('End of track'),
                selected: _selectedMinutes == 0,
                onSelected: (_) => setState(() {
                  _selectedMinutes = 0;
                  _showCustomInput = false;
                }),
                selectedColor: spectral,
                backgroundColor: AfColors.surfaceRaised,
                labelStyle: AfTypography.bodySmall.copyWith(
                  color: _selectedMinutes == 0
                      ? AfColors.surfaceCanvas
                      : AfColors.textPrimary,
                ),
              ),
              ChoiceChip(
                label: Text(
                  _showCustomInput ||
                          (_selectedMinutes != null &&
                              _selectedMinutes != 0 &&
                              !_presets.contains(_selectedMinutes))
                      ? '${_selectedMinutes ?? "?"} min'
                      : 'Custom',
                ),
                selected:
                    _showCustomInput ||
                    (_selectedMinutes != null &&
                        _selectedMinutes != 0 &&
                        !_presets.contains(_selectedMinutes)),
                onSelected: (_) => setState(() => _showCustomInput = true),
                selectedColor: spectral,
                backgroundColor: AfColors.surfaceRaised,
                labelStyle: AfTypography.bodySmall.copyWith(
                  color:
                      _showCustomInput ||
                          (_selectedMinutes != null &&
                              _selectedMinutes != 0 &&
                              !_presets.contains(_selectedMinutes))
                      ? AfColors.surfaceCanvas
                      : AfColors.textPrimary,
                ),
              ),
            ],
          ),
          if (_showCustomInput) ...[
            const SizedBox(height: AfSpacing.s16),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _customController,
                    autofocus: true,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Minutes',
                      hintText: 'Minutes',
                      isDense: true,
                    ),
                    onSubmitted: (_) => _applyCustom(),
                  ),
                ),
                const SizedBox(width: AfSpacing.s8),
                TextButton(onPressed: _applyCustom, child: const Text('Set')),
              ],
            ),
          ],
          const SizedBox(height: AfSpacing.s24),
          ElevatedButton(
            onPressed: _selectedMinutes == null ? null : _setTimer,
            child: Text(_selectedMinutes == null ? 'Pick a time' : 'Set timer'),
          ),
        ],
      ),
    );
  }
}
