import 'dart:async' show unawaited;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:go_router/go_router.dart';

import 'package:cached_network_image/cached_network_image.dart';

import '../../../core/youtube/innertube_client.dart';
import '../../../utils/log.dart';
import '../../../widgets/af_loading_indicator.dart';
import '../../../core/youtube/youtube_auth.dart';
import '../../../core/youtube/youtube_home_content.dart';
import '../../../design_tokens/tokens.dart';
import '../../../state/youtube_music_providers.dart';

import '../../../widgets/press_scale.dart';
import 'youtube_section_widgets.dart';

/// Full YouTube Music home view — header, chips, dynamic sections.
///
/// Composed as a standalone widget so [HomeScreen] stays compact.
class YouTubeHomeView extends ConsumerStatefulWidget {
  const YouTubeHomeView({super.key, required this.scrollController});
  final ScrollController scrollController;

  @override
  ConsumerState<YouTubeHomeView> createState() => _YouTubeHomeViewState();
}

class _YouTubeHomeViewState extends ConsumerState<YouTubeHomeView> {
  bool _autoLoaded = false;

  void _checkAutoLoad(YouTubeHomeContent home) {
    if (_autoLoaded) return;
    if (home.continuation != null && home.sections.length < 5) {
      _autoLoaded = true;
      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted) {
          ref.read(youtubeHomeProvider.notifier).loadMore();
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final homeAsync = ref.watch(youtubeHomeProvider);
    return SafeArea(
      child: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(youtubeHomeProvider);
          await ref.read(youtubeHomeProvider.future);
        },
        color: AfColors.indigo300,
        backgroundColor: AfColors.surfaceBase,
        child: CustomScrollView(
          controller: widget.scrollController,
          physics: const AlwaysScrollableScrollPhysics(
            parent: ClampingScrollPhysics(),
          ),
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AfSpacing.s16,
                  AfSpacing.s8,
                  AfSpacing.s16,
                  AfSpacing.s16,
                ),
                child: Row(
                  children: [
                    ShaderMask(
                      shaderCallback: (bounds) => const LinearGradient(
                        colors: [Color(0xFFFF0000), Color(0xFFFF4444)],
                      ).createShader(bounds),
                      child: Text(
                        'YouTube Music',
                        style: AfTypography.display.copyWith(
                          color: AfColors.textPrimary,
                        ),
                      ),
                    ),
                    const Spacer(),
                    const YouTubeAccountButton(),
                    const SizedBox(width: AfSpacing.s8),
                    GlassSearchButton(onTap: () => context.push('/search')),
                  ],
                ),
              ),
            ),

            // Chips Row
            homeAsync.when(
              data: (home) {
                if (home.chips.isEmpty) {
                  return const SliverToBoxAdapter(child: SizedBox.shrink());
                }
                return SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: AfSpacing.s16),
                    child: YouTubeChipsRow(chips: home.chips),
                  ),
                );
              },
              loading: () => const SliverToBoxAdapter(child: SizedBox.shrink()),
              error: (_, _) =>
                  const SliverToBoxAdapter(child: SizedBox.shrink()),
            ),

            // Dynamic Home Sections
            homeAsync.when(
              data: (home) {
                _checkAutoLoad(home);
                if (home.sections.isEmpty) {
                  return SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.all(AfSpacing.s16),
                      child: Text(
                        'No sections found',
                        style: AfTypography.bodyMedium.copyWith(
                          color: AfColors.textTertiary,
                        ),
                      ),
                    ),
                  );
                }
                return SliverList(
                  delegate: SliverChildListDelegate([
                    for (final section in home.sections) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                          AfSpacing.s16,
                          AfSpacing.s4,
                          AfSpacing.s16,
                          AfSpacing.s2,
                        ),
                        child: Text(
                          section.title,
                          style: AfTypography.titleMedium,
                        ),
                      ),
                      if (section.items.isNotEmpty &&
                          section.items.every(
                            (item) => item.type == InnerTubeItemType.song,
                          ))
                        YouTubeSongGrid(items: section.items)
                      else
                        YouTubeHomeTileList(items: section.items),
                    ],
                  ]),
                );
              },
              loading: () => const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.all(AfSpacing.s32),
                  child: Center(child: AfLoadingIndicator()),
                ),
              ),
              error: (e, _) => SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(AfSpacing.s16),
                  child: Text(
                    'Couldn\u2019t load recommendations',
                    style: AfTypography.bodyMedium.copyWith(
                      color: AfColors.textTertiary,
                    ),
                  ),
                ),
              ),
            ),

            const SliverToBoxAdapter(
              child: SizedBox(height: AfSpacing.bottomInsetWithMiniAndNav),
            ),
          ],
        ),
      ),
    );
  }
}

