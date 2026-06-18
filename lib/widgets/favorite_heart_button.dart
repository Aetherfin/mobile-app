import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/jellyfin/models/items.dart';
import '../design_tokens/tokens.dart';
import '../state/providers.dart';
import '../utils/display_error.dart';
import '../utils/log.dart';

/// Tappable heart button for a single [AfTrack].
///
/// Drives `backend.setFavorite(trackId, next)` directly and writes the
/// optimistic flip into the session-wide
/// [trackFavoriteOverridesProvider] so every heart for the same track
/// id flips in lock-step. On failure the override is rolled back and a
/// `SnackBar` surfaces `displayError`.
class FavoriteHeartButton extends ConsumerStatefulWidget {
  const FavoriteHeartButton({super.key, required this.track, this.size = 20});

  final AfTrack track;

  /// Heart icon size in logical pixels (default 20).
  final double size;

  @override
  ConsumerState<FavoriteHeartButton> createState() =>
      _FavoriteHeartButtonState();
}

class _FavoriteHeartButtonState extends ConsumerState<FavoriteHeartButton>
    with SingleTickerProviderStateMixin {
  bool _busy = false;

  late final AnimationController _pulseCtrl = AnimationController(
    vsync: this,
    duration: AfDurations.quick,
    reverseDuration: AfDurations.standard,
  );
  late final Animation<double> _pulseScale = TweenSequence([
    TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.35), weight: 40),
    TweenSequenceItem(tween: Tween(begin: 1.35, end: 1.0), weight: 60),
  ]).animate(CurvedAnimation(parent: _pulseCtrl, curve: AfCurves.easeStandard));

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  bool _isFavoriteFromOverrides(Map<String, bool> overrides) =>
      overrides[widget.track.id] ?? widget.track.isFavorite;

  Future<void> _toggle() async {
    if (_busy) return;
    final backend = ref.read(musicBackendProvider);
    if (backend == null) return;

    final overrides = ref.read(trackFavoriteOverridesProvider);
    final wasFavorite = _isFavoriteFromOverrides(overrides);
    final next = !wasFavorite;
    setState(() => _busy = true);

    ref
        .read(trackFavoriteOverridesProvider.notifier)
        .update((s) => {...s, widget.track.id: next});

    unawaited(_pulseCtrl.forward(from: 0));

    final current = ref.read(currentTrackProvider);
    if (current?.id == widget.track.id) {
      ref
          .read(currentTrackProvider.notifier)
          .set(current!.copyWith(isFavorite: next));
    }

    try {
      await backend.setFavorite(widget.track.id, next);
      afLog(
        'data',
        'trackFavorite source=live id=${widget.track.id} isFavorite=$next',
      );
      ref.invalidate(favoriteAlbumsProvider);
      ref.invalidate(favoriteTracksProvider);
      ref.invalidate(recentlyPlayedTracksProvider);
    } on Exception catch (e, stack) {
      afLog(
        'error',
        'trackFavorite toggle failed',
        error: e,
        stackTrace: stack,
      );
      if (!mounted) return;
      ref
          .read(trackFavoriteOverridesProvider.notifier)
          .update((s) => {...s, widget.track.id: wasFavorite});
      if (current?.id == widget.track.id) {
        ref.read(currentTrackProvider.notifier).set(current);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(displayError(e, prefix: 'Could not update favorite')),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isFavorite = ref.watch(
      trackFavoriteOverridesProvider.select(
        (map) => map[widget.track.id] ?? widget.track.isFavorite,
      ),
    );
    final icon = Icon(
      isFavorite ? LucideIcons.heart : LucideIcons.heart,
      color: isFavorite ? AfColors.semanticError : AfColors.textTertiary,
      size: widget.size,
    );
    return Semantics(
      toggled: isFavorite,
      label: isFavorite ? 'Unlike' : 'Like',
      child: IconButton(
        icon: ScaleTransition(scale: _pulseScale, child: icon),
        onPressed: _toggle,
        tooltip: isFavorite ? 'Unlike' : 'Like',
        padding: EdgeInsets.zero,
        visualDensity: VisualDensity.compact,
        constraints: const BoxConstraints(
          minWidth: AfSpacing.minHitTarget,
          minHeight: AfSpacing.minHitTarget,
        ),
      ),
    );
  }
}
