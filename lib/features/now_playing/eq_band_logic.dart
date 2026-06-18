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
        ChorusSettings,
        CrossfeedSettings,
        CrystalizerSettings,
        DeesserSettings,
        FlangerSettings,
        LoudnormSettings,
        RubberbandSettings,
        StereowidenSettings,
        TrebleSettings,
        TremoloSettings,
        VibratoSettings,
        VirtualbassSettings;

/// Mutable DSP state holding all equalizer and effects parameters.
///
/// Centralises the ~40 fields that were previously scattered across
/// [_EqDspScreenState] so the screen becomes a thin UI orchestrator.
class EqDspState {
  EqDspState()
    : masterEnabled = true,
      bass = 0,
      treble = 0,
      loudnorm = false,
      compressor = false,
      compThreshold = 0.1,
      compRatio = 4.0,
      compAttack = 20.0,
      compRelease = 250.0,
      rubberbandEnabled = false,
      pitch = 1.0,
      tempo = 1.0,
      crossfeed = false,
      crossfeedStrength = 0.2,
      stereoWiden = false,
      stereoWidenDelay = 20.0,
      exciter = false,
      exciterAmount = 1.0,
      crystalizer = false,
      crystalizerIntensity = 2.0,
      virtualBass = false,
      virtualBassCutoff = 250.0,
      gate = false,
      gateThreshold = 0.01,
      gateRatio = 2.0,
      gateAttack = 20.0,
      gateRelease = 250.0,
      deesser = false,
      deesserIntensity = 0,
      deesserMix = 0.5,
      deesserFreq = 0.5,
      echoEnabled = false,
      echoInGain = 0.6,
      echoOutGain = 0.3,
      echoDelays = '500',
      echoDecays = '0.5',
      phaser = false,
      phaserInGain = 0.4,
      phaserOutGain = 0.74,
      phaserDelay = 3.0,
      phaserDecay = 0.4,
      phaserSpeed = 0.5,
      flanger = false,
      flangerDelay = 0.0,
      flangerDepth = 2.0,
      flangerRegen = 0.0,
      flangerWidth = 71.0,
      flangerSpeed = 0.5,
      chorus = false,
      chorusInGain = 0.4,
      chorusOutGain = 0.4,
      chorusDelays = '40|60',
      chorusDecays = '0.4|0.32',
      chorusSpeeds = '0.25|0.4',
      chorusDepths = '2|3',
      tremolo = false,
      tremoloFreq = 5.0,
      tremoloDepth = 0.5,
      vibrato = false,
      vibratoFreq = 5.0,
      vibratoDepth = 0.5,
      crusher = false,
      crusherBits = 8.0,
      crusherMix = 0.5,
      crusherSamples = 1.0;

  // ── Master ──
  bool masterEnabled;

  // ── Tone ──
  double bass;
  double treble;

  // ── Dynamics ──
  bool loudnorm;
  bool compressor;
  double compThreshold;
  double compRatio;
  double compAttack;
  double compRelease;

  // ── Gate ──
  bool gate;
  double gateThreshold;
  double gateRatio;
  double gateAttack;
  double gateRelease;

  // ── De-esser ──
  bool deesser;
  double deesserIntensity;
  double deesserMix;
  double deesserFreq;

  // ── Pitch & tempo ──
  bool rubberbandEnabled;
  double pitch;
  double tempo;

  // ── Spatial ──
  bool crossfeed;
  double crossfeedStrength;
  bool stereoWiden;
  double stereoWidenDelay;

  // ── Creative ──
  bool exciter;
  double exciterAmount;
  bool crystalizer;
  double crystalizerIntensity;
  bool virtualBass;
  double virtualBassCutoff;

  // ── Echo / Delay ──
  bool echoEnabled;
  double echoInGain;
  double echoOutGain;
  String echoDelays;
  String echoDecays;

  // ── Modulation ──
  bool phaser;
  double phaserInGain;
  double phaserOutGain;
  double phaserDelay;
  double phaserDecay;
  double phaserSpeed;

