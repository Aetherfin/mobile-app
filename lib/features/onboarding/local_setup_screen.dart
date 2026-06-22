import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/local/app_mode_store.dart';
import '../../design_tokens/tokens.dart';
import '../../state/providers.dart';
import '../../widgets/press_scale.dart';
import '../../widgets/stagger_reveal.dart';

/// Onboarding screen for local mode: pick a folder, scan it, then proceed.
///
/// SAF folder picker with permission request flow and library path display.
class LocalSetupScreen extends ConsumerStatefulWidget {
  const LocalSetupScreen({super.key});

  @override
  ConsumerState<LocalSetupScreen> createState() => _LocalSetupScreenState();
}

class _LocalSetupScreenState extends ConsumerState<LocalSetupScreen> {
  String? _folderUri;
  String? _folderDisplay;
  bool _scanning = false;
  int _scannedCount = 0;
  int _totalCount = 0;
  String? _error;

  Future<void> _pickFolder() async {
    setState(() => _error = null);
    final library = ref.read(localLibraryProvider);
    final uri = await library.pickAndAddFolder();
    if (uri == null) return;
    final folders = await ref.read(localLibraryProvider).getFolders();
    final folder = folders.lastOrNull;
    if (!mounted) return;
    setState(() {
      _folderUri = uri;
      _folderDisplay = folder?.displayPath ?? uri;
    });
  }

  Future<void> _startScan() async {
    if (_folderUri == null) return;
    setState(() {
      _scanning = true;
      _scannedCount = 0;
      _totalCount = 0;
      _error = null;
    });

    try {
      final count = await ref
          .read(localLibraryProvider)
          .scanFolder(
            _folderUri!,
            onProgress: (completed, total) {
              if (mounted) {
                setState(() {
                  _scannedCount = completed;
                  _totalCount = total;
                });
                ref.read(localScanProgressProvider.notifier).set((
                  completed: completed,
                  total: total,
                ));
              }
            },
          );

      if (!mounted) return;
      ref.read(localScanProgressProvider.notifier).set(null);

      if (count == 0 && _totalCount == 0) {
        setState(() {
          _scanning = false;
          _error = 'No audio files found in this folder.';
        });
        return;
      }

      setState(() => _scanning = false);
      // Invalidate local providers so home/library screens pick up the data.
      ref.invalidate(localAlbumsProvider);
      ref.invalidate(localArtistsProvider);
      ref.invalidate(localTracksProvider);
      ref.invalidate(localGenresProvider);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('af.local_onboarding_completed', true);

      if (mounted) {
        // Setting this provider triggers onboardingSub in main.dart, which
        // calls notifyAuthChanged() → router redirect returns '/home'.
        // Do NOT call context.go('/home') — that races with the redirect's
        // internal navigation and produces a blank screen.
        ref.read(localOnboardingCompletedProvider.notifier).set(true);
      }
    } on Exception {
      if (mounted) {
        setState(() {
          _scanning = false;
          _error =
              'Scan failed. Check that the folder exists and contains audio files (MP3, FLAC, AAC, OGG, or M4A).';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final spectral = ref.watch(
      currentSpectralProvider.select((s) => s.primary),
    );
    return Scaffold(
      backgroundColor: AfColors.surfaceCanvas,
      appBar: AppBar(
        backgroundColor: AfColors.surfaceCanvas,
        surfaceTintColor: AfColors.transparent,
        title: Text('Local files', style: AfTypography.titleMedium),
        leading: IconButton(
          icon: const Icon(LucideIcons.arrowLeft),
          tooltip: 'Back',
          onPressed: () async {
            // Reset mode on back — user wants to re-decide at the
            // WelcomeScreen. This also prevents stale redirects on
            // app restart after going back.
            await AppModeStore.clear();
            if (context.mounted) {
              ref.read(appModeProvider.notifier).set(null);
              // null triggers resetRouterMode() in main.dart's modeSub,
              // clearing the router's _appMode and _localOnboardingCompleted.
              //
              // Use go('/') instead of pop() to avoid redirect race:
              // notifyAuthChanged() from modeSub fires synchronously and
              // causes GoRouter to re-evaluate the redirect mid-pop,
              // resulting in a "reload" of the same screen.
              context.go('/');
            }
          },
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AfSpacing.s24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Text(
                  'Step 2 of 2',
                  style: AfTypography.caption.copyWith(
                    color: AfColors.textTertiary,
                  ),
                ),
              ),
              StaggerReveal(
                children: [
                  const SizedBox(height: AfSpacing.s24),
                  Text(
                    'Select music folder',
                    style: AfTypography.titleLarge,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AfSpacing.s8),
                  Text(
                    'Pick a folder containing your music files. '
                    'Aetherfin will scan it for audio.',
                    style: AfTypography.bodyMedium.copyWith(
                      color: AfColors.textSecondary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AfSpacing.s32),

                  // Folder selection
                  Material(
                    color: AfColors.surfaceRaised,
                    borderRadius: AfRadii.borderLg,
                    child: PressScale(
                      onTap: _scanning ? null : _pickFolder,
                      child: Container(
                        padding: const EdgeInsets.all(AfSpacing.s16),
                        decoration: BoxDecoration(
                          borderRadius: AfRadii.borderLg,
                          border: Border.all(
                            color: _folderUri != null
                                ? spectral.withValues(alpha: 0.4)
                                : AfColors.surfaceHigh,
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                color: spectral.withValues(alpha: 0.15),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                LucideIcons.folderOpen,
                                color: spectral,
                              ),
                            ),
                            const SizedBox(width: AfSpacing.s12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _folderUri != null
                                        ? 'Folder selected'
                                        : 'Tap to choose a folder',
                                    style: AfTypography.bodyMedium,
                                  ),
                                  if (_folderDisplay != null)
                                    Text(
                                      _folderDisplay!,
                                      style: AfTypography.bodySmall.copyWith(
                                        color: AfColors.textTertiary,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                ],
                              ),
                            ),
                            if (_folderUri == null)
                              const Icon(
                                LucideIcons.plus,
                                color: AfColors.textTertiary,
                              ),
                            if (_folderUri != null)
                              const Icon(
                                LucideIcons.checkCircle,
                                color: AfColors.semanticSuccess,
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: AfSpacing.s24),

              // Scan progress
              if (_scanning) ...[
                LinearProgressIndicator(
                  value: _totalCount > 0 ? _scannedCount / _totalCount : null,
                  backgroundColor: AfColors.surfaceHigh,
                  valueColor: AlwaysStoppedAnimation(spectral),
                  borderRadius: AfRadii.borderXs,
                ),
                const SizedBox(height: AfSpacing.s8),
                Text(
                  _totalCount > 0
                      ? 'Scanning... $_scannedCount / $_totalCount'
                      : 'Scanning...',
                  style: AfTypography.bodySmall.copyWith(
                    color: AfColors.textTertiary,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],

              // Error
              if (_error != null) ...[
                const SizedBox(height: AfSpacing.s12),
                Text(
                  _error!,
                  style: AfTypography.bodySmall.copyWith(
                    color: AfColors.semanticError,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],

              const Spacer(),

              // Scan button
              ElevatedButton(
                onPressed: _folderUri != null && !_scanning ? _startScan : null,
                child: Text(_scanning ? 'Scanning...' : 'Scan & continue'),
              ),
              const SizedBox(height: AfSpacing.s32),
            ],
          ),
        ),
      ),
    );
  }
}
