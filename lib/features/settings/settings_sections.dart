import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/audio/player_settings_store.dart';
import '../../core/audio/player_service.dart';
import '../../design_tokens/tokens.dart';
import '../../state/providers.dart';
import 'settings_widgets.dart';

void launchSettingsUrl(String url) {
  launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
}

class MusicFoldersCard extends ConsumerStatefulWidget {
  const MusicFoldersCard({super.key});
  @override
  ConsumerState<MusicFoldersCard> createState() => MusicFoldersCardState();
}

class MusicFoldersCardState extends ConsumerState<MusicFoldersCard> {
  List<({String uri, String displayPath})> _folders = [];
  bool _loading = true;
  bool _scanning = false;
  int _scannedCount = 0;
  int _totalCount = 0;

  @override
  void initState() {
    super.initState();
    _loadFolders();
  }

  Future<void> _loadFolders() async {
    final lib = ref.read(localLibraryProvider);
    final folders = await lib.getFolders();
    if (mounted) {
      setState(() {
        _folders = folders;
        _loading = false;
      });
    }
  }

  void _onProgress(int completed, int total) {
    if (mounted) {
      setState(() {
        _scannedCount = completed;
        _totalCount = total;
      });
    }
  }

  /// Shared scan method — used by both _addFolder and _rescan.
  /// When [folderUri] is null, scans all folders; otherwise scans the given folder.
  Future<void> _startScan(String? folderUri) async {
    if (!mounted) return;
    setState(() {
      _scanning = true;
      _scannedCount = 0;
      _totalCount = 0;
    });

    final lib = ref.read(localLibraryProvider);
    try {
      int count;
      if (folderUri != null) {
        count = await lib.scanFolder(folderUri, onProgress: _onProgress);
      } else {
        count = await lib.scanAll(onProgress: _onProgress);
      }

      if (!mounted) return;

      // If we never got a progress callback, the total stayed at 0.
      // This means no files were scanned — show a clearer message.
      final msg = _totalCount == 0
          ? 'No audio files found'
          : 'Scan complete — $count tracks updated';

      ref.invalidate(localAlbumsProvider);
      ref.invalidate(localArtistsProvider);
      ref.invalidate(localTracksProvider);
      ref.invalidate(localGenresProvider);

      setState(() => _scanning = false);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(msg)));
      }
    } on Exception catch (e) {
      if (!mounted) return;
      setState(() => _scanning = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Scan failed: $e')));
    }
  }

  Future<void> _addFolder() async {
    if (_scanning) return;
    final svc = ref.read(playerServiceProvider);
    await svc.stopAndClear();

    final lib = ref.read(localLibraryProvider);
    final uri = await lib.pickAndAddFolder();
    if (uri != null) {
      await _loadFolders();
      await _startScan(uri);
    }
  }

  Future<void> _removeFolder(String uri) async {
    if (_scanning) return;
    final svc = ref.read(playerServiceProvider);
    await svc.stopAndClear();

    final lib = ref.read(localLibraryProvider);
    await lib.removeFolder(uri);
    await _loadFolders();
    ref.invalidate(localAlbumsProvider);
    ref.invalidate(localArtistsProvider);
    ref.invalidate(localTracksProvider);
    ref.invalidate(localGenresProvider);
  }

  Future<void> _rescan() async {
    if (_scanning) return;
    await _startScan(null);
  }

  @override
  Widget build(BuildContext context) {
    final spectralPrimary = ref.watch(
      currentSpectralProvider.select((s) => s.primary),
    );

    return SettingsGroup(
      children: [
        if (_loading)
          const Padding(
            padding: EdgeInsets.all(AfSpacing.s16),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_scanning)
          _buildProgressCard()
        else ...[
          for (final folder in _folders)
            SettingsTile(
              icon: LucideIcons.folder,
              iconColor: spectralPrimary,
              title: folder.displayPath,
              trailing: IconButton(
                icon: const Icon(
                  LucideIcons.circleMinus,
                  color: AfColors.semanticError,
                  size: 20,
                ),
                onPressed: () => _removeFolder(folder.uri),
              ),
            ),
          SettingsTile(
            icon: LucideIcons.plus,
            iconColor: spectralPrimary,
            title: 'Add folder',
            subtitle: 'Pick another music folder',
            onTap: _addFolder,
          ),
          SettingsTile(
            icon: LucideIcons.refreshCcw,
            iconColor: spectralPrimary,
            title: 'Re-scan library',
            subtitle: 'Check for new or changed files',
            onTap: _rescan,
          ),
        ],
      ],
    );
  }

  Widget _buildProgressCard() {
    // Before the first progress callback, show an indeterminate state
    // instead of "0 / 0 files" which looks broken.
    final hasKnownTotal = _totalCount > 0;
    return Padding(
      padding: const EdgeInsets.all(AfSpacing.s16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            hasKnownTotal
                ? 'Scanning your music folder...'
                : 'Preparing to scan...',
            style: AfTypography.bodyMedium.copyWith(
              color: AfColors.textPrimary,
            ),
          ),
          const SizedBox(height: AfSpacing.s12),
          LinearProgressIndicator(
            value: hasKnownTotal ? _scannedCount / _totalCount : null,
          ),
          if (hasKnownTotal) ...[
            const SizedBox(height: AfSpacing.s8),
            Text(
              '$_scannedCount / $_totalCount files',
              style: AfTypography.bodySmall.copyWith(
                color: AfColors.textSecondary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class PrefetchToggle extends StatefulWidget {
  const PrefetchToggle({super.key, required this.svc});
  final AfPlayerService svc;

  @override
  State<PrefetchToggle> createState() => PrefetchToggleState();
}

class PrefetchToggleState extends State<PrefetchToggle> {
  late bool _enabled;

  @override
  void initState() {
    super.initState();
    _enabled = widget.svc.prefetchPlaylist;
  }

  @override
  Widget build(BuildContext context) {
    return SettingsSwitchTile(
      icon: LucideIcons.download,
      iconColor: AfColors.textSecondary,
      title: 'Prefetch next track',
      subtitle: 'Pre-load next playlist entry in background',
      value: _enabled,
      onChanged: (v) {
        setState(() => _enabled = v);
        unawaited(widget.svc.setPrefetchPlaylist(v));
        unawaited(PlayerSettingsStore.savePrefetchPlaylist(v));
      },
    );
  }
}

class SmartQueueToggle extends ConsumerWidget {
  const SmartQueueToggle({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(smartQueueEnabledProvider);
    return SettingsSwitchTile(
      icon: LucideIcons.lightbulb,
      iconColor: AfColors.textSecondary,
      title: 'Smart queue',
      subtitle: 'Learn from skips and plays for better suggestions',
      value: enabled,
      onChanged: (v) {
        ref.read(smartQueueEnabledProvider.notifier).state = v;
      },
    );
  }
}
