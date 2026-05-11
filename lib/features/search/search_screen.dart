import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/audio/play_actions.dart';
import '../../core/jellyfin/models/items.dart';
import '../../design_tokens/tokens.dart';
import '../../state/providers.dart';
import '../../widgets/artwork.dart';
import '../../widgets/section_header.dart';
import '../../widgets/track_row.dart';
import 'ask_sheet.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _controller = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AfSpacing.s16,
              AfSpacing.s8,
              AfSpacing.s16,
              AfSpacing.s8,
            ),
            child: Text('Search', style: AfTypography.titleLarge),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AfSpacing.s16),
            child: TextField(
              controller: _controller,
              autofocus: false,
              decoration: const InputDecoration(
                hintText: 'Artists, albums, tracks…',
                prefixIcon: Icon(Icons.search_rounded),
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          const SizedBox(height: AfSpacing.s16),
          Expanded(
            child: _query.isEmpty
                ? _SearchIdleState(
                    onAskTap: () => AskSheet.show(context),
                  )
                : _LiveSearchResults(query: _query),
          ),
        ],
      ),
    );
  }
}

/// Live results panel — watches [searchProvider] so a flick of the
/// keyboard hits the Jellyfin server (`/Users/{id}/Items?searchTerm=`),
/// not `DemoLibrary`. Loading state is intentionally blank so the rapid
/// keystrokes don't trigger a spinner storm; an empty-result state has
/// its own message.
class _LiveSearchResults extends ConsumerWidget {
  final String query;
  const _LiveSearchResults({required this.query});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(searchProvider(query));
    return async.maybeWhen(
      data: (res) {
        final empty = res.tracks.isEmpty &&
            res.albums.isEmpty &&
            res.artists.isEmpty &&
            res.playlists.isEmpty;
        if (empty) {
          return Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AfSpacing.s16,
              vertical: AfSpacing.s24,
            ),
            child: Text(
              'No results for “$query”.',
              style: AfTypography.bodyMedium.copyWith(
                color: AfColors.textTertiary,
              ),
            ),
          );
        }
        return _SearchResults(
          tracks: res.tracks,
          albums: res.albums,
          artists: res.artists,
          playlists: res.playlists,
        );
      },
      error: (e, _) => Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AfSpacing.s16,
          vertical: AfSpacing.s24,
        ),
        child: Text(
          'Search failed: $e',
          style: AfTypography.bodySmall.copyWith(
            color: AfColors.semanticError,
          ),
        ),
      ),
      orElse: () => const SizedBox.shrink(),
    );
  }
}

/// Idle (empty query) panel. Genres come from `allGenresProvider` so
/// signed-in users see their real library, signed-out users see the
/// demo palette — single source of truth, no duplicated fallback.
class _SearchIdleState extends ConsumerWidget {
  final VoidCallback onAskTap;
  const _SearchIdleState({required this.onAskTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final genresAsync = ref.watch(allGenresProvider);
    final genres = genresAsync.maybeWhen(
      data: (g) => g,
      orElse: () => const <AfGenre>[],
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AfSpacing.s16),
      child: ListView(
        children: [
          SectionHeader(title: 'Genres', uppercase: true),
          const SizedBox(height: AfSpacing.s12),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: genres.length,
            gridDelegate:
                const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisExtent: 80,
              crossAxisSpacing: AfSpacing.s12,
              mainAxisSpacing: AfSpacing.s12,
            ),
            itemBuilder: (context, i) {
              final g = genres[i];
              final tint = Color(int.parse(
                  g.tint.replaceFirst('#', '0xFF')));
              return Container(
                decoration: BoxDecoration(
                  color: tint,
                  borderRadius: AfRadii.borderMd,
                ),
                padding: const EdgeInsets.all(AfSpacing.s12),
                alignment: Alignment.bottomLeft,
                child: Text(
                  g.name,
                  style: AfTypography.titleSmall.copyWith(
                    color: AfColors.textOnPrimary,
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: AfSpacing.s24),
          GestureDetector(
            onTap: onAskTap,
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AfSpacing.s16,
                vertical: AfSpacing.s12,
              ),
              decoration: BoxDecoration(
                color: AfColors.surfaceBase,
                borderRadius: AfRadii.borderPill,
                border: Border.all(
                    color: AfColors.surfaceHigh, width: 1),
              ),
              child: Row(
                children: [
                  const Icon(Icons.auto_awesome_rounded,
                      color: AfColors.indigo300, size: 20),
                  const SizedBox(width: AfSpacing.s12),
                  Expanded(
                    child: Text(
                      'Ask your library…',
                      style: AfTypography.bodyMedium.copyWith(
                        color: AfColors.textSecondary,
                      ),
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded,
                      color: AfColors.textTertiary),
                ],
              ),
            ),
          ),
          const SizedBox(height: AfSpacing.bottomInsetWithMiniAndNav),
        ],
      ),
    );
  }
}

class _SearchResults extends ConsumerWidget {
  final List<AfTrack> tracks;
  final List<AfAlbum> albums;
  final List<AfArtist> artists;
  final List<AfPlaylist> playlists;

