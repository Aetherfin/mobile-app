import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../design_tokens/tokens.dart';
import '../../../state/providers.dart';
import '../../../widgets/bottom_sheet.dart';
import '../../../widgets/press_scale.dart';

/// Split info section — avatar on left, user info + stats on right.
class SplitInfoSection extends ConsumerWidget {
  const SplitInfoSection({
    super.key,
    required this.name,
    required this.serverName,
    required this.isYouTubeMusic,
    this.networkProfileUrl,
    required this.profilePhoto,
    required this.trackCount,
    required this.albumCount,
  });

  final String name;
  final String serverName;
  final bool isYouTubeMusic;
  final String? networkProfileUrl;
  final ({bool isUploading, String? localPath, String? networkUrl})
  profilePhoto;
  final String trackCount;
  final String albumCount;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AfSpacing.s16,
        AfSpacing.s16,
        AfSpacing.s16,
        0,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Left: Avatar
          CompactAvatar(
            name: name,
            isUploading: profilePhoto.isUploading,
            localPath: profilePhoto.localPath,
            networkUrl: profilePhoto.networkUrl ?? networkProfileUrl,
            authHeaders: ref.watch(musicBackendProvider)?.authHeaders,
            onPickPhoto: (source) async {
              final picker = ImagePicker();
              try {
                final image = await picker.pickImage(
                  source: source,
                  maxWidth: 512,
                  maxHeight: 512,
                  imageQuality: 85,
                );
                if (image != null) {
                  final bytes = await image.readAsBytes();
                  final mimeType = image.mimeType ?? 'image/jpeg';
                  await ref
                      .read(profilePhotoProvider.notifier)
                      .updatePhoto(bytes, mimeType);
                }
              } on Exception catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Failed to update profile photo: $e'),
                      backgroundColor: AfColors.semanticError,
                    ),
                  );
                }
              }
            },
            onRemovePhoto: () async {
              try {
                await ref.read(profilePhotoProvider.notifier).removePhoto();
              } on Exception catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Failed to remove profile photo: $e'),
                      backgroundColor: AfColors.semanticError,
                    ),
                  );
                }
              }
            },
          ),
          const SizedBox(width: AfSpacing.s16),

          // Right: Info + Stats
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: AfTypography.titleMedium),
                const SizedBox(height: AfSpacing.s4),
                Row(
                  children: [
                    Icon(
                      isYouTubeMusic ? LucideIcons.music : LucideIcons.server,
                      size: 12,
                      color: AfColors.textTertiary,
                    ),
                    const SizedBox(width: AfSpacing.s4),
                    Flexible(
                      child: Text(
                        serverName,
                        style: AfTypography.bodySmall.copyWith(
                          color: AfColors.textTertiary,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AfSpacing.s8),
                Row(
                  children: [
                    MiniStat(value: trackCount, label: 'Tracks'),
                    const SizedBox(width: AfSpacing.s16),
                    MiniStat(value: albumCount, label: 'Albums'),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 80dp compact avatar with image picker.
class CompactAvatar extends ConsumerWidget {
  const CompactAvatar({
    super.key,
    required this.name,
    required this.isUploading,
    this.localPath,
    this.networkUrl,
    this.authHeaders,
    required this.onPickPhoto,
    required this.onRemovePhoto,
  });

  final String name;
  final bool isUploading;
  final String? localPath;
  final String? networkUrl;
  final Map<String, String>? authHeaders;
  final ValueChanged<ImageSource> onPickPhoto;
  final VoidCallback onRemovePhoto;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spectral = ref.watch(
      currentSpectralProvider.select(
        (s) => (primary: s.primary, secondary: s.secondary, muted: s.muted),
      ),
    );
    final hasPhoto =
        (localPath != null && File(localPath!).existsSync()) ||
        networkUrl != null;

    return GestureDetector(
      onTap: isUploading
          ? null
          : () {
              showBlurBottomSheet(
                context: context,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ListTile(
                      leading: const Icon(
                        LucideIcons.camera,
                        color: AfColors.textPrimary,
                      ),
                      title: Text(
                        'Take Photo',
                        style: AfTypography.bodyMedium.copyWith(
                          color: AfColors.textPrimary,
                        ),
                      ),
                      onTap: () {
                        if (context.canPop()) context.pop();
                        onPickPhoto(ImageSource.camera);
                      },
                    ),
                    ListTile(
                      leading: const Icon(
                        LucideIcons.image,
                        color: AfColors.textPrimary,
                      ),
                      title: Text(
                        'Choose from Gallery',
                        style: AfTypography.bodyMedium.copyWith(
                          color: AfColors.textPrimary,
                        ),
                      ),
                      onTap: () {
                        if (context.canPop()) context.pop();
                        onPickPhoto(ImageSource.gallery);
                      },
                    ),
                    if (hasPhoto)
                      ListTile(
                        leading: const Icon(
                          LucideIcons.trash2,
                          color: AfColors.semanticError,
                        ),
                        title: Text(
                          'Remove Photo',
                          style: AfTypography.bodyMedium.copyWith(
                            color: AfColors.semanticError,
                          ),
                        ),
                        onTap: () {
                          if (context.canPop()) context.pop();
                          onRemovePhoto();
                        },
                      ),
                    const SizedBox(height: AfSpacing.s12),
                  ],
                ),
              );
            },
      child: Semantics(
        button: true,
        label: 'Change $name profile photo',
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Avatar rounded rectangle
            Container(
              width: 80,
              height: 80,
              decoration: const BoxDecoration(
                color: AfColors.surfaceRaised,
                borderRadius: AfRadii.borderLg,
              ),
              child: ClipRRect(
                borderRadius: AfRadii.borderLg,
                child: _buildAvatarContent(spectral.muted),
              ),
            ),

            // Camera badge
            if (!isUploading)
              Positioned(
                bottom: 0,
                right: 0,
                child: Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: spectral.secondary,
                  ),
                  child: const Icon(
                    LucideIcons.camera,
                    size: 12,
                    color: AfColors.textOnPrimary,
                  ),
                ),
              ),

            // Upload overlay
            if (isUploading)
              Positioned.fill(
                child: Container(
                  decoration: const BoxDecoration(
                    color: AfColors.surfaceScrim,
                    borderRadius: AfRadii.borderLg,
                  ),
                  child: Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: spectral.primary,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildAvatarContent(Color bgColor) {
    if (localPath != null && File(localPath!).existsSync()) {
      return Image.file(
        File(localPath!),
        width: 80,
        height: 80,
        cacheWidth: 80,
        cacheHeight: 80,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => _initialsAvatar(bgColor),
      );
    }
    if (networkUrl != null) {
      return CachedNetworkImage(
        imageUrl: networkUrl!,
        httpHeaders: authHeaders,
        width: 80,
        height: 80,
        fit: BoxFit.cover,
        placeholder: (context, url) => _initialsAvatar(bgColor),
        errorWidget: (context, url, error) => _initialsAvatar(bgColor),
      );
    }
    return _initialsAvatar(bgColor);
  }

  Widget _initialsAvatar(Color bgColor) {
    return Container(
      width: 80,
      height: 80,
      color: bgColor,
      alignment: Alignment.center,
      child: Text(
        name.isEmpty ? 'A' : name[0].toUpperCase(),
        style: AfTypography.titleLarge.copyWith(color: AfColors.textOnPrimary),
      ),
    );
  }
}

/// Inline stat display — value + label.
class MiniStat extends StatelessWidget {
  const MiniStat({super.key, required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: AfTypography.titleMedium.copyWith(
            color: AfColors.accentPrimary,
          ),
        ),
        Text(
          label,
          style: AfTypography.caption.copyWith(color: AfColors.textTertiary),
        ),
      ],
    );
  }
}

/// Pill-shaped settings button.
class SettingsButton extends StatelessWidget {
  const SettingsButton({super.key});

  @override
  Widget build(BuildContext context) {
    return PressScale(
      onTap: () => context.push('/settings'),
      child: Container(
        decoration: const BoxDecoration(
          color: AfColors.surfaceRaised,
          borderRadius: AfRadii.borderPill,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AfSpacing.s12,
            vertical: AfSpacing.s8,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                LucideIcons.settings,
                size: 16,
                color: AfColors.textSecondary,
              ),
              const SizedBox(width: AfSpacing.s8),
              Text(
                'Settings',
                style: AfTypography.bodySmall.copyWith(
                  color: AfColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
