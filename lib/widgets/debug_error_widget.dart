import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:aetherfin/design_tokens/tokens.dart';

/// Last-line-of-defense error widget so the user always sees *something*
/// instead of a gray rectangle when a build throws.
///
/// In debug builds: shows full exception + stack trace + Copy/Share buttons.
/// In release builds: shows generic message + Copy button only (no PII leaks).
///
/// File:line extraction from the stack trace helps pinpoint the crash location
/// when debugging via bug reports or screenshots.
class DebugErrorWidget extends StatelessWidget {
  const DebugErrorWidget({super.key, required this.details});

  final FlutterErrorDetails details;

  /// Extract the first project-internal file:line from the stack trace.
  String? _extractFileLine(StackTrace? stack) {
    if (stack == null) return null;
    final lines = stack.toString().split('\n');
    for (final line in lines) {
      final match = RegExp(r'\(([^)]+)\)').firstMatch(line);
      if (match != null) {
        final loc = match.group(1)!;
        if (loc.contains('aetherfin') || loc.contains('package:aetherfin')) {
          return loc;
        }
      }
    }
    return null;
  }

  /// Format stack trace — first 15 lines for readability.
  String _formatStackTrace(StackTrace? stack) {
    if (stack == null) return '(no stack trace)';
    return stack.toString().split('\n').take(15).join('\n');
  }

  /// Build full error text for copy clipboard.
  String _buildFullText() {
    final exceptionStr = details.exceptionAsString();
    final stackStr = _formatStackTrace(details.stack);
    final fileLine = _extractFileLine(details.stack);

    final buf = StringBuffer('Aetherfin Error\n\n');
    buf.writeln('Exception: $exceptionStr');
    if (fileLine != null) {
      buf.writeln('Location: $fileLine');
    }
    buf.writeln();
    buf.writeln('Stack Trace:');
    buf.write(stackStr);
    return buf.toString();
  }

  @override
  Widget build(BuildContext context) {
    const isDebug = kDebugMode;
    final exceptionStr = details.exceptionAsString();
    final fileLine = _extractFileLine(details.stack);
    final fullText = _buildFullText();

    return Directionality(
      textDirection: TextDirection.ltr,
      child: ColoredBox(
        color: AfColors.surfaceCanvas,
        child: Padding(
          padding: const EdgeInsets.all(AfSpacing.s24),
          child: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Header row: icon + title + action buttons ──
                Row(
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        color: AfColors.semanticError.withAlpha(26),
                        borderRadius: AfRadii.borderSm,
                      ),
                      padding: const EdgeInsets.all(AfSpacing.s8),
                      child: const Icon(
                        LucideIcons.alertTriangle,
                        color: AfColors.semanticError,
                        size: AfIconSizes.md,
                      ),
                    ),
                    const SizedBox(width: AfSpacing.s12),
                    Expanded(
                      child: Text(
                        'Aetherfin hit a snag',
                        style: AfTypography.titleMediumLarge.copyWith(
                          color: AfColors.textPrimary,
                        ),
                      ),
                    ),
                    // ── Copy to clipboard ──
                    _ActionIconButton(
                      icon: LucideIcons.clipboard,
                      tooltip: 'Copy error details',
                      onPressed: () async {
                        // Capture messenger before async gap — this is a
                        // StatelessWidget so the error widget root context
                        // stays valid for the process lifetime.
                        final messenger = ScaffoldMessenger.maybeOf(context);
                        await Clipboard.setData(ClipboardData(text: fullText));
                        _showCopiedSnackBarWith(messenger);
                      },
                    ),
                  ],
                ),
                const SizedBox(height: AfSpacing.s16),

                // ── Error details section ──
                Expanded(
                  child: ClipRRect(
                    borderRadius: AfRadii.borderMd,
                    child: ColoredBox(
                      color: AfColors.surfaceLow,
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(AfSpacing.s12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Location chip
                            if (fileLine != null && isDebug) ...[
                              Container(
                                decoration: BoxDecoration(
                                  color: AfColors.semanticError.withAlpha(20),
                                  borderRadius: AfRadii.borderSm,
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: AfSpacing.s8,
                                  vertical: AfSpacing.s4,
                                ),
                                child: Text(
                                  fileLine,
                                  style: AfTypography.monoSmall.copyWith(
                                    color: AfColors.semanticError,
                                  ),
                                ),
                              ),
                              const SizedBox(height: AfSpacing.s12),
                            ],

                            // Exception message
                            SelectableText(
                              isDebug
                                  ? exceptionStr
                                  : 'An unexpected error occurred. Please restart the app.',
                              style: AfTypography.bodyMedium.copyWith(
                                color: AfColors.textPrimary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: AfSpacing.s16),

                            // Stack trace (debug only)
                            if (isDebug) ...[
                              Text(
                                'Stack Trace',
                                style: AfTypography.label.copyWith(
                                  color: AfColors.textTertiary,
                                ),
                              ),
                              const SizedBox(height: AfSpacing.s8),
                              SelectableText(
                                _formatStackTrace(details.stack),
                                style: AfTypography.mono.copyWith(
                                  color: AfColors.textSecondary,
                                  height: 1.5,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: AfSpacing.s16),

                // ── Help text ──
                Row(
                  children: [
                    const Icon(
                      LucideIcons.info,
                      size: AfIconSizes.sm,
                      color: AfColors.textTertiary,
                    ),
                    const SizedBox(width: AfSpacing.s8),
                    Expanded(
                      child: Text(
                        isDebug
                            ? 'Hot reload to retry after fixing the issue.'
                            : 'Tap Restart on Android to retry.',
                        style: AfTypography.bodySmall.copyWith(
                          color: AfColors.textTertiary,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showCopiedSnackBarWith(ScaffoldMessengerState? messenger) {
    // Best-effort snackbar. ErrorWidget runs outside normal Scaffold
    // hierarchy, so this may silently fail — that's acceptable.
    if (messenger == null) return;
    try {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Error details copied to clipboard'),
          duration: AfDurations.snackBarInfo,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (_) {
      // Silently ignore — the error widget must never crash.
    }
  }
}

/// Small circular icon button for error widget actions.
class _ActionIconButton extends StatelessWidget {
  const _ActionIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: AfRadii.borderPill,
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.all(AfSpacing.s8),
            child: Icon(
              icon,
              color: AfColors.textSecondary,
              size: AfIconSizes.sm,
            ),
          ),
        ),
      ),
    );
  }
}
