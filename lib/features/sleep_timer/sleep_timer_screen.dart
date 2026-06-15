import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../design_tokens/tokens.dart';
import '../../state/providers.dart';
import '../../widgets/press_scale.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Sleep timer state — lives in providers.dart scope so it survives
// navigation away from the sheet.
// ─────────────────────────────────────────────────────────────────────────────

/// The DateTime at which the player should pause. Null = no timer active.
final sleepTimerProvider = StateProvider<DateTime?>((ref) => null);

/// Remaining duration until the timer fires. Null when no timer is active.
/// Recomputed every second by [_SleepTimerScreenState].
final sleepTimerRemainingProvider = StateProvider<Duration?>((ref) => null);

// ─────────────────────────────────────────────────────────────────────────────
// Screen
// ─────────────────────────────────────────────────────────────────────────────

/// Sleep timer sheet — lets the user schedule an automatic pause.
///
/// Presets: 5 / 10 / 15 / 30 / 45 / 60 minutes, or "End of track"
/// (pauses when the current track finishes).
///
/// The timer fires in [_SleepTimerWatcher] which is mounted in the app
/// shell so it keeps ticking even when the sheet is closed.
class SleepTimerScreen extends ConsumerStatefulWidget {
  const SleepTimerScreen({super.key});

  @override
  ConsumerState<SleepTimerScreen> createState() => _SleepTimerScreenState();
}

class _SleepTimerScreenState extends ConsumerState<SleepTimerScreen> {
  int? _selectedMinutes; // null = nothing picked, 0 = end of track
  Timer? _countdownTimer;

  static const _presets = [5, 10, 15, 30, 45, 60];

