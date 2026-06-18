import 'dart:convert';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:mpv_audio_kit/mpv_audio_kit.dart'
    show
        AcompressorSettings,
        AcrusherSettings,
        AechoSettings,
        AexciterSettings,
        AgateSettings,
        AphaserSettings,
        AudioEffects,
        BassSettings,
        Cache,
        ChorusSettings,
        CrossfeedSettings,
        CrystalizerSettings,
        DeesserSettings,
        FlangerSettings,
        Format,
        Gapless,
        LoudnormSettings,
        ReplayGain,
        ReplayGainSettings,
        RubberbandSettings,
        StereowidenSettings,
        SuperequalizerSettings,
        TrebleSettings,
        TremoloSettings,
        VibratoSettings,
        VirtualbassSettings;
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/lastfm/lastfm_storage.dart';
import 'models/graphic_eq_state.dart';
import 'models/parametric_eq_state.dart';
import '../../utils/log.dart';
import 'player_service.dart';

/// Typed descriptor for a persisted setting key.
///
/// Pairs the string key with conversion functions so [PlayerSettingsStore]
/// can read and write any supported type through a single generic path.
class SettingsKey<T> {
  const SettingsKey(
    this.key, {
    required this.fromStorage,
    required this.toStorage,
  });
  final String key;
  final T Function(dynamic) fromStorage;
  final dynamic Function(T) toStorage;

  static SettingsKey<int> intKey(String k) => SettingsKey<int>(
    k,
    fromStorage: (v) => (v as num).toInt(),
    toStorage: (v) => v,
  );

  static SettingsKey<double> doubleKey(String k) => SettingsKey<double>(
    k,
    fromStorage: (v) => (v as num).toDouble(),
    toStorage: (v) => v,
  );

  static SettingsKey<bool> boolKey(String k) =>
      SettingsKey<bool>(k, fromStorage: (v) => v as bool, toStorage: (v) => v);

  static SettingsKey<String> stringKey(String k) => SettingsKey<String>(
    k,
    fromStorage: (v) => v as String,
    toStorage: (v) => v,
  );
}

/// Persists user-tweakable mpv runtime settings to `shared_preferences`
/// so they survive app restarts.
///
/// mpv resets every property to its compiled-in default on each `Player()`
/// construction. The settings dialogs (`SettingsScreen`) write through to
/// mpv via `AfPlayerService.setX()`, but without persistence those values
/// vanish on app cold-start.
///
/// Flow:
/// 1. UI calls `PlayerSettingsStore.saveX(value)` after a successful setter.
/// 2. On app start, `applyPersisted(svc)` reads every key and replays the
///    setters against the freshly-constructed player.
///
/// All simple (non-compound) settings are persisted through the typed
/// [SettingsKey] descriptor system. Complex types like [AudioEffects] and
/// [EqPreset] use custom JSON serialization.
class PlayerSettingsStore {
  /// Creates a [PlayerSettingsStore] backed by [prefs].
  ///
  /// Also sets the static backing store so that legacy static methods
  /// (still used by tests) resolve to the same prefs instance.
  PlayerSettingsStore(this.prefs) {
    _staticPrefs ??= prefs;
  }

  /// The injected [SharedPreferences] instance.
  final SharedPreferences prefs;

  // ── Static backing for legacy static methods (tests) ──────────────────
  static SharedPreferences? _staticPrefs;

  /// Returns the active [SharedPreferences].
  ///
  /// Prefers the instance injected via the constructor (set in `_staticPrefs`).
  /// Falls back to `SharedPreferences.getInstance()` for tests and callers
  /// that don't go through the provider.
  static Future<SharedPreferences> _ensurePrefs() async {
    return _staticPrefs ?? await SharedPreferences.getInstance();
  }

