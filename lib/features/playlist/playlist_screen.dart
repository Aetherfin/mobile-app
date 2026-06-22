import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/audio/play_actions.dart';
import '../../core/backend/music_backend.dart';
import '../../core/jellyfin/models/items.dart';
import '../../design_tokens/tokens.dart';
import '../../state/providers.dart';
import '../../utils/display_error.dart';
import '../../utils/navigation.dart';
import '../../widgets/af_scrollbar.dart';
import '../../widgets/async_error_view.dart';
import '../../widgets/breadcrumb.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/track_context_menu.dart';
import '../../widgets/skeletons/playlist_skeleton.dart';
import 'export_m3u_dialog.dart';
import 'playlist_dialogs.dart';
import 'playlist_header.dart';
import 'playlist_track_list.dart';

/// Playlist detail screen with full management:
///   • Play / Shuffle
///   • Drag-to-reorder tracks
///   • Swipe-to-remove tracks
///   • Rename playlist (appbar action)
///   • Delete playlist (appbar action)
class PlaylistScreen extends ConsumerStatefulWidget {
  const PlaylistScreen({super.key, required this.playlistId});
  final String playlistId;

  @override
  ConsumerState<PlaylistScreen> createState() => _PlaylistScreenState();
}

class _PlaylistScreenState extends ConsumerState<PlaylistScreen> {
  /// Local mutable copy of the track list for optimistic reorder/remove.
  List<AfTrack>? _localTracks;

