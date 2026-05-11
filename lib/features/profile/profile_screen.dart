import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/jellyfin/models/items.dart';
import '../../design_tokens/tokens.dart';
import '../../state/providers.dart';
import '../../widgets/artwork.dart';
import '../../widgets/section_header.dart';

/// Mockup 09 — Profile.
///
/// Per non-negotiable §4.1: shows TRACKS and ALBUMS, never followers.
/// Jellyfin is personal; there is no "follower" concept.
///
/// Every section on this screen is now wired to a live Riverpod provider
/// instead of the previous hard-coded ("Skylark / Field Notes / Pinemoth
/// / Marrow Bay") demo strings:
///   • Stats        ← allAlbumsProvider.length + allTracksProvider.length
///   • Pinned       ← favoriteAlbumsProvider (falls back to recently-added)
///   • Playlists    ← allPlaylistsProvider
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    final name = auth?.userName ?? 'You';
    final serverName = auth?.server.name ?? 'Demo library';

    final tracksAsync = ref.watch(allTracksProvider);
    final albumsAsync = ref.watch(allAlbumsProvider);
    final favAlbumsAsync = ref.watch(favoriteAlbumsProvider);
    final recentAlbumsAsync = ref.watch(recentlyAddedAlbumsProvider);
    final playlistsAsync = ref.watch(allPlaylistsProvider);

    String fmtCount<T>(AsyncValue<List<T>> async) => async.maybeWhen(
          data: (list) => _fmt(list.length),
          orElse: () => '—',
        );

    // Favourites first, else most-recently-added so the row is never empty.
    final pinned = favAlbumsAsync.maybeWhen(
      data: (favs) => favs.isNotEmpty
          ? favs.take(8).toList()
          : recentAlbumsAsync.maybeWhen(
              data: (recent) => recent.take(8).toList(),
              orElse: () => const <AfAlbum>[],
            ),
      orElse: () => const <AfAlbum>[],
    );

    final playlists = playlistsAsync.maybeWhen(
      data: (list) => list,
      orElse: () => const <AfPlaylist>[],
    );

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: AfSpacing.s16),
        children: [
          const SizedBox(height: AfSpacing.s24),
          Center(
            child: Column(
              children: [
                CircleAvatar(
                  radius: 40,
                  backgroundColor: AfColors.indigo800,
                  child: Text(
                    name.isEmpty ? 'A' : name[0].toUpperCase(),
                    style: AfTypography.titleLarge.copyWith(
                      color: AfColors.textOnPrimary,
                    ),
                  ),
                ),
                const SizedBox(height: AfSpacing.s12),
                Text(name, style: AfTypography.titleLarge),
                const SizedBox(height: 2),
                Text(
                  serverName,
                  style: AfTypography.bodySmall
                      .copyWith(color: AfColors.textTertiary),
                ),
              ],
            ),
          ),
          const SizedBox(height: AfSpacing.s24),
          Row(
            children: [
              _StatCard(label: 'Tracks', value: fmtCount(tracksAsync)),
              const SizedBox(width: AfSpacing.s12),
              _StatCard(label: 'Albums', value: fmtCount(albumsAsync)),
            ],
          ),
          const SizedBox(height: AfSpacing.s24),
          SectionHeader(title: 'Pinned', uppercase: true),
          const SizedBox(height: AfSpacing.s8),
          _PinnedRow(albums: pinned),
          const SizedBox(height: AfSpacing.s24),
          SectionHeader(title: 'Playlists', uppercase: true),
          const SizedBox(height: AfSpacing.s8),
          if (playlists.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(
                vertical: AfSpacing.s16,
                horizontal: AfSpacing.s4,
              ),
              child: Text(
                playlistsAsync.isLoading
                    ? 'Loading playlists…'
                    : 'No playlists yet.',
                style: AfTypography.bodySmall
                    .copyWith(color: AfColors.textTertiary),
              ),
            )
          else
            for (final p in playlists)
              Padding(
                padding: const EdgeInsets.only(bottom: AfSpacing.s4),
                child: ListTile(
                  leading: const Icon(Icons.playlist_play_rounded,
                      color: AfColors.indigo300),
                  title: Text(p.name),
                  subtitle: Text(
                    '${p.trackCount} '
                    '${p.trackCount == 1 ? "track" : "tracks"}'
                    '${p.isPublic ? "  •  Public" : ""}',
                    style: AfTypography.bodySmall
                        .copyWith(color: AfColors.textTertiary),
                  ),
                  tileColor: AfColors.surfaceBase,
                  shape: const RoundedRectangleBorder(
                      borderRadius: AfRadii.borderMd),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: AfSpacing.s16),
                  onTap: () => context.push('/playlist/${p.id}'),
                ),
              ),
          const SizedBox(height: AfSpacing.s24),
          SectionHeader(title: 'Account', uppercase: true),
          const SizedBox(height: AfSpacing.s8),
          ListTile(
            leading: const Icon(Icons.settings_outlined),
            title: const Text('Settings'),
            tileColor: AfColors.surfaceBase,
            shape: const RoundedRectangleBorder(
                borderRadius: AfRadii.borderMd),
            onTap: () => context.push('/settings'),
          ),
          const SizedBox(height: AfSpacing.s8),
          ListTile(
            leading: const Icon(Icons.logout_rounded),
            title: const Text('Sign out'),
            tileColor: AfColors.surfaceBase,
            shape: const RoundedRectangleBorder(
                borderRadius: AfRadii.borderMd),
            onTap: () async {
              await ref.read(authProvider.notifier).clear();
              if (context.mounted) context.go('/');
            },
          ),
          const SizedBox(height: AfSpacing.bottomInsetWithMiniAndNav),
        ],
      ),
    );
  }

  /// Format a count with thousands separators ("2,247").
  String _fmt(int n) {
    final s = n.toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return buf.toString();
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  const _StatCard({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(AfSpacing.s16),
        decoration: BoxDecoration(
          color: AfColors.surfaceBase,
          borderRadius: AfRadii.borderMd,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value, style: AfTypography.titleLarge),
            const SizedBox(height: 2),
            Text(
              label,
              style: AfTypography.bodySmall.copyWith(
                color: AfColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PinnedRow extends StatelessWidget {
  final List<AfAlbum> albums;
  const _PinnedRow({required this.albums});

  @override
  Widget build(BuildContext context) {
    if (albums.isEmpty) {
      return SizedBox(
        height: 120,
        child: Center(
          child: Text(
            'Heart an album to pin it here.',
            style: AfTypography.bodySmall
                .copyWith(color: AfColors.textTertiary),
          ),
        ),
      );
    }
    return SizedBox(
      height: 120,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: albums.length,
        separatorBuilder: (_, __) => const SizedBox(width: AfSpacing.s12),
        itemBuilder: (context, i) {
          final a = albums[i];
          return GestureDetector(
            onTap: () => context.push('/album/${a.id}'),
            child: SizedBox(
              width: 120,
              child: Stack(
                children: [
                  Artwork(
                    url: a.imageUrl,
                    size: 120,
                    radius: AfRadii.borderMd,
                  ),
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: AfRadii.borderMd,
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            Colors.black.withValues(alpha: 0.55),
                          ],
                          stops: const [0.5, 1.0],
                        ),
                      ),
                      alignment: Alignment.bottomLeft,
                      padding: const EdgeInsets.all(AfSpacing.s8),
                      child: Text(
                        a.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AfTypography.bodySmall.copyWith(
                          color: AfColors.textOnPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
