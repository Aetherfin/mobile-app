import 'package:mpv_audio_kit/mpv_audio_kit.dart';

/// Band keys matching [kEqBands] in order ('1b' through '18b').
const _bandKeys = [
  '1b',
  '2b',
  '3b',
  '4b',
  '5b',
  '6b',
  '7b',
  '8b',
  '9b',
  '10b',
  '11b',
  '12b',
  '13b',
  '14b',
  '15b',
  '16b',
  '17b',
  '18b',
];

/// Persistent state for the 18-band graphic equalizer.
class GraphicEqState {
  /// Restores a [GraphicEqState] from a JSON map.
  ///
  /// Missing keys fall back to defaults (18 zero levels, disabled).
  factory GraphicEqState.fromJson(Map<String, dynamic> json) {
    final rawLevels = json['levels'];
    final levels = rawLevels != null
        ? List<double>.from(
            (rawLevels as List).map((e) => (e as num).toDouble()),
          )
        : List<double>.filled(18, 0.0);
    final enabled = json['enabled'] as bool? ?? false;
    return GraphicEqState(levels: levels, enabled: enabled);
  }

  /// Restores a [GraphicEqState] from an [AudioEffects] bundle.
  ///
  /// Reads the superequalizer params and converts them back to band levels.
  /// Missing bands default to `0.0`.
  factory GraphicEqState.fromAudioEffects(AudioEffects fx) {
    final se = fx.superequalizer;
    final levels = List<double>.filled(18, 0.0);
    for (var i = 0; i < 18; i++) {
      final gain = se.params[_bandKeys[i]];
      if (gain != null) {
        levels[i] = gain - 0.5;
      }
    }
    return GraphicEqState(levels: levels, enabled: se.enabled);
  }

  /// Creates a [GraphicEqState].
  ///
  /// [levels] defaults to 18 zeros (flat / no boost or cut).
  /// [enabled] defaults to `false`.
  GraphicEqState({List<double>? levels, this.enabled = false})
    : levels = levels ?? List<double>.filled(18, 0.0);

  /// Per-band level values in dB (range typically -12 to +12).
  final List<double> levels;

  /// Whether the graphic EQ is active.
  final bool enabled;

  // ── JSON ─────────────────────────────────────────────────────────────────

  /// Serialises to a JSON-compatible map.
  Map<String, dynamic> toJson() => {'levels': levels, 'enabled': enabled};

  // ── Audio effects conversion ─────────────────────────────────────────────

  /// Converts band levels to an [AudioEffects] with superequalizer params.
  ///
  /// Each band level (dB) is mapped to a superequalizer gain value.
  /// Entries where the level is exactly `0.0` are omitted (no boost/cut).
  AudioEffects toAudioEffects(AudioEffects current) {
    final params = <String, double>{};
    for (var i = 0; i < 18; i++) {
      if (levels[i] != 0.0) {
        params[_bandKeys[i]] = levels[i] + 0.5;
      }
    }
    return current.copyWith(
      superequalizer: SuperequalizerSettings(enabled: enabled, params: params),
    );
  }

  // ── Copy ─────────────────────────────────────────────────────────────────

  /// Creates an independent copy of this state.
  GraphicEqState copy() {
    return GraphicEqState(levels: List<double>.from(levels), enabled: enabled);
  }
}
