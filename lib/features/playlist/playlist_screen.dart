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
import '../../widgets/af_dialog.dart';
import '../../widgets/af_scrollbar.dart';
import '../../widgets/async_error_view.dart';
import '../../widgets/press_scale.dart';
import '../../widgets/track_context_menu.dart';
import '../../widgets/track_row.dart';
import '../../widgets/skeletons/playlist_skeleton.dart';
import 'export_m3u_dialog.dart';
import 'playlist_list_screen.dart' show AbstractPlaylistCover;

class PlaylistScreen extends ConsumerStatefulWidget {
  const PlaylistScreen({super.key, required this.playlistId});
  final String playlistId;

  @override
  ConsumerState<PlaylistScreen> createState() => _PlaylistScreenState();
}

class _PlaylistScreenState extends ConsumerState<PlaylistScreen> {
  List<AfTrack>? _localTracks;

  @override
  Widget build(BuildContext context) {
    final detailAsync = ref.watch(playlistDetailProvider(widget.playlistId));
    final backend = ref.watch(musicBackendProvider);
    final activeTrack = ref.watch(currentTrackProvider);
    final activeId = activeTrack?.id;
    final isBuffering = ref.watch(isBufferingProvider);
    final activeAccent = ref.watch(currentSpectralProvider).energy;

    return Scaffold(
      backgroundColor: AfColors.surfaceCanvas,
      appBar: AppBar(
        backgroundColor: AfColors.surfaceCanvas,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(LucideIcons.arrowLeft, size: 20),
          onPressed: () => context.pop(),
        ),
        title: const Text(
          'PLAYLIST INDEX',
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: AfColors.textTertiary,
            letterSpacing: 1.0,
          ),
        ),
        centerTitle: true,
        actions: [
          if (backend != null)
            PopupMenuButton<_PlaylistAction>(
              icon: const Icon(LucideIcons.moreVertical, size: 20),
              color: AfColors.surfaceBase,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              onSelected: (action) =>
                  _handleAction(context, action, detailAsync.valueOrNull),
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: _PlaylistAction.rename,
                  child: ListTile(
                    leading: Icon(LucideIcons.edit3, size: 16),
                    title: Text('RENAME'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                const PopupMenuItem(
                  value: _PlaylistAction.exportM3U,
                  child: ListTile(
                    leading: Icon(LucideIcons.download, size: 16),
                    title: Text('EXPORT M3U'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                const PopupMenuItem(
                  value: _PlaylistAction.delete,
                  child: ListTile(
                    leading: Icon(
                      LucideIcons.trash2,
                      color: AfColors.semanticError,
                      size: 16,
                    ),
                    title: Text(
                      'DELETE',
                      style: TextStyle(color: AfColors.semanticError),
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
              child: CustomScrollView(
                physics: const ClampingScrollPhysics(),
                slivers: [
                  // Header
                  SliverToBoxAdapter(
                    child: _Header(pl: pl, tracks: tracks),
                  ),

                  // Action row
                  SliverToBoxAdapter(
                    child: _ActionRow(
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
                    child: SizedBox(height: AfSpacing.s24),
                  ),

                  // Track list — reorderable when signed in.
                  if (backend != null && tracks.isNotEmpty)
                    SliverToBoxAdapter(
                      child: ReorderableListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        padding: const EdgeInsets.symmetric(
                          horizontal: AfSpacing.s16,
                        ),
                        buildDefaultDragHandles: false,
                        itemCount: tracks.length,
                        onReorderItem: (oldIndex, newIndex) => _onReorder(
                          oldIndex,
                          newIndex,
                          tracks,
                          backend,
                          pl.id,
                        ),
                        itemBuilder: (context, i) {
                          final t = tracks[i];
                          final displayIdx = (i + 1).toString().padLeft(3, '0');
                          final isPlaying = t.id == activeId;

                          return Dismissible(
                            key: ValueKey('${t.id}-$i'),
                            direction: DismissDirection.endToStart,
                            background: Container(
                              alignment: Alignment.centerRight,
                              padding: const EdgeInsets.only(
                                right: AfSpacing.s16,
                              ),
                              color: AfColors.semanticError.withValues(
                                alpha: 0.15,
                              ),
                              child: const Icon(
                                LucideIcons.trash2,
                                color: AfColors.semanticError,
                                size: 20,
                              ),
                            ),
                            confirmDismiss: (_) =>
                                _confirmRemove(context, t.title),
                            onDismissed: (_) =>
                                _removeTrack(i, tracks, backend, pl.id),
                            child: Container(
                              key: ValueKey('container-${t.id}-$i'),
                              decoration: const BoxDecoration(
                                border: Border(
                                  bottom: BorderSide(
                                    color: AfColors.surfaceBase,
                                    width: 1,
                                  ),
                                ),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(vertical: 4),
                                child: Row(
                                  children: [
                                    // Three-digit serial
                                    SizedBox(
                                      width: 32,
                                      child: Text(
                                        displayIdx,
                                        style: TextStyle(
                                          fontFamily: 'monospace',
                                          fontSize: 10,
                                          fontWeight: FontWeight.w700,
                                          color: isPlaying ? AfColors.indigo400 : AfColors.textDisabled,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: TrackRow(
                                        track: t,
                                        isActive: isPlaying,
                                        isBuffering:
                                            isPlaying && isBuffering,
                                        activeAccent: activeAccent,
                                        onTap: () => ref
                                            .read(playActionsProvider)
                                            .playQueue(tracks, startIndex: i),
                                        onLongPress: () =>
                                            showTrackContextMenu(context, ref, t),
                                      ),
                                    ),
                                    ReorderableDragStartListener(
                                      index: i,
                                      child: const Padding(
                                        padding: EdgeInsets.symmetric(
                                          horizontal: AfSpacing.s8,
                                        ),
                                        child: Icon(
                                          LucideIcons.gripVertical,
                                          color: AfColors.textTertiary,
                                          size: 16,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    )
                  else
                    SliverFixedExtentList(
                      itemExtent: 68.0,
                      delegate: SliverChildBuilderDelegate(
                        childCount: tracks.length,
                        (context, i) {
                          final t = tracks[i];
                          final displayIdx = (i + 1).toString().padLeft(3, '0');
                          final isPlaying = t.id == activeId;

                          return Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AfSpacing.s16,
                            ),
                            child: Container(
                              decoration: const BoxDecoration(
                                border: Border(
                                  bottom: BorderSide(
                                    color: AfColors.surfaceBase,
                                    width: 1,
                                  ),
                                ),
                              ),
                              child: Row(
                                children: [
                                  // Three-digit serial
                                  SizedBox(
                                    width: 32,
                                    child: Text(
                                      displayIdx,
                                      style: TextStyle(
                                        fontFamily: 'monospace',
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700,
                                        color: isPlaying ? AfColors.indigo400 : AfColors.textDisabled,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: TrackRow(
                                      track: t,
                                      isActive: isPlaying,
                                      isBuffering: isPlaying && isBuffering,
                                      activeAccent: activeAccent,
                                      onTap: () => ref
                                          .read(playActionsProvider)
                                          .playQueue(tracks, startIndex: i),
                                      onLongPress: () =>
                                          showTrackContextMenu(context, ref, t),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),

                  const SliverToBoxAdapter(
                    child: SizedBox(height: AfSpacing.bottomInsetWithMiniAndNav),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

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

  Future<bool> _confirmRemove(BuildContext context, String title) async {
    return await showBlurDialog<bool>(
          context: context,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Remove track', style: AfTypography.titleMedium),
              const SizedBox(height: AfSpacing.s12),
              Text(
                'Remove "$title" from this playlist?',
                style: AfTypography.bodyMedium,
              ),
              const SizedBox(height: AfSpacing.s24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Cancel'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text(
                      'Remove',
                      style: TextStyle(color: AfColors.semanticError),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ) ??
        false;
  }

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
    } catch (e) {
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
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(displayError(e, prefix: 'Could not undo removal')),
          ),
        );
      }
    }
  }

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
        final newName = await _showRenameDialog(context, detail.playlist.name);
        if (newName == null || newName.isEmpty) return;
        try {
          await backend.renamePlaylist(widget.playlistId, newName);
          ref.invalidate(playlistDetailProvider(widget.playlistId));
          ref.invalidate(allPlaylistsProvider);
        } catch (e) {
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
        } catch (e) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(displayError(e, prefix: 'Could not export')),
              ),
            );
          }
        }

      case _PlaylistAction.delete:
        final confirmed = await showBlurDialog<bool>(
          context: context,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Delete playlist', style: AfTypography.titleMedium),
              const SizedBox(height: AfSpacing.s12),
              Text(
                'Delete "${detail.playlist.name}"? This cannot be undone.',
                style: AfTypography.bodyMedium,
              ),
              const SizedBox(height: AfSpacing.s24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Cancel'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text(
                      'Delete',
                      style: TextStyle(color: AfColors.semanticError),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
        if (confirmed != true) return;
        try {
          await backend.deletePlaylist(widget.playlistId);
          ref.invalidate(allPlaylistsProvider);
          if (context.mounted) context.pop();
        } catch (e) {
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

  Future<String?> _showRenameDialog(
    BuildContext context,
    String currentName,
  ) async {
    final ctl = TextEditingController(text: currentName);
    try {
      return await showBlurDialog<String>(
        context: context,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Rename playlist', style: AfTypography.titleMedium),
            const SizedBox(height: AfSpacing.s16),
            TextField(
              controller: ctl,
              autofocus: true,
              decoration: const InputDecoration(hintText: 'Playlist name'),
              onSubmitted: (v) => Navigator.pop(context, v),
            ),
            const SizedBox(height: AfSpacing.s24),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, ctl.text),
                  child: const Text('Rename'),
                ),
              ],
            ),
          ],
        ),
      );
    } finally {
      ctl.dispose();
    }
  }
}

enum _PlaylistAction { rename, exportM3U, delete }

// ── Sub-widgets ─────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  const _Header({required this.pl, required this.tracks});
  final AfPlaylist pl;
  final List<AfTrack> tracks;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AfSpacing.s16,
        AfSpacing.s16,
        AfSpacing.s16,
        AfSpacing.s24,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Generative playlist artwork with asymmetric borders
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(20),
                bottomRight: Radius.circular(20),
              ),
              border: Border.all(
                color: AfColors.surfaceHigh,
                width: 1.5,
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: AbstractPlaylistCover(seed: pl.id),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(
                    color: AfColors.surfaceBase,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: AfColors.surfaceHigh),
                  ),
                  child: Text(
                    'PL.ID // ${pl.id.substring(0, 4).toUpperCase()}',
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 8,
                      fontWeight: FontWeight.w700,
                      color: AfColors.indigo400,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  pl.name.toUpperCase(),
                  style: AfTypography.titleMedium.copyWith(
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.2,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 8),
                Text(
                  '${tracks.length} INDEXED TRACKS',
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 9,
                    color: AfColors.textTertiary,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.tracks,
    required this.onPlay,
    required this.onShuffle,
  });
  final List<AfTrack> tracks;
  final VoidCallback onPlay;
  final VoidCallback onShuffle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AfSpacing.s16),
      child: Row(
        children: [
          Expanded(
            child: PressScale(
              onTap: tracks.isEmpty ? null : onPlay,
              child: Container(
                height: 44,
                decoration: BoxDecoration(
                  color: AfColors.indigo600,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: AfColors.indigo500,
                    width: 1,
                  ),
                ),
                alignment: Alignment.center,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      LucideIcons.play,
                      color: AfColors.textOnPrimary,
                      size: 14,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'PLAY SET',
                      style: AfTypography.bodyMedium.copyWith(
                        color: AfColors.textOnPrimary,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.8,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: PressScale(
              onTap: tracks.isEmpty ? null : onShuffle,
              child: Container(
                height: 44,
                decoration: BoxDecoration(
                  color: AfColors.surfaceLow,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AfColors.surfaceHigh, width: 1.5),
                ),
                alignment: Alignment.center,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      LucideIcons.shuffle,
                      color: AfColors.textPrimary,
                      size: 14,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'SHUFFLE',
                      style: AfTypography.bodyMedium.copyWith(
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.8,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
