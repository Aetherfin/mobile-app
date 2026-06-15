import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/jellyfin/models/items.dart';
import '../../design_tokens/tokens.dart';
import '../../state/providers.dart';
import '../../widgets/favorite_heart_button.dart';
import '../../widgets/quality_chip.dart';
import 'artist_navigation.dart';

class MetadataRow extends ConsumerWidget {
  const MetadataRow({super.key, required this.track});

  final AfTrack track;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Semantics(
      liveRegion: true,
      child: Column(
        children: [
          Text(
            track.title,
            style: AfTypography.titleLarge,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            maxLines: 1,
          ),
          const SizedBox(height: AfSpacing.s4),
          GestureDetector(
            onTap: () => navigateToArtist(
              context,
              ref,
              artistId: track.artistId,
              artistName: track.artistName,
            ),
            child: Text(
              track.artistName,
              style: AfTypography.bodyLarge.copyWith(
                color: AfColors.textSecondary,
              ),
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              maxLines: 1,
            ),
          ),
          const SizedBox(height: AfSpacing.s12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const _AbLoopButton(),
              const SizedBox(width: AfSpacing.s12),
              FavoriteHeartButton(track: track),
              if (track.quality != null) ...[
                const SizedBox(width: AfSpacing.s8),
                QualityChip(quality: track.quality!),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _AbLoopButton extends ConsumerWidget {
  const _AbLoopButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spectral = ref.watch(
      currentSpectralProvider.select((s) => s.primary),
    );
    final abA = ref.watch(abLoopAProvider);
    final abB = ref.watch(abLoopBProvider);
    final active = abA != null || abB != null;
    return Semantics(
      label: 'A-B loop',
      button: true,
      child: GestureDetector(
        onTap: () {
          if (active) {
            ref.read(playerServiceProvider).setAbLoopA(null);
            ref.read(playerServiceProvider).setAbLoopB(null);
            ref.read(abLoopAProvider.notifier).state = null;
            ref.read(abLoopBProvider.notifier).state = null;
            return;
          }
          final pos = ref.read(positionStreamProvider);
          ref.read(playerServiceProvider).setAbLoopA(pos);
          ref.read(abLoopAProvider.notifier).state = pos;
        },
        child: Icon(
          LucideIcons.repeat1,
          size: 20,
          color: active ? spectral : AfColors.textTertiary,
        ),
      ),
    );
  }
}
