import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../design_tokens/tokens.dart';
import '../../widgets/empty_state.dart';

/// Empty state shown when no track is playing.
class NowPlayingEmptyState extends StatelessWidget {
  const NowPlayingEmptyState({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AfColors.surfaceCanvas,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(LucideIcons.chevronDown),
          tooltip: 'Collapse',
          onPressed: () => Navigator.maybePop(context),
        ),
      ),
      body: const EmptyState(
        icon: LucideIcons.music,
        title: 'Nothing playing yet',
        body: 'Start playing to see your music here',
      ),
    );
  }
}
