import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../design_tokens/tokens.dart';
import '../../../widgets/press_scale.dart';
import '../../../widgets/section_header.dart';

/// About section with app info and links.
/// Wrapped in a glass card for visual consistency with other profile sections.
class AboutSection extends StatelessWidget {
  const AboutSection({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(AfSpacing.s16, 0, AfSpacing.s16, 0),
          child: SectionHeader(title: 'About', uppercase: true),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AfSpacing.s16),
          child: _AboutCard(),
        ),
      ],
    );
  }
}

/// Glass morphism about card with app info.
class _AboutCard extends StatefulWidget {
  @override
  State<_AboutCard> createState() => _AboutCardState();
}

class _AboutCardState extends State<_AboutCard> {
  PackageInfo? _packageInfo;

  @override
  void initState() {
    super.initState();
    _loadPackageInfo();
  }

  Future<void> _loadPackageInfo() async {
    final info = await PackageInfo.fromPlatform();
    if (mounted) {
      setState(() => _packageInfo = info);
    }
  }

  @override
  Widget build(BuildContext context) {
    final version = _packageInfo?.version ?? '—';
    final buildNumber = _packageInfo?.buildNumber ?? '—';

    return Container(
      padding: const EdgeInsets.all(AfSpacing.s16),
      decoration: BoxDecoration(
        color: AfColors.glassFill,
        borderRadius: AfRadii.borderLg,
        border: Border.all(color: AfColors.glassBorder, width: 1),
      ),
      child: Column(
        children: [
          // App icon + name
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AfColors.accentPrimary.withValues(alpha: 0.15),
                  borderRadius: AfRadii.borderMd,
                ),
                child: const Icon(
                  LucideIcons.music,
                  size: 24,
                  color: AfColors.accentPrimary,
                ),
              ),
              const SizedBox(width: AfSpacing.s12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Aetherfin', style: AfTypography.titleMedium),
                    Text(
                      'v$version ($buildNumber)',
                      style: AfTypography.bodySmall.copyWith(
                        color: AfColors.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AfSpacing.s16),

          // Description
          Text(
            'Your music. Your server. No compromises.',
            style: AfTypography.bodyMedium.copyWith(
              color: AfColors.textSecondary,
            ),
          ),
          const SizedBox(height: AfSpacing.s16),

          // Action tiles
          _AboutTile(
            icon: LucideIcons.globe,
            title: 'Website',
            onTap: () => _launchUrl('https://aetherfin.dev'),
          ),
          _AboutTile(
            icon: LucideIcons.code,
            title: 'Source Code',
            onTap: () => _launchUrl('https://github.com/Aetherfin/mobile-app'),
          ),
          _AboutTile(
            icon: LucideIcons.bookOpen,
            title: 'Licenses',
            onTap: () => showLicensePage(
              context: context,
              applicationName: 'Aetherfin',
              applicationVersion: version,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _launchUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}

/// About tile with icon and title.
class _AboutTile extends StatelessWidget {
  const _AboutTile({
    required this.icon,
    required this.title,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AfColors.transparent,
      child: PressScale(
        onTap: onTap,
        child: Semantics(
          button: true,
          label: title,
          child: InkWell(
            borderRadius: AfRadii.borderMd,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AfSpacing.s12,
                vertical: AfSpacing.s12,
              ),
              child: Row(
                children: [
                  Icon(icon, size: 20, color: AfColors.textSecondary),
                  const SizedBox(width: AfSpacing.s12),
                  Expanded(
                    child: Text(
                      title,
                      style: AfTypography.bodyMedium.copyWith(
                        color: AfColors.textPrimary,
                      ),
                    ),
                  ),
                  const Icon(
                    LucideIcons.chevronRight,
                    size: 16,
                    color: AfColors.textTertiary,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
