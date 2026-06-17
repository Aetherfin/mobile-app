/// Audio quality readout — surfaced honestly on Now Playing and on the
/// active row's quality chip.
///
/// Shape mirrors what Jellyfin returns from `/Sessions/Playing` and
/// `/Items/{id}/MediaInfo`. We carry the raw codec name + bitrate +
/// the transcode flag and present them in the UI without spin.
class TrackQuality {
  const TrackQuality({
    required this.sourceCodec,
    this.bitrateKbps,
    this.bitDepth,
    this.sampleRateKhz,
    this.isTranscoded = false,
    this.transcodeCodec,
    this.transcodeBitrateKbps,
  });

  /// 'flac', 'aac', 'opus', etc. Lowercased, source codec.
  final String sourceCodec;

  /// kbps for lossy. For lossless we expose [bitDepth] and [sampleRate]
  /// to render `FLAC 24/96` instead.
  final int? bitrateKbps;

  /// Lossless bit depth — e.g. 16, 24.
  final int? bitDepth;

  /// Lossless sample rate in kHz — e.g. 44, 48, 96.
  final int? sampleRateKhz;

  /// True when the server is transcoding to a different codec.
  final bool isTranscoded;

  /// Codec the server is transcoding TO, if [isTranscoded].
  final String? transcodeCodec;

  /// Transcode bitrate in kbps.
  final int? transcodeBitrateKbps;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TrackQuality &&
          other.sourceCodec == sourceCodec &&
          other.bitrateKbps == bitrateKbps &&
          other.bitDepth == bitDepth &&
          other.sampleRateKhz == sampleRateKhz &&
          other.isTranscoded == isTranscoded &&
          other.transcodeCodec == transcodeCodec &&
          other.transcodeBitrateKbps == transcodeBitrateKbps;

  @override
  int get hashCode => Object.hash(
    sourceCodec,
    bitrateKbps,
    bitDepth,
    sampleRateKhz,
    isTranscoded,
    transcodeCodec,
    transcodeBitrateKbps,
  );

  /// Display label for the quality chip.
  ///
  ///   `FLAC 24/96`  — native lossless
  ///   `AAC 256`     — native lossy
  ///   `AAC 192 · ↻` — transcoded
  ///   `Direct`      — settings only
  String get chipLabel {
    if (isTranscoded) {
      final codec = (transcodeCodec ?? sourceCodec).toUpperCase();
      final bitrate = transcodeBitrateKbps ?? bitrateKbps;
      if (bitrate != null) return '$codec $bitrate · ↻';
      return '$codec · ↻';
    }
    final codec = sourceCodec.toUpperCase();
    if (bitDepth != null && sampleRateKhz != null) {
      return '$codec $bitDepth/$sampleRateKhz';
    }
    if (bitrateKbps != null) {
      return '$codec $bitrateKbps';
    }
    return codec;
  }

  /// True when the quality chip should add a 1dp warning border.
  bool get isDegraded => isTranscoded;
}
