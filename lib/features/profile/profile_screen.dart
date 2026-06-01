import 'dart:async';
import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/audio/play_actions.dart';
import '../../core/backend/music_backend.dart';
import '../../core/jellyfin/models/items.dart';
import '../../design_tokens/tokens.dart';
import '../../state/lastfm_stats_providers.dart';
import '../../state/providers.dart';
import '../../utils/display_error.dart';
import '../../widgets/artwork.dart';
import '../../widgets/bottom_sheet.dart';
import '../../widgets/section_header.dart';

/// Reworked Profile Screen — Music Identity Passport & Diagnostic Hub.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    final name = auth?.userName ?? 'YOU';
    final serverName = auth?.server.name ?? 'LOCAL LIBRARY';
    final profilePhoto = ref.watch(profilePhotoProvider);

    final mode = ref.watch(appModeProvider);
    final isLocal = mode == AppMode.local;
    final tracksAsync = isLocal
        ? ref.watch(localTracksProvider)
        : ref.watch(allTracksProvider);
    final albumsAsync = isLocal
        ? ref.watch(localAlbumsProvider)
        : ref.watch(allAlbumsProvider);
    final favAlbumsAsync = ref.watch(favoriteAlbumsProvider);
    final recentAlbumsAsync = ref.watch(recentlyAddedAlbumsProvider);

    String fmtCount<T>(AsyncValue<List<T>> async) =>
        async.maybeWhen(data: (list) => _fmt(list.length), orElse: () => '—');

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

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: AfSpacing.s16),
        children: [
          const SizedBox(height: AfSpacing.s20),

          // ── PHYSICAL MEMBER PASS CARD ──
          _MemberPassCard(
            name: name,
            serverName: serverName,
            profilePhoto: profilePhoto,
            isLocal: isLocal,
            onPickPhoto: (source) async {
              final picker = ImagePicker();
              try {
                final image = await picker.pickImage(
                  source: source,
                  maxWidth: 512,
                  maxHeight: 512,
                  imageQuality: 85,
                );
                if (image != null) {
                  final bytes = await image.readAsBytes();
                  final mimeType = image.mimeType ?? 'image/jpeg';
                  await ref
                      .read(profilePhotoProvider.notifier)
                      .updatePhoto(bytes, mimeType);
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Failed to update profile photo: $e'),
                      backgroundColor: AfColors.semanticError,
                    ),
                  );
                }
              }
            },
            onRemovePhoto: () async {
              try {
                await ref.read(profilePhotoProvider.notifier).removePhoto();
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Failed to remove profile photo: $e'),
                      backgroundColor: AfColors.semanticError,
                    ),
                  );
                }
              }
            },
            authHeaders: ref.watch(musicBackendProvider)?.authHeaders,
          ),

          const SizedBox(height: AfSpacing.s24),

          // ── SYSTEM DIAGNOSTIC STATS ──
          Row(
            children: [
              _ReworkedStatCard(
                label: 'TRACKS INDEXED',
                value: fmtCount(tracksAsync),
                progress: 0.72,
              ),
              const SizedBox(width: AfSpacing.s16),
              _ReworkedStatCard(
                label: 'ALBUMS INDEXED',
                value: fmtCount(albumsAsync),
                progress: 0.48,
              ),
            ],
          ),

          const SizedBox(height: AfSpacing.s24),

          // ── PINNED CD STACK / OVERLAPPING CAROUSEL ──
          const SectionHeader(title: 'PINNED ARCHIVES', uppercase: true),
          const SizedBox(height: AfSpacing.s12),
          _OverlappingCDStack(albums: pinned),

          const SizedBox(height: AfSpacing.s24),

          // ── LISTENING STATS DASHBOARD ──
          const SectionHeader(title: 'LISTENING INTEL', uppercase: true),
          const SizedBox(height: AfSpacing.s12),
          if (!isLastFmConnected) _LastFmConnectionCTA(),
          _StatsDashboard(isLastFmConnected: isLastFmConnected),
          const SizedBox(height: AfSpacing.s24),

          // ── ACCOUNT OPTIONS ──
          const SectionHeader(title: 'SYSTEM SETTINGS', uppercase: true),
          const SizedBox(height: AfSpacing.s8),
          ListTile(
            leading: const Icon(LucideIcons.settings, size: 18, color: AfColors.indigo400),
            title: const Text(
              'PREFERENCES & SETUP',
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
              ),
            ),
            tileColor: AfColors.surfaceBase,
            shape: const RoundedRectangleBorder(borderRadius: AfRadii.borderMd),
            onTap: () => context.push('/settings'),
            trailing: const Icon(LucideIcons.chevronRight, size: 16, color: AfColors.textTertiary),
          ),
          const SizedBox(height: AfSpacing.bottomInsetWithMiniAndNav),
        ],
      ),
    );
  }

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

