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
import '../../widgets/stagger_reveal.dart';

/// Landing screen: server vs local mode selection.
///
/// Large serif "Aetherfin" title, tagline, two floating mode cards with
/// surfaceRaised background and accent border on hover.
class WelcomeScreen extends ConsumerWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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

          // Radial glow behind logo — warm amber tint
          Positioned(
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
                    spectral.withValues(alpha: 0.12),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),

          // Content
          SafeArea(
            child: Column(
              children: [
                const SizedBox(height: AfSpacing.s16),
                Center(
                  child: Text(
                    'Step 1',
                    style: AfTypography.caption.copyWith(
                      color: AfColors.textTertiary,
                    ),
                  ),
                ),
                const Spacer(flex: 2),

                // Logo + branding
                StaggerReveal(
                  children: [
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        color: AfColors.surfaceBase.withValues(alpha: 0.6),
                        borderRadius: AfRadii.borderRounded,
                        border: Border.all(
                          color: spectral.withValues(alpha: 0.3),
                        ),
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
                    const SizedBox(height: AfSpacing.s24),

                    // Serif "Aetherfin" title
                    Text(
                      'Aetherfin',
                      style: AfTypography.display.copyWith(
                        color: AfColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: AfSpacing.s12),
                    Text(
                      'Music. Your way.',
                      style: AfTypography.bodyLarge.copyWith(
                        color: AfColors.textSecondary,
                      ),
                    ),
                  ],
                ),

                const Spacer(flex: 3),

                // Floating mode cards
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AfSpacing.s24,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'How do you listen?',
                        style: AfTypography.titleSmall.copyWith(
                          color: AfColors.textSecondary,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: AfSpacing.s16),
                      _ModeCard(
                        icon: LucideIcons.smartphone,
                        title: 'Play local files',
                        subtitle: 'Music on your device',
                        onTap: () async {
                          ref.read(appModeProvider.notifier).set(AppMode.local);
                          await AppModeStore.save(AppMode.local);
                          if (context.mounted) {
                            await context.push('/onboarding/local-setup');
                            if (!context.mounted) return;
                          }
                        },
                      ),
                      const SizedBox(height: AfSpacing.s12),
                      _ModeCard(
                        icon: LucideIcons.play,
                        title: 'YouTube Music',
                        subtitle: 'Stream from YouTube catalog',
                        onTap: () async {
                          ref
                              .read(appModeProvider.notifier)
                              .set(AppMode.youtubeMusic);
                          await AppModeStore.save(AppMode.youtubeMusic);
                          if (context.mounted) {
                            context.go('/home');
                          }
                        },
                      ),
                      const SizedBox(height: AfSpacing.s12),
                      _ModeCard(
                        icon: LucideIcons.cloud,
                        title: 'Stream from server',
                        subtitle: 'Jellyfin or Navidrome',
                        onTap: () async {
                          await HapticFeedback.lightImpact();
                          ref
                              .read(appModeProvider.notifier)
                              .set(AppMode.server);
                          await AppModeStore.save(AppMode.server);
                          if (context.mounted) {
                            await context.push('/onboarding/discover');
                            if (!context.mounted) return;
                          }
                        },
                      ),
                    ],
                  ),
                ),
                SizedBox(height: bottomPadding + AfSpacing.s32),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ModeCard extends ConsumerWidget {
  const _ModeCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spectral = ref.watch(
      currentSpectralProvider.select((s) => s.primary),
    );
    return PressScale(
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
    );
  }
}