  @override
  void initState() {
    super.initState();
    // If a timer is already active, pre-select the closest preset.
    final existing = ref.read(sleepTimerProvider);
    if (existing != null) {
      final remaining = existing.difference(DateTime.now());
      if (remaining.isNegative) {
        // Timer already fired — clear it.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          ref.read(sleepTimerProvider.notifier).state = null;
          ref.read(sleepTimerRemainingProvider.notifier).state = null;
        });
      }
    }
    _startCountdown();
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }

  void _startCountdown() {
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final target = ref.read(sleepTimerProvider);
      if (target == null) {
        ref.read(sleepTimerRemainingProvider.notifier).state = null;
        return;
      }
      final remaining = target.difference(DateTime.now());
      if (remaining.isNegative) {
        ref.read(sleepTimerProvider.notifier).state = null;
        ref.read(sleepTimerRemainingProvider.notifier).state = null;
      } else {
        ref.read(sleepTimerRemainingProvider.notifier).state = remaining;
      }
    });
  }

  void _setTimer() {
    if (_selectedMinutes == null) return;
    if (_selectedMinutes == 0) {
      // End of track — set a sentinel far in the future; the watcher
      // checks for track completion separately.
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
    Navigator.maybePop(context);
  }

  void _cancelTimer() {
    ref.read(sleepTimerProvider.notifier).state = null;
    ref.read(sleepTimerRemainingProvider.notifier).state = null;
    setState(() => _selectedMinutes = null);
  }

  String _formatRemaining(Duration d) {
    if (d.inSeconds <= 0) return '0:00';
    final m = d.inMinutes;
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final activeTimer = ref.watch(sleepTimerProvider);
    final remaining = ref.watch(sleepTimerRemainingProvider);
    final isEndOfTrack =
        activeTimer != null &&
        activeTimer.difference(DateTime.now()).inHours > 12;
    final isActive = activeTimer != null;
    final spectral = ref.watch(
      currentSpectralProvider.select(
        (s) => (primary: s.primary, muted: s.muted),
      ),
    );

    return Scaffold(
      backgroundColor: AfColors.surfaceCanvas,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(LucideIcons.x),
          tooltip: 'Close',
          onPressed: () => Navigator.maybePop(context),
        ),
        title: Text('Sleep timer', style: AfTypography.display),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AfSpacing.gutterGenerous,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: AfSpacing.s8),

              // Active timer status.
              if (isActive) ...[
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AfSpacing.s16,
                    vertical: AfSpacing.s12,
                  ),
                  decoration: BoxDecoration(
                    color: spectral.muted.withValues(alpha: 0.4),
                    borderRadius: AfRadii.borderMd,
                    border: Border.all(color: spectral.primary, width: 1),
                  ),
                  child: Row(
                    children: [
                      Icon(LucideIcons.moon, color: spectral.primary, size: 20),
                      const SizedBox(width: AfSpacing.s12),
                      Expanded(
                        child: Text(
                          isEndOfTrack
                              ? 'Pausing after current track'
                              : 'Pausing in ${remaining != null ? _formatRemaining(remaining) : '…'}',
                          style: AfTypography.bodyMedium.copyWith(
                            color: spectral.primary,
                          ),
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
                const SizedBox(height: AfSpacing.s24),
              ] else ...[
                Text(
                  'Pause playback after a set time.',
                  style: AfTypography.bodyMedium.copyWith(
                    color: AfColors.textSecondary,
                  ),
                ),
                const SizedBox(height: AfSpacing.s24),
              ],

              // Preset chips.
              Wrap(
                spacing: AfSpacing.s12,
                runSpacing: AfSpacing.s12,
                children: [
                  for (final m in _presets)
                    _TimerChip(
                      label: '$m min',
                      selected: _selectedMinutes == m,
                      onTap: () => setState(() => _selectedMinutes = m),
                      accentColor: spectral.primary,
                    ),
                  _TimerChip(
                    label: 'End of track',
                    selected: _selectedMinutes == 0,
                    onTap: () => setState(() => _selectedMinutes = 0),
                    accentColor: spectral.primary,
                  ),
                ],
              ),

              const Spacer(),

              ElevatedButton(
                onPressed: _selectedMinutes == null ? null : _setTimer,
                style: ElevatedButton.styleFrom(
                  backgroundColor: spectral.primary,
                  foregroundColor: AfColors.textOnPrimary,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AfSpacing.s24,
                    vertical: AfSpacing.s12,
                  ),
                  shape: const RoundedRectangleBorder(
                    borderRadius: AfRadii.borderPill,
                  ),
                ),
                child: Text(
                  _selectedMinutes == null ? 'Pick a time' : 'Set timer',
                ),
              ),
              const SizedBox(height: AfSpacing.s24),
            ],
          ),
        ),
      ),
    );
  }
}

