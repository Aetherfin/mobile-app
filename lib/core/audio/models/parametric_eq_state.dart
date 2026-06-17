import 'package:mpv_audio_kit/mpv_audio_kit.dart';

/// Band type for a parametric EQ filter.
enum BandType {
  peak,
  lowShelf,
  highShelf,
  lowCut,
  highCut;

  /// Serialize to JSON-friendly string.
  String toJsonString() {
    switch (this) {
      case BandType.peak:
        return 'peak';
      case BandType.lowShelf:
        return 'low_shelf';
      case BandType.highShelf:
        return 'high_shelf';
      case BandType.lowCut:
        return 'low_cut';
      case BandType.highCut:
        return 'high_cut';
    }
  }

  /// Parse from JSON string. Returns null for unknown types.
  static BandType? fromJsonString(String s) {
    switch (s) {
      case 'peak':
        return BandType.peak;
      case 'low_shelf':
        return BandType.lowShelf;
      case 'high_shelf':
        return BandType.highShelf;
      case 'low_cut':
        return BandType.lowCut;
      case 'high_cut':
        return BandType.highCut;
      default:
        return null;
    }
  }
}

/// A single parametric EQ band with frequency, gain, Q, and type.
class ParametricEqBand {
  const ParametricEqBand({
    required this.frequency,
    this.gain = 0.0,
    this.q = 1.0,
    required this.type,
    this.enabled = false,
  });

  factory ParametricEqBand.fromJson(Map<String, dynamic> json) =>
      ParametricEqBand(
        frequency: (json['frequency'] as num).toDouble(),
        gain: (json['gain'] as num).toDouble(),
        q: (json['q'] as num).toDouble(),
        type:
            BandType.fromJsonString(json['type'] as String? ?? '') ??
            BandType.peak,
        enabled: json['enabled'] as bool? ?? false,
      );

  /// Center frequency in Hz.
  final double frequency;

  /// Gain in dB.
  final double gain;

  /// Q factor / bandwidth.
  final double q;

  /// Filter type.
  final BandType type;

  /// Whether this band is active.
  final bool enabled;

  Map<String, dynamic> toJson() => {
    'frequency': frequency,
    'gain': gain,
    'q': q,
    'type': type.toJsonString(),
    'enabled': enabled,
  };

  /// Convert to lavfi filter string.
  /// Returns empty if disabled or gain is effectively zero (for gain-based types).
  String toLavfiString() {
    if (!enabled) return '';

    // For filter types that don't use gain, always emit when enabled.
    if (type != BandType.lowCut && type != BandType.highCut) {
      if (gain.abs() < 0.05) return '';
    }

    final fStr = 'f=${frequency.toStringAsFixed(1)}';
    final qStr = ':t=q:w=${q.toStringAsFixed(2)}';

    switch (type) {
      case BandType.peak:
        return 'lavfi-equalizer=$fStr$qStr:g=${gain.toStringAsFixed(1)}';
      case BandType.lowShelf:
        return 'lavfi-bass=$fStr$qStr:g=${gain.toStringAsFixed(1)}';
      case BandType.highShelf:
        return 'lavfi-treble=$fStr$qStr:g=${gain.toStringAsFixed(1)}';
      case BandType.lowCut:
        return 'lavfi-highpass=$fStr$qStr';
      case BandType.highCut:
        return 'lavfi-lowpass=$fStr$qStr';
    }
  }
}

/// Manages the state of an 18-band parametric equalizer.
class ParametricEqState {
  ParametricEqState()
    : bands = [
        for (final f in _defaultFrequencies)
          ParametricEqBand(frequency: f, type: BandType.peak),
      ];

  ParametricEqState._(this.bands);

  /// Deserialize from JSON.
  factory ParametricEqState.fromJson(Map<String, dynamic> json) {
    final bandList = json['bands'] as List<dynamic>? ?? [];
    return ParametricEqState._(
      bandList
          .map((b) => ParametricEqBand.fromJson(b as Map<String, dynamic>))
          .toList(),
    );
  }

