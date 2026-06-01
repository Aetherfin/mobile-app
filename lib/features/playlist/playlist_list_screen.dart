import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/jellyfin/models/items.dart';
import '../../design_tokens/tokens.dart';
import '../../state/providers.dart';
import '../../widgets/skeletons/playlist_skeleton.dart';
import '../../widgets/af_scrollbar.dart';
import 'import_m3u_dialog.dart';

/// Aetherfin Reworked Playlist Library - Generative & Bookcase inspired layout.
class PlaylistListScreen extends ConsumerWidget {
  const PlaylistListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playlists = ref.watch(allPlaylistsProvider);
    final smartPlaylists = ref.watch(smartPlaylistsProvider);
    final smartCount = smartPlaylists.maybeWhen(
      data: (list) => list.length,
      orElse: () => 0,
    );

    return SafeArea(
      child: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(allPlaylistsProvider);
          await ref.read(allPlaylistsProvider.future);
        },
        color: AfColors.indigo300,
        backgroundColor: AfColors.surfaceBase,
        child: AfScrollbar(
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(
              parent: ClampingScrollPhysics(),
            ),
            slivers: [
              // Header
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AfSpacing.s16,
                    AfSpacing.s16,
                    AfSpacing.s16,
                    AfSpacing.s24,
                  ),
                  child: Row(
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'CURATED BY YOU',
                            style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: AfColors.indigo400,
                              letterSpacing: 1.5,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'PLAYLISTS',
                            style: AfTypography.titleLarge.copyWith(
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.5,
                            ),
                          ),
                        ],
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(
                          LucideIcons.plus,
                          color: AfColors.textPrimary,
                          size: 20,
                        ),
                        tooltip: 'Import M3U',
                        style: IconButton.styleFrom(
                          backgroundColor: AfColors.surfaceBase,
                          side: const BorderSide(color: AfColors.surfaceHigh, width: 1.5),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        onPressed: () => ref
                            .read(importM3UActionProvider)
                            .import(context: context),
                      ),
                    ],
                  ),
                ),
              ),

              // Smart Playlists (Top banner style)
              if (smartCount > 0) ...[
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AfSpacing.s16, 0, AfSpacing.s16, AfSpacing.s12,
                    ),
                    child: const Text(
                      'AUTOMATED INDEXES',
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        color: AfColors.textTertiary,
                        letterSpacing: 1.0,
                      ),
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: AfSpacing.s16),
                    child: Container(
                      decoration: BoxDecoration(
                        color: AfColors.surfaceLow,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: AfColors.surfaceHigh,
                          width: 1,
                        ),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: () => context.push('/smart-playlists'),
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Row(
                            children: [
                              Container(
                                width: 48,
                                height: 48,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(10),
                                  color: AfColors.surfaceBase,
                                  border: Border.all(color: AfColors.indigo400.withValues(alpha: 0.3)),
                                ),
                                child: const Icon(
                                  Icons.auto_awesome_rounded,
                                  color: AfColors.indigo300,
                                  size: 24,
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'SMART PLAYLISTS',
                                      style: AfTypography.bodyMedium.copyWith(
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '$smartCount dynamically updated sets',
                                      style: AfTypography.caption.copyWith(
                                        color: AfColors.textTertiary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const Icon(
                                LucideIcons.chevronRight,
                                color: AfColors.textTertiary,
                                size: 18,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: AfSpacing.s24)),
              ],

              // Main Playlists section
              ...playlists.when(
                data: (list) => _buildGridSlivers(context, ref, list),
                loading: () => [
                  const SliverToBoxAdapter(child: PlaylistSkeleton()),
                ],
                error: (e, _) => [
                  SliverToBoxAdapter(
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(AfSpacing.s24),
                        child: Text(
                          'Couldn\u2019t load playlists',
                          style: AfTypography.bodyMedium.copyWith(
                            color: AfColors.semanticError,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SliverToBoxAdapter(
                child: SizedBox(height: AfSpacing.bottomInsetWithMiniAndNav),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildGridSlivers(
    BuildContext context,
    WidgetRef ref,
    List<AfPlaylist> list,
  ) {
    if (list.isEmpty) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  LucideIcons.listMusic,
                  color: AfColors.textTertiary,
                  size: 40,
                ),
                const SizedBox(height: 12),
                Text(
                  'No playlists yet'.toUpperCase(),
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11,
                    color: AfColors.textTertiary,
                    letterSpacing: 1.0,
                  ),
                ),
              ],
            ),
          ),
        )
      ];
    }

    return [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AfSpacing.s16, 0, AfSpacing.s16, AfSpacing.s12,
          ),
          child: const Text(
            'USER COLLECTIONS',
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 9,
              fontWeight: FontWeight.w700,
              color: AfColors.textTertiary,
              letterSpacing: 1.0,
            ),
          ),
        ),
      ),
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: AfSpacing.s16),
        sliver: SliverGrid(
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisExtent: 235,
            crossAxisSpacing: 16,
            mainAxisSpacing: 20,
          ),
          delegate: SliverChildBuilderDelegate(
            childCount: list.length,
            (context, i) {
              final p = list[i];
              return _PlaylistGridCard(playlist: p);
            },
          ),
        ),
      ),
    ];
  }
}

