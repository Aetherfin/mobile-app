import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/backend/music_backend.dart';
import '../../core/jellyfin/models/items.dart';
import '../../core/youtube/youtube_music_client.dart';
import '../../design_tokens/tokens.dart';
import '../../state/providers.dart';
import '../../utils/display_error.dart';
import '../../utils/log.dart';
import '../../widgets/af_dialog.dart';

/// Prompts for a name and creates a new playlist containing every
/// track in [items]. The default name is "Queue · YYYY-MM-DD HH:mm"
/// so distinct saves never collide visually.
///
/// Works in both local and server modes — both backends implement
/// `MusicBackend.createPlaylist`. Returns silently when [items] is empty.
Future<void> saveQueueAsPlaylist(
  BuildContext context,
  WidgetRef ref,
  List<AfTrack> items,
) async {
  if (items.isEmpty) return;
  final backend = ref.read(musicBackendProvider);
  if (backend == null) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Sign in to save playlists')));
    return;
  }

  final now = DateTime.now();
  String two(int n) => n.toString().padLeft(2, '0');
  final defaultName =
      'Queue · ${now.year}-${two(now.month)}-${two(now.day)} '
      '${two(now.hour)}:${two(now.minute)}';
  final controller = TextEditingController(text: defaultName);
  final String? name;
  try {
    name = await showBlurDialog<String>(
      context: context,
      builder: (context, dismiss) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Save queue as playlist', style: AfTypography.titleMedium),
          const SizedBox(height: AfSpacing.s16),
          TextField(
            controller: controller,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Playlist name',
              hintText: 'Playlist name',
              border: OutlineInputBorder(
                borderRadius: AfRadii.borderSm,
                borderSide: BorderSide(color: AfColors.surfaceHigh),
              ),
            ),
            onSubmitted: (v) => dismiss(v.trim()),
          ),
          const SizedBox(height: AfSpacing.s24),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => dismiss(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => dismiss(controller.text.trim()),
                child: const Text('Save'),
              ),
            ],
          ),
        ],
      ),
    );
  } finally {
    controller.dispose();
  }

  if (name == null || name.isEmpty || !context.mounted) return;

  final snapshot = List<String>.from(items.map((t) => t.id));
  try {
    await backend.createPlaylist(name, snapshot);
    ref.invalidate(allPlaylistsProvider);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Saved as "$name" · ${snapshot.length} tracks')),
    );
  } on Exception catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(displayError(e, prefix: 'Failed to save queue'))),
    );
  }
}

/// Resolves which selected indices should be removed, mapping local list
/// indices to actual player-queue indices.
///
/// Skips the currently playing track (identified by [currentId]). Returns a
/// list of `(actualIndex, track)` pairs sorted descending by actualIndex so
/// that removals don't shift earlier indices.
///
/// This is used by the multi-select batch-remove flow in [QueueScreen].
List<(int actualIndex, AfTrack track)> resolveBatchRemoveTargets({
  required List<AfTrack> items,
  required Set<int> selectedIndices,
  required String? currentId,
  required List<AfTrack> playerQueue,
}) {
  if (selectedIndices.isEmpty) return const [];

  // Collect pairs of (local index, track) for valid selections.
  final pairs = <(int localIdx, AfTrack track)>[];
  for (final idx in selectedIndices) {
    if (idx < 0 || idx >= items.length) continue;
    final track = items[idx];
    if (track.id == currentId) continue; // skip playing track
    pairs.add((idx, track));
  }

  // Map local indices to actual player-queue indices.
  final targets = <(int actualIndex, AfTrack track)>[];
  for (final (_, track) in pairs) {
    final actualIndex = playerQueue.indexWhere((q) => q.id == track.id);
    if (actualIndex < 0) continue;
    targets.add((actualIndex, track));
  }

  // Sort descending by actualIndex so higher removals don't shift lower ones.
  targets.sort((a, b) => b.$1.compareTo(a.$1));
  return targets;
}

/// Returns the local-list indices to remove, excluding the currently
/// playing track. Indices are sorted descending for safe removal.
///
/// Used by [QueueScreen._batchRemoveSelected] to compute which items
/// to strip from the local list before calling the player service.
Set<int> localIndicesToRemove({
  required List<AfTrack> items,
  required Set<int> selectedIndices,
  required String? currentId,
}) {
  final result = <int>{};
  for (final idx in selectedIndices) {
    if (idx < 0 || idx >= items.length) continue;
    if (items[idx].id == currentId) continue; // skip playing track
    result.add(idx);
  }
  return result;
}

/// Resolve a stream URL for the track — used by undo-reinsert logic.
///
/// Handles local content URIs, YouTube Music, offline cache, and
/// standard server streaming.
Future<String> resolveTrackStreamUrl(
  AfTrack track, {
  required AppMode mode,
  required MusicBackend? backend,
  required WidgetRef ref,
}) async {
  if (mode == AppMode.local) return track.id;

  if (backend is YouTubeMusicClient) {
    try {
      return await backend.resolveStreamUrl(track.id);
    } on Exception catch (e) {
      afLog('audio', 'YouTube stream resolve failed', error: e);
      return 'about:blank';
    }
  }

  final cacheEnabled = ref.read(offlineCacheEnabledProvider);
  if (cacheEnabled) {
    final cache = ref.read(offlineCacheServiceProvider);
    final cachedUri = await cache.cachedFileUri(track.id);
    if (cachedUri != null) return cachedUri;
  }
  if (backend != null) {
    final maxBitrate = ref.read(maxBitrateProvider);
    return backend.trackStreamUrl(
      track.id,
      maxBitrateKbps: maxBitrate == 0 ? null : maxBitrate,
    );
  }
  return 'about:blank';
}