/// Styled timer preset chip matching the design system pill shape.
class _TimerChip extends StatelessWidget {
  const _TimerChip({
    required this.label,
    required this.selected,
    required this.onTap,
    required this.accentColor,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    return PressScale(
      onTap: onTap,
      child: AnimatedContainer(
        duration: AfDurations.quick,
        curve: AfCurves.easeStandard,
        padding: const EdgeInsets.symmetric(
          horizontal: AfSpacing.s16,
          vertical: AfSpacing.s8,
        ),
        decoration: BoxDecoration(
          color: selected ? accentColor : AfColors.surfaceBase,
          borderRadius: AfRadii.borderPill,
          border: Border.all(
            color: selected ? accentColor : AfColors.surfaceHigh,
          ),
        ),
        child: Text(
          label,
          style: AfTypography.bodyMedium.copyWith(
            color: selected ? AfColors.textOnPrimary : AfColors.textPrimary,
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SleepTimerWatcher — mounts in AppShell, fires the actual pause
// ─────────────────────────────────────────────────────────────────────────────

/// Invisible widget that watches [sleepTimerProvider] and pauses the player
/// when the timer fires. Mount this once in [AppShell] so it stays alive
/// regardless of which screen is open.
class SleepTimerWatcher extends ConsumerStatefulWidget {
  const SleepTimerWatcher({super.key});

  @override
  ConsumerState<SleepTimerWatcher> createState() => _SleepTimerWatcherState();
}

class _SleepTimerWatcherState extends ConsumerState<SleepTimerWatcher> {
  Timer? _timer;

  /// ID of the track that was playing when an "end of track" timer
  /// was armed. Cleared when the timer is cancelled or fires.
  ///
  /// The watcher fires when the current track no longer matches this
  /// ID — that is the only signal that reliably catches both the
  /// auto-advance case (mpv jumps to the next track, `isPlaying`
  /// stays true) and the queue-end case (mpv stops, `isPlaying`
  /// flips false). The previous implementation only checked the
  /// queue-end case, so the timer silently failed for users with
  /// more than one track queued — the most common scenario.
  String? _endOfTrackAnchorId;

  @override
  void initState() {
    super.initState();
    // Only start the timer if one is already active (e.g. app restart
    // with a timer in progress). Otherwise wait for the provider to change.
    if (ref.read(sleepTimerProvider) != null) {
      _scheduleCheck();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _scheduleCheck() {
    _timer?.cancel();

    // Capture the track that's active when an "end of track" timer is
    // armed so we can detect when mpv moves on (auto-advance OR stop).
    final target = ref.read(sleepTimerProvider);
    if (target != null && target.difference(DateTime.now()).inHours > 12) {
      _endOfTrackAnchorId = ref.read(playerServiceProvider).currentTrack?.id;
    } else {
      _endOfTrackAnchorId = null;
    }

    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final target = ref.read(sleepTimerProvider);
      if (target == null) {
        _timer?.cancel();
        _endOfTrackAnchorId = null;
        // Defensive: clear stale remaining if the provider was already
        // null but the timer somehow ticked one last time.
        if (ref.read(sleepTimerRemainingProvider) != null) {
          ref.read(sleepTimerRemainingProvider.notifier).state = null;
        }
        return;
      }

      final isEndOfTrack = target.difference(DateTime.now()).inHours > 12;

      if (isEndOfTrack) {
        // "End of track" timers have no numeric countdown — surface
        // the special-case null so the badge can render the bedtime
        // icon without a label.
        if (ref.read(sleepTimerRemainingProvider) != null) {
          ref.read(sleepTimerRemainingProvider.notifier).state = null;
        }

        final svc = ref.read(playerServiceProvider);
        final current = svc.currentTrack;

        // Late-arming: timer was set with no active track. Adopt the
        // first track that starts as the anchor and wait for it to end.
        if (_endOfTrackAnchorId == null) {
          if (current != null) _endOfTrackAnchorId = current.id;
          return;
        }

        // Anchor changed (auto-advanced to next, queue ended, or user
        // skipped) — the song the user was listening to has finished.
        if (current == null || current.id != _endOfTrackAnchorId) {
          _fire();
          return;
        }
      } else {
        // Numeric timer — publish the remaining duration on every tick
        // so any surface watching `sleepTimerRemainingProvider` can
        // render a live countdown regardless of whether the sleep
        // timer sheet is open. Previously this only happened while the
        // sheet was visible, so the badge in Now Playing would freeze
        // the moment the user backed out.
        final remaining = target.difference(DateTime.now());
        if (remaining.isNegative || remaining.inSeconds <= 0) {
          _fire();
          return;
        }
        ref.read(sleepTimerRemainingProvider.notifier).state = remaining;
      }
    });
  }

  void _fire() {
    _timer?.cancel();
    _endOfTrackAnchorId = null;
    ref.read(sleepTimerProvider.notifier).state = null;
    ref.read(sleepTimerRemainingProvider.notifier).state = null;
    ref.read(playerServiceProvider).pause();
  }

  @override
  Widget build(BuildContext context) {
    // Start/stop the periodic timer based on whether a sleep timer is active.
    // This avoids waking the main isolate every second when no timer is set.
    ref.listen(sleepTimerProvider, (prev, next) {
      if (next != null) {
        _scheduleCheck();
      } else {
        _timer?.cancel();
        _endOfTrackAnchorId = null;
      }
    });
    return const SizedBox.shrink();
  }
}
