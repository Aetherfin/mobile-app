import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/backend/music_backend.dart';
import '../core/jellyfin/models/items.dart';
import '../design_tokens/tokens.dart';
import '../state/providers.dart';
import '../utils/display_error.dart';
import '../utils/log.dart';
import '../widgets/skeletons/sheet_skeleton.dart';
import 'bottom_sheet.dart';

/// Shows the "Save to playlist" sheet for an arbitrary [AfTrack].
///
/// Lists the user's existing playlists, lets them add the track to one
/// in a single tap, or create-and-add a new playlist inline. Used by
/// the Now Playing utility row AND the long-press track context menu
/// so the user can save a song without having to play it first.
void showSaveToPlaylistSheet(
  BuildContext context,
  WidgetRef ref,
  AfTrack track,
) {
  final backend = ref.read(musicBackendProvider);
  if (backend == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Sign in to save to playlists')),
    );
    return;
  }
  HapticFeedback.mediumImpact();
  showBlurBottomSheet<void>(
    context: context,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 360, maxHeight: 480),
      child: SaveToPlaylistSheet(track: track, backend: backend),
    ),
  );
}

/// Inline list of existing playlists with an optional "New playlist"
/// row at the top. Invalidates providers internally via its own ref.
class SaveToPlaylistSheet extends ConsumerStatefulWidget {
  const SaveToPlaylistSheet({
    super.key,
    required this.track,
    required this.backend,
  });
  final AfTrack track;
  final MusicBackend backend;

  @override
  ConsumerState<SaveToPlaylistSheet> createState() =>
      _SaveToPlaylistSheetState();
}

class _SaveToPlaylistSheetState extends ConsumerState<SaveToPlaylistSheet> {
  List<AfPlaylist>? _playlists;
  bool _loading = true;
  bool _saving = false;
  String? _error;
  final _newNameCtl = TextEditingController();
  bool _showNewPlaylist = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _newNameCtl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final playlists = await widget.backend.playlists();
      if (mounted) {
        setState(() {
          _playlists = playlists;
          _loading = false;
        });
      }
    } on Exception catch (e) {
      if (mounted) {
        setState(() {
          _error = displayError(e);
          _loading = false;
        });
      }
    }
  }

  Future<void> _undoAdd(
    String playlistId,
    List<String> trackIds,
    MusicBackend backend,
  ) async {
    final action = ref.read(playlistUndoBufferProvider).pop(playlistId);
    if (action == null) return;
    try {
      await backend.removeFromPlaylist(playlistId, action.trackIds);
      _invalidate(playlistId: playlistId);
    } on Exception catch (e) {
      afLog('playlist', 'Undo remove from playlist failed', error: e);
    }
  }

  void _invalidate({String? playlistId}) {
    ref.invalidate(allPlaylistsProvider);
    ref.invalidate(playlistTrackIdsProvider);
    if (playlistId != null) {
      ref.invalidate(playlistDetailProvider(playlistId));
    }
  }

  void _onSaved() {
    ref
        .read(savedTrackIdsProvider.notifier)
        .update((ids) => {...ids, widget.track.id});
    ref.invalidate(playlistTrackIdsProvider);
  }

  Future<void> _addTo(AfPlaylist playlist) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await widget.backend.addToPlaylist(playlist.id, [widget.track.id]);

      ref.read(playlistUndoBufferProvider).pushAdd(playlist.id, [
        widget.track.id,
      ]);

      _invalidate(playlistId: playlist.id);
      _onSaved();
      if (mounted) {
        unawaited(Navigator.maybePop(context));
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(
            SnackBar(
              content: Text('Added to ${playlist.name}'),
              action: SnackBarAction(
                label: 'Undo',
                onPressed: () =>
                    _undoAdd(playlist.id, [widget.track.id], widget.backend),
              ),
            ),
          );
      }
    } on Exception catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(displayError(e, prefix: 'Failed'))),
        );
      }
    }
  }

  Future<void> _createAndAdd() async {
    if (_saving) return;
    final name = _newNameCtl.text.trim();
    if (name.isEmpty) return;
    setState(() => _saving = true);
    try {
      await widget.backend.createPlaylist(name, [widget.track.id]);
      _invalidate();
      _onSaved();
      if (mounted) {
        unawaited(Navigator.maybePop(context));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Created "$name" and added track')),
        );
      }
    } on Exception catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(displayError(e, prefix: 'Failed'))),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AfSpacing.gutterGenerous,
          ),
          child: Text('Save to playlist', style: AfTypography.titleSmall),
        ),
        const SizedBox(height: AfSpacing.s8),
        if (_loading)
          const Padding(
            padding: EdgeInsets.all(AfSpacing.s24),
            child: SheetSkeleton(),
          )
        else if (_error != null)
          Padding(
            padding: const EdgeInsets.all(AfSpacing.gutterGenerous),
            child: Column(
              children: [
                Text(
                  _error!,
                  style: AfTypography.bodySmall.copyWith(
                    color: AfColors.semanticError,
                  ),
                ),
                const SizedBox(height: AfSpacing.s12),
                TextButton(
                  onPressed: () {
                    setState(() {
                      _error = null;
                      _loading = true;
                    });
                    _load();
                  },
                  child: const Text('Retry'),
                ),
              ],
            ),
          )
        else ...[
          if (_showNewPlaylist)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AfSpacing.gutterGenerous,
                0,
                AfSpacing.gutterGenerous,
                AfSpacing.s8,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _newNameCtl,
                      autofocus: true,
                      decoration: const InputDecoration(
                        labelText: 'Playlist name',
                        hintText: 'Playlist name',
                      ),
                      onSubmitted: (_) => _createAndAdd(),
                    ),
                  ),
                  const SizedBox(width: AfSpacing.s8),
                  TextButton(
                    onPressed: _saving ? null : _createAndAdd,
                    child: const Text('Create'),
                  ),
                ],
              ),
            )
          else
            ListTile(
              leading: const Icon(
                LucideIcons.plus,
                color: AfColors.accentPrimary,
              ),
              title: Text(
                'New playlist',
                style: AfTypography.bodyMedium.copyWith(
                  color: AfColors.accentPrimary,
                ),
              ),
              onTap: () => setState(() => _showNewPlaylist = true),
            ),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 300),
            child: _playlists != null && _playlists!.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: AfSpacing.s24,
                      ),
                      child: Text(
                        'No playlists yet',
                        style: AfTypography.bodySmall.copyWith(
                          color: AfColors.textTertiary,
                        ),
                      ),
                    ),
                  )
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: _playlists?.length ?? 0,
                    itemBuilder: (context, i) {
                      final p = _playlists![i];
                      return ListTile(
                        key: ValueKey(p.id),
                        leading: const Icon(
                          LucideIcons.listMusic,
                          color: AfColors.accentPrimary,
                        ),
                        title: Text(p.name, style: AfTypography.bodyMedium),
                        subtitle: Text(
                          p.trackCountLabel,
                          style: AfTypography.bodySmall.copyWith(
                            color: AfColors.textTertiary,
                          ),
                        ),
                        onTap: _saving ? null : () => _addTo(p),
                      );
                    },
                  ),
          ),
        ],
        const SizedBox(height: AfSpacing.s12),
      ],
    );
  }
}
