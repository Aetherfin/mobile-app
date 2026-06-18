import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/jellyfin/models/items.dart';
import '../../design_tokens/tokens.dart';
import '../../widgets/track_context_menu.dart';
import '../../widgets/track_row.dart';

/// The reorderable, swipe-to-remove queue list used inside [QueueScreen].
///
/// Extracted to keep the parent file under 250 LOC.
class QueueListView extends ConsumerWidget {
  const QueueListView({
    super.key,
    required this.items,
    required this.currentId,
    required this.isBuffering,
    required this.scrollController,
    this.isSelectionMode = false,
    this.selectedIndices = const {},
    required this.onReorder,
    required this.onDismiss,
    required this.onTap,
    this.onLongPress,
    this.onSelectToggle,
  });

  final List<AfTrack> items;
  final String? currentId;
  final bool isBuffering;
  final ScrollController scrollController;
  final bool isSelectionMode;
  final Set<int> selectedIndices;
  final void Function(int oldIndex, int newIndex) onReorder;
  final void Function(int index, AfTrack track) onDismiss;
  final void Function(int index) onTap;
  final void Function(int index)? onLongPress;
  final void Function(int index)? onSelectToggle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ReorderableListView.builder(
      scrollController: scrollController,
      padding: const EdgeInsets.only(
        top: AfSpacing.s16,
        bottom: AfSpacing.s8,
        left: AfSpacing.s16,
        right: AfSpacing.s16,
      ),
      itemCount: items.length,
      buildDefaultDragHandles: false,
      onReorderItem: onReorder,
      itemBuilder: (context, i) {
        final t = items[i];
        final active = currentId == t.id;
        final selected = selectedIndices.contains(i);
        return Semantics(
          key: ValueKey('q-${t.id}-$i'),
          label: '${i + 1}. ${t.title} by ${t.artistName}',
          child: Dismissible(
            key: ValueKey('d-${t.id}-$i'),
            direction: isSelectionMode || active
                ? DismissDirection.none
                : DismissDirection.endToStart,
            background: Container(
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.symmetric(horizontal: AfSpacing.s24),
              color: AfColors.semanticError.withValues(alpha: 0.25),
              child: const Icon(
                LucideIcons.trash2,
                color: AfColors.semanticError,
              ),
            ),
            confirmDismiss: (_) async {
              if (active) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Skip to remove the currently playing track.',
                    ),
                    duration: AfDurations.snackBarInfo,
                  ),
                );
                return false;
              }
              unawaited(HapticFeedback.lightImpact());
              return true;
            },
            onDismissed: (_) => onDismiss(i, t),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: AfSpacing.s4),
              child: Container(
                decoration: active
                    ? const BoxDecoration(
                        color: AfColors.surfaceBase,
                        borderRadius: AfRadii.borderMd,
                      )
                    : null,
                child: Row(
                  children: [
                    if (isSelectionMode)
                      GestureDetector(
                        onTap: () => onSelectToggle?.call(i),
                        child: Semantics(
                          button: true,
                          label: 'Select track: ${t.title}',
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AfSpacing.s12,
                            ),
                            child: Icon(
                              selected
                                  ? LucideIcons.circleCheck
                                  : LucideIcons.circle,
                              size: 22,
                              color: selected
                                  ? AfColors.accentPrimary
                                  : AfColors.textTertiary,
                            ),
                          ),
                        ),
                      ),
                    Expanded(
                      child: TrackRow(
                        track: t,
                        density: TrackRowDensity.compact,
                        isActive: active,
                        isBuffering: active && isBuffering,
                        showHeart: false,
                        onTap: () => onTap(i),
                        onLongPress: onLongPress != null
                            ? () => onLongPress!(i)
                            : () => showTrackContextMenu(context, ref, t),
                      ),
                    ),
                    if (!isSelectionMode)
                      ReorderableDragStartListener(
                        index: i,
                        child: const Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: AfSpacing.s8,
                          ),
                          child: Icon(
                            LucideIcons.gripVertical,
                            color: AfColors.textTertiary,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
