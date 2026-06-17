import 'package:flutter/material.dart';

import '../design_tokens/tokens.dart';

/// Connection state for the server pill in the top app bar.
enum ServerPillState {
  hidden, // connected to default server — pill not rendered
  connectedOther,
  reconnecting,
  offline,
}

/// `[● ServerName]` — top-right of the app bar.
///
/// Hidden when the user is connected to their default server. Visible only
/// when the connection state warrants attention.
class ServerPill extends StatelessWidget {
  const ServerPill({
    super.key,
    required this.state,
    required this.label,
    this.onTap,
  });
  final ServerPillState state;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    if (state == ServerPillState.hidden) return const SizedBox.shrink();

    final dotColor = switch (state) {
      ServerPillState.connectedOther => AfColors.semanticSuccess,
      ServerPillState.reconnecting => AfColors.semanticWarning,
      ServerPillState.offline => AfColors.semanticOffline,
      ServerPillState.hidden => AfColors.semanticOffline,
    };

    final bg = state == ServerPillState.offline
        ? AfColors.surfaceHigh
        : AfColors.surfaceRaised;

    final stateLabel = switch (state) {
      ServerPillState.connectedOther => 'Connected to $label',
      ServerPillState.reconnecting => 'Reconnecting to $label',
      ServerPillState.offline => '$label offline',
      ServerPillState.hidden => label,
    };
    return Semantics(
      button: true,
      label: stateLabel,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AfSpacing.s12,
              vertical: 6,
            ),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: AfRadii.borderPill,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _Dot(
                  color: dotColor,
                  pulse: state == ServerPillState.reconnecting,
                ),
                const SizedBox(width: AfSpacing.s8),
                Text(
                  _truncate(label),
                  style: AfTypography.bodySmall.copyWith(
                    color: AfColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _truncate(String s) => s.length > 12 ? '${s.substring(0, 12)}…' : s;
}

class _Dot extends StatefulWidget {
  const _Dot({required this.color, required this.pulse});
  final Color color;
  final bool pulse;
  @override
  State<_Dot> createState() => _DotState();
}

class _DotState extends State<_Dot> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: AfDurations.pulse, // 1.2 Hz
  );

  @override
  void initState() {
    super.initState();
    if (widget.pulse) {
      final reduced = MediaQuery.of(context).disableAnimations;
      if (!reduced) _ctrl.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(_Dot old) {
    super.didUpdateWidget(old);
    final reduced = MediaQuery.of(context).disableAnimations;
    if (widget.pulse && !_ctrl.isAnimating && !reduced) {
      _ctrl.repeat(reverse: true);
    } else if (!widget.pulse && _ctrl.isAnimating) {
      _ctrl.stop();
      _ctrl.value = 1;
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        final opacity = widget.pulse ? 0.5 + 0.5 * _ctrl.value : 1.0;
        return Opacity(
          opacity: opacity,
          child: Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: widget.color,
              shape: BoxShape.circle,
            ),
          ),
        );
      },
    );
  }
}