  // ── Typed key descriptors ────────────────────────────────────────────────
  static final kSampleRate = SettingsKey.intKey('af.audio_sample_rate');
  static final kFormat = SettingsKey.stringKey('af.audio_format');
  static final kExclusive = SettingsKey.boolKey('af.audio_exclusive');
  static final kBufferMs = SettingsKey.intKey('af.audio_buffer_ms');
  static final kStreamSilence = SettingsKey.boolKey('af.audio_stream_silence');
  static final kCacheSecs = SettingsKey.intKey('af.cache_secs');
  static final kCachePauseInitial = SettingsKey.boolKey(
    'af.cache_pause_initial',
  );
  static final kReplayGain = SettingsKey.stringKey('af.replay_gain_mode');
  static final kGapless = SettingsKey.stringKey('af.gapless');
  static final kReplayGainPreamp = SettingsKey.doubleKey(
    'af.replay_gain_preamp',
  );
  static final kReplayGainFallback = SettingsKey.doubleKey(
    'af.replay_gain_fallback',
  );
  static final kReplayGainClip = SettingsKey.boolKey('af.replay_gain_clip');
  static final kPrefetchPlaylist = SettingsKey.boolKey('af.prefetch_playlist');
  static final kDspMasterEnabled = SettingsKey.boolKey('af.dsp_master_enabled');
  static final kArtworkPulse = SettingsKey.boolKey('af.artwork_pulse_enabled');
  static final kOfflineCacheEnabled = SettingsKey.boolKey(
    'af.offline_cache_enabled',
  );
  static final kOfflineCacheMaxSize = SettingsKey.intKey(
    'af.offline_cache_max_size',
  );
  static final kMaxBitrate = SettingsKey.intKey('af.max_bitrate_kbps');
  static final kShuffleEnabled = SettingsKey.boolKey('af.shuffle_enabled');
  static final kLastFmScrobbleEnabled = SettingsKey.boolKey(
    'af.lastfm_scrobble_enabled',
  );
  static final kDefaultAudioDevice = SettingsKey.stringKey(
    'af.default_audio_device',
  );
  static final kAcceptAllCerts = SettingsKey.boolKey('af.accept_all_certs');

  // Compound keys (custom JSON serialization)
  static const kAudioEffects = 'af.audio_effects_json';
  static const kEqPresets = 'af.eq_presets_json';
  static const kActivePreset = 'af.active_eq_preset';

  // Split persistence keys (3-key architecture)
  static const kDspState = 'af.dsp_state_json';
  static const kGraphicEq = 'af.graphic_eq_json';
  static const kParametricEq = 'af.parametric_eq_json';

  // ── Generic persistence ──────────────────────────────────────────────────

  /// Save a typed value through its descriptor.
  static Future<void> saveValue<T>(SettingsKey<T> desc, T value) async {
    final p = await _ensurePrefs();
    final stored = desc.toStorage(value);
    switch (stored) {
      case final int v:
        await p.setInt(desc.key, v);
      case final double v:
        await p.setDouble(desc.key, v);
      case final bool v:
        await p.setBool(desc.key, v);
      case final String v:
        await p.setString(desc.key, v);
      default:
        throw ArgumentError(
          'Unsupported type for key ${desc.key}: ${stored.runtimeType}',
        );
    }
  }

  /// Load a typed value through its descriptor. Returns `null` if absent.
  static Future<T?> loadValue<T>(SettingsKey<T> desc) async {
    final p = await _ensurePrefs();
    final raw = p.get(desc.key);
    if (raw == null) return null;
    return desc.fromStorage(raw);
  }

  // ── Last.fm Settings ──────────────────────────────────────────────────────

  static Future<void> saveLastFmApiKey(String val) =>
      LastFmStorage().saveApiKey(val);
  static Future<void> saveLastFmApiSecret(String val) =>
      LastFmStorage().saveApiSecret(val);
  static Future<void> saveLastFmSessionKey(String val) =>
      LastFmStorage().saveSessionKey(val);
  static Future<void> saveLastFmUsername(String val) =>
      LastFmStorage().saveUsername(val);
  static Future<void> saveLastFmScrobbleEnabled(bool val) =>
      LastFmStorage().saveScrobbleEnabled(val);

  // ── Setters (called from UI) ──────────────────────────────────────────────

  static Future<void> saveSampleRate(int rate) async =>
      saveValue(kSampleRate, rate);

  static Future<void> saveFormat(Format format) async =>
      saveValue(kFormat, format.name);

  static Future<void> saveExclusive(bool enabled) async =>
      saveValue(kExclusive, enabled);

  static Future<void> saveBufferMs(int ms) async => saveValue(kBufferMs, ms);

  static Future<void> saveStreamSilence(bool enabled) async =>
      saveValue(kStreamSilence, enabled);

  static Future<void> saveCacheSecs(int secs) async =>
      saveValue(kCacheSecs, secs);

  static Future<void> saveCachePauseInitial(bool enabled) async =>
      saveValue(kCachePauseInitial, enabled);

  static Future<void> saveReplayGain(ReplayGain mode) async =>
      saveValue(kReplayGain, mode.name);

  static Future<void> saveReplayGainFull(ReplayGainSettings settings) async {
    final p = await _ensurePrefs();
    await saveValue(kReplayGain, settings.mode.name);
    await p.setDouble(kReplayGainPreamp.key, settings.preamp);
    await p.setDouble(kReplayGainFallback.key, settings.fallback);
    await p.setBool(kReplayGainClip.key, settings.clip);
  }

  static Future<void> savePrefetchPlaylist(bool enabled) async =>
      saveValue(kPrefetchPlaylist, enabled);

  static Future<void> saveGapless(Gapless mode) async =>
      saveValue(kGapless, mode.name);

  /// Persist the DSP master switch state.
  static Future<void> saveDspMasterEnabled(bool enabled) async =>
      saveValue(kDspMasterEnabled, enabled);