/// Physical Member Pass Card with a fake barcode
class _MemberPassCard extends StatelessWidget {
  const _MemberPassCard({
    required this.name,
    required this.serverName,
    required this.profilePhoto,
    required this.isLocal,
    required this.onPickPhoto,
    required this.onRemovePhoto,
    this.authHeaders,
  });

  final String name;
  final String serverName;
  final ProfilePhotoState profilePhoto;
  final bool isLocal;
  final ValueChanged<ImageSource> onPickPhoto;
  final VoidCallback onRemovePhoto;
  final Map<String, String>? authHeaders;

  @override
  Widget build(BuildContext context) {
    final passId = 'ID.${name.hashCode.abs().toString().padLeft(6, '0').substring(0, 6)}';

    return Container(
      decoration: BoxDecoration(
        color: AfColors.surfaceLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AfColors.surfaceHigh, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 8,
            offset: const Offset(0, 4),
          )
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Avatar on Left
              _AvatarImagePicker(
                name: name,
                isUploading: profilePhoto.isUploading,
                localPath: profilePhoto.localPath,
                networkUrl: profilePhoto.networkUrl,
                authHeaders: authHeaders,
                onPickPhoto: onPickPhoto,
                onRemovePhoto: onRemovePhoto,
              ),
              const SizedBox(width: 16),
              // Pass Details on Right
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'MEMBER PASS',
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            color: AfColors.indigo400,
                            letterSpacing: 1.5,
                          ),
                        ),
                        Text(
                          isLocal ? 'OFFLINE' : 'ONLINE',
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                            color: isLocal ? AfColors.textTertiary : AfColors.semanticSuccess,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      name.toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AfTypography.titleMedium.copyWith(
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      serverName.toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 10,
                        color: AfColors.textTertiary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      passId,
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 9,
                        color: AfColors.textDisabled,
                        letterSpacing: 1.0,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Fake barcode decoration at the bottom
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 24,
                  child: Row(
                    children: List.generate(24, (i) {
                      final widths = [3.0, 1.0, 4.0, 2.0, 1.0, 3.0, 2.0, 5.0, 1.0, 2.0, 4.0, 1.0];
                      final isGap = i % 2 == 1;
                      final w = widths[i % widths.length];
                      return isGap
                          ? SizedBox(width: w)
                          : Container(
                              width: w,
                              color: AfColors.textTertiary.withValues(alpha: 0.7),
                            );
                    }),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'SYS.AETHER.81',
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 8,
                  color: AfColors.textTertiary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Stat card with architectural diagnostics
class _ReworkedStatCard extends StatelessWidget {
  const _ReworkedStatCard({
    required this.label,
    required this.value,
    required this.progress,
  });
  final String label;
  final String value;
  final double progress;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AfColors.surfaceBase,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AfColors.surfaceHigh),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 9,
                fontWeight: FontWeight.w700,
                color: AfColors.textTertiary,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              value,
              style: AfTypography.titleMedium.copyWith(
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 12),
            // Diagnostic bar
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 3,
                backgroundColor: AfColors.surfaceLow,
                valueColor: const AlwaysStoppedAnimation<Color>(AfColors.indigo400),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// CD stack / Overlapping vinyl carousel
class _OverlappingCDStack extends StatelessWidget {
  const _OverlappingCDStack({required this.albums});
  final List<AfAlbum> albums;

  @override
  Widget build(BuildContext context) {
    if (albums.isEmpty) {
      return Container(
        height: 110,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AfColors.surfaceLow,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Text(
          'NO PINNED ITEMS',
          style: TextStyle(fontFamily: 'monospace', fontSize: 10, color: AfColors.textTertiary),
        ),
      );
    }

    return SizedBox(
      height: 120,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: albums.length,
        itemBuilder: (context, i) {
          final album = albums[i];
          // Positive translation shift
          final shift = i == 0 ? 0.0 : -20.0 * i;

          return Transform.translate(
            offset: Offset(shift, 0),
            child: GestureDetector(
              onTap: () => context.push('/album/${album.id}'),
              child: Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.3),
                      blurRadius: 4,
                      offset: const Offset(-2, 2),
                    )
                  ],
                ),
                clipBehavior: Clip.antiAlias,
                child: Artwork(
                  url: album.imageUrl,
                  size: 100,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _AvatarImagePicker extends StatelessWidget {
  const _AvatarImagePicker({
    required this.name,
    required this.isUploading,
    this.localPath,
    this.networkUrl,
    this.authHeaders,
    required this.onPickPhoto,
    required this.onRemovePhoto,
  });

  final String name;
  final bool isUploading;
  final String? localPath;
  final String? networkUrl;
  final Map<String, String>? authHeaders;
  final ValueChanged<ImageSource> onPickPhoto;
  final VoidCallback onRemovePhoto;

  @override
  Widget build(BuildContext context) {
    ImageProvider? imageProvider;
    if (localPath != null && localPath!.isNotEmpty) {
      imageProvider = FileImage(File(localPath!));
    } else if (networkUrl != null && networkUrl!.isNotEmpty) {
      imageProvider = CachedNetworkImageProvider(
        networkUrl!,
        headers: authHeaders,
      );
    }

    final fallbackChar = name.isNotEmpty ? name[0].toUpperCase() : 'Y';

    return GestureDetector(
      onTap: () => _showPickerSheet(context),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Visual offset ring
          Positioned(
            top: 2,
            left: 2,
            child: Container(
              width: 78,
              height: 78,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: AfColors.indigo400.withValues(alpha: 0.4),
                  width: 1.5,
                ),
              ),
            ),
          ),
          Container(
            width: 78,
            height: 78,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AfColors.surfaceBase,
              border: Border.all(color: AfColors.surfaceHigh, width: 1.5),
            ),
            clipBehavior: Clip.antiAlias,
            child: imageProvider != null
                ? Image(image: imageProvider, fit: BoxFit.cover)
                : Center(
                    child: Text(
                      fallbackChar,
                      style: AfTypography.titleLarge.copyWith(
                        fontWeight: FontWeight.w900,
                        color: AfColors.indigo300,
                      ),
                    ),
                  ),
          ),
          if (isUploading)
            Container(
              width: 78,
              height: 78,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.black45,
              ),
              child: const Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AfColors.indigo300,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _showPickerSheet(BuildContext context) {
    showBlurBottomSheet(
      context: context,
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 8),
          const Center(
            child: Text(
              'EDIT PHOTO',
              style: TextStyle(
                fontFamily: 'monospace',
                fontWeight: FontWeight.bold,
                fontSize: 12,
                color: AfColors.indigo400,
                letterSpacing: 1.0,
              ),
            ),
          ),
          const SizedBox(height: 12),
          ListTile(
            leading: const Icon(LucideIcons.camera, size: 18),
            title: const Text('TAKE PHOTO', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
            onTap: () {
              Navigator.pop(context);
              onPickPhoto(ImageSource.camera);
            },
          ),
          ListTile(
            leading: const Icon(LucideIcons.image, size: 18),
            title: const Text('CHOOSE FROM GALLERY', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
            onTap: () {
              Navigator.pop(context);
              onPickPhoto(ImageSource.gallery);
            },
          ),
          if (localPath != null || networkUrl != null)
            ListTile(
              leading: const Icon(LucideIcons.trash2, color: AfColors.semanticError, size: 18),
              title: const Text('REMOVE CURRENT PHOTO', style: TextStyle(color: AfColors.semanticError, fontSize: 12, fontWeight: FontWeight.bold)),
              onTap: () {
                Navigator.pop(context);
                onRemovePhoto();
              },
            ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

class _LastFmConnectionCTA extends StatelessWidget {
  const _LastFmConnectionCTA();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AfColors.surfaceLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AfColors.surfaceHigh),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'LAST.FM NOT CONNECTED',
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 10,
              fontWeight: FontWeight.w800,
              color: AfColors.indigo300,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Connect your Last.fm account in settings to track, analyze, and display your musical profile intelligence.',
            style: TextStyle(fontSize: 11, color: AfColors.textTertiary),
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: () => context.push('/settings'),
            style: TextButton.styleFrom(
              backgroundColor: AfColors.surfaceBase,
              side: const BorderSide(color: AfColors.surfaceHigh),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
            ),
            child: const Text(
              'LINK ACCOUNT',
              style: TextStyle(fontFamily: 'monospace', fontSize: 11, fontWeight: FontWeight.bold, color: AfColors.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatsDashboard extends ConsumerWidget {
  const _StatsDashboard({required this.isLastFmConnected});
  final bool isLastFmConnected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activePeriod = ref.watch(statsPeriodProvider);
    final activeTab = ref.watch(statsTabProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (isLastFmConnected) ...[
          // Period Selector
          Row(
            children: [
              _PeriodButton(
                label: '7 DAYS',
                value: '7day',
                activeValue: activePeriod,
              ),
              const SizedBox(width: 8),
              _PeriodButton(
                label: '30 DAYS',
                value: '1month',
                activeValue: activePeriod,
              ),
              const SizedBox(width: 8),
              _PeriodButton(
                label: 'ALL TIME',
                value: 'overall',
                activeValue: activePeriod,
              ),
            ],
          ),
          const SizedBox(height: 12),
        ],

        // Tabs Selector (Songs | Artists | Albums)
        Container(
          padding: const EdgeInsets.all(2),
          decoration: const BoxDecoration(
            color: AfColors.surfaceBase,
            borderRadius: AfRadii.borderMd,
          ),
          child: Row(
            children: [
              _TabButton(
                label: 'SONGS',
                value: 'songs',
                activeValue: activeTab,
              ),
              _TabButton(
                label: 'ARTISTS',
                value: 'artists',
                activeValue: activeTab,
              ),
              _TabButton(
                label: 'ALBUMS',
                value: 'albums',
                activeValue: activeTab,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // List render
        _renderActiveList(context, ref, activeTab),
      ],
    );
  }

  Widget _renderActiveList(
    BuildContext context,
    WidgetRef ref,
    String activeTab,
  ) {
    switch (activeTab) {
      case 'songs':
        final songsAsync = ref.watch(topTracksProvider);
        return songsAsync.when(
          loading: _loadingIndicator,
          error: (err, _) => _errorText(err),
          data: (tracks) => _SongsList(tracks: tracks),
        );
      case 'artists':
        final artistsAsync = ref.watch(topArtistsProvider);
        return artistsAsync.when(
          loading: _loadingIndicator,
          error: (err, _) => _errorText(err),
          data: (artists) => _ArtistsList(artists: artists),
        );
      case 'albums':
        final albumsAsync = ref.watch(topAlbumsProvider);
        return albumsAsync.when(
          loading: _loadingIndicator,
          error: (err, _) => _errorText(err),
          data: (albums) => _AlbumsList(albums: albums),
        );
      default:
        return const SizedBox();
    }
  }

  Widget _loadingIndicator() {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(AfSpacing.s32),
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: AfColors.indigo300,
          ),
        ),
      ),
    );
  }

  Widget _errorText(Object error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AfSpacing.s16),
        child: Text(
          'Failed to load statistics: $error',
          style: AfTypography.bodySmall.copyWith(color: AfColors.semanticError),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

class _PeriodButton extends ConsumerWidget {
  const _PeriodButton({
    required this.label,
    required this.value,
    required this.activeValue,
  });
  final String label;
  final String value;
  final String activeValue;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = value == activeValue;
    return GestureDetector(
      onTap: () => ref.read(statsPeriodProvider.notifier).state = value,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: active ? AfColors.indigo600 : AfColors.surfaceBase,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: 10,
            color: active ? AfColors.textOnPrimary : AfColors.textSecondary,
            fontWeight: active ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}

class _TabButton extends ConsumerWidget {
  const _TabButton({
    required this.label,
    required this.value,
    required this.activeValue,
  });
  final String label;
  final String value;
  final String activeValue;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = value == activeValue;
    return Expanded(
      child: GestureDetector(
        onTap: () => ref.read(statsTabProvider.notifier).state = value,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active ? AfColors.surfaceHigh : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 11,
              color: active ? AfColors.textPrimary : AfColors.textTertiary,
              fontWeight: active ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }
}

/// Songs list statistics with relative progress visual indicator
class _SongsList extends ConsumerWidget {
  const _SongsList({required this.tracks});
  final List<({String artist, String title, int playCount, String? imageUrl})>
  tracks;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (tracks.isEmpty) {
      return _emptyState(
        'No history logged yet. Listen to tracks to collect metrics.',
      );
    }

    final maxCount = tracks.first.playCount;

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: tracks.length,
      separatorBuilder: (context, index) => const SizedBox(height: 10),
      itemBuilder: (context, i) {
        final t = tracks[i];
        final ratio = maxCount > 0 ? t.playCount / maxCount : 0.0;
        final displayIdx = (i + 1).toString().padLeft(2, '0');

        return InkWell(
          onTap: () => _playTrackFromStats(context, ref, t.artist, t.title),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
            decoration: BoxDecoration(
              color: AfColors.surfaceLow,
              border: Border.all(color: AfColors.surfaceHigh),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Text(
                      displayIdx,
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 10, color: AfColors.indigo400, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(width: 12),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: t.imageUrl != null
                          ? Artwork(url: t.imageUrl, size: 32)
                          : Container(
                              width: 32,
                              height: 32,
                              color: AfColors.surfaceHigh,
                              child: const Icon(LucideIcons.music, size: 14, color: AfColors.textTertiary),
                            ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            t.title.toUpperCase(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            t.artist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 9, color: AfColors.textTertiary),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${t.playCount} SCROBBLES',
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 9, color: AfColors.indigo300),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // Tiny relative popularity bar
                ClipRRect(
                  borderRadius: BorderRadius.circular(1),
                  child: LinearProgressIndicator(
                    value: ratio,
                    minHeight: 1.5,
                    backgroundColor: Colors.transparent,
                    valueColor: const AlwaysStoppedAnimation<Color>(AfColors.indigo400),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Festival Lineup Poster style list for top artists
class _ArtistsList extends ConsumerWidget {
  const _ArtistsList({required this.artists});
  final List<({String artist, int playCount})> artists;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (artists.isEmpty) {
      return _emptyState('No history logged yet.');
    }

    final topArtists = artists.take(8).toList();

    return Container(
      decoration: BoxDecoration(
        color: AfColors.surfaceLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AfColors.indigo400.withValues(alpha: 0.35), width: 1.5),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Festival header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'AETHERFIN INTEL',
                style: TextStyle(fontFamily: 'monospace', fontSize: 8, color: AfColors.indigo400, fontWeight: FontWeight.bold, letterSpacing: 1.0),
              ),
              Text(
                'LINEUP / STATS',
                style: TextStyle(fontFamily: 'monospace', fontSize: 8, color: AfColors.textTertiary.withValues(alpha: 0.8), letterSpacing: 0.5),
              ),
            ],
          ),
          const Divider(color: AfColors.surfaceHigh, height: 20, thickness: 1.0),
          const SizedBox(height: 8),
          
          // Lineup text wrap
          Wrap(
            spacing: 12.0,
            runSpacing: 14.0,
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: List.generate(topArtists.length, (idx) {
              final art = topArtists[idx];
              
              // Scale size/weight based on ranking
              double fSize = 11.0;
              FontWeight fWeight = FontWeight.w500;
              Color fColor = AfColors.textTertiary;
              
              if (idx == 0) {
                fSize = 24.0;
                fWeight = FontWeight.w900;
                fColor = AfColors.textPrimary;
              } else if (idx < 3) {
                fSize = 18.0;
                fWeight = FontWeight.w800;
                fColor = AfColors.textSecondary;
              } else if (idx < 6) {
                fSize = 14.0;
                fWeight = FontWeight.w700;
                fColor = AfColors.textTertiary;
              }
              
              return InkWell(
                onTap: () => _navigateToArtistFromStats(context, ref, art.artist),
                child: Text(
                  art.artist.toUpperCase(),
                  style: TextStyle(
                    fontSize: fSize,
                    fontWeight: fWeight,
                    color: fColor,
                    letterSpacing: 0.5,
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

class _AlbumsList extends ConsumerWidget {
  const _AlbumsList({required this.albums});
  final List<({String artist, String album, int playCount, String? imageUrl})>
  albums;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (albums.isEmpty) {
      return _emptyState('No history logged yet.');
    }
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: albums.length,
      separatorBuilder: (context, index) => const SizedBox(height: 10),
      itemBuilder: (context, i) {
        final alb = albums[i];
        final displayIdx = (i + 1).toString().padLeft(2, '0');
        
        return InkWell(
          onTap: () => _navigateToAlbumFromStats(context, ref, alb.artist, alb.album),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
            decoration: BoxDecoration(
              color: AfColors.surfaceLow,
              border: Border.all(color: AfColors.surfaceHigh),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Text(
                  displayIdx,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 10, color: AfColors.indigo400, fontWeight: FontWeight.bold),
                ),
                const SizedBox(width: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: alb.imageUrl != null
                      ? Artwork(url: alb.imageUrl, size: 32)
                      : Container(
                          width: 32,
                          height: 32,
                          color: AfColors.surfaceHigh,
                          child: const Icon(LucideIcons.disc, size: 14, color: AfColors.textTertiary),
                        ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        alb.album.toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        alb.artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 9, color: AfColors.textTertiary),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${alb.playCount} SCROBBLES',
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 9, color: AfColors.indigo300),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

Widget _emptyState(String text) {
  return Center(
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
      child: Text(
        text,
        style: AfTypography.bodySmall.copyWith(color: AfColors.textTertiary),
        textAlign: TextAlign.center,
      ),
    ),
  );
}

// ── Search/Resolution Helpers ────────────────────────────────────────────────

Future<void> _playTrackFromStats(
  BuildContext context,
  WidgetRef ref,
  String artist,
  String title,
 ) async {
  unawaited(
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: Card(
          color: AfColors.surfaceBase,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AfColors.indigo300,
                  ),
                ),
                SizedBox(width: 16),
                Text(
                  'Locating track in library...',
                  style: TextStyle(color: AfColors.textPrimary),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  try {
    final backend = ref.read(musicBackendProvider);
    if (backend == null) throw Exception('No connected library.');

    AfTrack? resolved;
    if (backend.serverType == ServerType.local) {
      final db = ref.read(localLibraryProvider).db;
      resolved = await db.searchTrackByArtistAndTitle(artist, title);
    } else {
      final results = await backend.search('$artist $title');
      for (final t in results.tracks) {
        if (t.title.toLowerCase() == title.toLowerCase() &&
            t.artistName.toLowerCase() == artist.toLowerCase()) {
          resolved = t;
          break;
        }
      }
      if (resolved == null) {
        for (final t in results.tracks) {
          if (t.title.toLowerCase().contains(title.toLowerCase()) &&
              t.artistName.toLowerCase().contains(artist.toLowerCase())) {
            resolved = t;
            break;
          }
        }
      }
    }

    if (context.mounted) Navigator.pop(context); // Close loading HUD

    if (resolved != null) {
      await ref.read(playActionsProvider).playQueue([resolved], startIndex: 0);
    } else {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('"$title" by $artist is not in your library.'),
          ),
        );
      }
    }
  } catch (e) {
    if (context.mounted) Navigator.pop(context); // Close loading HUD
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to resolve track: ${displayError(e)}')),
      );
    }
  }
}

Future<void> _navigateToArtistFromStats(
  BuildContext context,
  WidgetRef ref,
  String artistName,
) async {
  unawaited(
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: Card(
          color: AfColors.surfaceBase,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AfColors.indigo300,
                  ),
                ),
                SizedBox(width: 16),
                Text(
                  'Locating artist...',
                  style: TextStyle(color: AfColors.textPrimary),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  try {
    final backend = ref.read(musicBackendProvider);
    if (backend == null) throw Exception('No connected library.');

    String? artistId;
    if (backend.serverType == ServerType.local) {
      final db = ref.read(localLibraryProvider).db;
      final resolved = await db.artistByName(artistName);
      artistId = resolved?.id;
    } else {
      final results = await backend.search(artistName);
      for (final art in results.artists) {
        if (art.name.toLowerCase() == artistName.toLowerCase()) {
          artistId = art.id;
          break;
        }
      }
    }

    if (context.mounted) Navigator.pop(context); // Close loading HUD

    if (artistId != null) {
      if (context.mounted) unawaited(context.push('/artist/$artistId'));
    } else {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Artist "$artistName" not found in library.')),
        );
      }
    }
  } catch (e) {
    if (context.mounted) Navigator.pop(context); // Close loading HUD
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to resolve artist: ${displayError(e)}')),
      );
    }
  }
}

Future<void> _navigateToAlbumFromStats(
  BuildContext context,
  WidgetRef ref,
  String artistName,
  String albumName,
) async {
  unawaited(
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: Card(
          color: AfColors.surfaceBase,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AfColors.indigo300,
                  ),
                ),
                SizedBox(width: 16),
                Text(
                  'Locating album...',
                  style: TextStyle(color: AfColors.textPrimary),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  try {
    final backend = ref.read(musicBackendProvider);
    if (backend == null) throw Exception('No connected library.');

    String? albumId;
    if (backend.serverType == ServerType.local) {
      final db = ref.read(localLibraryProvider).db;
      final resolved = await db.albumByKey(albumName, artistName);
      albumId = resolved?.id;
    } else {
      final results = await backend.search('$artistName $albumName');
      for (final alb in results.albums) {
        if (alb.name.toLowerCase() == albumName.toLowerCase() &&
            alb.artistName.toLowerCase() == artistName.toLowerCase()) {
          albumId = alb.id;
          break;
        }
      }
    }

    if (context.mounted) Navigator.pop(context); // Close loading HUD

    if (albumId != null) {
      if (context.mounted) unawaited(context.push('/album/$albumId'));
    } else {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Album "$albumName" by $artistName not found in library.',
            ),
          ),
        );
      }
    }
  } catch (e) {
    if (context.mounted) Navigator.pop(context); // Close loading HUD
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to resolve album: ${displayError(e)}')),
      );
    }
  }
}
