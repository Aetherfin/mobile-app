import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/jellyfin/models/items.dart';
import '../design_tokens/tokens.dart';
import '../state/providers.dart';
import '../utils/display_error.dart';
import '../utils/log.dart';

/// Tappable heart button for a single [AfTrack].
///
/// Drives `backend.setFavorite(trackId, next)` directly and writes the
/// **optimistic flip** into the session-wide
/// [trackFavoriteOverridesProvider] so every heart for the same track
/// id — on the album screen, the playlist screen, search results, the
/// Now Playing icon — flips in lock-step. The round-trip to the server
/// is hidden behind the user's tap. On failure the override is rolled
/// back to the previous value and a `SnackBar` surfaces `displayError`.
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
/// Displayed state is derived from
/// `trackFavoriteOverridesProvider[track.id] ?? track.isFavorite`, so
/// a toggle from anywhere is reflected here as soon as Riverpod
/// rebuilds — no `didUpdateWidget` / local mirror dance needed.
/// `_busy` stays local because it gates *this* button's request, not
/// the global toggle state.
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
  bool _busy = false;

  /// Authoritative "is this track favorited *right now*" — overrides
  /// the (potentially stale) `widget.track.isFavorite` field cached on
  /// whatever provider produced the track list.
  bool _isFavoriteFromOverrides(Map<String, bool> overrides) =>
      overrides[widget.track.id] ?? widget.track.isFavorite;

  Future<void> _toggle() async {
    if (_busy) return;
    final backend = ref.read(musicBackendProvider);
    if (backend == null) return; // signed-out / demo mode

    final overrides = ref.read(trackFavoriteOverridesProvider);
    final wasFavorite = _isFavoriteFromOverrides(overrides);
    final next = !wasFavorite;
    setState(() => _busy = true);

    // Optimistic global flip — every heart for this track id rebuilds
    // immediately, including this one (via the `ref.watch` in `build`).
    ref.read(trackFavoriteOverridesProvider.notifier).update(
          (s) => {...s, widget.track.id: next},
        );

    // Keep `currentTrackProvider` in sync if this is the playing track,
    // so Now Playing's icon doesn't lag a list-screen toggle.
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
      // Roll the override back to the pre-toggle value (which itself
      // might have been an earlier override or the model default).
      ref.read(trackFavoriteOverridesProvider.notifier).update(
            (s) => {...s, widget.track.id: wasFavorite},
          );
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
    final overrides = ref.watch(trackFavoriteOverridesProvider);
    final isFavorite = _isFavoriteFromOverrides(overrides);
    return IconButton(
      icon: Icon(
        isFavorite ? Icons.favorite : Icons.favorite_border,
        color: isFavorite ? AfColors.semanticError : AfColors.textTertiary,
        size: widget.size,
      ),
      onPressed: _toggle,
      tooltip: isFavorite ? 'Unfavorite' : 'Favorite',
      padding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints(
        minWidth: AfSpacing.minHitTarget,
        minHeight: AfSpacing.minHitTarget,
      ),
    );
  }
}