  /// Load the DSP master switch state. Defaults to false (effects off).
  static Future<bool> loadDspMasterEnabled() async =>
      (await loadValue(kDspMasterEnabled)) ?? false;

  /// Persist the artwork pulse animation toggle.
  static Future<void> saveArtworkPulse(bool enabled) async =>
      saveValue(kArtworkPulse, enabled);

  /// Load the artwork pulse animation toggle. Defaults to true (pulse on).
  static Future<bool> loadArtworkPulse() async =>
      (await loadValue(kArtworkPulse)) ?? true;

  /// Persist offline cache enabled state.
  static Future<void> saveOfflineCacheEnabled(bool enabled) async =>
      saveValue(kOfflineCacheEnabled, enabled);

  /// Persist offline cache max size in bytes.
  static Future<void> saveOfflineCacheMaxSize(int bytes) async =>
      saveValue(kOfflineCacheMaxSize, bytes);

  /// Load offline cache enabled state. Defaults to false (disabled).
  static Future<bool> loadOfflineCacheEnabled() async =>
      (await loadValue(kOfflineCacheEnabled)) ?? false;

  /// Load offline cache max size. Defaults to 1 GB.
  static Future<int> loadOfflineCacheMaxSize() async =>
      (await loadValue(kOfflineCacheMaxSize)) ?? (1024 * 1024 * 1024);

  /// Persist max streaming bitrate in kbps. 0 means Original / Lossless.
  static Future<void> saveMaxBitrate(int kbps) async =>
      saveValue(kMaxBitrate, kbps);

  /// Load max streaming bitrate in kbps. Defaults to 0 (Original / Lossless).
  static Future<int> loadMaxBitrate() async =>
      (await loadValue(kMaxBitrate)) ?? 0;

  /// Persist shuffle enabled state.
  static Future<void> saveShuffleEnabled(bool enabled) async =>
      saveValue(kShuffleEnabled, enabled);

  /// Persist the default audio device name. Pass `null` to clear
  /// (revert to "auto" behavior on next startup).
  static Future<void> saveDefaultAudioDevice(String? deviceName) async {
    if (deviceName == null) {
      final p = await _ensurePrefs();
      await p.remove(kDefaultAudioDevice.key);
    } else {
      await saveValue(kDefaultAudioDevice, deviceName);
    }
  }

  /// Load the persisted default audio device name. Returns `null` when
  /// no device has been saved (meaning "auto" should be used).
  static Future<String?> loadDefaultAudioDevice() async =>
      loadValue(kDefaultAudioDevice);

  /// Persist the accept-all-certificates escape hatch.
  static Future<void> saveAcceptAllCerts(bool enabled) async =>
      saveValue(kAcceptAllCerts, enabled);

  /// Load the accept-all-certificates escape hatch. Defaults to false.
  static Future<bool> loadAcceptAllCerts() async =>
      (await loadValue(kAcceptAllCerts)) ?? false;

  /// Serialize the user-visible audio effects to JSON and persist.
  /// Delegates to [_serializeAudioEffects] to avoid duplication.
  static Future<void> saveAudioEffects(AudioEffects fx) async {
    final p = await _ensurePrefs();
    await p.setString(kAudioEffects, jsonEncode(_serializeAudioEffects(fx)));
  }

  // ── EQ Presets ────────────────────────────────────────────────────────────

  /// Save a named EQ preset (18-band params + bass/treble).
  static Future<void> saveEqPreset(String name, EqPreset preset) async {
    final p = await _ensurePrefs();
    final all = loadEqPresets(p);
    all[name] = preset;
    final encoded = all.map((k, v) => MapEntry(k, v.toJson()));
    await p.setString(kEqPresets, jsonEncode(encoded));
  }

  /// Delete a named EQ preset.
  static Future<void> deleteEqPreset(String name) async {
    final p = await _ensurePrefs();
    final all = loadEqPresets(p);
    all.remove(name);
    final encoded = all.map((k, v) => MapEntry(k, v.toJson()));
    await p.setString(kEqPresets, jsonEncode(encoded));
  }

  /// Load all user-saved EQ presets.
  static Map<String, EqPreset> loadEqPresets(SharedPreferences p) {
    final json = p.getString(kEqPresets);
    if (json == null) return {};
    try {
      final raw = jsonDecode(json) as Map<String, dynamic>;
      return raw.map(
        (k, v) => MapEntry(k, EqPreset.fromJson(v as Map<String, dynamic>)),
      );
    } on Exception catch (e, stack) {
      afLog(
        'audio',
        'Failed to load EQ presets from storage',
        error: e,
        stackTrace: stack,
      );
      return {};
    }
  }

