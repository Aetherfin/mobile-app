import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/jellyfin/models/items.dart';
import '../../design_tokens/tokens.dart';
import '../../state/providers.dart';
import '../../state/youtube_music_providers.dart';
import '../../widgets/collapse_header.dart';
import '../../widgets/press_scale.dart';
import 'sections/about_section.dart';
import 'sections/listening_stats_section.dart';
import 'sections/profile_header.dart';
import 'sections/settings_section.dart';

/// Profile screen — orchestrator that composes extracted section widgets.
class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  late final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final mode = ref.watch(appModeProvider);
    final isYouTubeMusic = mode == AppMode.youtubeMusic;

    // YouTube Music mode: use YT auth data
    final ytAuth = isYouTubeMusic ? ref.watch(youtubeAuthProvider) : null;
    final name = isYouTubeMusic
        ? (ytAuth?.email.isNotEmpty == true
              ? ytAuth!.email.split('@').first
              : 'YouTube Music')
        : (auth?.userName ?? 'You');
    final serverName = isYouTubeMusic
        ? 'YouTube Music'
        : (auth?.server.name ?? 'Local library');
    final ytProfileUrl = isYouTubeMusic ? ytAuth?.profileUrl : null;
    final profilePhoto = ref.watch(profilePhotoProvider);

    // For YouTube Music: use local profile pic if available
    final isLocalPath =
        ytProfileUrl != null && !ytProfileUrl.startsWith('http');

    final isLocal = mode == AppMode.local;
    final tracksAsync = isYouTubeMusic
        ? const AsyncValue<List<AfTrack>>.data([])
        : isLocal
        ? ref.watch(localTracksProvider)
        // ponytail: server mode count comes from trackCountProvider
        : const AsyncValue<List<AfTrack>>.data([]);
    // ponytail: count-only for server mode — avoids loading all tracks
    final trackCountAsync = isYouTubeMusic
        ? const AsyncValue<int>.data(0)
        : isLocal
        ? const AsyncValue<int>.data(0) // derived from tracksAsync.length below
        : ref.watch(trackCountProvider);
    final albumsAsync = isYouTubeMusic
        ? const AsyncValue<List<AfAlbum>>.data([])
        : isLocal
        ? ref.watch(localAlbumsProvider)
        : ref.watch(allAlbumsProvider);
    final artistsAsync = isYouTubeMusic
        ? const AsyncValue<List<AfArtist>>.data([])
        : isLocal
        ? ref.watch(localArtistsProvider)
        : ref.watch(allArtistsProvider);
    final playlistsAsync = ref.watch(allPlaylistsProvider);
    final favAlbumsAsync = ref.watch(favoriteAlbumsProvider);
    final recentAlbumsAsync = ref.watch(recentlyAddedAlbumsProvider);

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

    // Last.fm connection state.
    final lastFmSession = ref.watch(lastfmSessionKeyProvider);
    final lastFmUser = ref.watch(lastfmUsernameProvider);
    final isLastFmConnected = lastFmSession.isNotEmpty && lastFmUser.isNotEmpty;

    final (:primary, :secondary) = ref.watch(
      currentSpectralProvider.select(
        (s) => (primary: s.primary, secondary: s.secondary),
      ),
    );

    return SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) {
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: AfLayout.maxContentWidth,
              ),
              child: Column(
                children: [
                  CollapseHeader(
                    title: 'Profile',
                    spectral: (primary: primary, secondary: secondary),
                    scrollController: _scrollController,
                    action: Tooltip(
                      message: 'Settings',
                      child: PressScale(
                        onTap: () => context.push('/settings'),
                        child: Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: AfColors.glassFill,
                            borderRadius: AfRadii.borderPill,
                            border: Border.all(
                              color: AfColors.glassBorderStrong,
                              width: 1,
                            ),
                          ),
                          child: const Icon(
                            LucideIcons.settings,
                            color: AfColors.textSecondary,
                            size: 18,
                          ),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: CustomScrollView(
                      controller: _scrollController,
                      physics: const AlwaysScrollableScrollPhysics(
                        parent: ClampingScrollPhysics(),
                      ),
                      slivers: [
                        // ── Split info — avatar + info + inline stats ────
                        SliverToBoxAdapter(
                          child: SplitInfoSection(
                            name: name,
                            serverName: serverName,
                            isYouTubeMusic: isYouTubeMusic,
                            networkProfileUrl: isLocalPath
                                ? null
                                : ytProfileUrl,
                            profilePhoto: (
                              isUploading: profilePhoto.isUploading,
                              localPath:
                                  profilePhoto.localPath ??
                                  (isLocalPath ? ytProfileUrl : null),
                              networkUrl: profilePhoto.networkUrl,
                            ),
                            trackCount: isLocal
                                ? _fmtCount(tracksAsync)
                                : trackCountAsync.maybeWhen(
                                    data: _fmt,
                                    orElse: () => '—',
                                  ),
                            albumCount: _fmtCount(albumsAsync),
                          ),
                        ),

                        // ── Quick stats — artists + playlists ────────────────────────
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.only(top: AfSpacing.s16),
                            child: QuickStatsRow(
                              artistCount: _fmtCount(artistsAsync),
                              playlistCount: _fmtCount(playlistsAsync),
                            ),
                          ),
                        ),

                        // ── Pinned ───────────────────────────────────────────────────
                        const SliverToBoxAdapter(child: PinnedSectionHeader()),
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.only(top: AfSpacing.s8),
                            child: PinnedAlbumsRow(albums: pinned),
                          ),
                        ),

                        // ── Listening Stats ──────────────────────────────────────────
                        SliverToBoxAdapter(
                          child: ListeningStatsSection(
                            isLastFmConnected: isLastFmConnected,
                          ),
                        ),

                        // ── About ───────────────────────────────────────────────────
                        const SliverToBoxAdapter(child: AboutSection()),

                        const SliverToBoxAdapter(
                          child: SizedBox(
                            height: AfSpacing.bottomInsetWithMiniAndNav,
                          ),
                        ),
                      ],
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

  /// Format an AsyncValue count with thousands separators ("2,247").
  String _fmtCount<T>(AsyncValue<List<T>> async) =>
      async.maybeWhen(data: (list) => _fmt(list.length), orElse: () => '—');

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
