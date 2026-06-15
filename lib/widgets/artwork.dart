import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../design_tokens/tokens.dart';
import '../state/providers.dart';
import '../utils/url.dart';

/// Custom cache manager that limits total disk cache to ~200 MB.
///
/// Uses [maxNrOfCacheObjects] (2000) as a proxy — typical artwork images
/// are 50–150 KB each, so 2000 files ≈ 100–300 MB.
class ArtworkCacheManager extends CacheManager with ImageCacheManager {
  ArtworkCacheManager._()
    : super(
        Config(
          'aetherfinArtworkCache',
          stalePeriod: const Duration(days: 30),
          maxNrOfCacheObjects: 2000,
        ),
      );

  /// Singleton accessor.
  factory ArtworkCacheManager() => _instance;

  static final ArtworkCacheManager _instance = ArtworkCacheManager._();
}

/// Network artwork that gracefully degrades to a dark placeholder
/// when the URL is null or fails to load. Used everywhere we
/// need an album/playlist/track cover.
///
/// The widget reads `musicBackendProvider` so it can send the active
/// auth header alongside the image fetch.
class Artwork extends ConsumerWidget {
  const Artwork({
    super.key,
    required this.url,
    this.size = 56,
    this.height,
    this.radius = AfRadii.borderMd,
    this.fit = BoxFit.cover,
    this.semanticLabel,
    this.mutedColor = AfColors.accentMuted,
  });

  final String? url;
  final double size;
  final double? height;
  final BorderRadius radius;
  final BoxFit fit;
  final String? semanticLabel;
  final Color mutedColor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final w = size;
    final h = height ?? size;
    final isFinite = w.isFinite;

    final double layoutW;
    final double layoutH;
    if (isFinite) {
      layoutW = w;
      layoutH = h;
    } else {
      final mediaQuery = MediaQuery.maybeOf(context);
      layoutW = mediaQuery?.size.width ?? 152.0;
      layoutH = h.isFinite ? h : layoutW;
    }

    final placeholder = Container(
      width: isFinite ? w : null,
      height: h.isFinite ? h : null,
      decoration: BoxDecoration(
        borderRadius: radius,
        color: AfColors.surfaceBase,
      ),
      child: Center(
        child: Icon(LucideIcons.music, color: mutedColor, size: 28),
      ),
    );

    if (url == null || url!.isEmpty) {
      return Semantics(label: semanticLabel, child: placeholder);
    }

    // Upgrade YouTube thumbnails to higher resolution
    final upgradedUrl = upgradeYtThumbnail(url!);

    final dpr = MediaQuery.maybeOf(context)?.devicePixelRatio ?? 2.0;
    int? clampedCachePx(double logicalPx) {
      final physical = (logicalPx * dpr).round();
      if (physical <= 0) return null;
      return physical > 2048 ? 2048 : physical;
    }

    final cacheW = clampedCachePx(layoutW);
    final cacheH = clampedCachePx(layoutH);

    final headers = ref.watch(
      musicBackendProvider.select((b) => b?.authHeaders),
    );

    // Local files: load from disk directly.
    if (url!.startsWith('file://')) {
      final filePath = url!.substring('file://'.length);
      // Check file existence before calling Image.file() to avoid
      // loading errors when cover files have been evicted from cache.
      if (!File(filePath).existsSync()) {
        return Semantics(label: semanticLabel, child: placeholder);
      }
      return ClipRRect(
        borderRadius: radius,
        child: SizedBox(
          width: isFinite ? w : null,
          height: h.isFinite ? h : null,
          child: Image.file(
            File(filePath),
            fit: fit,
            width: isFinite ? w : null,
            height: h.isFinite ? h : null,
            errorBuilder: (context, error, stack) => placeholder,
            cacheWidth: cacheW,
            cacheHeight: cacheH,
          ),
        ),
      );
    }

    return ClipRRect(
      borderRadius: radius,
      child: SizedBox(
        width: isFinite ? w : null,
        height: h.isFinite ? h : null,
        child: CachedNetworkImage(
          cacheKey: stableImageCacheKey(upgradedUrl),
          imageUrl: upgradedUrl,
          httpHeaders: headers,
          fit: fit,
          cacheManager: ArtworkCacheManager(),
          placeholder: (context, url) => placeholder,
          errorWidget: (context, url, error) => placeholder,
          fadeInDuration: MediaQuery.maybeOf(context)?.disableAnimations == true
              ? Duration.zero
              : AfDurations.quick,
          memCacheWidth: cacheW,
          memCacheHeight: cacheH,
          maxHeightDiskCache: 1024,
          maxWidthDiskCache: 1024,
        ),
      ),
    );
  }
}

/// Circular variant for artist tiles.
class CircularArtwork extends StatelessWidget {
  const CircularArtwork({
    super.key,
    required this.url,
    this.size = 64,
    this.semanticLabel,
  });

  final String? url;
  final double size;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxW = constraints.maxWidth;
        return Artwork(
          url: url,
          size: maxW,
          radius: maxW.isFinite && maxW > 0
              ? AfRadii.borderPill
              : BorderRadius.circular(
                  AfSpacing.s32,
                ), // no exact AfRadii match for 32dp fallback
          semanticLabel: semanticLabel,
        );
      },
    );
  }
}