  bool flanger;
  double flangerDelay;
  double flangerDepth;
  double flangerRegen;
  double flangerWidth;
  double flangerSpeed;

  bool chorus;
  double chorusInGain;
  double chorusOutGain;
  String chorusDelays;
  String chorusDecays;
  String chorusSpeeds;
  String chorusDepths;

  bool tremolo;
  double tremoloFreq;
  double tremoloDepth;

  bool vibrato;
  double vibratoFreq;
  double vibratoDepth;

  // ── Bit-crusher ──
  bool crusher;
  double crusherBits;
  double crusherMix;
  double crusherSamples;

  // ── Field dispatch ────────────────────────────────────────────────────────

  /// Updates a single effect field by name without triggering a rebuild.
  ///
  /// The screen's own [setState] handles the parent rebuild; section
  /// widgets use their local setState for immediate slider feedback.
  ///
  /// Prefer the typed setter methods for compile-time safety. This
  /// method is kept for backward compatibility with section widgets.
  void setField(String field, dynamic value) {
    switch (field) {
      case 'loudnorm':
        loudnorm = value as bool;
      case 'bass':
        bass = value as double;
      case 'treble':
        treble = value as double;
      case 'compressor':
        compressor = value as bool;
      case 'compThreshold':
        compThreshold = value as double;
      case 'compRatio':
        compRatio = value as double;
      case 'compAttack':
        compAttack = value as double;
      case 'compRelease':
        compRelease = value as double;
      case 'gate':
        gate = value as bool;
      case 'gateThreshold':
        gateThreshold = value as double;
      case 'gateRatio':
        gateRatio = value as double;
      case 'gateAttack':
        gateAttack = value as double;
      case 'gateRelease':
        gateRelease = value as double;
      case 'deesser':
        deesser = value as bool;
      case 'deesserIntensity':
        deesserIntensity = value as double;
      case 'deesserMix':
        deesserMix = value as double;
      case 'deesserFreq':
        deesserFreq = value as double;
      case 'echoEnabled':
        echoEnabled = value as bool;
      case 'echoInGain':
        echoInGain = value as double;
      case 'echoOutGain':
        echoOutGain = value as double;
      case 'echoDelays':
        echoDelays = value as String;
      case 'echoDecays':
        echoDecays = value as String;
      case 'rubberbandEnabled':
        rubberbandEnabled = value as bool;
      case 'pitch':
        pitch = value as double;
      case 'tempo':
        tempo = value as double;
      case 'crossfeed':
        crossfeed = value as bool;
      case 'crossfeedStrength':
        crossfeedStrength = value as double;
      case 'stereoWiden':
        stereoWiden = value as bool;
      case 'stereoWidenDelay':
        stereoWidenDelay = value as double;
      case 'phaser':
        phaser = value as bool;
      case 'phaserInGain':
        phaserInGain = value as double;
      case 'phaserOutGain':
        phaserOutGain = value as double;
      case 'phaserDelay':
        phaserDelay = value as double;
      case 'phaserDecay':
        phaserDecay = value as double;
      case 'phaserSpeed':
        phaserSpeed = value as double;
      case 'flanger':
        flanger = value as bool;
      case 'flangerDelay':
        flangerDelay = value as double;
      case 'flangerDepth':
        flangerDepth = value as double;
      case 'flangerRegen':
        flangerRegen = value as double;
      case 'flangerWidth':
        flangerWidth = value as double;
      case 'flangerSpeed':
        flangerSpeed = value as double;
      case 'chorus':
        chorus = value as bool;
      case 'chorusInGain':
        chorusInGain = value as double;
      case 'chorusOutGain':
        chorusOutGain = value as double;
      case 'chorusDelays':
        chorusDelays = value as String;
      case 'chorusDecays':
        chorusDecays = value as String;
      case 'chorusSpeeds':
        chorusSpeeds = value as String;
      case 'chorusDepths':
        chorusDepths = value as String;
      case 'tremolo':
        tremolo = value as bool;
      case 'tremoloFreq':
        tremoloFreq = value as double;
      case 'tremoloDepth':
        tremoloDepth = value as double;
      case 'vibrato':
        vibrato = value as bool;
      case 'vibratoFreq':
        vibratoFreq = value as double;
      case 'vibratoDepth':
        vibratoDepth = value as double;
      case 'exciter':
        exciter = value as bool;
      case 'exciterAmount':
        exciterAmount = value as double;
      case 'crystalizer':
        crystalizer = value as bool;
      case 'crystalizerIntensity':
        crystalizerIntensity = value as double;
      case 'virtualBass':
        virtualBass = value as bool;
      case 'virtualBassCutoff':
        virtualBassCutoff = value as double;
      case 'crusher':
        crusher = value as bool;
      case 'crusherBits':
        crusherBits = value as double;
      case 'crusherMix':
        crusherMix = value as double;
      case 'crusherSamples':
        crusherSamples = value as double;
    }
  }