  @override
  Widget build(BuildContext context) {
    final detailAsync = ref.watch(playlistDetailProvider(widget.playlistId));
    final backend = ref.watch(musicBackendProvider);
    final activeTrack = ref.watch(currentTrackProvider);
    final activeId = activeTrack?.id;
    final isBuffering = ref.watch(isBufferingProvider);
    final playing = ref.watch(playingStreamProvider).value ?? false;
    final activeAccent = ref.watch(
      currentSpectralProvider.select((s) => s.energy),
    );
    final spectral = ref.watch(
      currentSpectralProvider.select((s) => s.primary),
    );

    return Scaffold(
      backgroundColor: AfColors.surfaceCanvas,
      appBar: AppBar(
        backgroundColor: AfColors.surfaceCanvas,
        leading: IconButton(
          icon: const Icon(LucideIcons.arrowLeft),
          tooltip: 'Back',
          onPressed: () => context.safePop(),
        ),
        title: Text('Playlist', style: AfTypography.titleSmall),
        actions: [
          if (backend != null)
            PopupMenuButton<_PlaylistAction>(
              icon: const Icon(LucideIcons.ellipsisVertical),
              tooltip: 'More options',
              onSelected: (action) =>
                  _handleAction(context, action, detailAsync.value),
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: _PlaylistAction.rename,
                  child: ListTile(
                    leading: Icon(LucideIcons.pencil, size: 20),
                    title: Text('Rename'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                const PopupMenuItem(
                  value: _PlaylistAction.exportM3U,
                  child: ListTile(
                    leading: Icon(LucideIcons.download, size: 20),
                    title: Text('Export M3U'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                PopupMenuItem(
                  value: _PlaylistAction.delete,
                  child: ListTile(
                    leading: const Icon(
                      LucideIcons.trash2,
                      color: AfColors.semanticError,
                      size: 20,
                    ),
                    title: Text(
                      'Delete playlist',
                      style: AfTypography.bodyMedium.copyWith(
                        color: AfColors.semanticError,
                      ),
                    ),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ],
            ),
        ],
      ),
      body: detailAsync.when(
        loading: () => const PlaylistSkeleton(),
        error: (e, _) => AsyncErrorView(
          label: 'Could not load playlist',
          error: e,
          onRetry: () =>
              ref.invalidate(playlistDetailProvider(widget.playlistId)),
        ),
        data: (detail) {
          if (detail == null) {
            return const Center(child: Text('Playlist not found'));
          }
          final pl = detail.playlist;
          final tracks = _localTracks ?? detail.tracks;

          return SafeArea(
            child: AfScrollbar(
              child: RefreshIndicator(
                onRefresh: () async {
                  if (mounted) setState(() => _localTracks = null);
                  ref.invalidate(playlistDetailProvider(widget.playlistId));
                  await ref.read(
                    playlistDetailProvider(widget.playlistId).future,
                  );
                },
                color: spectral,
                backgroundColor: AfColors.surfaceBase,
                child: CustomScrollView(
                  physics: const AlwaysScrollableScrollPhysics(
                    parent: ClampingScrollPhysics(),
                  ),
                  slivers: [
                    // Breadcrumb.
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.only(
                          top: AfSpacing.s16,
                          bottom: AfSpacing.s8,
                        ),
                        child: AfBreadcrumb(
                          items: [
                            BreadcrumbItem(
                              label: 'Playlists',
                              onTap: () => context.go('/playlists'),
                            ),
                            BreadcrumbItem(label: pl.name),
                          ],
                        ),
                      ),
                    ),

                    // Header.
                    SliverToBoxAdapter(
                      child: PlaylistHeader(
                        playlist: pl,
                        tracks: tracks,
                        primaryColor: spectral,
                      ),
                    ),

                    // Action row.
                    SliverToBoxAdapter(
                      child: PlaylistActionRow(
                        tracks: tracks,
                        onPlay: () =>
                            ref.read(playActionsProvider).playQueue(tracks),
                        onShuffle: () async {
                          await ref.read(playActionsProvider).playQueue(tracks);
                          await ref
                              .read(playerServiceProvider)
                              .setAfShuffleMode(true);
                        },
                      ),
                    ),

                    const SliverToBoxAdapter(
                      child: SizedBox(height: AfSpacing.s16),
                    ),

                    // Track list.
                    if (tracks.isNotEmpty)
                      SliverToBoxAdapter(
                        child: PlaylistTrackList(
                          tracks: tracks,
                          hasBackend: backend != null,
                          activeId: activeId,
                          isBuffering: isBuffering,
                          isPlaying: playing,
                          activeAccent: activeAccent,
                          spectral: spectral,
                          onReorder: (oldIndex, newIndex) => _onReorder(
                            oldIndex,
                            newIndex,
                            tracks,
                            backend!,
                            pl.id,
                          ),
                          confirmDismiss: (title) =>
                              confirmRemoveTrack(context, title),
                          onDismissed: (index) =>
                              _removeTrack(index, tracks, backend!, pl.id),
                          onTap: (index) => ref
                              .read(playActionsProvider)
                              .playQueue(tracks, startIndex: index),
                          onLongPress: (track) =>
                              showTrackContextMenu(context, ref, track),
                        ),
                      ),

                    if (tracks.isEmpty)
                      const SliverToBoxAdapter(
                        child: Padding(
                          padding: EdgeInsets.only(top: AfSpacing.s48),
                          child: EmptyState(
                            icon: LucideIcons.listMusic,
                            title: 'Empty playlist',
                            body: 'Add songs to get started',
                          ),
                        ),
                      ),

                    const SliverToBoxAdapter(
                      child: SizedBox(
                        height: AfSpacing.bottomInsetWithMiniAndNav,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // ── Reorder ────────────────────────────────────────────────────────────────

  void _onReorder(
    int oldIndex,
    int newIndex,
    List<AfTrack> tracks,
    MusicBackend client,
    String playlistId,
  ) {
    final updated = List<AfTrack>.from(tracks);
    final item = updated.removeAt(oldIndex);
    updated.insert(newIndex, item);
    setState(() => _localTracks = updated);

    client.movePlaylistItem(playlistId, item.id, newIndex).catchError((
      Object e,
    ) {
      if (mounted) {
        setState(() => _localTracks = tracks);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(displayError(e, prefix: 'Could not reorder'))),
        );
      }
    });
  }

  // ── Remove ─────────────────────────────────────────────────────────────────

  /// Remove a track from the playlist.
  ///
  /// Awaits the server call before invalidating providers so the refetch
  /// sees the updated list (not the pre-delete snapshot). Reverts the
  /// optimistic local state on failure.
  Future<void> _removeTrack(
    int index,
    List<AfTrack> tracks,
    MusicBackend client,
    String playlistId,
  ) async {
    final removed = tracks[index];
    final updated = List<AfTrack>.from(tracks)..removeAt(index);
    setState(() => _localTracks = updated);

    try {
      await client.removeFromPlaylist(playlistId, [removed.id]);

      ref
          .read(playlistUndoBufferProvider)
          .pushRemove(playlistId, [removed.id], [removed.id]);

      ref.invalidate(playlistDetailProvider(widget.playlistId));
      ref.invalidate(allPlaylistsProvider);

      if (mounted) {
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(
            SnackBar(
              content: Text('Removed "${removed.title}"'),
              action: SnackBarAction(
                label: 'Undo',
                onPressed: () => _undoRemove(playlistId, client),
              ),
            ),
          );
      }
    } on Exception catch (e) {
      if (mounted) {
        setState(() => _localTracks = tracks);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(displayError(e, prefix: 'Could not remove'))),
        );
      }
    }
  }

  Future<void> _undoRemove(String playlistId, MusicBackend client) async {
    final action = ref.read(playlistUndoBufferProvider).pop(playlistId);
    if (action == null) return;
    try {
      await client.addToPlaylist(playlistId, action.trackIds);
      ref.invalidate(playlistDetailProvider(playlistId));
      ref.invalidate(allPlaylistsProvider);
    } on Exception catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(displayError(e, prefix: 'Could not undo removal')),
          ),
        );
      }
    }
  }

  // ── Rename / Delete / Export ───────────────────────────────────────────────

  Future<void> _handleAction(
    BuildContext context,
    _PlaylistAction action,
    ({AfPlaylist playlist, List<AfTrack> tracks})? detail,
  ) async {
    if (detail == null) return;
    final backend = ref.read(musicBackendProvider);
    if (backend == null) return;

    switch (action) {
      case _PlaylistAction.rename:
        final newName = await showRenamePlaylistDialog(
          context,
          detail.playlist.name,
        );
        if (newName == null || newName.isEmpty) return;
        try {
          await backend.renamePlaylist(widget.playlistId, newName);
          ref.invalidate(playlistDetailProvider(widget.playlistId));
          ref.invalidate(allPlaylistsProvider);
        } on Exception catch (e) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(displayError(e, prefix: 'Could not rename')),
              ),
            );
          }
        }

      case _PlaylistAction.exportM3U:
        try {
          await ref
              .read(exportM3UActionProvider)
              .export(
                tracks: detail.tracks,
                playlistName: detail.playlist.name,
                context: context,
              );
        } on Exception catch (e) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(displayError(e, prefix: 'Could not export')),
              ),
            );
          }
        }

      case _PlaylistAction.delete:
        final confirmed = await confirmDeletePlaylist(
          context,
          detail.playlist.name,
        );
        if (!confirmed) return;
        try {
          await backend.deletePlaylist(widget.playlistId);
          ref.invalidate(allPlaylistsProvider);
          if (context.mounted) context.safePop();
        } on Exception catch (e) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(displayError(e, prefix: 'Could not delete')),
              ),
            );
          }
        }
    }
  }
}

enum _PlaylistAction { rename, exportM3U, delete }
