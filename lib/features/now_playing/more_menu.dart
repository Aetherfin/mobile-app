import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/audio/play_actions.dart';
import '../../core/jellyfin/models/items.dart';
import '../../design_tokens/tokens.dart';
import '../../state/providers.dart';
import '../../widgets/bottom_sheet.dart';
import '../../widgets/press_scale.dart';
import '../../widgets/save_to_playlist_sheet.dart';
import '../../widgets/track_details_sheet.dart';
import 'menu/ab_loop_dialog.dart';
import 'menu/audio_output_picker.dart';
import 'menu/playback_speed_dialog.dart';
import 'menu/volume_dialog.dart';
import 'sleep_timer_dialog.dart';

// ─────────────────────────────────────────────────────────────────────────────
// More sheet
// ─────────────────────────────────────────────────────────────────────────────

void showMoreSheet(BuildContext context, WidgetRef ref) {
  final pageNotifier = ValueNotifier<_MorePage>(_MorePage.menu);

  showBlurBottomSheet<void>(
    context: context,
    builder: (context, dismiss) => ValueListenableBuilder<_MorePage>(
      valueListenable: pageNotifier,
      builder: (context, page, _) {
        if (page == _MorePage.details) {
          final track = ref.read(currentTrackProvider);
          if (track == null) {
            pageNotifier.value = _MorePage.menu;
            return const SizedBox.shrink();
          }
          return _DetailsView(
            track: track,
            onBack: () => pageNotifier.value = _MorePage.menu,
          );
        }
        return _MoreMenu(
          dismiss: dismiss,
          context: context,
          ref: ref,
          pageNotifier: pageNotifier,
        );
      },
    ),
  );
}

enum _MorePage { menu, details }

class _MoreMenu extends StatelessWidget {
  const _MoreMenu({
    required this.dismiss,
    required this.context,
    required this.ref,
    required this.pageNotifier,
  });

  final void Function() dismiss;
  final BuildContext context;
  final WidgetRef ref;
  final ValueNotifier<_MorePage> pageNotifier;

