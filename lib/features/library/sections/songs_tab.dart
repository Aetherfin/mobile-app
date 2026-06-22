import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/audio/play_actions.dart';
import '../../../core/jellyfin/models/items.dart';
import '../../../design_tokens/tokens.dart';
import '../../../state/providers.dart';
import '../../../widgets/async_error_view.dart';
import '../../../widgets/empty_state.dart';
import '../../../widgets/skeletons/library_skeleton.dart';
import '../../../widgets/track_context_menu.dart';
import '../../../widgets/track_row.dart';

/// Songs list — local mode (SQL) or server mode (paginated).
///
/// Returns sliver-compatible widgets for use inside a [CustomScrollView].
class SongsTab extends ConsumerWidget {
  const SongsTab({required this.isLocal, super.key});
  final bool isLocal;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeId = ref.watch(currentTrackProvider)?.id;
    // ponytail: isBuffering is a bool — no narrower select possible.
    // SliverChildBuilderDelegate rebuilds only visible items.
    final isBuffering = ref.watch(isBufferingProvider);
    final playing = ref.watch(playingStreamProvider).value ?? false;
    // ponytail: .select(s.energy) avoids full Spectral rebuilds.
    final accent = ref.watch(currentSpectralProvider.select((s) => s.energy));

    if (isLocal) {
      final tracks = ref.watch(localTracksProvider);
      return tracks.when(
        data: (list) =>
            _buildSliverList(list, activeId, isBuffering, playing, accent, ref),
        loading: () => const SliverToBoxAdapter(
          child: LibrarySkeleton(mode: LibrarySkeletonMode.songs),
        ),
        error: (e, _) => SliverToBoxAdapter(
          child: AsyncErrorView(
            label: 'Couldn\u2019t load songs',
            error: e,
            onRetry: () => ref.invalidate(localTracksProvider),
          ),
        ),
      );
    }

    final tracksState = ref.watch(tracksPaginationProvider);
    if (tracksState.error != null && tracksState.items.isEmpty) {
      return SliverToBoxAdapter(
        child: AsyncErrorView(
          label: 'Couldn\u2019t load songs',
          error: Exception(tracksState.error),
          onRetry: () =>
              ref.read(tracksPaginationProvider.notifier).loadFirstPage(),
        ),
      );
    }
    if (tracksState.items.isEmpty && tracksState.isLoadingMore) {
      return const SliverToBoxAdapter(
        child: Center(child: CircularProgressIndicator()),
      );
    }

    return _buildSliverList(
      tracksState.items,
      activeId,
      isBuffering,
      playing,
      accent,
      ref,
    );
  }

  Widget _buildSliverList(
    List<AfTrack> tracks,
    String? activeId,
    bool isBuffering,
    bool isPlaying,
    Color accent,
    WidgetRef ref,
  ) {
    if (tracks.isEmpty) {
      return const SliverToBoxAdapter(
        child: EmptyState(
          icon: LucideIcons.music,
          title: 'No songs yet',
          body: 'Songs from your library will appear here',
        ),
      );
    }

    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(
        AfSpacing.s8,
        0,
        AfSpacing.s8,
        AfSpacing.bottomInsetWithMiniAndNav,
      ),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate((context, i) {
          final t = tracks[i];
          return RepaintBoundary(
            child: Padding(
              padding: const EdgeInsets.only(bottom: AfSpacing.s4),
              child: Semantics(
                button: true,
                label: '${t.title} by ${t.artistName}',
                child: TrackRow(
                  track: t,
                  isActive: t.id == activeId,
                  isPlaying: t.id == activeId && isPlaying,
                  isBuffering: t.id == activeId && isBuffering,
                  activeAccent: accent,
                  onTap: () =>
                      ref.read(playActionsProvider).playSmartQueue(t, tracks),
                  onLongPress: () => showTrackContextMenu(context, ref, t),
                ),
              ),
            ),
          );
        }, childCount: tracks.length),
      ),
    );
  }
}
