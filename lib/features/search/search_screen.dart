import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../design_tokens/tokens.dart';
import '../../state/providers.dart';
import 'search_filters.dart';
import 'search_results.dart';

// ─────────────────────────────────────────────────────────────────────────────
// SearchScreen
//
// Architecture
// ────────────
// • Query state lives in a ValueNotifier<String> so only the results
//   panel rebuilds on keystroke — the search field and header are static.
//
// • Normalization: queries are trimmed + lowercased before comparison so
//   "Radiohead", "radiohead ", " RADIOHEAD" all hit the same provider key.
//
// • Minimum length: queries shorter than 2 chars don't fire a request.
//
// • Stale-result guard: Riverpod autoDispose.family cancels in-flight
//   requests when the query key changes. The when() builder (not maybeWhen)
//   surfaces loading state so the user sees a skeleton instead of stale data.
// ─────────────────────────────────────────────────────────────────────────────

/// Minimum query length before a server request is fired.
const _kMinQueryLength = 2;

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key, this.initialQuery});

  /// When non-null, the search field is pre-filled and the query is committed
  /// immediately on build. Used when navigating here from Now Playing as a
  /// fallback when no artistId is available.
  final String? initialQuery;

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _controller = TextEditingController();
  // ValueNotifier so only the results panel rebuilds on query change.
  final _queryNotifier = ValueNotifier<String>('');
  // Filter chip selection — independent ValueNotifier so toggling
  // chips doesn't force the search field or recent-history widget
  // to rebuild.
  final _filterNotifier = ValueNotifier<SearchFilter>(SearchFilter.all);

  static const _debounce = Duration(milliseconds: 250);
  Timer? _debounceTimer;

  @override
  void initState() {
    super.initState();
    // Pre-fill the search field if an initial query was provided (e.g. when
    // tapping an artist name in Now Playing with no artistId).
    final q = widget.initialQuery?.trim();
    if (q != null && q.length >= _kMinQueryLength) {
      _controller.text = q;
      _queryNotifier.value = q.toLowerCase();
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          unawaited(ref.read(searchHistoryProvider.notifier).push(q.toLowerCase()));
        }
      });
    }
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _controller.dispose();
    _queryNotifier.dispose();
    _filterNotifier.dispose();
    super.dispose();
  }

  void _onChanged(String raw) {
    _debounceTimer?.cancel();
    // Normalize: trim + lowercase for consistent provider key.
    final normalized = raw.trim().toLowerCase();

    // Empty → collapse to idle immediately (feels instant on clear).
    if (normalized.isEmpty) {
      _queryNotifier.value = '';
      return;
    }

    // Below minimum length → show idle, don't fire request.
    if (normalized.length < _kMinQueryLength) {
      _queryNotifier.value = '';
      return;
    }

    // Debounce: wait for typing to settle before firing.
    _debounceTimer = Timer(_debounce, () {
      if (!mounted) return;
      if (_queryNotifier.value == normalized) return;
      _queryNotifier.value = normalized;
      // Persist the committed query as a recent search. We push on
      // debounce-commit (not every keystroke) so the history only
      // captures queries the user actually waited on a result for.
      unawaited(ref.read(searchHistoryProvider.notifier).push(normalized));
    });
  }

  /// Re-run a recent search from the chip row — sets the field text,
  /// commits the query immediately (no debounce — the chip tap is
  /// already a deliberate commit), and re-promotes the entry to the
  /// head of the history.
  void _runRecent(String query) {
    _debounceTimer?.cancel();
    _controller.text = query;
    _controller.selection = TextSelection.collapsed(offset: query.length);
    _queryNotifier.value = query;
    unawaited(ref.read(searchHistoryProvider.notifier).push(query));
  }

  @override
  Widget build(BuildContext context) {
    final spectral = ref.watch(
      currentSpectralProvider.select(
        (s) => (primary: s.primary, secondary: s.secondary),
      ),
    );
    return Scaffold(
      backgroundColor: AfColors.surfaceCanvas,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AfSpacing.s16,
                AfSpacing.s8,
                AfSpacing.s16,
                AfSpacing.s16,
              ),
              child: ShaderMask(
                shaderCallback: (bounds) => LinearGradient(
                  colors: [spectral.primary, spectral.secondary],
                ).createShader(bounds),
                child: Text(
                  'Search',
                  style: AfTypography.display.copyWith(
                    color: AfColors.textOnPrimary,
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AfSpacing.s16),
              child: TextField(
                controller: _controller,
                autofocus: true,
                textInputAction: TextInputAction.search,
                decoration: const InputDecoration(
                  labelText: 'Search music',
                  hintText: 'Artists, albums, tracks…',
                  prefixIcon: Icon(
                    LucideIcons.search,
                    color: AfColors.textTertiary,
                    size: AfIconSizes.sm,
                  ),
                ),
                onChanged: _onChanged,
                onSubmitted: (_) {
                  // Commit immediately on keyboard search action.
                  _debounceTimer?.cancel();
                  final normalized = _controller.text.trim().toLowerCase();
                  if (normalized.length >= _kMinQueryLength) {
                    _queryNotifier.value = normalized;
                    unawaited(
                      ref.read(searchHistoryProvider.notifier).push(normalized),
                    );
                  }
                },
              ),
            ),
            const SizedBox(height: AfSpacing.s12),
            // Filter chips — only visible once a query is committed.
            ValueListenableBuilder<String>(
              valueListenable: _queryNotifier,
              builder: (context, query, _) {
                if (query.isEmpty) return const SizedBox.shrink();
                return ValueListenableBuilder<SearchFilter>(
                  valueListenable: _filterNotifier,
                  builder: (context, filter, _) => SearchFilterChips(
                    selected: filter,
                    onChanged: (next) => _filterNotifier.value = next,
                  ),
                );
              },
            ),
            Expanded(
              // ValueListenableBuilder: only this subtree rebuilds on query change.
              child: ValueListenableBuilder<String>(
                valueListenable: _queryNotifier,
                builder: (context, query, _) => query.isEmpty
                    ? SearchIdleState(onRecent: _runRecent)
                    : ValueListenableBuilder<SearchFilter>(
                        valueListenable: _filterNotifier,
                        builder: (context, filter, _) =>
                            LiveSearchResults(query: query, filter: filter),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