  /// Load all user-saved EQ presets (async convenience).
  static Future<Map<String, EqPreset>> loadEqPresetsAsync() async {
    final p = await _ensurePrefs();
    return loadEqPresets(p);
  }

  /// Save the name of the currently active preset (null to clear).
  static Future<void> saveActivePreset(String? name) async {
    final p = await _ensurePrefs();
    if (name == null) {
      await p.remove(kActivePreset);
    } else {
      await p.setString(kActivePreset, name);
    }
  }

  /// Load the name of the currently active preset.
  static String? loadActivePreset(SharedPreferences p) {
    return p.getString(kActivePreset);
  }

  /// Restore audio effects from JSON.
  /// Delegates to [_deserializeAudioEffects] to avoid duplication.
  static AudioEffects? loadAudioEffects(SharedPreferences p) {
    final json = p.getString(kAudioEffects);
    if (json == null) return null;
    try {
      return _deserializeAudioEffects(json);
    } on Exception catch (e, stack) {
      afLog(
        'audio',
        'Failed to load audio effects from storage',
        error: e,
        stackTrace: stack,
      );
      return null;
    }
  }

  // ── Split persistence (3-key architecture) ────────────────────────────────
  // These methods are kept for migration purposes only.
  // All screens now save/load through the unified key (saveAudioEffects/loadAudioEffects).

  /// Migrate from the old combined `af.audio_effects_json` key to the
  /// 3-key split (DSP, Graphic EQ, Parametric EQ).
  ///
  /// Idempotent: if the old key is already removed, this is a no-op.
  static Future<void> migrateFromOldKey(SharedPreferences p) async {
    final oldJson = p.getString(kAudioEffects);
    if (oldJson == null) return;

    try {
      final fx = _deserializeAudioEffects(oldJson);
      if (fx == null) return;

      // Extract graphic EQ from superequalizer params.
      final graphicEq = GraphicEqState.fromAudioEffects(fx);

      // Extract parametric EQ from custom lavfi filter strings.
      final parametricEq = ParametricEqState.fromCustomFilters(fx.custom);

      // DSP state: all effects with default superequalizer and empty custom.
      final dspFx = fx.copyWith(
        superequalizer: const SuperequalizerSettings(),
        custom: const [],
      );

      // Persist to the 3 new keys.
      await p.setString(kGraphicEq, jsonEncode(graphicEq.toJson()));
      await p.setString(kParametricEq, jsonEncode(parametricEq.toJson()));
      await p.setString(kDspState, jsonEncode(_serializeAudioEffects(dspFx)));

      // Remove the old combined key.
      await p.remove(kAudioEffects);
    } on Exception catch (e, stack) {
      afLog(
        'audio',
        'Failed to migrate audio effects from old key',
        error: e,
        stackTrace: stack,
      );
    }
  }

  /// Migrate from orphaned split keys (DSP, Graphic EQ, Parametric EQ)
  /// back to the unified `af.audio_effects_json` key.
  ///
  /// If the unified key already exists, split keys are simply removed.
  /// If not, the split keys are merged into a combined state.
  /// Idempotent: safe to call multiple times.
  static Future<void> migrateSplitKeys(SharedPreferences p) async {
    final hasLegacy =
        p.containsKey(kDspState) ||
        p.containsKey(kGraphicEq) ||
        p.containsKey(kParametricEq);
    if (!hasLegacy) return;

    // If no combined key exists, reconstruct from split keys
    if (!p.containsKey(kAudioEffects)) {
      final dspFx = _loadDspStateFromPrefs(p);
      final graphicEq = _loadGraphicEqFromPrefs(p);
      final parametricEq = _loadParametricEqFromPrefs(p);
      if (dspFx != null) {
        var merged = dspFx;
        merged = graphicEq.toAudioEffects(merged);
        merged = parametricEq.toAudioEffects(merged);
        await p.setString(
          kAudioEffects,
          jsonEncode(_serializeAudioEffects(merged)),
        );
      }
    }

    // Remove orphaned split keys
    await p.remove(kDspState);
    await p.remove(kGraphicEq);
    await p.remove(kParametricEq);
  }

  /// Serialize [AudioEffects] for testing purposes.
  @visibleForTesting
  static Map<String, dynamic> testSerializeAudioEffects(AudioEffects fx) =>
      _serializeAudioEffects(fx);

  /// Load DSP state directly from SharedPreferences (internal helper).
  static AudioEffects? _loadDspStateFromPrefs(SharedPreferences p) {
    final json = p.getString(kDspState);
    if (json == null) return null;
    try {
      return _deserializeAudioEffects(json);
    } on Exception catch (e, stack) {
      afLog(
        'error',
        'DSP state deserialization failed',
        error: e,
        stackTrace: stack,
      );
      return null;
    }
  }

