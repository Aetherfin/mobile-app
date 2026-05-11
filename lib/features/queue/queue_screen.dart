import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/jellyfin/models/items.dart';
import '../../design_tokens/tokens.dart';
import '../../state/providers.dart';
import '../../widgets/track_row.dart';

/// Live queue mirror. Watches `playerQueueProvider` (a broadcast stream
/// on top of `AfPlayerService.queueStream`) so the list reflects the
/// actual player state — reorder / skip / play-new-album shows up the
/// moment the player applies it, without snapshotting `DemoLibrary`.
class QueueScreen extends ConsumerStatefulWidget {
  const QueueScreen({super.key});

  @override
  ConsumerState<QueueScreen> createState() => _QueueScreenState();
}

class _QueueScreenState extends ConsumerState<QueueScreen> {
  /// Local mutable mirror of the player queue — needed because
  /// `ReorderableListView` requires synchronous list mutation in its
  /// `onReorder` callback. Refreshed whenever the player emits a new
  /// queue snapshot.
  List<AfTrack> _items = const [];
  List<String> _lastQueueIds = const [];

  @override
  Widget build(BuildContext context) {
    final queueAsync = ref.watch(playerQueueProvider);
    final current = ref.watch(currentTrackProvider);

    final liveQueue = queueAsync.maybeWhen(
      data: (q) => q,
      orElse: () => const <AfTrack>[],
    );

    // Sync our mutable mirror whenever the player's queue identity
    // changes (compared as ID sequence so a reorder we just performed
    // doesn't get clobbered the moment the stream re-emits the new
    // order back at us).
    final liveIds = liveQueue.map((t) => t.id).toList(growable: false);
    if (!_listsMatch(liveIds, _lastQueueIds)) {
      _items = List<AfTrack>.from(liveQueue);
      _lastQueueIds = liveIds;
    }

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.keyboard_arrow_down_rounded),
          onPressed: () => Navigator.maybePop(context),
        ),
        title: Text('Queue', style: AfTypography.titleSmall),
        actions: [
          Consumer(builder: (context, ref, _) {
            final shuffleOn = ref.watch(shuffleModeProvider).maybeWhen(
                  data: (v) => v,
                  orElse: () => false,
                );
            return IconButton(
              icon: Icon(
                Icons.shuffle_rounded,
                color: shuffleOn
                    ? AfColors.indigo300
                    : AfColors.textPrimary,
              ),
              tooltip: shuffleOn ? 'Shuffle on' : 'Shuffle',
              onPressed: () {
                final svc = ref.read(playerServiceProvider);
                svc.setAfShuffleMode(!svc.isShuffleEnabled);
              },
            );
          }),
          IconButton(
            icon: const Icon(Icons.lyrics_outlined),
            onPressed: () => context.go('/lyrics'),
            tooltip: 'Lyrics',
          ),
        ],
      ),
      body: SafeArea(
        child: _items.isEmpty
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AfSpacing.gutterGenerous,
                  ),
                  child: Text(
                    'Queue is empty. Pick an album or track to start playback.',
                    style: AfTypography.bodyMedium.copyWith(
                      color: AfColors.textTertiary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              )
            : ReorderableListView.builder(
                padding: const EdgeInsets.symmetric(
                    horizontal: AfSpacing.s16, vertical: AfSpacing.s8),
                itemCount: _items.length,
                buildDefaultDragHandles: false,
                onReorder: (oldIndex, newIndex) {
                  setState(() {
                    if (newIndex > oldIndex) newIndex -= 1;
                    final item = _items.removeAt(oldIndex);
                    _items.insert(newIndex, item);
                  });
                },
                itemBuilder: (context, i) {
                  final t = _items[i];
                  final active = current?.id == t.id;
                  return Padding(
                    key: ValueKey(t.id),
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      children: [
                        Expanded(
                          child: TrackRow(
                            track: t,
                            density: TrackRowDensity.compact,
                            isActive: active,
                            showHeart: false,
                          ),
                        ),
                        ReorderableDragStartListener(
                          index: i,
                          child: const Padding(
                            padding: EdgeInsets.symmetric(
                                horizontal: AfSpacing.s8),
                            child: Icon(Icons.drag_indicator_rounded,
                                color: AfColors.textTertiary),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
      ),
    );
  }

  static bool _listsMatch(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