  // ── Typed setters (m1) ───────────────────────────────────────────────────
  // Compile-time safe alternatives to setField(). Each setter has the
  // correct type signature, eliminating runtime cast errors.

  // ── Tone ──
  void setBass(double v) => bass = v;
  void setTreble(double v) => treble = v;

  // ── Dynamics ──
  void setLoudnorm(bool v) => loudnorm = v;
  void setCompressor(bool v) => compressor = v;
  void setCompThreshold(double v) => compThreshold = v;
  void setCompRatio(double v) => compRatio = v;
  void setCompAttack(double v) => compAttack = v;
  void setCompRelease(double v) => compRelease = v;
  void setGate(bool v) => gate = v;
  void setGateThreshold(double v) => gateThreshold = v;
  void setGateRatio(double v) => gateRatio = v;
  void setGateAttack(double v) => gateAttack = v;
  void setGateRelease(double v) => gateRelease = v;
  void setDeesser(bool v) => deesser = v;
  void setDeesserIntensity(double v) => deesserIntensity = v;
  void setDeesserMix(double v) => deesserMix = v;
  void setDeesserFreq(double v) => deesserFreq = v;

  // ── Echo ──
  void setEchoEnabled(bool v) => echoEnabled = v;
  void setEchoInGain(double v) => echoInGain = v;
  void setEchoOutGain(double v) => echoOutGain = v;
  void setEchoDelays(String v) => echoDelays = v;
  void setEchoDecays(String v) => echoDecays = v;

  // ── Pitch ──
  void setRubberbandEnabled(bool v) => rubberbandEnabled = v;
  void setPitch(double v) => pitch = v;
  void setTempo(double v) => tempo = v;

  // ── Spatial ──
  void setCrossfeed(bool v) => crossfeed = v;
  void setCrossfeedStrength(double v) => crossfeedStrength = v;
  void setStereoWiden(bool v) => stereoWiden = v;
  void setStereoWidenDelay(double v) => stereoWidenDelay = v;

  // ── Modulation ──
  void setPhaser(bool v) => phaser = v;
  void setPhaserInGain(double v) => phaserInGain = v;
  void setPhaserOutGain(double v) => phaserOutGain = v;
  void setPhaserDelay(double v) => phaserDelay = v;
  void setPhaserDecay(double v) => phaserDecay = v;
  void setPhaserSpeed(double v) => phaserSpeed = v;
  void setFlanger(bool v) => flanger = v;
  void setFlangerDelay(double v) => flangerDelay = v;
  void setFlangerDepth(double v) => flangerDepth = v;
  void setFlangerRegen(double v) => flangerRegen = v;
  void setFlangerWidth(double v) => flangerWidth = v;
  void setFlangerSpeed(double v) => flangerSpeed = v;
  void setChorus(bool v) => chorus = v;
  void setChorusInGain(double v) => chorusInGain = v;
  void setChorusOutGain(double v) => chorusOutGain = v;
  void setChorusDelays(String v) => chorusDelays = v;
  void setChorusDecays(String v) => chorusDecays = v;
  void setChorusSpeeds(String v) => chorusSpeeds = v;
  void setChorusDepths(String v) => chorusDepths = v;
  void setTremolo(bool v) => tremolo = v;
  void setTremoloFreq(double v) => tremoloFreq = v;
  void setTremoloDepth(double v) => tremoloDepth = v;
  void setVibrato(bool v) => vibrato = v;
  void setVibratoFreq(double v) => vibratoFreq = v;
  void setVibratoDepth(double v) => vibratoDepth = v;