  const _SearchResults({
    required this.tracks,
    required this.albums,
    required this.artists,
    required this.playlists,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AfSpacing.s16,
        0,
        AfSpacing.s16,
        AfSpacing.bottomInsetWithMiniAndNav,
      ),
      children: [
        if (tracks.isNotEmpty) ...[
          SectionHeader(title: 'Tracks', uppercase: true),
          const SizedBox(height: AfSpacing.s8),
          // Show up to 20 result rows (was 4) and tap any to play.
          // Tapping replaces the queue with the full set of search
          // results so the user can skip-next through them.
          for (var i = 0; i < tracks.length && i < 20; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: TrackRow(
                track: tracks[i],
                onTap: () => ref
                    .read(playActionsProvider)
                    .playQueue(tracks, startIndex: i),
              ),
            ),
          const SizedBox(height: AfSpacing.s16),
        ],
        if (albums.isNotEmpty) ...[
          SectionHeader(title: 'Albums', uppercase: true),
          const SizedBox(height: AfSpacing.s8),
          for (final a in albums.take(10))
            ListTile(
              leading: SizedBox(
                width: 44,
                height: 44,
                child: Artwork(
                  url: a.imageUrl,
                  size: 44,
                ),
              ),
              title: Text(a.name, style: AfTypography.bodyMedium),
              subtitle: Text(
                a.artistName,
                style: AfTypography.bodySmall.copyWith(
                  color: AfColors.textTertiary,
                ),
              ),
              tileColor: Colors.transparent,
              contentPadding: EdgeInsets.zero,
              onTap: () => context.push('/album/${a.id}'),
            ),
          const SizedBox(height: AfSpacing.s16),
        ],
        if (artists.isNotEmpty) ...[
          SectionHeader(title: 'Artists', uppercase: true),
          const SizedBox(height: AfSpacing.s8),
          for (final a in artists.take(10))
            ListTile(
              leading: CircleAvatar(
                radius: 22,
                backgroundColor: AfColors.indigo800,
                backgroundImage: a.imageUrl != null
                    ? NetworkImage(a.imageUrl!)
                    : null,
                child: a.imageUrl == null
                    ? Text(
                        a.name.isNotEmpty ? a.name.substring(0, 1) : '?',
                        style: AfTypography.titleSmall.copyWith(
                          color: AfColors.textOnPrimary,
                        ),
                      )
                    : null,
              ),
              title: Text(a.name, style: AfTypography.bodyMedium),
              subtitle: Text(
                a.statLine,
                style: AfTypography.bodySmall.copyWith(
                  color: AfColors.textTertiary,
                ),
              ),
              tileColor: Colors.transparent,
              contentPadding: EdgeInsets.zero,
              onTap: () => context.push('/artist/${a.id}'),
            ),
          const SizedBox(height: AfSpacing.s16),
        ],
        if (playlists.isNotEmpty) ...[
          SectionHeader(title: 'Playlists', uppercase: true),
          const SizedBox(height: AfSpacing.s8),
          for (final p in playlists.take(10))
            ListTile(
              leading: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  borderRadius: AfRadii.borderSm,
                  gradient: const LinearGradient(
                    colors: [AfColors.indigo700, AfColors.indigo900],
                  ),
                ),
                child: const Icon(Icons.playlist_play_rounded,
                    color: AfColors.indigo300),
              ),
              title: Text(p.name, style: AfTypography.bodyMedium),
              subtitle: Text(
                '${p.trackCount} tracks',
                style: AfTypography.bodySmall.copyWith(
                  color: AfColors.textTertiary,
                ),
              ),
              tileColor: Colors.transparent,
              contentPadding: EdgeInsets.zero,
              onTap: () => context.push('/playlist/${p.id}'),
            ),
        ],
      ],
    );
  }
}