/// Bookcase/Vinyl stack layout card with generative custom geometric art
class _PlaylistGridCard extends StatelessWidget {
  const _PlaylistGridCard({required this.playlist});
  final AfPlaylist playlist;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => context.push('/playlist/${playlist.id}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Generative abstract cover
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  bottomRight: Radius.circular(16),
                ),
                border: Border.all(
                  color: AfColors.surfaceHigh,
                  width: 1,
                ),
              ),
              clipBehavior: Clip.antiAlias,
              child: AbstractPlaylistCover(seed: playlist.id),
            ),
          ),
          const SizedBox(height: 10),
          // Details
          Text(
            playlist.name.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AfTypography.bodyMedium.copyWith(
              fontWeight: FontWeight.w900,
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            playlist.trackCountLabel.toUpperCase(),
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 9,
              color: AfColors.textTertiary,
            ),
          ),
        ],
      ),
    );
  }
}

/// Generative geometric cover art using CustomPainter
class AbstractPlaylistCover extends StatelessWidget {
  const AbstractPlaylistCover({super.key, required this.seed});
  final String seed;

  @override
  Widget build(BuildContext context) {
    final hash = seed.hashCode;
    return Container(
      color: AfColors.surfaceLow,
      child: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: _GeometricCoverPainter(hash: hash),
            ),
          ),
          // Subdued logo/serial label overlay at the bottom left
          Positioned(
            bottom: 8,
            left: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(2),
              ),
              child: Text(
                'SET.ID // ${seed.substring(0, math.min(seed.length, 4)).toUpperCase()}',
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 7,
                  color: AfColors.textTertiary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GeometricCoverPainter extends CustomPainter {
  _GeometricCoverPainter({required this.hash});
  final int hash;

  @override
  void paint(Canvas canvas, Size size) {
    final rand = _Lcg(hash);
    
    final paintShape = Paint()
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    final paintStroke = Paint()
      ..style = PaintingStyle.stroke
      ..isAntiAlias = true
      ..strokeWidth = 1.0;

    // Draw grid guide line (minimal blueprint style)
    paintStroke.color = AfColors.surfaceHigh.withValues(alpha: 0.6);
    canvas.drawLine(Offset(0, size.height * 0.5), Offset(size.width, size.height * 0.5), paintStroke);
    canvas.drawLine(Offset(size.width * 0.5, 0), Offset(size.width * 0.5, size.height), paintStroke);

    // Draw diagonal vector
    paintStroke.color = AfColors.indigo400.withValues(alpha: 0.25);
    paintStroke.strokeWidth = 1.2;
    if (rand.nextBool()) {
      canvas.drawLine(Offset(0, 0), Offset(size.width, size.height), paintStroke);
    } else {
      canvas.drawLine(Offset(size.width, 0), Offset(0, size.height), paintStroke);
    }

    // 1. Draw large circle (either hollow or filled semitransparent)
    final cx = size.width * (0.3 + rand.nextDouble() * 0.4);
    final cy = size.height * (0.3 + rand.nextDouble() * 0.4);
    final radius = size.width * (0.2 + rand.nextDouble() * 0.25);

    if (rand.nextBool()) {
      paintShape.color = AfColors.indigo600.withValues(alpha: 0.15);
      canvas.drawCircle(Offset(cx, cy), radius, paintShape);
    } else {
      paintStroke.color = AfColors.indigo300.withValues(alpha: 0.3);
      paintStroke.strokeWidth = 1.5;
      canvas.drawCircle(Offset(cx, cy), radius, paintStroke);
    }

    // 2. Draw secondary accent geometric element (e.g. triangle or rotated box)
    final shapeType = rand.nextInt(3);
    final ax = size.width * (0.2 + rand.nextDouble() * 0.6);
    final ay = size.height * (0.2 + rand.nextDouble() * 0.6);
    final side = size.width * (0.15 + rand.nextDouble() * 0.2);

    if (shapeType == 0) {
      // Rotated Square
      canvas.save();
      canvas.translate(ax, ay);
      canvas.rotate(rand.nextDouble() * math.pi);
      paintShape.color = AfColors.surfaceHigh.withValues(alpha: 0.4);
      canvas.drawRect(Rect.fromCenter(center: Offset.zero, width: side, height: side), paintShape);
      paintStroke.color = AfColors.indigo100.withValues(alpha: 0.25);
      paintStroke.strokeWidth = 1.0;
      canvas.drawRect(Rect.fromCenter(center: Offset.zero, width: side, height: side), paintStroke);
      canvas.restore();
    } else if (shapeType == 1) {
      // Triangle
      final path = Path()
        ..moveTo(ax, ay - side / 2)
        ..lineTo(ax - side / 2, ay + side / 2)
        ..lineTo(ax + side / 2, ay + side / 2)
        ..close();
      paintShape.color = AfColors.indigo400.withValues(alpha: 0.08);
      canvas.drawPath(path, paintShape);
      paintStroke.color = AfColors.indigo400.withValues(alpha: 0.2);
      paintStroke.strokeWidth = 1.0;
      canvas.drawPath(path, paintStroke);
    } else {
      // Concentric small rings
      paintStroke.color = AfColors.textTertiary.withValues(alpha: 0.2);
      canvas.drawCircle(Offset(ax, ay), side * 0.4, paintStroke);
      canvas.drawCircle(Offset(ax, ay), side * 0.2, paintStroke);
    }
  }

  @override
  bool shouldRepaint(covariant _GeometricCoverPainter old) => old.hash != hash;
}

/// Simple LCG (Linear Congruential Generator) for deterministic random generation from a seed hash
class _Lcg {
  _Lcg(this.seed);
  int seed;

  int next() {
    seed = (seed * 1103515245 + 12345) & 0x7fffffff;
    return seed;
  }

  double nextDouble() {
    return next() / 2147483647.0;
  }

  int nextInt(int max) {
    return next() % max;
  }

  bool nextBool() {
    return next() % 2 == 0;
  }
}
