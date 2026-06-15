import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/jellyfin/models/items.dart';
import '../../core/lyrics/lrc_parser.dart';
import '../../core/local/local_backend.dart';
import '../../core/local/saf_picker.dart';
import '../../design_tokens/tokens.dart';
import '../../state/providers.dart';
import '../../widgets/press_scale.dart';

/// Synced lyrics list with auto-scroll, tap-to-seek, and user scroll pause.
class LyricsList extends ConsumerStatefulWidget {
  const LyricsList({
    super.key,
    required this.lrc,
    required this.spectralEnergy,
    required this.scrollController,
    required this.isSynced,
  });

  final Lrc lrc;
  final Color spectralEnergy;
  final ScrollController scrollController;
  final bool isSynced;

  @override
  ConsumerState<LyricsList> createState() => _LyricsListState();
}

class _LyricsListState extends ConsumerState<LyricsList> {
  /// Estimated height of a single lyric row in logical pixels.
  static const double _rowHeight = 36.0;

  int _lastScrolledIndex = -1;
  bool _userScrolled = false;
  Timer? _userScrollTimer;

  @override
  void initState() {
    super.initState();
    widget.scrollController.addListener(_onScroll);
  }

  @override
  void didUpdateWidget(covariant LyricsList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scrollController != widget.scrollController) {
      oldWidget.scrollController.removeListener(_onScroll);
      widget.scrollController.addListener(_onScroll);
    }
  }

  @override
  void dispose() {
    widget.scrollController.removeListener(_onScroll);
    _userScrollTimer?.cancel();
    super.dispose();
  }

  void _onScroll() {
    if (widget.scrollController.hasClients &&
        widget.scrollController.position.userScrollDirection !=
            ScrollDirection.idle) {
      if (!_userScrolled) {
        setState(() {
          _userScrolled = true;
        });
      }
      _userScrollTimer?.cancel();
      _userScrollTimer = Timer(const Duration(seconds: 4), () {
        if (mounted) {
          setState(() {
            _userScrolled = false;
            _lastScrolledIndex = -1;
          });
        }
      });
    }
  }

  /// Scroll the list so the active line sits in the vertical centre,
  /// but never below the centre — even when near the end of the list.
  void _scrollToActive(int activeIndex, int lineCount) {
    if (!widget.scrollController.hasClients) {
      _lastScrolledIndex = -1;
      return;
    }

    final viewportHeight = widget.scrollController.position.viewportDimension;
    final minScroll = widget.scrollController.position.minScrollExtent;
    final maxScroll = widget.scrollController.position.maxScrollExtent;

    final expectedContentHeight = lineCount * _rowHeight;
    if (maxScroll == 0.0 && expectedContentHeight > viewportHeight) {
      _lastScrolledIndex = -1;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
      return;
    }

    const paddingTop = AfSpacing.s16;
    final activeLinePos = paddingTop + activeIndex * _rowHeight;
    final idealCenter = activeLinePos - (viewportHeight / 2) + (_rowHeight / 2);
    final maxSafe = activeLinePos - (viewportHeight / 2);
    final clamped = idealCenter.clamp(
      minScroll,
      maxScroll < maxSafe ? maxScroll : maxSafe,
    );

    widget.scrollController.animateTo(
      clamped,
      duration: AfDurations.standard,
      curve: AfCurves.easeStandard,
    );
  }

  @override
  Widget build(BuildContext context) {
    final position = widget.isSynced
        ? ref.watch(positionStreamProvider)
        : Duration.zero;
    final active = widget.isSynced ? widget.lrc.activeIndex(position) : -1;

    // Auto-scroll to active line.
    if (widget.lrc.lines.isNotEmpty &&
        active >= 0 &&
        active != _lastScrolledIndex &&
        !_userScrolled) {
      _lastScrolledIndex = active;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToActive(active, widget.lrc.lines.length);
      });
    }

    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.35,
      child: ListView.builder(
        controller: widget.scrollController,
        padding: const EdgeInsets.symmetric(
          horizontal: AfSpacing.s16,
          vertical: AfSpacing.s4,
        ),
        itemCount: widget.lrc.lines.length,
        itemBuilder: (context, i) {
          final isActive = i == active;
          final line = widget.lrc.lines[i];
          return PressScale(
            onTap: widget.isSynced
                ? () {
                    unawaited(HapticFeedback.selectionClick());
                    ref.read(playerServiceProvider).seek(line.start);
                  }
                : null,
            ensureHitTarget: false,
            pressedScale: 0.98,
            duration: AfDurations.instant,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: AfSpacing.s4),
              child: AnimatedDefaultTextStyle(
                duration: AfDurations.quick,
                style: AfTypography.bodyLarge.copyWith(
                  color: isActive
                      ? widget.spectralEnergy
                      : AfColors.textPrimary.withValues(alpha: 0.5),
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                  shadows: isActive
                      ? [
                          Shadow(
                            color: widget.spectralEnergy.withValues(alpha: 0.5),
                            blurRadius: 8,
                          ),
                        ]
                      : null,
                ),
                child: Text(line.text),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Empty lyrics state — with LRC file import for local backends.
class EmptyLyrics extends ConsumerWidget {
  const EmptyLyrics({super.key, required this.track});
  final AfTrack track;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spectral = ref.watch(
      currentSpectralProvider.select((s) => s.primary),
    );
    final backend = ref.watch(musicBackendProvider);
    final isLocal = backend is LocalBackend;

    return Padding(
      padding: const EdgeInsets.all(AfSpacing.s24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'No lyrics available',
            style: AfTypography.bodyMedium.copyWith(
              color: AfColors.textTertiary,
            ),
          ),
          if (isLocal) ...[
            const SizedBox(height: AfSpacing.s12),
            FilledButton.icon(
              onPressed: () async {
                final lyricsContent = await SafPicker.pickAndReadLrcFile();
                if (lyricsContent == null || lyricsContent.trim().isEmpty) {
                  return;
                }

                final success = await backend.saveSidecarLrc(
                  track.id,
                  lyricsContent,
                );
                if (success) {
                  ref.invalidate(lyricsProvider(track.id));
                } else {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Failed to save lyrics')),
                    );
                  }
                }
              },
              icon: const Icon(LucideIcons.upload, size: 18),
              label: const Text('Load LRC File'),
              style: FilledButton.styleFrom(backgroundColor: spectral),
            ),
          ],
        ],
      ),
    );
  }
}
