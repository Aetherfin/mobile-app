import 'package:animate_do/animate_do.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_shaders_ui/flutter_shaders_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../design_tokens/tokens.dart';
import '../features/sleep_timer/sleep_timer_screen.dart';
import '../state/providers.dart';
import 'bottom_nav.dart';
import 'bottom_sheet.dart';
import 'mini_now_playing.dart';

// ── Media key intents ─────────────────────────────────────────────────────────

class _PlayPauseIntent extends Intent {
  const _PlayPauseIntent();
}

class _MediaNextIntent extends Intent {
  const _MediaNextIntent();
}

class _MediaPreviousIntent extends Intent {
  const _MediaPreviousIntent();
}

class _MediaStopIntent extends Intent {
  const _MediaStopIntent();
}

/// App shell — wraps every authed-app tab with the persistent 4-tab
/// bottom nav.
///
/// Design:
///   - Full-bleed gradient background: deep dark (#0A0A0A → #111111)
///   - Tab content with directional slide + fade (left/right based on nav direction)
///   - Sleep timer watcher (zero-sized, invisible)
///   - Bottom nav bar
///   - Keyboard shortcuts for media controls
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key, required this.shell});
  final StatefulNavigationShell shell;

  static final _allItems = [
    const AfBottomNavItem(icon: LucideIcons.home, label: 'Home'),
    const AfBottomNavItem(icon: LucideIcons.library, label: 'Library'),
    const AfBottomNavItem(icon: LucideIcons.listMusic, label: 'Playlists'),
    const AfBottomNavItem(icon: LucideIcons.user, label: 'Profile'),
  ];

  /// YT Music: 3 tabs — Home, Library (was Playlists), Profile.
  static final _ytItems = [
    const AfBottomNavItem(icon: LucideIcons.home, label: 'Home'),
    const AfBottomNavItem(icon: LucideIcons.library, label: 'Library'),
    const AfBottomNavItem(icon: LucideIcons.user, label: 'Profile'),
  ];

  // Maps YT Music nav index → shell branch index.
  static const _ytToBranch = [0, 2, 3];

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  @override
  Widget build(BuildContext context) {
    final mode = ref.watch(appModeProvider);
    final isYt = mode == AppMode.youtubeMusic;

    // Watch spectral for a dynamic accent on the bottom nav pill.
    final spectral = ref.watch(
      currentSpectralProvider.select(
        (s) => (shadow: s.shadow, energy: s.energy),
      ),
    );

    final svc = ref.read(playerServiceProvider);

    return Shortcuts(
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.mediaPlayPause): _PlayPauseIntent(),
        SingleActivator(LogicalKeyboardKey.mediaTrackNext): _MediaNextIntent(),
        SingleActivator(LogicalKeyboardKey.mediaTrackPrevious):
            _MediaPreviousIntent(),
        SingleActivator(LogicalKeyboardKey.mediaStop): _MediaStopIntent(),
        // Common keyboard equivalents
        SingleActivator(LogicalKeyboardKey.space): _PlayPauseIntent(),
        SingleActivator(LogicalKeyboardKey.mediaPlay): _PlayPauseIntent(),
        SingleActivator(LogicalKeyboardKey.mediaPause): _PlayPauseIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          _PlayPauseIntent: CallbackAction<_PlayPauseIntent>(
            onInvoke: (_) async {
              if (svc.isPlaying) {
                await svc.pause();
              } else {
                await svc.play();
              }
              return null;
            },
          ),
          _MediaNextIntent: CallbackAction<_MediaNextIntent>(
            onInvoke: (_) async {
              await svc.skipToNext();
              return null;
            },
          ),
          _MediaPreviousIntent: CallbackAction<_MediaPreviousIntent>(
            onInvoke: (_) async {
              await svc.skipToPrevious();
              return null;
            },
          ),
          _MediaStopIntent: CallbackAction<_MediaStopIntent>(
            onInvoke: (_) async {
              await svc.pause();
              return null;
            },
          ),
        },
        child: _buildScaffold(
          context,
          ref,
          isYt: isYt,
          shadow: spectral.shadow,
          energy: spectral.energy,
        ),
      ),
    );
  }

  Widget _buildScaffold(
    BuildContext context,
    WidgetRef ref, {
    required bool isYt,
    required Color shadow,
    required Color energy,
  }) {
    final bottomInset = MediaQuery.of(context).padding.bottom;
    final miniBottom = AfSpacing.bottomNavHeight + bottomInset + AfSpacing.s4;

    final newIndex = widget.shell.currentIndex;

    // Shell-level PopScope — controls predictive back for all shell tabs.
    // canPop: false → the shell itself never pops. System handles app exit
    // with the correct Android predictive back animation (shrink-to-home).
    // Non-root branches oscillate to Home before exit.
    return PopScope<Object?>(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        // Dismiss topmost blur sheet before any navigation.
        if (blurSheetCount.value > 0) {
          blurSheetDismiss.value?.call();
          return;
        }
        // Non-root branch → oscillate back to Home (branch 0).
        final currentIdx = widget.shell.currentIndex;
        if (currentIdx != 0) {
          widget.shell.goBranch(0);
        }
        // Root branch (Home) with no sub-routes: do nothing.
        // canPop is false, so the system will handle app exit.
      },
      child: Scaffold(
        backgroundColor: Colors.transparent,
        extendBody: true,
        body: Stack(
          fit: StackFit.expand,
          children: [
            // Full-bleed background — GPU shader (zero banding)
            Positioned.fill(
              child: WaveBackground(
                color1: shadow,
                color2: AfColors.surfaceCanvas,
                amplitude: 0.15,
                speed: 0.3,
              ),
            ),

            // Tab content — FadeInUp on tab change.
            // ExcludeFocus when a blur sheet is open to prevent
            // keyboard focus escaping behind the sheet.
            ValueListenableBuilder<int>(
              valueListenable: blurSheetCount,
              builder: (context, count, child) {
                return ExcludeFocus(excluding: count > 0, child: child!);
              },
              child: RepaintBoundary(
                child: FadeInUp(
                  key: ValueKey('shell-tab-$newIndex'),
                  duration: AfDurations.quick,
                  from: 10,
                  curve: AfCurves.easeEmphasized,
                  child: widget.shell,
                ),
              ),
            ),

            // Sleep timer watcher — zero-sized, invisible.
            const Positioned(
              key: ValueKey('sleep-timer-watcher'),
              width: 0,
              height: 0,
              child: SleepTimerWatcher(),
            ),

            // Mini now-playing — floating pill above bottom nav.
            // AnimatedSlide + AnimatedOpacity for expand/collapse.
            Positioned(
              left: 0,
              right: 0,
              bottom: miniBottom,
              child: MiniNowPlaying(
                isVisible: ref.watch(
                  currentTrackProvider.select((t) => t != null),
                ),
              ),
            ),
          ],
        ),
        bottomNavigationBar: AfBottomNav(
          currentIndex: isYt
              ? AppShell._ytToBranch.indexOf(widget.shell.currentIndex)
              : widget.shell.currentIndex,
          onSelect: (i) {
            if (isYt) {
              widget.shell.goBranch(AppShell._ytToBranch[i]);
            } else {
              widget.shell.goBranch(i);
            }
          },
          items: isYt ? AppShell._ytItems : AppShell._allItems,
          accentColor: energy,
        ),
      ),
    );
  }
}