  /// Load GraphicEqState directly from SharedPreferences (internal helper).
  static GraphicEqState _loadGraphicEqFromPrefs(SharedPreferences p) {
    final json = p.getString(kGraphicEq);
    if (json == null) return GraphicEqState();
    try {
      return GraphicEqState.fromJson(jsonDecode(json) as Map<String, dynamic>);
    } on Exception catch (e, stack) {
      afLog(
        'error',
        'Graphic EQ state deserialization failed',
        error: e,
        stackTrace: stack,
      );
      return GraphicEqState();
    }
  }

  /// Load ParametricEqState directly from SharedPreferences (internal helper).
  static ParametricEqState _loadParametricEqFromPrefs(SharedPreferences p) {
    final json = p.getString(kParametricEq);
    if (json == null) return ParametricEqState();
    try {
      return ParametricEqState.fromJson(
        jsonDecode(json) as Map<String, dynamic>,
      );
    } on Exception catch (e, stack) {
      afLog(
        'error',
        'Parametric EQ state deserialization failed',
        error: e,
        stackTrace: stack,
      );
      return ParametricEqState();
    }
  }

  // ── Private helpers for AudioEffects JSON ────────────────────────────────

  /// Serialize [AudioEffects] to a JSON-compatible map.
  /// Uses the same field layout as [saveAudioEffects].
  static Map<String, dynamic> _serializeAudioEffects(AudioEffects fx) {
    return <String, dynamic>{
      'bass_g': fx.bass?.g ?? 0.0,
      'bass_enabled': fx.bass?.enabled ?? false,
      'treble_g': fx.treble?.g ?? 0.0,
      'treble_enabled': fx.treble?.enabled ?? false,
      'loudnorm_enabled': fx.loudnorm?.enabled ?? false,
      'compressor_enabled': fx.acompressor?.enabled ?? false,
      'compressor_threshold': fx.acompressor?.threshold ?? 0.125,
      'compressor_ratio': fx.acompressor?.ratio ?? 2.0,
      'compressor_attack': fx.acompressor?.attack ?? 20.0,
      'compressor_release': fx.acompressor?.release ?? 250.0,
      'eq_enabled': fx.superequalizer?.enabled ?? false,
      'eq_params': fx.superequalizer?.params ?? const <String, double>{},
      'rubberband_enabled': fx.rubberband?.enabled ?? false,
      'rubberband_pitch': fx.rubberband?.pitch ?? 1.0,
      'rubberband_tempo': fx.rubberband?.tempo ?? 1.0,
      'crossfeed_enabled': fx.crossfeed?.enabled ?? false,
      'crossfeed_strength': fx.crossfeed?.strength ?? 0.2,
      'stereowiden_enabled': fx.stereowiden?.enabled ?? false,
      'stereowiden_delay': fx.stereowiden?.delay ?? 20.0,
      'exciter_enabled': fx.aexciter?.enabled ?? false,
      'exciter_amount': fx.aexciter?.amount ?? 1.0,
      'crystalizer_enabled': fx.crystalizer?.enabled ?? false,
      'crystalizer_i': fx.crystalizer?.i ?? 2.0,
      'virtualbass_enabled': fx.virtualbass?.enabled ?? false,
      'virtualbass_cutoff': fx.virtualbass?.cutoff ?? 250.0,
      'gate_enabled': fx.agate?.enabled ?? false,
      'gate_threshold': fx.agate?.threshold ?? 0.125,
      'gate_ratio': fx.agate?.ratio ?? 2.0,
      'gate_attack': fx.agate?.attack ?? 20.0,
      'gate_release': fx.agate?.release ?? 250.0,
      'deesser_enabled': fx.deesser?.enabled ?? false,
      'deesser_i': fx.deesser?.i ?? 0.0,
      'deesser_m': fx.deesser?.m ?? 0.5,
      'deesser_f': fx.deesser?.f ?? 0.5,
      'echo_enabled': fx.aecho?.enabled ?? false,
      'echo_in_gain': fx.aecho?.in_gain ?? 0.6,
      'echo_out_gain': fx.aecho?.out_gain ?? 0.3,
      'echo_delays': fx.aecho?.delays ?? '1000',
      'echo_decays': fx.aecho?.decays ?? '0.5',
      'phaser_enabled': fx.aphaser?.enabled ?? false,
      'phaser_in_gain': fx.aphaser?.in_gain ?? 0.4,
      'phaser_out_gain': fx.aphaser?.out_gain ?? 0.74,
      'phaser_delay': fx.aphaser?.delay ?? 3.0,
      'phaser_decay': fx.aphaser?.decay ?? 0.4,
      'phaser_speed': fx.aphaser?.speed ?? 0.5,
      'flanger_enabled': fx.flanger?.enabled ?? false,
      'flanger_delay': fx.flanger?.delay ?? 0.0,
      'flanger_depth': fx.flanger?.depth ?? 2.0,
      'flanger_regen': fx.flanger?.regen ?? 0.0,
      'flanger_width': fx.flanger?.width ?? 71.0,
      'flanger_speed': fx.flanger?.speed ?? 0.5,
      'chorus_enabled': fx.chorus?.enabled ?? false,
      'chorus_in_gain': fx.chorus?.in_gain ?? 0.4,
      'chorus_out_gain': fx.chorus?.out_gain ?? 0.4,
      'chorus_delays': fx.chorus?.delays ?? '40|60',
      'chorus_decays': fx.chorus?.decays ?? '0.4|0.32',
      'chorus_speeds': fx.chorus?.speeds ?? '0.25|0.4',
      'chorus_depths': fx.chorus?.depths ?? '2|1.3',
      'tremolo_enabled': fx.tremolo?.enabled ?? false,
      'tremolo_f': fx.tremolo?.f ?? 5.0,
      'tremolo_d': fx.tremolo?.d ?? 0.5,
      'vibrato_enabled': fx.vibrato?.enabled ?? false,
      'vibrato_f': fx.vibrato?.f ?? 5.0,
      'vibrato_d': fx.vibrato?.d ?? 0.5,
      'crusher_enabled': fx.acrusher?.enabled ?? false,
      'crusher_bits': fx.acrusher?.bits ?? 8.0,
      'crusher_mix': fx.acrusher?.mix ?? 0.5,
      'crusher_samples': fx.acrusher?.samples ?? 1.0,
      'custom_filters': fx.custom,
    };
  }

