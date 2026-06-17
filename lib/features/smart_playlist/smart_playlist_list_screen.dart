import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/smart_playlist/smart_playlist_model.dart';
import '../../design_tokens/tokens.dart';
import '../../state/providers.dart';
import '../../widgets/af_dialog.dart';
import '../../widgets/async_error_view.dart';
import '../../widgets/skeletons/playlist_skeleton.dart';

/// Lists all user-created smart playlists — Dark Moody style.
class SmartPlaylistListScreen extends ConsumerWidget {
  const SmartPlaylistListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playlistsAsync = ref.watch(smartPlaylistsProvider);
    final spectral = ref.watch(
      currentSpectralProvider.select((s) => s.primary),
    );

    return Scaffold(
      backgroundColor: AfColors.surfaceCanvas,
      appBar: AppBar(
        backgroundColor: AfColors.surfaceCanvas,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(LucideIcons.arrowLeft),
          tooltip: 'Back',
          onPressed: () => context.pop(),
        ),
        title: Text('Smart Playlists', style: AfTypography.display),
        centerTitle: false,
        titleSpacing: 0,
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push('/smart-playlist/new'),
        backgroundColor: spectral,
        tooltip: 'Create smart playlist',
        child: const Icon(LucideIcons.plus, color: AfColors.surfaceCanvas),
      ),
      body: playlistsAsync.when(
        data: (playlists) => playlists.isEmpty
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        color: spectral.withValues(alpha: 0.08),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        LucideIcons.sparkles,
                        size: 36,
                        color: spectral,
                      ),
                    ),
                    const SizedBox(height: AfSpacing.s16),
                    Text(
                      'No smart playlists yet',
                      style: AfTypography.titleSmall,
                    ),
                    const SizedBox(height: AfSpacing.s4),
                    Text(
                      'Create rule-based playlists that update automatically',
                      style: AfTypography.bodySmall.copyWith(
                        color: AfColors.textTertiary,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              )
            : ListView(
                padding: const EdgeInsets.symmetric(
                  horizontal: AfSpacing.s16,
                  vertical: AfSpacing.s8,
                ),
                children: [
                  // Grouped card container
                  Container(
                    clipBehavior: Clip.antiAlias,
                    decoration: const BoxDecoration(
                      color: AfColors.surfaceBase,
                      borderRadius: AfRadii.borderLg,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (int i = 0; i < playlists.length; i++) ...[
                          _PlaylistTile(
                            playlist: playlists[i],
                            onTap: () => context.push(
                              '/smart-playlist/${playlists[i].id}',
                            ),
                            onDelete: () async {
                              final db = ref.read(smartPlaylistDbProvider);
                              await db.delete(playlists[i].id);
                              ref.invalidate(smartPlaylistsProvider);
                            },
                          ),
                          if (i < playlists.length - 1)
                            const Divider(
                              height: 0,
                              thickness: 0.5,
                              indent: 60,
                              color: AfColors.surfaceHigh,
                            ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: AfSpacing.s24),
                ],
              ),
        loading: () => const PlaylistSkeleton(),
        error: (e, _) => AsyncErrorView(
          label: 'Could not load smart playlists',
          error: e,
          onRetry: () => ref.invalidate(smartPlaylistsProvider),
        ),
      ),
    );
  }
}

class _PlaylistTile extends ConsumerWidget {
  const _PlaylistTile({
    required this.playlist,
    required this.onTap,
    required this.onDelete,
  });
  final SmartPlaylist playlist;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spectral = ref.watch(
      currentSpectralProvider.select((s) => s.primary),
    );
    return InkWell(
      onTap: onTap,
      onLongPress: () => _showDeleteDialog(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AfSpacing.s16,
          vertical: AfSpacing.s12,
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: spectral.withValues(alpha: 0.12),
                borderRadius: AfRadii.borderSm,
              ),
              child: Icon(LucideIcons.sparkles, size: 20, color: spectral),
            ),
            const SizedBox(width: AfSpacing.s12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(playlist.name, style: AfTypography.bodyMedium),
                  Padding(
                    padding: const EdgeInsets.only(top: AfSpacing.s2),
                    child: Text(
                      playlist.ruleSummary,
                      style: AfTypography.bodySmall.copyWith(
                        color: AfColors.textTertiary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
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
    );
  }

  void _showDeleteDialog(BuildContext context) {
    showBlurDialog<void>(
      context: context,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Delete "${playlist.name}"?', style: AfTypography.titleMedium),
          const SizedBox(height: AfSpacing.s12),
          Text('This action cannot be undone.', style: AfTypography.bodyMedium),
          const SizedBox(height: AfSpacing.s24),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  onDelete();
                },
                child: Text(
                  'Delete',
                  style: AfTypography.bodyMedium.copyWith(
                    color: AfColors.semanticError,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
