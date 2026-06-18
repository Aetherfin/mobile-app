import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/jellyfin/models/library.dart';
import '../../design_tokens/tokens.dart';
import '../../state/providers.dart';
import '../../widgets/af_loading_indicator.dart';
import '../../utils/log.dart';

/// Library content-type picker during first run.
///
/// Toggle switches for: Albums, Artists, Songs, Genres.
/// Continue button persists selection and navigates to home.
class LibraryScopeScreen extends ConsumerStatefulWidget {
  const LibraryScopeScreen({super.key});

  @override
  ConsumerState<LibraryScopeScreen> createState() => _LibraryScopeScreenState();
}

class _LibraryScopeScreenState extends ConsumerState<LibraryScopeScreen> {
  List<LibraryView> _views = const [];
  final _selected = <String>{};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final backend = ref.read(musicBackendProvider);
    List<LibraryView> views = const [];
    if (backend != null) {
      try {
        views = await backend.userViews();
      } on Exception catch (e) {
        afLog('onboarding', 'User views fetch failed', error: e);
      }
    }
    if (views.where((v) => v.hasAudio).length <= 1) {
      // Auto-skip when there's nothing to choose.
      if (!mounted) return;
      _selected.addAll(views.map((v) => v.id));
      ref.read(selectedLibraryIdsProvider.notifier).set(_selected.toSet());
      await context.push('/onboarding/done');
      if (!mounted) return;
      return;
    }
    if (!mounted) return;
    setState(() {
      _views = views.where((v) => v.hasAudio).toList();
      _selected.addAll(_views.map((v) => v.id));
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final spectral = ref.watch(
      currentSpectralProvider.select((s) => s.primary),
    );
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(LucideIcons.arrowLeft),
          tooltip: 'Back',
          onPressed: () => Navigator.maybePop(context),
        ),
        title: Text('Choose libraries', style: AfTypography.titleMedium),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AfSpacing.gutterGenerous,
          ),
          child: _loading
              ? const Center(child: AfLoadingIndicator())
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Text(
                        'Step 4 of 5',
                        style: AfTypography.caption.copyWith(
                          color: AfColors.textTertiary,
                        ),
                      ),
                    ),
                    Text(
                      'Pick which libraries Aetherfin should index.',
                      style: AfTypography.bodyMedium.copyWith(
                        color: AfColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: AfSpacing.s24),
                    Expanded(
                      child: ListView.separated(
                        itemCount: _views.length,
                        separatorBuilder: (context, index) =>
                            const SizedBox(height: AfSpacing.s8),
                        itemBuilder: (context, i) {
                          final v = _views[i];
                          final selected = _selected.contains(v.id);
                          return Container(
                            key: ValueKey(_views[i].id),
                            decoration: BoxDecoration(
                              color: AfColors.surfaceRaised,
                              borderRadius: AfRadii.borderMd,
                              border: Border.all(
                                color: selected
                                    ? spectral.withValues(alpha: 0.4)
                                    : AfColors.surfaceHigh,
                              ),
                            ),
                            child: CheckboxListTile(
                              value: selected,
                              onChanged: (val) {
                                setState(() {
                                  if (val == true) {
                                    _selected.add(v.id);
                                  } else {
                                    _selected.remove(v.id);
                                  }
                                });
                              },
                              controlAffinity: ListTileControlAffinity.leading,
                              shape: const RoundedRectangleBorder(
                                borderRadius: AfRadii.borderMd,
                              ),
                              activeColor: spectral,
                              title: Text(
                                v.name,
                                style: AfTypography.titleSmall,
                              ),
                              subtitle: Text(
                                v.collectionType,
                                style: AfTypography.bodySmall.copyWith(
                                  color: AfColors.textTertiary,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    ElevatedButton(
                      onPressed: () {
                        // Persist selected library IDs
                        ref
                            .read(selectedLibraryIdsProvider.notifier)
                            .set(_selected.toSet());
                        context.push('/onboarding/done');
                      },
                      child: const Text('Continue'),
                    ),
                    const SizedBox(height: AfSpacing.s24),
                  ],
                ),
        ),
      ),
    );
  }
}