  /// Deserialize [AudioEffects] from a JSON string.
  /// Uses the same field layout as [loadAudioEffects].
  static AudioEffects? _deserializeAudioEffects(String jsonString) {
    final m = jsonDecode(jsonString) as Map<String, dynamic>;
    final eqParamsRaw = m['eq_params'] as Map<String, dynamic>?;
    final eqParams =
        eqParamsRaw?.map((k, v) => MapEntry(k, (v as num).toDouble())) ??
        const <String, double>{};
    return AudioEffects(
      bass: BassSettings(
        enabled: m['bass_enabled'] as bool? ?? false,
        g: (m['bass_g'] as num?)?.toDouble() ?? 0.0,
      ),
      treble: TrebleSettings(
        enabled: m['treble_enabled'] as bool? ?? false,
        g: (m['treble_g'] as num?)?.toDouble() ?? 0.0,
      ),
      loudnorm: LoudnormSettings(
        enabled: m['loudnorm_enabled'] as bool? ?? false,
      ),
      acompressor: AcompressorSettings(
        enabled: m['compressor_enabled'] as bool? ?? false,
        threshold: (m['compressor_threshold'] as num?)?.toDouble() ?? 0.1,
        ratio: (m['compressor_ratio'] as num?)?.toDouble() ?? 4.0,
        attack: (m['compressor_attack'] as num?)?.toDouble() ?? 20.0,
        release: (m['compressor_release'] as num?)?.toDouble() ?? 250.0,
      ),
      superequalizer: SuperequalizerSettings(
        enabled: m['eq_enabled'] as bool? ?? false,
        params: eqParams,
      ),
      rubberband: RubberbandSettings(
        enabled: m['rubberband_enabled'] as bool? ?? false,
        pitch: (m['rubberband_pitch'] as num?)?.toDouble() ?? 1.0,
        tempo: (m['rubberband_tempo'] as num?)?.toDouble() ?? 1.0,
      ),
      crossfeed: CrossfeedSettings(
        enabled: m['crossfeed_enabled'] as bool? ?? false,
        strength: (m['crossfeed_strength'] as num?)?.toDouble() ?? 0.2,
      ),
      stereowiden: StereowidenSettings(
        enabled: m['stereowiden_enabled'] as bool? ?? false,
        delay: (m['stereowiden_delay'] as num?)?.toDouble() ?? 20.0,
      ),
      aexciter: AexciterSettings(
        enabled: m['exciter_enabled'] as bool? ?? false,
        amount: (m['exciter_amount'] as num?)?.toDouble() ?? 1.0,
      ),
      crystalizer: CrystalizerSettings(
        enabled: m['crystalizer_enabled'] as bool? ?? false,
        i: (m['crystalizer_i'] as num?)?.toDouble() ?? 2.0,
      ),
      virtualbass: VirtualbassSettings(
        enabled: m['virtualbass_enabled'] as bool? ?? false,
        cutoff: (m['virtualbass_cutoff'] as num?)?.toDouble() ?? 250.0,
      ),
      agate: AgateSettings(
        enabled: m['gate_enabled'] as bool? ?? false,
        threshold: (m['gate_threshold'] as num?)?.toDouble() ?? 0.01,
        ratio: (m['gate_ratio'] as num?)?.toDouble() ?? 2.0,
        attack: (m['gate_attack'] as num?)?.toDouble() ?? 20.0,
        release: (m['gate_release'] as num?)?.toDouble() ?? 250.0,
      ),
      deesser: DeesserSettings(
        enabled: m['deesser_enabled'] as bool? ?? false,
        i: (m['deesser_i'] as num?)?.toDouble() ?? 0.0,
        m: (m['deesser_m'] as num?)?.toDouble() ?? 0.5,
        f: (m['deesser_f'] as num?)?.toDouble() ?? 0.5,
      ),
      aecho: AechoSettings(
        enabled: m['echo_enabled'] as bool? ?? false,
        in_gain: (m['echo_in_gain'] as num?)?.toDouble() ?? 0.6,
        out_gain: (m['echo_out_gain'] as num?)?.toDouble() ?? 0.3,
        delays: m['echo_delays'] as String? ?? '500',
        decays: m['echo_decays'] as String? ?? '0.5',
      ),
      aphaser: AphaserSettings(
        enabled: m['phaser_enabled'] as bool? ?? false,
        in_gain: (m['phaser_in_gain'] as num?)?.toDouble() ?? 0.4,
        out_gain: (m['phaser_out_gain'] as num?)?.toDouble() ?? 0.74,
        delay: (m['phaser_delay'] as num?)?.toDouble() ?? 3.0,
        decay: (m['phaser_decay'] as num?)?.toDouble() ?? 0.4,
        speed: (m['phaser_speed'] as num?)?.toDouble() ?? 0.5,
      ),
      flanger: FlangerSettings(
        enabled: m['flanger_enabled'] as bool? ?? false,
        delay: (m['flanger_delay'] as num?)?.toDouble() ?? 0.0,
        depth: (m['flanger_depth'] as num?)?.toDouble() ?? 2.0,
        regen: (m['flanger_regen'] as num?)?.toDouble() ?? 0.0,
        width: (m['flanger_width'] as num?)?.toDouble() ?? 71.0,
        speed: (m['flanger_speed'] as num?)?.toDouble() ?? 0.5,
      ),
      chorus: ChorusSettings(
        enabled: m['chorus_enabled'] as bool? ?? false,
        in_gain: (m['chorus_in_gain'] as num?)?.toDouble() ?? 0.4,
        out_gain: (m['chorus_out_gain'] as num?)?.toDouble() ?? 0.4,
        delays: m['chorus_delays'] as String? ?? '40|60',
        decays: m['chorus_decays'] as String? ?? '0.4|0.32',
        speeds: m['chorus_speeds'] as String? ?? '0.25|0.4',
        depths: m['chorus_depths'] as String? ?? '2|3',
      ),
      tremolo: TremoloSettings(
        enabled: m['tremolo_enabled'] as bool? ?? false,
        f: (m['tremolo_f'] as num?)?.toDouble() ?? 5.0,
        d: (m['tremolo_d'] as num?)?.toDouble() ?? 0.5,
      ),
      vibrato: VibratoSettings(
        enabled: m['vibrato_enabled'] as bool? ?? false,
        f: (m['vibrato_f'] as num?)?.toDouble() ?? 5.0,
        d: (m['vibrato_d'] as num?)?.toDouble() ?? 0.5,
      ),
      acrusher: AcrusherSettings(
        enabled: m['crusher_enabled'] as bool? ?? false,
        bits: (m['crusher_bits'] as num?)?.toDouble() ?? 8.0,
        mix: (m['crusher_mix'] as num?)?.toDouble() ?? 0.5,
        samples: (m['crusher_samples'] as num?)?.toDouble() ?? 1.0,
      ),
      custom: (m['custom_filters'] is List)
          ? (m['custom_filters'] as List<dynamic>).whereType<String>().toList()
          : const [],
    );
  }

