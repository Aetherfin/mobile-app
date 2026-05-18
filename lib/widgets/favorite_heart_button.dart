import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/jellyfin/models/items.dart';
import '../design_tokens/tokens.dart';
import '../state/providers.dart';
import '../utils/display_error.dart';
import '../utils/log.dart';

/// Tappable heart button for a single [AfTrack].
///
/// Drives `backend.setFavorite(trackId, next)` directly and manages an
/// **optimistic local flip** so the icon updates on the next frame —
/// the round-trip to the server is hidden behind the user's tap. On
/// failure the flip is reverted and a `SnackBar` surfaces `displayError`.
///
/// This widget replaces the previously-dead `onHeartTap` callback hole
/// in [TrackRow]: every list screen that rendered a `TrackRow` with
/// `showHeart: true` (Album, Playlist, Search, Home Recently-Played,
/// Library, Artist, Smart Playlist) showed a `Icon(Icons.favorite_…)`
/// inside an `IconButton(onPressed: null)`. The button was disabled —
/// taps did nothing — even though the heart was visually present. The
/// `favoriteToggleProvider` only worked from `now_playing_screen.dart`
/// because it special-cases `currentTrackProvider`; non-current tracks
/// never had a wired-up handler at all.
///
/// Invalidates the Home/Library favorite providers on success so a
/// favorited track immediately shows up in "Favorites" rows without
/// a manual pull-to-refresh. Also keeps `currentTrackProvider` in sync
/// when the tapped track is the one currently playing — otherwise the
/// Now Playing screen would lag behind a list-screen toggle.
///
/// Uses `didUpdateWidget` to re-seed local state when the parent
/// re-fetches the track (e.g. after a favorite-provider invalidation)
/// — but skips re-seeding while a toggle is in flight so the optimistic
/// state isn't clobbered.
class FavoriteHeartButton extends ConsumerStatefulWidget {
  /// The track to favorite/unfavorite. Only `id` and `isFavorite` are
  /// read; the rest of the model is forwarded to `currentTrackProvider`
  /// when this row is the playing track.
  final AfTrack track;

  /// Heart icon size in logical pixels (default 20, matching the
  /// previous inline `IconButton` styling in `TrackRow`).
  final double size;

  const FavoriteHeartButton({
    super.key,
    required this.track,
    this.size = 20,
  });

  @override
  ConsumerState<FavoriteHeartButton> createState() =>
      _FavoriteHeartButtonState();
}

class _FavoriteHeartButtonState extends ConsumerState<FavoriteHeartButton> {
  late bool _isFavorite;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _isFavorite = widget.track.isFavorite;
  }

  @override
  void didUpdateWidget(covariant FavoriteHeartButton old) {
    super.didUpdateWidget(old);
    // Sync with parent when the source-of-truth track changes — but not
    // mid-toggle, so we don't clobber the optimistic flip with the stale
    // pre-toggle value.
    if (!_busy && old.track.isFavorite != widget.track.isFavorite) {
      _isFavorite = widget.track.isFavorite;
    }
  }

  Future<void> _toggle() async {
    if (_busy) return;
    final backend = ref.read(musicBackendProvider);
    if (backend == null) return; // signed-out / demo mode

    final next = !_isFavorite;
    setState(() {
      _busy = true;
      _isFavorite = next;
    });

    // Keep `currentTrackProvider` in sync if this is the playing track,
    // so Now Playing's heart icon doesn't lag a list-screen toggle.
    final current = ref.read(currentTrackProvider);
    if (current?.id == widget.track.id) {
      ref.read(currentTrackProvider.notifier).state =
          current!.copyWith(isFavorite: next);
    }

    try {
      await backend.setFavorite(widget.track.id, next);
      afLog(
        'data',
        'trackFavorite source=live id=${widget.track.id} isFavorite=$next',
      );
      // Refresh the rails that surface favorites/recents on Home and
      // Library so they pick up this change without a pull-to-refresh.
      ref.invalidate(favoriteAlbumsProvider);
      ref.invalidate(favoriteTracksProvider);
      ref.invalidate(recentlyPlayedTracksProvider);
    } catch (e, stack) {
      afLog('error', 'trackFavorite toggle failed',
          error: e, stackTrace: stack);
      if (!mounted) return;
      setState(() => _isFavorite = !next);
      // Revert the playing-track copy if we were the source of truth.
      if (current?.id == widget.track.id) {
        ref.read(currentTrackProvider.notifier).state = current;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text(displayError(e, prefix: 'Could not update favorite')),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(
        _isFavorite ? Icons.favorite : Icons.favorite_border,
        color: _isFavorite ? AfColors.semanticError : AfColors.textTertiary,
        size: widget.size,
      ),
      onPressed: _toggle,
      tooltip: _isFavorite ? 'Unfavorite' : 'Favorite',
      padding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints(
        minWidth: AfSpacing.minHitTarget,
        minHeight: AfSpacing.minHitTarget,
      ),
    );
  }
}