/// Glass pill button for the search icon in the YouTube Music header.
class GlassSearchButton extends StatelessWidget {
  const GlassSearchButton({super.key, required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return FocusPressScale(
      ensureHitTarget: false,
      onTap: onTap,
      child: ClipRRect(
        borderRadius: AfRadii.borderPill,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            padding: const EdgeInsets.all(AfSpacing.s12),
            decoration: BoxDecoration(
              color: AfColors.glassFill,
              borderRadius: AfRadii.borderPill,
              border: Border.all(color: AfColors.glassFillStrong, width: 1),
            ),
            child: const Icon(
              LucideIcons.search,
              size: 18,
              color: AfColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

/// Horizontal chip selector for YouTube Music home categories.
class YouTubeChipsRow extends ConsumerWidget {
  const YouTubeChipsRow({super.key, required this.chips});
  final List<InnerTubeChip> chips;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedChip = ref.watch(youtubeSelectedChipProvider);
    return SizedBox(
      height: 48,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AfSpacing.s16),
        itemCount: chips.length,
        separatorBuilder: (_, _) => const SizedBox(width: AfSpacing.s8),
        itemBuilder: (context, index) {
          final chip = chips[index];
          final isSelected = selectedChip?.title == chip.title;
          return ChoiceChip(
            label: Text(
              chip.title,
              style: AfTypography.bodySmall.copyWith(
                color: isSelected
                    ? AfColors.surfaceCanvas
                    : AfColors.textPrimary,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
            selected: isSelected,
            selectedColor: AfColors.textOnPrimary,
            backgroundColor: AfColors.surfaceRaised,
            onSelected: (_) {
              if (isSelected) {
                ref.read(youtubeSelectedChipProvider.notifier).set(null);
                ref.read(youtubeHomeParamsProvider.notifier).set(null);
              } else {
                ref.read(youtubeSelectedChipProvider.notifier).set(chip);
                ref.read(youtubeHomeParamsProvider.notifier).set(chip.params);
              }
            },
          );
        },
      ),
    );
  }
}

/// Account/login button for YouTube Music header.
///
/// Shows a person icon when not logged in (tap to open login screen).
/// When logged in, shows the user's email initial as an avatar.
class YouTubeAccountButton extends ConsumerWidget {
  const YouTubeAccountButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(youtubeAuthProvider);
    final isLoggedIn = auth?.isValid == true;

    return FocusPressScale(
      ensureHitTarget: false,
      onTap: () {
        if (isLoggedIn) {
          _showAccountMenu(context, ref, auth!);
        } else {
          context.push('/onboarding/youtube-login');
        }
      },
      child: ClipOval(
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: isLoggedIn
                ? AfColors.indigo600
                : Colors.white.withValues(
                    alpha: 0.06,
                  ), // decorative avatar bg — not semantic
            shape: BoxShape.circle,
          ),
          child: isLoggedIn
              ? (auth!.profileUrl != null && auth.profileUrl!.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: auth.profileUrl!,
                        width: 32,
                        height: 32,
                        fit: BoxFit.cover,
                        placeholder: (context, url) => Center(
                          child: Text(
                            (auth.email.isNotEmpty ? auth.email[0] : 'Y')
                                .toUpperCase(),
                            style: AfTypography.bodyMedium.copyWith(
                              color: AfColors.textOnPrimary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        errorWidget: (context, url, error) => Center(
                          child: Text(
                            (auth.email.isNotEmpty ? auth.email[0] : 'Y')
                                .toUpperCase(),
                            style: AfTypography.bodyMedium.copyWith(
                              color: AfColors.textOnPrimary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      )
                    : Center(
                        child: Text(
                          (auth.email.isNotEmpty ? auth.email[0] : 'Y')
                              .toUpperCase(),
                          style: AfTypography.bodyMedium.copyWith(
                            color: AfColors.textOnPrimary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ))
              : const Icon(
                  LucideIcons.user,
                  size: 16,
                  color: AfColors.textSecondary,
                ),
        ),
      ),
    );
  }

  void _showAccountMenu(
    BuildContext context,
    WidgetRef ref,
    YouTubeAuthBundle auth,
  ) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AfColors.surfaceRaised,
        title: Text(
          auth.email.isNotEmpty ? auth.email : 'YouTube Music',
          style: AfTypography.bodyMedium.copyWith(color: AfColors.textPrimary),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (auth.displayName.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: AfSpacing.s8),
                child: Text(
                  auth.displayName,
                  style: AfTypography.bodySmall.copyWith(
                    color: AfColors.textSecondary,
                  ),
                ),
              ),
            Text(
              'Signed in',
              style: AfTypography.bodySmall.copyWith(
                color: AfColors.textTertiary,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () async {
              ctx.pop();
              // Clear WebView cookies so next login starts fresh.
              try {
                const channel = MethodChannel('aetherfin.youtube_auth');
                await channel.invokeMethod('clearCookies');
              } on Exception catch (e, stack) {
                afLog(
                  'error',
                  'YouTube cookie clear failed',
                  error: e,
                  stackTrace: stack,
                );
              }
              unawaited(ref.read(youtubeAuthProvider.notifier).clear());
              ref.invalidate(youtubeHomeProvider);
            },
            child: Text(
              'Sign out',
              style: TextStyle(color: Colors.red.shade300),
            ),
          ),
          TextButton(
            onPressed: () => ctx.pop(),
            child: const Text(
              'Close',
              style: TextStyle(color: AfColors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}