  // ── Apply on startup ──────────────────────────────────────────────────────

  /// Reads every persisted key and replays the matching setter on [svc].
  /// Call this once after the player has been constructed and configured.
  /// Failures are logged but do not throw — a single bad value should not
  /// break startup.
  Future<void> applyPersisted(AfPlayerService svc) async {
    final p = prefs;

    // One-time cleanup of orphaned split keys from the 3-key era
    await migrateSplitKeys(p);

    Future<void> tryApply(String label, Future<void> Function() action) async {
      try {
        await action();
      } on Exception catch (e, stack) {
        afLog(
          'error',
          'PlayerSettingsStore apply $label failed',
          error: e,
          stackTrace: stack,
        );
      }
    }

    // Read all values from prefs first (synchronous in-memory), then apply
    // setters in parallel via Future.wait.  Each setter is an independent
    // platform-channel round-trip — no ordering dependency between them.
    final sampleRate = p.getInt(kSampleRate.key);
    final formatName = p.getString(kFormat.key);
    final exclusive = p.getBool(kExclusive.key);
    final bufferMs = p.getInt(kBufferMs.key);
    final streamSilence = p.getBool(kStreamSilence.key);
    final cacheSecs = p.getInt(kCacheSecs.key);
    final cachePauseInitial = p.getBool(kCachePauseInitial.key);
    final replayGainName = p.getString(kReplayGain.key);
    final gaplessName = p.getString(kGapless.key);
    final prefetch = p.getBool(kPrefetchPlaylist.key);
    final fx = loadAudioEffects(p);
    final masterEnabled = p.getBool(kDspMasterEnabled.key) ?? false;
    final shuffleEnabled = p.getBool(kShuffleEnabled.key);

    final futures = <Future<void>>[];

    if (sampleRate != null) {
      futures.add(
        tryApply(
          'sampleRate=$sampleRate',
          () => svc.setAudioSampleRate(sampleRate),
        ),
      );
    }

    if (formatName != null) {
      final format = Format.values.firstWhere(
        (f) => f.name == formatName,
        orElse: () => Format.auto,
      );
      futures.add(
        tryApply('format=$formatName', () => svc.setAudioFormat(format)),
      );
    }

    if (exclusive != null) {
      futures.add(
        tryApply(
          'exclusive=$exclusive',
          () => svc.setAudioExclusive(exclusive),
        ),
      );
    }

    if (bufferMs != null) {
      futures.add(
        tryApply(
          'bufferMs=$bufferMs',
          () => svc.setAudioBuffer(Duration(milliseconds: bufferMs)),
        ),
      );
    }

    if (streamSilence != null) {
      futures.add(
        tryApply(
          'streamSilence=$streamSilence',
          () => svc.setAudioStreamSilence(streamSilence),
        ),
      );
    }

    if (cacheSecs != null) {
      futures.add(
        tryApply('cacheSecs=$cacheSecs', () async {
          await svc.setCache(
            svc.cacheSettings.copyWith(
              mode: Cache.yes,
              secs: Duration(seconds: cacheSecs),
            ),
          );
        }),
      );
    }

    if (cachePauseInitial != null) {
      futures.add(
        tryApply('cachePauseInitial=$cachePauseInitial', () async {
          await svc.setCache(
            svc.cacheSettings.copyWith(pauseInitial: cachePauseInitial),
          );
        }),
      );
    }

    if (replayGainName != null) {
      final mode = ReplayGain.values.firstWhere(
        (m) => m.name == replayGainName,
        orElse: () => ReplayGain.no,
      );
      final preamp = p.getDouble(kReplayGainPreamp.key) ?? 0.0;
      final fallback = p.getDouble(kReplayGainFallback.key) ?? 0.0;
      final clip = p.getBool(kReplayGainClip.key) ?? false;
      futures.add(
        tryApply('replayGain=$replayGainName', () async {
          await svc.setReplayGain(
            ReplayGainSettings(
              mode: mode,
              preamp: preamp,
              fallback: fallback,
              clip: clip,
            ),
          );
        }),
      );
    }

    if (gaplessName != null) {
      final mode = Gapless.values.firstWhere(
        (g) => g.name == gaplessName,
        orElse: () => Gapless.weak,
      );
      futures.add(tryApply('gapless=$gaplessName', () => svc.setGapless(mode)));
    }

    if (prefetch != null) {
      futures.add(
        tryApply(
          'prefetchPlaylist=$prefetch',
          () => svc.setPrefetchPlaylist(prefetch),
        ),
      );
    }

    if (fx != null && masterEnabled) {
      futures.add(tryApply('audioEffects', () => svc.setAudioEffects(fx)));
    }

    if (shuffleEnabled != null) {
      futures.add(
        tryApply(
          'shuffleEnabled=$shuffleEnabled',
          () => svc.setAfShuffleMode(shuffleEnabled),
        ),
      );
    }

    await Future.wait(futures);
    afLog('boot', 'PlayerSettingsStore applied persisted settings');
  }
}

/// A named EQ preset containing 18-band params + bass/treble shelves.
class EqPreset {
  const EqPreset({required this.bands, this.bass = 0.0, this.treble = 0.0});

  factory EqPreset.fromJson(Map<String, dynamic> json) {
    final bandsRaw = json['bands'] as Map<String, dynamic>?;
    final bands =
        bandsRaw?.map((k, v) => MapEntry(k, (v as num).toDouble())) ??
        const <String, double>{};
    return EqPreset(
      bands: bands,
      bass: (json['bass'] as num?)?.toDouble() ?? 0.0,
      treble: (json['treble'] as num?)?.toDouble() ?? 0.0,
    );
  }
  final Map<String, double> bands;
  final double bass;
  final double treble;

  Map<String, dynamic> toJson() => {
    'bands': bands,
    'bass': bass,
    'treble': treble,
  };
}
