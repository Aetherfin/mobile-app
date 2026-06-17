import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:aetherfin/design_tokens/colors.dart';
import 'package:aetherfin/state/providers.dart';
import 'package:aetherfin/state/state_holder.dart';

/// Builds a [ProviderContainer] with the common overrides needed by
/// most screens: spectral fallback + app mode + null backend.
ProviderContainer createTestContainer() {
  return ProviderContainer(
    overrides: [
      // ── Spectral: fallback palette ──
      currentSpectralProvider.overrideWith((ref) => Spectral.fallback),

      // ── App mode: local (avoids YouTube/Server branches) ──
      appModeProvider.overrideWith(
        () => StateHolder<AppMode?>((ref) => AppMode.local),
      ),

      // ── Backend: null (no server connected) ──
      musicBackendProvider.overrideWith((ref) => null),
    ],
  );
}
