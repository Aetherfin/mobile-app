import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../state/providers.dart';

/// Navigates to the artist page for [artistId] if non-null.
///
/// When [artistId] is null (e.g. tracks played from search where the server
/// did not return an artist ID), falls back to a backend search by [artistName]
/// and navigates to the first exact-match artist page found. If no artist is
/// found, opens the search screen pre-filled with [artistName] as a last resort.
///
/// Shows a brief snackbar while the async lookup is in-flight so the user
/// gets tactile feedback immediately on tap.
Future<void> navigateToArtist(
  BuildContext context,
  WidgetRef ref, {
  required String? artistId,
  required String artistName,
}) async {
  if (!context.mounted) return;

  // Fast path — we have the artist ID already.
  if (artistId != null && artistId.isNotEmpty) {
    unawaited(context.push('/artist/$artistId'));
    return;
  }

  if (artistName.isEmpty) return;

  // Slow path — look up the artist by name via backend search.
  final backend = ref.read(musicBackendProvider);
  if (backend == null) {
    // No backend (local mode etc.) — open search as last resort.
    if (context.mounted) {
      unawaited(context.push('/search?q=${Uri.encodeComponent(artistName)}'));
    }
    return;
  }

  // Show a quick snackbar so the user knows we're loading.
  unawaited(
    ScaffoldMessenger.of(context)
        .showSnackBar(
          SnackBar(
            content: Text('Looking up $artistName…'),
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        )
        .closed,
  );

  try {
    final results = await backend.search(artistName);
    if (!context.mounted) return;

    // Prefer an exact (case-insensitive) name match; fall back to first result.
    final nameLower = artistName.toLowerCase();
    final match = results.artists.firstWhere(
      (a) => a.name.toLowerCase() == nameLower,
      orElse: () => results.artists.isNotEmpty
          ? results.artists.first
          : throw StateError('no artists'),
    );

    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    if (context.mounted) {
      unawaited(context.push('/artist/${match.id}'));
    }
  } catch (_) {
    // Backend search failed or returned no artists → open search screen.
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    if (context.mounted) {
      unawaited(
        context.push('/search?q=${Uri.encodeComponent(artistName)}'),
      );
    }
  }
}
