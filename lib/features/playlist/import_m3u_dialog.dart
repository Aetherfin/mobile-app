import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/local/local_backend.dart';
import '../../core/local/m3u_parser.dart';
import '../../design_tokens/tokens.dart';
import '../../state/providers.dart';
import '../../utils/log.dart';
import '../../widgets/af_dialog.dart';

/// Service/Action to import an M3U playlist.
class ImportM3UAction {
  ImportM3UAction(this._ref);
  final Ref _ref;

  /// Open a paste dialog, parse the M3U content, resolve tracks,
  /// and create a new playlist.
  Future<void> import({required BuildContext context}) async {
    final controller = TextEditingController();
    final spectral = _ref.read(currentSpectralProvider);
    final content = await showBlurDialog<String>(
      context: context,
      builder: (context, dismiss) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Import M3U Playlist', style: AfTypography.titleMedium),
          const SizedBox(height: AfSpacing.s12),
          Text(
            'Paste M3U content below to import as a new playlist. '
            'Tracks will be resolved by ID or name search.',
            style: AfTypography.bodySmall.copyWith(
              color: AfColors.textTertiary,
            ),
          ),
          const SizedBox(height: AfSpacing.s16),
          Container(
            decoration: const BoxDecoration(
              color: AfColors.surfaceHigh,
              borderRadius: AfRadii.borderSm,
            ),
            child: TextField(
              controller: controller,
              maxLines: 8,
              style: AfTypography.bodyMedium,
              decoration: InputDecoration(
                labelText: 'M3U playlist data',
                hintText: '#EXTM3U\n#EXTINF:180,Artist - Title\n...',
                hintStyle: AfTypography.bodySmall.copyWith(
                  color: AfColors.textDisabled,
                ),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.all(AfSpacing.s12),
              ),
            ),
          ),
          const SizedBox(height: AfSpacing.s24),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => dismiss(),
                child: const Text('Cancel'),
              ),
              const SizedBox(width: AfSpacing.s8),
              FilledButton.icon(
                onPressed: () => dismiss(controller.text),
                icon: const Icon(LucideIcons.download, size: 18),
                label: const Text('Import'),
                style: FilledButton.styleFrom(
                  backgroundColor: spectral.primary,
                  foregroundColor: AfColors.surfaceCanvas,
                ),
              ),
            ],
          ),
        ],
      ),
    );
    controller.dispose();

    if (content == null || content.trim().isEmpty || !context.mounted) return;

    final parsed = M3uParser.parse(content);
    if (parsed.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No tracks found in M3U content')),
      );
      return;
    }

    final backend = _ref.read(musicBackendProvider);
    if (backend == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sign in to import playlists')),
      );
      return;
    }

    // Show loading dialog during resolution.
    if (!context.mounted) return;
    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => Center(
          child: SizedBox(
            width: 48,
            height: 48,
            child: CircularProgressIndicator(
              color: spectral.primary,
              strokeWidth: 2.5,
            ),
          ),
        ),
      ),
    );

    final resolved = <String>[];
    var failed = 0;

    for (final entry in parsed) {
      try {
        final aetherfinId = entry.tags['id'];
        // Try resolving by Aetherfin ID first
        if (aetherfinId != null) {
          if (backend is LocalBackend) {
            final track = await backend.db.trackById(aetherfinId);
            if (track != null) {
              resolved.add(track.id);
              continue;
            }
          } else {
            final details = await backend.trackDetails(aetherfinId);
            if (details != null) {
              resolved.add(details.track.id);
              continue;
            }
          }
        }

        // Fallback: search by title + artist
        final artist = entry.artist;
        final title = entry.title;
        final query =
            (artist != null &&
                artist.isNotEmpty &&
                title != null &&
                title.isNotEmpty)
            ? '$artist - $title'
            : (title ?? entry.path);
        final searchResult = await backend.search(query);
        if (searchResult.tracks.isNotEmpty) {
          resolved.add(searchResult.tracks.first.id);
        } else {
          failed++;
        }
      } catch (e, stack) {
        afLog(
          'error',
          'M3U import track resolution failed',
          error: e,
          stackTrace: stack,
        );
        failed++;
      }
    }

    // Dismiss loading dialog
    if (context.mounted) {
      Navigator.of(context).pop();
    }

    if (resolved.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not resolve any tracks in the M3U content'),
          ),
        );
      }
      return;
    }

    final playlistName =
        'Imported M3U (${DateTime.now().month}/${DateTime.now().day})';
    try {
      final playlistId = await backend.createPlaylist(playlistName, resolved);
      if (playlistId == null) throw Exception('Failed to create playlist');

      if (context.mounted) {
        _ref.invalidate(allPlaylistsProvider);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Imported ${resolved.length}/${parsed.length} tracks'
              '${failed > 0 ? '. $failed could not be found.' : ''}',
            ),
          ),
        );
      }
    } on Exception catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to create playlist: $e')),
        );
      }
    }
  }
}

/// Provider for ImportM3UAction.
final importM3UActionProvider = Provider<ImportM3UAction>(ImportM3UAction.new);
