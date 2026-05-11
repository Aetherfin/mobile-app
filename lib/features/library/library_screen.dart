import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../design_tokens/tokens.dart';
import '../../state/providers.dart';
import '../../widgets/tile.dart';
import '../../widgets/track_row.dart';

enum LibrarySection { albums, artists, songs, playlists, genres }

class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  LibrarySection _section = LibrarySection.albums;

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
            child: Row(
              children: [
                Text('Library', style: AfTypography.titleLarge),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.sort_rounded),
                  onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Sort coming soon'),
                      duration: Duration(seconds: 2),
                    ),
                  ),
                  tooltip: 'Sort',
                ),
              ],
            ),
          ),
          _SegmentedPill(
            value: _section,
            onChanged: (v) => setState(() => _section = v),
          ),
          const SizedBox(height: AfSpacing.s16),
          Expanded(
            child: _SectionBody(section: _section),
          ),
        ],
      ),
    );
  }
}

class _SegmentedPill extends StatelessWidget {
  final LibrarySection value;
  final ValueChanged<LibrarySection> onChanged;
  const _SegmentedPill({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AfSpacing.s16),
        itemCount: LibrarySection.values.length,
        separatorBuilder: (_, __) =>
            const SizedBox(width: AfSpacing.s8),
        itemBuilder: (context, i) {
          final s = LibrarySection.values[i];
          final selected = s == value;
          return GestureDetector(
            onTap: () => onChanged(s),
            child: AnimatedContainer(
              duration: AfDurations.quick,
              curve: AfCurves.easeStandard,
              padding: const EdgeInsets.symmetric(
                horizontal: AfSpacing.s16,
              ),
              decoration: BoxDecoration(
                color: selected
                    ? AfColors.indigo600
                    : AfColors.surfaceBase,
                borderRadius: AfRadii.borderPill,
              ),
              alignment: Alignment.center,
              child: Text(
                _label(s),
                style: AfTypography.bodyMedium.copyWith(
                  color: selected
                      ? AfColors.textOnPrimary
                      : AfColors.textSecondary,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  String _label(LibrarySection s) => switch (s) {
        LibrarySection.albums => 'Albums',
        LibrarySection.artists => 'Artists',
        LibrarySection.songs => 'Songs',
        LibrarySection.playlists => 'Playlists',
        LibrarySection.genres => 'Genres',
      };
}

class _SectionBody extends ConsumerWidget {
  final LibrarySection section;
  const _SectionBody({required this.section});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final padding = const EdgeInsets.symmetric(horizontal: AfSpacing.s16);
    switch (section) {
      case LibrarySection.albums:
        final albums = ref.watch(recentlyAddedAlbumsProvider);
        return albums.maybeWhen(
          data: (list) => GridView.builder(
            padding: padding.add(const EdgeInsets.only(
                bottom: AfSpacing.bottomInsetWithMiniAndNav)),
            itemCount: list.length,
            gridDelegate:
                const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisExtent: 220,
              crossAxisSpacing: AfSpacing.s16,
              mainAxisSpacing: AfSpacing.s16,
            ),
            itemBuilder: (context, i) {
              final a = list[i];
              return Tile(
                title: a.name,
                subtitle: a.artistName,
                variant: TileVariant.album,
                imageUrl: a.imageUrl,
                size: double.infinity,
                onTap: () => context.push('/album/${a.id}'),
              );
            },
          ),
          orElse: () => const Center(child: CircularProgressIndicator()),
        );
      case LibrarySection.artists:
        final artists = ref.watch(allArtistsProvider);
        return artists.maybeWhen(
          data: (list) => GridView.builder(
            padding: padding.add(const EdgeInsets.only(
                bottom: AfSpacing.bottomInsetWithMiniAndNav)),
            itemCount: list.length,
            gridDelegate:
                const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisExtent: 180,
              crossAxisSpacing: AfSpacing.s12,
              mainAxisSpacing: AfSpacing.s12,
            ),
            itemBuilder: (context, i) {
              final a = list[i];
              return Tile(
                title: a.name,
                subtitle: a.statLine,
                variant: TileVariant.artist,
                imageUrl: a.imageUrl,
                size: double.infinity,
                onTap: () => context.push('/artist/${a.id}'),
              );
            },
          ),
          orElse: () => const Center(child: CircularProgressIndicator()),
        );
      case LibrarySection.songs:
        return Consumer(builder: (context, ref, _) {
          final tracks = ref.watch(recentlyPlayedTracksProvider);
          return tracks.maybeWhen(
            data: (list) => ListView.separated(
              padding: padding.add(const EdgeInsets.only(
                  bottom: AfSpacing.bottomInsetWithMiniAndNav)),
              itemCount: list.length,
              separatorBuilder: (_, __) =>
                  const SizedBox(height: AfSpacing.s4),
              itemBuilder: (context, i) =>
                  TrackRow(track: list[i]),
            ),
            orElse: () => const Center(child: CircularProgressIndicator()),
          );
        });
      case LibrarySection.playlists:
        final playlists = ref.watch(allPlaylistsProvider);
        return playlists.maybeWhen(
          data: (list) => ListView.separated(
            padding: padding.add(const EdgeInsets.only(
                bottom: AfSpacing.bottomInsetWithMiniAndNav)),
            itemCount: list.length,
            separatorBuilder: (_, __) =>
                const SizedBox(height: AfSpacing.s8),
            itemBuilder: (context, i) {
              final p = list[i];
              return ListTile(
                leading: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    borderRadius: AfRadii.borderSm,
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [AfColors.indigo800, AfColors.indigo950],
                    ),
                  ),
                  child: const Icon(Icons.playlist_play_rounded,
                      color: AfColors.indigo300),
                ),
                title: Text(p.name, style: AfTypography.titleSmall),
                subtitle: Text(
                  '${p.trackCount} tracks',
                  style: AfTypography.bodySmall.copyWith(
                    color: AfColors.textTertiary,
                  ),
                ),
                tileColor: AfColors.surfaceBase,
                shape: const RoundedRectangleBorder(
                    borderRadius: AfRadii.borderMd),
              );
            },
          ),
          orElse: () => const Center(child: CircularProgressIndicator()),
        );
      case LibrarySection.genres:
        final genresAsync = ref.watch(allGenresProvider);
        return genresAsync.maybeWhen(
          data: (genres) => GridView.builder(
            padding: padding.add(const EdgeInsets.only(
                bottom: AfSpacing.bottomInsetWithMiniAndNav)),
            itemCount: genres.length,
            gridDelegate:
                const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisExtent: 96,
              crossAxisSpacing: AfSpacing.s12,
              mainAxisSpacing: AfSpacing.s12,
            ),
            itemBuilder: (context, i) {
              final g = genres[i];
              final tint = Color(int.parse(
                  g.tint.replaceFirst('#', '0xFF')));
              return GenreTile(
                name: g.name,
                tint: tint,
                width: double.infinity,
                height: double.infinity,
              );
            },
          ),
          orElse: () => const Center(child: CircularProgressIndicator()),
        );
    }
  }
}