  /// Parse lavfi filter strings back into a [ParametricEqState].
  ///
  /// If no parametric EQ filters are found in [custom], returns the default
  /// 18-band state so the screen always has bands to display and interact with.
  factory ParametricEqState.fromCustomFilters(List<String> custom) {
    final bands = <ParametricEqBand>[];
    for (final filter in custom) {
      final band = _parseLavfiFilter(filter);
      if (band != null) bands.add(band);
    }
    // Fall back to default state when no parametric EQ bands were parsed —
    // avoids an empty bands list that would crash the UI (RangeError on
    // _selectedBand access).
    if (bands.isEmpty) return ParametricEqState();
    return ParametricEqState._(bands);
  }

  /// Maximum number of bands.
  static const int maxBands = 18;

  /// ISO 1/3 octave center frequencies for 18 bands (25 Hz – 20 kHz).
  static const List<double> _defaultFrequencies = [
    25.0,
    31.5,
    50.0,
    80.0,
    125.0,
    200.0,
    315.0,
    500.0,
    800.0,
    1250.0,
    2000.0,
    3150.0,
    5000.0,
    8000.0,
    10000.0,
    12500.0,
    16000.0,
    20000.0,
  ];

  /// The list of EQ bands.
  final List<ParametricEqBand> bands;

  /// Replace the band at [index].
  void setBand(int index, ParametricEqBand band) {
    bands[index] = band;
  }

  /// Add a new enabled band with default values.
  void addBand() {
    bands.add(
      const ParametricEqBand(
        frequency: 1000.0,
        type: BandType.peak,
        enabled: true,
      ),
    );
  }

  /// Remove the band at [index]. No-op if only 1 band remains.
  void removeBand(int index) {
    if (bands.length <= 1) return;
    bands.removeAt(index);
  }

  /// Toggle the enabled state of the band at [index].
  void toggleBand(int index) {
    final band = bands[index];
    bands[index] = ParametricEqBand(
      frequency: band.frequency,
      gain: band.gain,
      q: band.q,
      type: band.type,
      enabled: !band.enabled,
    );
  }

  /// Serialize to JSON.
  Map<String, dynamic> toJson() => {
    'bands': bands.map((b) => b.toJson()).toList(),
  };

  /// Generate lavfi filter strings for all enabled, active bands.
  List<String> toLavfiStrings() {
    return bands
        .map((b) => b.toLavfiString())
        .where((s) => s.isNotEmpty)
        .toList();
  }

  /// Inject lavfi strings into an [AudioEffects]'s custom filter list.
  AudioEffects toAudioEffects(AudioEffects current) {
    final lavfi = toLavfiStrings();
    if (lavfi.isEmpty) return current;
    return current.copyWith(custom: [...current.custom, ...lavfi]);
  }

  /// Parse a single lavfi filter string into a [ParametricEqBand], or null.
  static ParametricEqBand? _parseLavfiFilter(String filter) {
    BandType? type;
    if (filter.startsWith('lavfi-equalizer=')) {
      type = BandType.peak;
    } else if (filter.startsWith('lavfi-bass=')) {
      type = BandType.lowShelf;
    } else if (filter.startsWith('lavfi-treble=')) {
      type = BandType.highShelf;
    } else if (filter.startsWith('lavfi-highpass=')) {
      type = BandType.lowCut;
    } else if (filter.startsWith('lavfi-lowpass=')) {
      type = BandType.highCut;
    }
    if (type == null) return null;

    // Parse key=value pairs after the filter prefix.
    final paramsStr = filter.substring(filter.indexOf('=') + 1);
    final params = <String, String>{};
    for (final part in paramsStr.split(':')) {
      final eqIndex = part.indexOf('=');
      if (eqIndex != -1) {
        params[part.substring(0, eqIndex)] = part.substring(eqIndex + 1);
      }
    }

    final frequency = double.tryParse(params['f'] ?? '') ?? 1000.0;
    final gain = double.tryParse(params['g'] ?? '') ?? 0.0;
    final q = double.tryParse(params['w'] ?? '') ?? 1.0;

    return ParametricEqBand(
      frequency: frequency,
      gain: gain,
      q: q,
      type: type,
      enabled: true,
    );
  }
}
