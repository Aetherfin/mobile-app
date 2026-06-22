/// Time-formatting helpers.
///
/// All durations are formatted in track time (mm:ss / hh:mm:ss).
String formatTrackDuration(Duration d) {
  if (d.isNegative) d = Duration.zero;
  final total = d.inSeconds;
  final hours = total ~/ 3600;
  final minutes = (total % 3600) ~/ 60;
  final seconds = total % 60;
  String two(int n) => n.toString().padLeft(2, '0');
  if (hours > 0) {
    return '${two(hours)}:${two(minutes)}:${two(seconds)}';
  }
  return '${two(minutes)}:${two(seconds)}';
}

/// Returns "-MM:SS" remaining time for the given remaining duration.
String formatRemaining(Duration d) {
  return '-${formatTrackDuration(d)}';
}

/// Whole-hour readout, e.g. `103h`. Used on the All Set artwork wall.
String formatHourCount(Duration d) {
  final hours = d.inMinutes / 60;
  if (hours < 1) {
    return '${d.inMinutes}m';
  }
  return '${hours.round()}h';
}

/// Parses a nullable numeric string and formats it compactly.
/// Returns '' for null, the raw string if unparseable, or a compact
/// representation like `1.2K`, `3.4M` for valid integers.
String formatCompactCountString(String? numStr) {
  if (numStr == null || numStr.isEmpty) return '';
  final n = int.tryParse(numStr);
  if (n == null) return numStr;
  return formatCompactCount(n);
}

/// "2,247" → "2.2K", "12,400" → "12K", small numbers untouched.
///
/// Each decimal-place tier truncates rather than rounds at the upper edge
/// so the readout never crosses its tier's ceiling. `toStringAsFixed(1)`
/// alone would render 9999 as `"10.0K"`, which is visually identical to
/// the *next* tier's `"10K"` but two characters wider — i.e. the column
/// re-flows on the boundary. Truncation gives the clean sequence
/// `9.8K, 9.9K, 10K`.
String formatCompactCount(int n) {
  if (n < 1000) return n.toString();
  if (n < 10_000) {
    final tenths = (n ~/ 100) % 10;
    final whole = n ~/ 1000;
    return '$whole.${tenths}K';
  }
  if (n < 1_000_000) return '${n ~/ 1000}K';
  if (n < 10_000_000) {
    final tenths = (n ~/ 100_000) % 10;
    final whole = n ~/ 1_000_000;
    return '$whole.${tenths}M';
  }
  return '${n ~/ 1_000_000}M';
}