  // ── Creative ──
  void setExciter(bool v) => exciter = v;
  void setExciterAmount(double v) => exciterAmount = v;
  void setCrystalizer(bool v) => crystalizer = v;
  void setCrystalizerIntensity(double v) => crystalizerIntensity = v;
  void setVirtualBass(bool v) => virtualBass = v;
  void setVirtualBassCutoff(double v) => virtualBassCutoff = v;
  void setCrusher(bool v) => crusher = v;
  void setCrusherBits(double v) => crusherBits = v;
  void setCrusherMix(double v) => crusherMix = v;
  void setCrusherSamples(double v) => crusherSamples = v;

  // ── Reset ─────────────────────────────────────────────────────────────────

  /// Reset all DSP fields to their defaults.
  void reset() {
    masterEnabled = true;
    bass = 0;
    treble = 0;
    loudnorm = false;
    compressor = false;
    compThreshold = 0.1;
    compRatio = 4.0;
    compAttack = 20.0;
    compRelease = 250.0;
    rubberbandEnabled = false;
    pitch = 1.0;
    tempo = 1.0;
    crossfeed = false;
    crossfeedStrength = 0.2;
    stereoWiden = false;
    stereoWidenDelay = 20.0;
    exciter = false;
    exciterAmount = 1.0;
    crystalizer = false;
    crystalizerIntensity = 2.0;
    virtualBass = false;
    virtualBassCutoff = 250.0;
    gate = false;
    gateThreshold = 0.01;
    gateRatio = 2.0;
    gateAttack = 20.0;
    gateRelease = 250.0;
    deesser = false;
    deesserIntensity = 0.0;
    deesserMix = 0.5;
    deesserFreq = 0.5;
    echoEnabled = false;
    echoInGain = 0.6;
    echoOutGain = 0.3;
    echoDelays = '500';
    echoDecays = '0.5';
    phaser = false;
    phaserInGain = 0.4;
    phaserOutGain = 0.74;
    phaserDelay = 3.0;
    phaserDecay = 0.4;
    phaserSpeed = 0.5;
    flanger = false;
    flangerDelay = 0.0;
    flangerDepth = 2.0;
    flangerRegen = 0.0;
    flangerWidth = 71.0;
    flangerSpeed = 0.5;
    chorus = false;
    chorusInGain = 0.4;
    chorusOutGain = 0.4;
    chorusDelays = '40|60';
    chorusDecays = '0.4|0.32';
    chorusSpeeds = '0.25|0.4';
    chorusDepths = '2|3';
    tremolo = false;
    tremoloFreq = 5.0;
    tremoloDepth = 0.5;
    vibrato = false;
    vibratoFreq = 5.0;
    vibratoDepth = 0.5;
    crusher = false;
    crusherBits = 8.0;
    crusherMix = 0.5;
    crusherSamples = 1.0;
  }

  // ── AudioEffects conversion ───────────────────────────────────────────────