  @override
  Widget build(BuildContext context) {
    final track = ref.watch(currentTrackProvider);
    final savedIds = ref.watch(savedTrackIdsProvider);
    final serverIds = ref
        .watch(playlistTrackIdsProvider)
        .maybeWhen(data: (ids) => ids, orElse: () => const <String>{});
    final spectral = ref.watch(
      currentSpectralProvider.select((s) => s.primary),
    );
    final isSaved =
        track != null &&
        (savedIds.contains(track.id) || serverIds.contains(track.id));

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Quick actions ──
        MoreItem(
          icon: const Icon(
            LucideIcons.radio,
            size: AfIconSizes.sm,
            color: AfColors.textSecondary,
          ),
          label: 'Start radio',
          onTap: () async {
            dismiss();
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Starting Instant Mix…'),
                  duration: AfDurations.snackBarInfo,
                ),
              );
            }
            await ref.read(playActionsProvider).playInstantMix(track!);
          },
        ),
        MoreItem(
          icon: const Icon(
            LucideIcons.slidersHorizontal,
            size: AfIconSizes.sm,
            color: AfColors.textSecondary,
          ),
          label: 'EQ',
          onTap: () {
            dismiss();
            context.push('/eq-dsp');
          },
        ),
        MoreItem(
          icon: Icon(
            LucideIcons.plus,
            size: AfIconSizes.sm,
            color: isSaved ? spectral : AfColors.textSecondary,
          ),
          label: isSaved ? 'Saved' : 'Save',
          onTap: () {
            dismiss();
            _showSaveDialog(this.context, ref);
          },
        ),
        MoreItem(
          icon: const Icon(
            LucideIcons.listMusic,
            size: AfIconSizes.sm,
            color: AfColors.textSecondary,
          ),
          label: 'Queue',
          onTap: () {
            dismiss();
            context.push('/queue');
          },
        ),
        if (track?.albumId != null)
          MoreItem(
            icon: const Icon(
              LucideIcons.disc3,
              size: AfIconSizes.sm,
              color: AfColors.textSecondary,
            ),
            label: 'Go to album',
            onTap: () {
              dismiss();
              context.push('/album/${track!.albumId}');
            },
          ),
        if (track?.artistId != null)
          MoreItem(
            icon: const Icon(
              LucideIcons.user,
              size: AfIconSizes.sm,
              color: AfColors.textSecondary,
            ),
            label: 'Go to artist',
            onTap: () {
              dismiss();
              context.push('/artist/${track!.artistId}');
            },
          ),
        const Divider(height: 1, color: AfColors.surfaceHigh),
        // ── Advanced actions ──
        MoreItem(
          icon: Icon(
            LucideIcons.arrowLeftRight,
            size: AfIconSizes.sm,
            color: ref.watch(abLoopAProvider) != null
                ? spectral
                : AfColors.textSecondary,
          ),
          label: 'A-B Loop',
          onTap: () {
            dismiss();
            showAbLoopDialog(this.context, ref);
          },
        ),
        MoreItem(
          icon: const Icon(
            LucideIcons.moon,
            size: AfIconSizes.sm,
            color: AfColors.textSecondary,
          ),
          label: 'Sleep timer',
          onTap: () {
            dismiss();
            _showSleepDialog(this.context, ref);
          },
        ),
        MoreItem(
          icon: const Icon(
            LucideIcons.gauge,
            size: AfIconSizes.sm,
            color: AfColors.textSecondary,
          ),
          label: 'Playback speed',
          onTap: () {
            dismiss();
            showSpeedDialog(this.context, ref);
          },
        ),
        MoreItem(
          icon: const Icon(
            LucideIcons.cast,
            size: AfIconSizes.sm,
            color: AfColors.textSecondary,
          ),
          label: 'Audio output',
          onTap: () {
            dismiss();
            showOutputDialog(this.context, ref);
          },
        ),
        MoreItem(
          icon: const Icon(
            LucideIcons.volume2,
            size: AfIconSizes.sm,
            color: AfColors.textSecondary,
          ),
          label: 'Volume',
          onTap: () {
            dismiss();
            showVolumeDialog(this.context, ref);
          },
        ),
        MoreItem(
          icon: const Icon(
            LucideIcons.bluetooth,
            size: AfIconSizes.sm,
            color: AfColors.textSecondary,
          ),
          label: 'Audio delay',
          onTap: () {
            dismiss();
            showAudioDelayDialog(this.context, ref);
          },
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: AfSpacing.s24),
          child: MoreItem(
            icon: const Icon(
              LucideIcons.info,
              size: AfIconSizes.sm,
              color: AfColors.textSecondary,
            ),
            label: 'Show details',
            onTap: () {
              pageNotifier.value = _MorePage.details;
            },
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Save dialog (thin wrapper)
// ─────────────────────────────────────────────────────────────────────────────

void _showSaveDialog(BuildContext context, WidgetRef ref) {
  final track = ref.read(currentTrackProvider);
  if (track == null) return;
  showSaveToPlaylistSheet(context, ref, track);
}

// ─────────────────────────────────────────────────────────────────────────────
// Sleep dialog (thin wrapper)
// ─────────────────────────────────────────────────────────────────────────────

void _showSleepDialog(BuildContext context, WidgetRef ref) {
  showBlurBottomSheet<void>(
    context: context,
    builder: (context, dismiss) => SleepTimerDialogContent(dismiss: dismiss),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Details view
// ─────────────────────────────────────────────────────────────────────────────

class _DetailsView extends ConsumerWidget {
  const _DetailsView({required this.track, required this.onBack});

  final AfTrack track;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _TrackDetailsWrapper(track: track, onBack: onBack);
  }
}

class _TrackDetailsWrapper extends StatefulWidget {
  const _TrackDetailsWrapper({required this.track, required this.onBack});

  final AfTrack track;
  final VoidCallback onBack;

  @override
  State<_TrackDetailsWrapper> createState() => _TrackDetailsWrapperState();
}

class _TrackDetailsWrapperState extends State<_TrackDetailsWrapper> {
  @override
  void initState() {
    super.initState();
    HapticFeedback.mediumImpact();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) widget.onBack();
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AfSpacing.s4,
              vertical: AfSpacing.s4,
            ),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(
                    LucideIcons.arrowLeft,
                    color: AfColors.textPrimary,
                    size: AfIconSizes.sm,
                  ),
                  tooltip: 'Back',
                  onPressed: widget.onBack,
                ),
                const SizedBox(width: AfSpacing.s8),
                Text('Track Details', style: AfTypography.titleSmall),
              ],
            ),
          ),
          Flexible(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 400),
              child: TrackDetailsBody(track: widget.track),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// More item
// ─────────────────────────────────────────────────────────────────────────────

class MoreItem extends StatelessWidget {
  const MoreItem({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final Widget icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressScale(
      onTap: onTap,
      child: InkWell(
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AfSpacing.gutterGenerous,
            vertical: AfSpacing.s12,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: AfIconSizes.sm,
                height: AfIconSizes.sm,
                child: Center(child: icon),
              ),
              const SizedBox(width: AfSpacing.s16),
              SizedBox(
                height: 20,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(label, style: AfTypography.bodyMedium),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
