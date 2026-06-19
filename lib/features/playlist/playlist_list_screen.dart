import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/jellyfin/models/items.dart';
import '../../design_tokens/tokens.dart';
import '../../state/providers.dart';
import '../../state/youtube_music_providers.dart';
import '../../widgets/async_error_view.dart';
import '../../widgets/press_scale.dart';
import '../../widgets/skeletons/playlist_skeleton.dart';
import '../../widgets/af_scrollbar.dart';
import '../../widgets/collapse_header.dart';
import '../../widgets/tile.dart';
import 'import_m3u_dialog.dart';

class PlaylistListScreen extends ConsumerWidget {
  const PlaylistListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(appModeProvider);
    final isYouTubeMusic = mode == AppMode.youtubeMusic;
    final ytAuth = isYouTubeMusic ? ref.watch(youtubeAuthProvider) : null;
    final isYtLoggedIn = ytAuth?.isValid == true;

    if (isYouTubeMusic && !isYtLoggedIn) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AfSpacing.s32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: ref
                      .watch(currentSpectralProvider.select((s) => s.primary))
                      .withValues(alpha: 0.1),
                ),
                child: Icon(
                  LucideIcons.music,
                  size: 36,
                  color: ref.watch(
                    currentSpectralProvider.select((s) => s.primary),
                  ),
                ),
              ),
              const SizedBox(height: AfSpacing.s24),
              Text(
                'Your YouTube Music library',
                style: AfTypography.titleMedium.copyWith(
                  color: AfColors.textPrimary,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AfSpacing.s8),
              Text(
                'Sign in to see your playlists',
                style: AfTypography.bodyMedium.copyWith(
                  color: AfColors.textTertiary,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AfSpacing.s24),
              PressScale(
                onTap: () => context.push('/onboarding/youtube-login'),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AfSpacing.s32,
                    vertical: AfSpacing.s16,
                  ),
                  decoration: BoxDecoration(
                    color: ref.watch(
                      currentSpectralProvider.select((s) => s.primary),
                    ),
                    borderRadius: AfRadii.borderPill,
                  ),
                  child: Text(
                    'Sign in with Google',
                    style: AfTypography.bodyMedium.copyWith(
                      color: AfColors.textOnPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final playlists = ref.watch(allPlaylistsProvider);
    final smartPlaylists = ref.watch(smartPlaylistsProvider);
    final smartCount = smartPlaylists.maybeWhen(
      data: (list) => list.length,
      orElse: () => 0,
    );
    final (:primary, :muted) = ref.watch(
      currentSpectralProvider.select(
        (s) => (primary: s.primary, muted: s.muted),
      ),
    );

    return SafeArea(
      child: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(allPlaylistsProvider);
          await ref.read(allPlaylistsProvider.future);
        },
        color: primary,
        backgroundColor: AfColors.surfaceBase,
        child: AfScrollbar(
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(
              parent: ClampingScrollPhysics(),
            ),
            slivers: [
              // ── Header ──────────────────────────────────────────────────
              SliverPersistentHeader(
                pinned: true,
                delegate: CollapseHeader(
                  title: 'Playlists',
                  spectral: (primary: primary, secondary: muted),
                  action: Tooltip(
                    message: 'Import M3U',
                    child: PressScale(
                      onTap: () => ref
                          .read(importM3UActionProvider)
                          .import(context: context),
                      child: Container(
                        width: AfSpacing.minHitTarget,
                        height: AfSpacing.minHitTarget,
                        decoration: BoxDecoration(
                          color: AfColors.glassFill,
                          borderRadius: AfRadii.borderPill,
                          border: Border.all(
                            color: AfColors.glassBorderStrong,
                            width: 1,
                          ),
                        ),
                        child: const Icon(
                          LucideIcons.listPlus,
                          color: AfColors.textSecondary,
                          size: 18,
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              // ── Playlist body ───────────────────────────────────────────
              ...playlists.when(
                data: (list) => _buildSlivers(
                  context,
                  ref,
                  list,
                  smartCount,
                  primary,
                  muted,
                ),
                loading: () => [
                  const SliverToBoxAdapter(child: PlaylistSkeleton()),
                ],
                error: (e, _) => [
                  SliverToBoxAdapter(
                    child: AsyncErrorView(
                      label: 'Couldn\u2019t load playlists',
                      error: e,
                      onRetry: () => ref.invalidate(allPlaylistsProvider),
                    ),
                  ),
                ],
              ),

              const SliverToBoxAdapter(
                child: SizedBox(height: AfSpacing.bottomInsetWithMiniAndNav),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildSlivers(
    BuildContext context,
    WidgetRef ref,
    List<AfPlaylist> list,
    int smartCount,
    Color primary,
    Color muted,
  ) {
    final slivers = <Widget>[];

    // ── Smart playlist shortcut ──────────────────────────────────────────
    if (smartCount > 0) {
      slivers.add(
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AfSpacing.s16,
              vertical: AfSpacing.s8,
            ),
            child: Text(
              'Smart Playlists',
              style: AfTypography.label.copyWith(color: AfColors.textSecondary),
            ),
          ),
        ),
      );
      slivers.add(
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AfSpacing.s16),
            child: _PlaylistCard(
              leading: _IconBadge(icon: LucideIcons.sparkles, tint: primary),
              title: 'Smart Playlists',
              subtitle: '$smartCount playlists',
              onTap: () => context.push('/smart-playlists'),
            ),
          ),
        ),
      );
      slivers.add(
        const SliverToBoxAdapter(child: SizedBox(height: AfSpacing.s12)),
      );
    }

    // ── User playlists ───────────────────────────────────────────────────
    if (list.isNotEmpty) {
      slivers.add(
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AfSpacing.s16,
              vertical: AfSpacing.s8,
            ),
            child: Text(
              'My Playlists',
              style: AfTypography.label.copyWith(color: AfColors.textSecondary),
            ),
          ),
        ),
      );
      slivers.add(
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: AfSpacing.s16),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: AfLayout.albumGridMaxTileExtent,
              mainAxisExtent: 240,
              crossAxisSpacing: AfSpacing.s16,
              mainAxisSpacing: AfSpacing.s16,
            ),
            delegate: SliverChildBuilderDelegate((context, i) {
              final p = list[i];
              return Tile(
                title: p.name,
                subtitle: p.trackCountLabel,
                variant: TileVariant.playlist,
                imageUrl: p.imageUrl,
                size: double.infinity,
                onTap: () => context.push('/playlist/${p.id}'),
              );
            }, childCount: list.length),
          ),
        ),
      );
    } else {
      // ── Empty state ────────────────────────────────────────────────────
      slivers.add(
        SliverFillRemaining(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: AfLayout.iconContainerMd,
                  height: AfLayout.iconContainerMd,
                  decoration: BoxDecoration(
                    color: primary.withValues(alpha: 0.08),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(LucideIcons.listMusic, color: muted, size: 36),
                ),
                const SizedBox(height: AfSpacing.s16),
                Text('No playlists yet', style: AfTypography.titleSmall),
                const SizedBox(height: AfSpacing.s4),
                Text(
                  'Create one or import an M3U file',
                  style: AfTypography.bodySmall.copyWith(
                    color: AfColors.textTertiary,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return slivers;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared sub-widgets
// ─────────────────────────────────────────────────────────────────────────────

class _PlaylistCard extends StatelessWidget {
  const _PlaylistCard({
    required this.leading,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final Widget leading;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '$title, $subtitle',
      child: Material(
        color: AfColors.surfaceRaised,
        borderRadius: AfRadii.borderMd,
        child: PressScale(
          onTap: onTap,
          child: InkWell(
            borderRadius: AfRadii.borderMd,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AfSpacing.s16,
                vertical: AfSpacing.s12,
              ),
              child: Row(
                children: [
                  leading,
                  const SizedBox(width: AfSpacing.s12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          title,
                          style: AfTypography.bodyMedium,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
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
                    color: AfColors.textDisabled,
                    size: 18,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _IconBadge extends StatelessWidget {
  const _IconBadge({required this.icon, required this.tint});
  final IconData icon;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.12),
        borderRadius: AfRadii.borderSm,
      ),
      child: Icon(icon, color: tint, size: 20),
    );
  }
}