  /// Build [AudioEffects] from the current state values, merging into
  /// [current] so that fields we don't own (superequalizer, custom)
  /// are preserved.
  AudioEffects toAudioEffects(AudioEffects current) {
    return current.copyWith(
      bass: BassSettings(enabled: bass != 0, g: bass),
      treble: TrebleSettings(enabled: treble != 0, g: treble),
      loudnorm: LoudnormSettings(enabled: loudnorm),
      acompressor: AcompressorSettings(
        enabled: compressor,
        threshold: compThreshold,
        ratio: compRatio,
        attack: compAttack,
        release: compRelease,
      ),
      rubberband: RubberbandSettings(
        enabled: rubberbandEnabled,
        pitch: pitch,
        tempo: tempo,
      ),
      crossfeed: CrossfeedSettings(
        enabled: crossfeed,
        strength: crossfeedStrength,
      ),
      stereowiden: StereowidenSettings(
        enabled: stereoWiden,
        delay: stereoWidenDelay,
      ),
      aexciter: AexciterSettings(enabled: exciter, amount: exciterAmount),
      crystalizer: CrystalizerSettings(
        enabled: crystalizer,
        i: crystalizerIntensity,
      ),
      virtualbass: VirtualbassSettings(
        enabled: virtualBass,
        cutoff: virtualBassCutoff,
      ),
      agate: AgateSettings(
        enabled: gate,
        threshold: gateThreshold,
        ratio: gateRatio,
        attack: gateAttack,
        release: gateRelease,
      ),
      deesser: DeesserSettings(
        enabled: deesser,
        i: deesserIntensity,
        m: deesserMix,
        f: deesserFreq,
      ),
      aecho: AechoSettings(
        enabled: echoEnabled,
        in_gain: echoInGain,
        out_gain: echoOutGain,
        delays: echoDelays,
        decays: echoDecays,
      ),
      aphaser: AphaserSettings(
        enabled: phaser,
        in_gain: phaserInGain,
        out_gain: phaserOutGain,
        delay: phaserDelay,
        decay: phaserDecay,
        speed: phaserSpeed,
      ),
      flanger: FlangerSettings(
        enabled: flanger,
        delay: flangerDelay,
        depth: flangerDepth,
        regen: flangerRegen,
        width: flangerWidth,
        speed: flangerSpeed,
      ),
      chorus: ChorusSettings(
        enabled: chorus,
        in_gain: chorusInGain,
        out_gain: chorusOutGain,
        delays: chorusDelays,
        decays: chorusDecays,
        speeds: chorusSpeeds,
        depths: chorusDepths,
      ),
      tremolo: TremoloSettings(
        enabled: tremolo,
        f: tremoloFreq,
        d: tremoloDepth,
      ),
      vibrato: VibratoSettings(
        enabled: vibrato,
        f: vibratoFreq,
        d: vibratoDepth,
      ),
      acrusher: AcrusherSettings(
        enabled: crusher,
        bits: crusherBits,
        mix: crusherMix,
        samples: crusherSamples,
      ),
      // superequalizer and custom are NOT touched — preserved from current
    );
  }

