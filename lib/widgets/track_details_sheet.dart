import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/jellyfin/models/items.dart';
import '../core/jellyfin/models/quality.dart';
import '../design_tokens/tokens.dart';
import '../state/providers.dart';
import '../utils/time_format.dart';
import 'bottom_sheet.dart';

void showTrackDetailsSheet(BuildContext context, WidgetRef ref, AfTrack track) {
  HapticFeedback.mediumImpact();
  showBlurBottomSheet<void>(
    context: context,
    child: SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 400),
              child: TrackDetailsBody(track: track),
            ),
          ),
        ],
      ),
    ),
  );
}

/// Track details bottom sheet body showing metadata, quality, and file info.
class TrackDetailsBody extends ConsumerWidget {
  const TrackDetailsBody({super.key, required this.track});
  final AfTrack track;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detailsAsync = ref.watch(trackDetailsProvider(track.id));

    return ListView(
      padding: const EdgeInsets.only(
        left: AfSpacing.gutterGenerous,
        right: AfSpacing.gutterGenerous,
        bottom: AfSpacing.s12,
      ),
      children: [
        // Header
        Text(
          track.title,
          style: AfTypography.titleSmall,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: AfSpacing.s2),
        Text(
          track.artistName,
          style: AfTypography.bodyMedium.copyWith(
            color: AfColors.textSecondary,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),

        const SizedBox(height: AfSpacing.s16),
        const Divider(height: 1, color: AfColors.surfaceHigh),
        const SizedBox(height: AfSpacing.s16),

        // ── Song info ───────────────────────────────────────────
        const _SectionTitle(label: 'Song info'),
        _DetailRow(label: 'Title', value: track.title),
        _DetailRow(label: 'Artist', value: track.artistName),
        _DetailRow(label: 'Album', value: track.albumName),
        if (track.trackNumber != null)
          _DetailRow(label: 'Track #', value: '${track.trackNumber}'),
        if (track.duration > Duration.zero)
          _DetailRow(
            label: 'Duration',
            value: formatTrackDuration(track.duration),
          ),
        if (track.dateAdded != null)
          _DetailRow(label: 'Date added', value: _formatDate(track.dateAdded!)),

        // ── Extended details (async) ────────────────────────────
        detailsAsync.when(
          data: (details) {
            if (details == null) return const SizedBox.shrink();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── More song info ──────────────────────────────
                if (details.albumArtist != null &&
                    details.albumArtist != track.artistName)
                  _DetailRow(
                    label: 'Album artist',
                    value: details.albumArtist!,
                  ),
                if (details.composer != null &&
                    details.composer != track.artistName)
                  _DetailRow(label: 'Composer', value: details.composer!),
                if (details.year != null)
                  _DetailRow(label: 'Year', value: '${details.year}'),
                if (details.discNumber != null)
                  _DetailRow(label: 'Disc', value: '${details.discNumber}'),
                if (details.genres.isNotEmpty)
                  _DetailRow(label: 'Genre', value: details.genres.join(', ')),
                if (details.isTranscoded)
                  const _DetailRow(
                    label: 'Transcoded',
                    value: 'Yes (server-side)',
                  ),

                // ── Listeners ───────────────────────────────────
                if (details.playCount != null ||
                    details.lastPlayedAt != null) ...[
                  const SizedBox(height: AfSpacing.s16),
                  const Divider(height: 1, color: AfColors.surfaceHigh),
                  const SizedBox(height: AfSpacing.s16),
                  const _SectionTitle(label: 'Listeners'),
                  if (details.playCount != null)
                    _DetailRow(
                      label: 'Play count',
                      value: '${details.playCount}',
                    ),
                  if (details.lastPlayedAt != null)
                    _DetailRow(
                      label: 'Last played',
                      value: _formatDate(details.lastPlayedAt!),
                    ),
                ],

                // ── File details ────────────────────────────────
                const SizedBox(height: AfSpacing.s16),
                const Divider(height: 1, color: AfColors.surfaceHigh),
                const SizedBox(height: AfSpacing.s16),
                const _SectionTitle(label: 'File details'),
                if (details.container != null)
                  _DetailRow(
                    label: 'Format',
                    value: details.container!.toUpperCase(),
                  ),
                if (track.quality != null)
                  _DetailRow(
                    label: 'Codec',
                    value: track.quality!.sourceCodec.toUpperCase(),
                  ),
                if (details.bitrateBps != null)
                  _DetailRow(
                    label: 'Bitrate',
                    value: '${details.bitrateBps! ~/ 1000} kbps',
                  ),
                if (details.sampleRateHz != null)
                  _DetailRow(
                    label: 'Sample rate',
                    value: _formatSampleRate(details.sampleRateHz!),
                  ),
                if (details.bitDepth != null)
                  _DetailRow(
                    label: 'Bit depth',
                    value: '${details.bitDepth}-bit',
                  ),
                if (details.formattedChannels != null)
                  _DetailRow(
                    label: 'Channels',
                    value: details.formattedChannels!,
                  ),
                if (details.formattedSize != null)
                  _DetailRow(label: 'File size', value: details.formattedSize!),
                if (details.path != null)
                  _DetailRow(
                    label: 'Path',
                    value: details.path!,
                    selectable: true,
                  ),
              ],
            );
          },
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: AfSpacing.s24),
            child: Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AfColors.accentPrimary,
                ),
              ),
            ),
          ),
          error: (_, _) => const SizedBox.shrink(),
        ),

        // ── Quality badge fallback (when no extended details) ───
        if (track.quality != null)
          detailsAsync.maybeWhen(
            data: (d) => d != null
                ? const SizedBox.shrink()
                : _qualityFallback(track.quality!),
            orElse: () => const SizedBox.shrink(),
          ),

        const SizedBox(height: AfSpacing.s24),
      ],
    );
  }

  Widget _qualityFallback(TrackQuality q) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: AfSpacing.s16),
        const Divider(height: 1, color: AfColors.surfaceHigh),
        const SizedBox(height: AfSpacing.s16),
        const _SectionTitle(label: 'File details'),
        _DetailRow(label: 'Codec', value: q.sourceCodec.toUpperCase()),
        if (q.bitrateKbps != null)
          _DetailRow(label: 'Bitrate', value: '${q.bitrateKbps} kbps'),
        if (q.bitDepth != null)
          _DetailRow(label: 'Bit depth', value: '${q.bitDepth}-bit'),
        if (q.sampleRateKhz != null)
          _DetailRow(label: 'Sample rate', value: '${q.sampleRateKhz} kHz'),
      ],
    );
  }

  static String _formatDate(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }

  static String _formatSampleRate(int hz) {
    if (hz % 1000 == 0) return '${hz ~/ 1000} kHz';
    return '${(hz / 1000).toStringAsFixed(1)} kHz';
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AfSpacing.s12),
      child: Text(
        label,
        style: AfTypography.caption.copyWith(
          color: AfColors.accentPrimary,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.label,
    required this.value,
    this.selectable = false,
  });
  final String label;
  final String value;
  final bool selectable;

  @override
  Widget build(BuildContext context) {
    final valueWidget = selectable
        ? SelectableText(
            value,
            maxLines: 3,
            style: AfTypography.bodyMedium.copyWith(
              color: AfColors.textPrimary,
            ),
          )
        : Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AfTypography.bodyMedium.copyWith(
              color: AfColors.textPrimary,
            ),
          );

    return Padding(
      padding: const EdgeInsets.only(bottom: AfSpacing.s8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: AfTypography.bodySmall.copyWith(
                color: AfColors.textTertiary,
              ),
            ),
          ),
          Expanded(child: valueWidget),
        ],
      ),
    );
  }
}
