import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../design_tokens/tokens.dart';
import '../../state/providers.dart';

/// Final onboarding confirmation with checkmark animation and sync progress.
///
/// Shows "All set!" serif text, a checkmark scale+fade animation,
/// stats row (tracks/albums), and a "Start listening" button.
class AllSetScreen extends ConsumerStatefulWidget {
  const AllSetScreen({super.key});

  @override
  ConsumerState<AllSetScreen> createState() => _AllSetScreenState();
}

class _AllSetScreenState extends ConsumerState<AllSetScreen>
    with TickerProviderStateMixin {
  late final AnimationController _checkController = AnimationController(
    vsync: this,
    duration: AfDurations.expressive,
  );
  late final AnimationController _stagger = AnimationController(
    vsync: this,
    duration: AfDurations.long,
  );

  @override
  void initState() {
    super.initState();
    _checkController.forward();
    _stagger.forward();
  }

  @override
  void dispose() {
    _checkController.dispose();
    _stagger.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final spectral = ref.watch(
      currentSpectralProvider.select((s) => s.primary),
    );
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AfSpacing.gutterGenerous,
            vertical: AfSpacing.s24,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Text(
                  'Step 5 of 5',
                  style: AfTypography.caption.copyWith(
                    color: AfColors.textTertiary,
                  ),
                ),
              ),
              const Spacer(flex: 2),

              // Checkmark animation
              Center(
                child: ScaleTransition(
                  scale: CurvedAnimation(
                    parent: _checkController,
                    curve: AfCurves.easeEmphasized,
                  ),
                  child: FadeTransition(
                    opacity: _checkController,
                    child: Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        color: spectral.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: spectral.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Semantics(
                        label: 'Setup complete',
                        child: Icon(
                          LucideIcons.check,
                          size: 40,
                          color: spectral,
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: AfSpacing.s32),

              // "All set!" serif text
              Text(
                'All set!',
                style: AfTypography.display.copyWith(
                  color: AfColors.textPrimary,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AfSpacing.s8),
              Text(
                auth == null
                    ? 'Your library is ready.'
                    : 'Connected to ${auth.server.name}. Your library is ready.',
                style: AfTypography.bodyLarge.copyWith(
                  color: AfColors.textSecondary,
                ),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: AfSpacing.s32),

              // Stats row
              _StatRow(staggerAnimation: _stagger),

              const Spacer(flex: 2),

              // Sync progress indicator (shown while library is loading)
              const _SyncProgressIndicator(),

              const SizedBox(height: AfSpacing.s24),

              ElevatedButton(
                onPressed: () => context.go('/home'),
                child: const Text('Start listening'),
              ),
              const SizedBox(height: AfSpacing.s24),
            ],
          ),
        ),
      ),
    );
  }
}

/// Animated stat cards showing track/album counts with staggered reveal.
class _StatRow extends ConsumerWidget {
  const _StatRow({required this.staggerAnimation});
  final Animation<double> staggerAnimation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isLocal = ref.watch(appModeProvider) == AppMode.local;

    // ponytail: count-only — avoids loading all tracks
    final localTracksAsync = isLocal ? ref.watch(localTracksProvider) : null;
    final trackCountAsync = isLocal ? null : ref.watch(trackCountProvider);
    final albumsAsync = isLocal
        ? ref.watch(localAlbumsProvider)
        : ref.watch(allAlbumsProvider);

    final trackCount =
        localTracksAsync?.maybeWhen(
          data: (list) => list.length,
          orElse: () => 0,
        ) ??
        trackCountAsync?.maybeWhen(data: (count) => count, orElse: () => 0) ??
        0;
    final albumCount = albumsAsync.maybeWhen(
      data: (list) => list.length,
      orElse: () => 0,
    );

    final trackLoaded =
        (localTracksAsync != null && localTracksAsync is AsyncData) ||
        (trackCountAsync != null && trackCountAsync is AsyncData);
    final albumLoaded = albumsAsync is AsyncData;
    final primaryColor = ref.watch(
      currentSpectralProvider.select((s) => s.primary),
    );

    return AnimatedBuilder(
      animation: staggerAnimation,
      builder: (context, _) {
        final t = (staggerAnimation.value * 2).clamp(0.0, 1.0);
        return Opacity(
          opacity: t.clamp(0.001, 0.999),
          child: Transform.translate(
            offset: Offset(0, (1 - t) * 12),
            child: Row(
              children: [
                _Stat(
                  icon: LucideIcons.music,
                  label: 'Tracks',
                  value: trackLoaded ? '$trackCount' : '—',
                  loaded: trackLoaded,
                  primaryColor: primaryColor,
                ),
                const SizedBox(width: AfSpacing.s12),
                _Stat(
                  icon: LucideIcons.disc3,
                  label: 'Albums',
                  value: albumLoaded ? '$albumCount' : '—',
                  loaded: albumLoaded,
                  primaryColor: primaryColor,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Stat extends ConsumerWidget {
  const _Stat({
    required this.icon,
    required this.label,
    required this.value,
    required this.loaded,
    required this.primaryColor,
  });
  final IconData icon;
  final String label;
  final String value;
  final bool loaded;
  final Color primaryColor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(
          vertical: AfSpacing.s16,
          horizontal: AfSpacing.s12,
        ),
        decoration: BoxDecoration(
          color: AfColors.surfaceRaised,
          borderRadius: AfRadii.borderMd,
          border: Border.all(color: AfColors.surfaceHigh),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 16, color: primaryColor),
                const SizedBox(width: AfSpacing.s4),
                Text(
                  value,
                  style: AfTypography.titleLarge.copyWith(
                    color: loaded
                        ? AfColors.textPrimary
                        : AfColors.textDisabled,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AfSpacing.s2),
            Text(
              label,
              style: AfTypography.bodySmall.copyWith(
                color: AfColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shows a subtle progress indicator while library data is loading.
class _SyncProgressIndicator extends ConsumerWidget {
  const _SyncProgressIndicator();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isLocal = ref.watch(appModeProvider) == AppMode.local;
    final scanProgress = isLocal ? ref.watch(localScanProgressProvider) : null;
    final spectral = ref.watch(
      currentSpectralProvider.select((s) => s.primary),
    );

    // Show progress only during active scanning
    if (scanProgress == null) return const SizedBox.shrink();

    return Column(
      children: [
        LinearProgressIndicator(
          value: scanProgress.total > 0
              ? scanProgress.completed / scanProgress.total
              : null,
          backgroundColor: AfColors.surfaceHigh,
          valueColor: AlwaysStoppedAnimation(spectral),
          borderRadius: AfRadii.borderXs,
        ),
        const SizedBox(height: AfSpacing.s4),
        Text(
          scanProgress.total > 0
              ? 'Syncing library… ${scanProgress.completed}/${scanProgress.total}'
              : 'Syncing library…',
          style: AfTypography.bodySmall.copyWith(color: AfColors.textTertiary),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}