  /// Populate this state from persisted [AudioEffects].
  void loadFromAudioEffects(AudioEffects fx) {
    bass = fx.bass?.g ?? 0.0;
    treble = fx.treble?.g ?? 0.0;
    loudnorm = fx.loudnorm?.enabled ?? false;
    compressor = fx.acompressor?.enabled ?? false;
    compThreshold = fx.acompressor?.threshold ?? 0.125;
    compRatio = fx.acompressor?.ratio ?? 2.0;
    compAttack = fx.acompressor?.attack ?? 20.0;
    compRelease = fx.acompressor?.release ?? 250.0;
    rubberbandEnabled = fx.rubberband?.enabled ?? false;
    pitch = fx.rubberband?.pitch ?? 1.0;
    tempo = fx.rubberband?.tempo ?? 1.0;
    crossfeed = fx.crossfeed?.enabled ?? false;
    crossfeedStrength = fx.crossfeed?.strength ?? 0.2;
    stereoWiden = fx.stereowiden?.enabled ?? false;
    stereoWidenDelay = fx.stereowiden?.delay ?? 20.0;
    exciter = fx.aexciter?.enabled ?? false;
    exciterAmount = fx.aexciter?.amount ?? 1.0;
    crystalizer = fx.crystalizer?.enabled ?? false;
    crystalizerIntensity = (fx.crystalizer?.i ?? 2.0).clamp(-10.0, 10.0);
    virtualBass = fx.virtualbass?.enabled ?? false;
    virtualBassCutoff = fx.virtualbass?.cutoff ?? 250.0;
    gate = fx.agate?.enabled ?? false;
    gateThreshold = fx.agate?.threshold ?? 0.125;
    gateRatio = fx.agate?.ratio ?? 2.0;
    gateAttack = fx.agate?.attack ?? 20.0;
    gateRelease = fx.agate?.release ?? 250.0;
    deesser = fx.deesser?.enabled ?? false;
    deesserIntensity = (fx.deesser?.i ?? 0.0).clamp(0.0, 1.0);
    deesserMix = (fx.deesser?.m ?? 0.5).clamp(0.0, 1.0);
    deesserFreq = (fx.deesser?.f ?? 0.5).clamp(0.0, 1.0);
    echoEnabled = fx.aecho?.enabled ?? false;
    echoInGain = fx.aecho?.in_gain ?? 0.6;
    echoOutGain = fx.aecho?.out_gain ?? 0.3;
    echoDelays = fx.aecho?.delays ?? '1000';
    echoDecays = fx.aecho?.decays ?? '0.5';
    phaser = fx.aphaser?.enabled ?? false;
    phaserInGain = fx.aphaser?.in_gain ?? 0.4;
    phaserOutGain = fx.aphaser?.out_gain ?? 0.74;
    phaserDelay = fx.aphaser?.delay ?? 3.0;
    phaserDecay = fx.aphaser?.decay ?? 0.4;
    phaserSpeed = fx.aphaser?.speed ?? 0.5;
    flanger = fx.flanger?.enabled ?? false;
    flangerDelay = fx.flanger?.delay ?? 0.0;
    flangerDepth = fx.flanger?.depth ?? 2.0;
    flangerRegen = fx.flanger?.regen ?? 0.0;
    flangerWidth = fx.flanger?.width ?? 71.0;
    flangerSpeed = fx.flanger?.speed ?? 0.5;
    chorus = fx.chorus?.enabled ?? false;
    chorusInGain = fx.chorus?.in_gain ?? 0.4;
    chorusOutGain = fx.chorus?.out_gain ?? 0.4;
    chorusDelays = fx.chorus?.delays ?? '40|60';
    chorusDecays = fx.chorus?.decays ?? '0.4|0.32';
    chorusSpeeds = fx.chorus?.speeds ?? '0.25|0.4';
    chorusDepths = fx.chorus?.depths ?? '2|1.3';
    tremolo = fx.tremolo?.enabled ?? false;
    tremoloFreq = fx.tremolo?.f ?? 5.0;
    tremoloDepth = fx.tremolo?.d ?? 0.5;
    vibrato = fx.vibrato?.enabled ?? false;
    vibratoFreq = fx.vibrato?.f ?? 5.0;
    vibratoDepth = fx.vibrato?.d ?? 0.5;
    crusher = fx.acrusher?.enabled ?? false;
    crusherBits = fx.acrusher?.bits ?? 8.0;
    crusherMix = fx.acrusher?.mix ?? 0.5;
    crusherSamples = fx.acrusher?.samples ?? 1.0;
  }

  // ── Badge counts ──────────────────────────────────────────────────────────

  int get dynamicsCount =>
      (loudnorm ? 1 : 0) +
      (compressor ? 1 : 0) +
      (gate ? 1 : 0) +
      (deesser ? 1 : 0);

  int get modulationCount =>
      (phaser ? 1 : 0) +
      (flanger ? 1 : 0) +
      (chorus ? 1 : 0) +
      (tremolo ? 1 : 0) +
      (vibrato ? 1 : 0);

  int get creativeCount =>
      (exciter ? 1 : 0) +
      (crystalizer ? 1 : 0) +
      (virtualBass ? 1 : 0) +
      (crusher ? 1 : 0);
}
