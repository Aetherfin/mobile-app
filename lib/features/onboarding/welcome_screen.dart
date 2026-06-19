import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_shaders_ui/flutter_shaders_ui.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/local/app_mode_store.dart';
import '../../design_tokens/tokens.dart';
import '../../state/providers.dart';
import '../../utils/log.dart';
import '../../widgets/press_scale.dart';

/// Landing screen: server vs local mode selection.
///
/// Cinematic entrance choreography (1.2s) followed by living breath state.
class WelcomeScreen extends ConsumerStatefulWidget {
  const WelcomeScreen({super.key});

  @override
  ConsumerState<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends ConsumerState<WelcomeScreen>
    with TickerProviderStateMixin {
  // ponytail: breathing durations don't match any AfDurations tier
  static const _breathDuration = Duration(milliseconds: 4000);
  static const _glowBreathDuration = Duration(milliseconds: 3000);

  // Phase 1: Entrance choreography
  late final AnimationController _entranceCtrl; // 1200ms
  late final AnimationController _glowCtrl; // 800ms

  // Phase 2: Living breath
  late final AnimationController _breathCtrl; // 4000ms, repeat
  late final AnimationController _glowBreathCtrl; // 3000ms, repeat

  @override
  void initState() {
    super.initState();
    _entranceCtrl = AnimationController(
      vsync: this,
      duration: AfDurations.ambient,
    );
    _glowCtrl = AnimationController(
      vsync: this,
      duration: AfDurations.spectral,
    );
    _breathCtrl = AnimationController(vsync: this, duration: _breathDuration);
    _glowBreathCtrl = AnimationController(
      vsync: this,
      duration: _glowBreathDuration,
    );

    final reduced = WidgetsBinding
        .instance
        .platformDispatcher
        .accessibilityFeatures
        .disableAnimations;
    if (reduced) {
      _entranceCtrl.value = 1.0;
      _glowCtrl.value = 1.0;
      // No repeat animations for reduced motion
    } else {
      _breathCtrl.repeat(reverse: true);
      _glowBreathCtrl.repeat(reverse: true);
      _startEntrance();
    }
  }

  Future<void> _startEntrance() async {
    // Glow flash: 320ms peak, settles by 800ms
    await _glowCtrl.forward();
    // Glow flash complete, now run entrance choreography
    unawaited(_entranceCtrl.forward());
  }

  @override
  void dispose() {
    _entranceCtrl.dispose();
    _glowCtrl.dispose();
    _breathCtrl.dispose();
    _glowBreathCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    afLog('boot', 'WelcomeScreen.build');
    final bottomPadding = MediaQuery.paddingOf(context).bottom;
    final spectral = ref.watch(
      currentSpectralProvider.select((s) => s.primary),
    );

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Background — GPU shader
          const WaveBackground(
            color1: AfColors.surfaceCanvas,
            color2: AfColors.surfaceLow,
            amplitude: 0.1,
            speed: 0.2,
          ),

          // Radial glow — flash then breathing
          _buildGlow(spectral),

          // Content
          SafeArea(
            child: Column(
              children: [
                const Spacer(flex: 2),

                // Logo
                _buildLogo(spectral),

                const SizedBox(height: AfSpacing.s24),

                // Serif "Aetherfin" title
                _buildTitle(),

                const SizedBox(height: AfSpacing.s12),

                // Tagline
                _buildTagline(),

                const Spacer(flex: 3),

                // Floating mode cards
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AfSpacing.s24,
                  ),
                  child: _buildModeCards(spectral),
                ),
                SizedBox(height: bottomPadding + AfSpacing.s32),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Spectral glow: flash during entrance, breathing after
  // ---------------------------------------------------------------------------
  Widget _buildGlow(Color spectral) {
    return AnimatedBuilder(
      animation: Listenable.merge([_glowCtrl, _glowBreathCtrl]),
      builder: (context, child) {
        // Flash: peaks at 0.25 alpha then settles to 0.12
        final flashAlpha = TweenSequence<double>([
          TweenSequenceItem(tween: Tween(begin: 0.0, end: 0.25), weight: 40),
          TweenSequenceItem(tween: Tween(begin: 0.25, end: 0.12), weight: 60),
        ]).animate(_glowCtrl).value;

        // Breathing: oscillates ±0.02 around 0.12
        final breathAlpha = 0.12 + (_glowBreathCtrl.value - 0.5) * 0.04;

        // Use flash during entrance, breathing after
        final alpha = _glowCtrl.status == AnimationStatus.completed
            ? breathAlpha
            : flashAlpha;

        return Positioned(
          top: -80,
          left: 0,
          right: 0,
          height: 400,
          child: Container(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment.center,
                radius: 0.8,
                colors: [
                  spectral.withValues(alpha: alpha),
                  Colors.transparent,
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Logo: spring scale entrance + breathing oscillation
  // ---------------------------------------------------------------------------
  Widget _buildLogo(Color spectral) {
    return AnimatedBuilder(
      animation: Listenable.merge([_entranceCtrl, _breathCtrl]),
      builder: (context, child) {
        final entranceScale = CurvedAnimation(
          parent: _entranceCtrl,
          curve: AfCurves.springPresent,
        ).value;
        final breathScale = 1.0 + _breathCtrl.value * 0.02;
        return Transform.scale(
          scale: entranceScale * breathScale,
          child: child,
        );
      },
      child: Semantics(
        label: 'Aetherfin logo',
        child: Container(
          width: AfLayout.iconContainerLg,
          height: AfLayout.iconContainerLg,
          decoration: BoxDecoration(
            color: AfColors.surfaceBase.withValues(alpha: 0.6),
            borderRadius: AfRadii.borderRounded,
            border: Border.all(color: spectral.withValues(alpha: 0.3)),
            boxShadow: [
              BoxShadow(
                color: spectral.withValues(alpha: 0.15),
                blurRadius: 40,
                spreadRadius: 8,
              ),
            ],
          ),
          child: Center(
            child: SvgPicture.asset(
              'assets/brand/logo-mark.svg',
              width: 40,
              height: 40,
              colorFilter: const ColorFilter.mode(
                AfColors.textOnPrimary,
                BlendMode.srcIn,
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Title: fade in + slide up from 24dp (interval 0.25–0.65)
  // ---------------------------------------------------------------------------
  Widget _buildTitle() {
    return AnimatedBuilder(
      animation: _entranceCtrl,
      builder: (context, child) {
        final animation = CurvedAnimation(
          parent: _entranceCtrl,
          curve: const Interval(0.25, 0.65, curve: AfCurves.easeEmphasized),
        );
        final opacity = Tween<double>(
          begin: 0,
          end: 1,
        ).animate(animation).value;
        final slide = Tween<double>(begin: 24, end: 0).animate(animation).value;
        return Opacity(
          opacity: opacity.clamp(0.001, 0.999),
          child: Transform.translate(offset: Offset(0, slide), child: child),
        );
      },
      child: Text(
        'Aetherfin',
        style: AfTypography.display.copyWith(color: AfColors.textPrimary),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Tagline: fade in + slide up from 16dp (interval 0.35–0.75)
  // ---------------------------------------------------------------------------
  Widget _buildTagline() {
    return AnimatedBuilder(
      animation: _entranceCtrl,
      builder: (context, child) {
        final animation = CurvedAnimation(
          parent: _entranceCtrl,
          curve: const Interval(0.35, 0.75, curve: AfCurves.easeStandard),
        );
        final opacity = Tween<double>(
          begin: 0,
          end: 1,
        ).animate(animation).value;
        final slide = Tween<double>(begin: 16, end: 0).animate(animation).value;
        return Opacity(
          opacity: opacity.clamp(0.001, 0.999),
          child: Transform.translate(offset: Offset(0, slide), child: child),
        );
      },
      child: Text(
        'Music. Your way.',
        style: AfTypography.bodyLarge.copyWith(color: AfColors.textSecondary),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Mode cards: staggered entrance + breathing float
  // ---------------------------------------------------------------------------
  Widget _buildModeCards(Color spectral) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Label
        AnimatedBuilder(
          animation: _entranceCtrl,
          builder: (context, child) {
            final opacity = Tween<double>(begin: 0, end: 1)
                .animate(
                  CurvedAnimation(
                    parent: _entranceCtrl,
                    curve: const Interval(
                      0.50,
                      0.75,
                      curve: AfCurves.easeStandard,
                    ),
                  ),
                )
                .value;
            return Opacity(opacity: opacity.clamp(0.001, 0.999), child: child);
          },
          child: Text(
            'How do you listen?',
            style: AfTypography.titleSmall.copyWith(
              color: AfColors.textSecondary,
            ),
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: AfSpacing.s16),
        _AnimatedModeCard(
          entranceCtrl: _entranceCtrl,
          breathCtrl: _breathCtrl,
          staggerIndex: 0,
          icon: LucideIcons.smartphone,
          title: 'Play local files',
          subtitle: 'Music on your device',
          onTap: () async {
            ref.read(appModeProvider.notifier).set(AppMode.local);
            try {
              await AppModeStore.save(AppMode.local);
            } catch (e) {
              afLog('error', 'Failed to save app mode', error: e);
            }
            if (!mounted) return;
            await context.push('/onboarding/local-setup');
            if (!mounted) return;
          },
        ),
        const SizedBox(height: AfSpacing.s12),
        _AnimatedModeCard(
          entranceCtrl: _entranceCtrl,
          breathCtrl: _breathCtrl,
          staggerIndex: 1,
          icon: LucideIcons.play,
          title: 'YouTube Music',
          subtitle: 'Sign in with your Google account',
          onTap: () async {
            ref.read(appModeProvider.notifier).set(AppMode.youtubeMusic);
            try {
              await AppModeStore.save(AppMode.youtubeMusic);
            } catch (e) {
              afLog('error', 'Failed to save app mode', error: e);
            }
            if (!mounted) return;
            context.go('/home');
          },
        ),
        const SizedBox(height: AfSpacing.s12),
        _AnimatedModeCard(
          entranceCtrl: _entranceCtrl,
          breathCtrl: _breathCtrl,
          staggerIndex: 2,
          icon: LucideIcons.cloud,
          title: 'Stream from server',
          subtitle: 'Jellyfin or Navidrome',
          onTap: () async {
            await HapticFeedback.lightImpact();
            ref.read(appModeProvider.notifier).set(AppMode.server);
            try {
              await AppModeStore.save(AppMode.server);
            } catch (e) {
              afLog('error', 'Failed to save app mode', error: e);
            }
            if (!mounted) return;
            await context.push('/onboarding/discover');
            if (!mounted) return;
          },
        ),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// Animated mode card: staggered entrance + breathing float
// -----------------------------------------------------------------------------
class _AnimatedModeCard extends ConsumerWidget {
  const _AnimatedModeCard({
    required this.entranceCtrl,
    required this.breathCtrl,
    required this.staggerIndex,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final AnimationController entranceCtrl;
  final AnimationController breathCtrl;
  final int staggerIndex;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  // Stagger: 0.55, 0.63, 0.71 start times (80ms apart on 1200ms entrance)
  static const _entranceStarts = [0.55, 0.63, 0.71];
  static const _entranceEnd = 0.95;
  // Breathing: 0ms, 500ms, 1000ms offsets on 4000ms cycle
  static const _breathOffsets = [0.0, 500, 1000];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spectral = ref.watch(
      currentSpectralProvider.select((s) => s.primary),
    );

    return AnimatedBuilder(
      animation: Listenable.merge([entranceCtrl, breathCtrl]),
      builder: (context, child) {
        final start = _entranceStarts[staggerIndex.clamp(0, 2)];
        final entranceAnim = CurvedAnimation(
          parent: entranceCtrl,
          curve: Interval(start, _entranceEnd, curve: AfCurves.easeEmphasized),
        );
        final entranceOpacity = Tween<double>(
          begin: 0,
          end: 1,
        ).animate(entranceAnim).value;
        final entranceSlide = Tween<double>(
          begin: 16,
          end: 0,
        ).animate(entranceAnim).value;

        // Breathing float: sin wave offset
        final breathPhase =
            (breathCtrl.value +
                _breathOffsets[staggerIndex.clamp(0, 2)] / 4000.0) %
            1.0;
        final breathOffset = sin(breathPhase * 2 * pi) * 2;

        return Opacity(
          opacity: entranceOpacity.clamp(0.001, 0.999),
          child: Transform.translate(
            offset: Offset(0, entranceSlide + breathOffset),
            child: child,
          ),
        );
      },
      child: PressScale(
        onTap: onTap,
        child: AnimatedContainer(
          duration: AfDurations.quick,
          curve: AfCurves.easeStandard,
          padding: const EdgeInsets.all(AfSpacing.s16),
          decoration: BoxDecoration(
            color: AfColors.surfaceRaised,
            borderRadius: AfRadii.borderLg,
            border: Border.all(color: AfColors.surfaceHigh, width: 1),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: spectral.withValues(alpha: 0.15),
                  borderRadius: AfRadii.borderMd,
                ),
                child: Icon(icon, color: spectral, size: 24),
              ),
              const SizedBox(width: AfSpacing.s16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: AfTypography.titleSmall),
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
              const Icon(
                LucideIcons.chevronRight,
                color: AfColors.textTertiary,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
