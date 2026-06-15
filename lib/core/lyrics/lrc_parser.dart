/// A single timestamped lyric line.
class LrcLine {
  const LrcLine(this.start, this.text);
  final Duration start;
  final String text;
}

/// Parsed LRC payload.
class Lrc {
  const Lrc({this.lines = const [], this.meta = const {}});

  /// Lines sorted by [LrcLine.start].
  final List<LrcLine> lines;

  /// Track-level metadata (`[ti:..]`, `[ar:..]`, `[al:..]`).
  final Map<String, String> meta;

  bool get isEmpty => lines.isEmpty;

  /// Index of the active line for the given playback position. Returns -1
  /// when no line is active yet (e.g. before the first lyric).
  ///
  /// Binary search: this is invoked on every position tick (4 Hz) and a
  /// long lyric file can hold a few hundred lines. Keeping it O(log n)
  /// instead of O(n) shaves real work off the highlight loop on lower-end
  /// devices.
  int activeIndex(Duration position) {
    if (lines.isEmpty) return -1;
    var lo = 0;
    var hi = lines.length - 1;
    var idx = -1;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      if (lines[mid].start <= position) {
        idx = mid;
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    return idx;
  }
}

/// Where the lyrics were fetched from.
enum LyricsSource {
  cache('Lyric provided by Cache'),
  server('Lyric provided by Server'),
  lrclib('Lyric provided by LRCLib'),
  netease('Lyric provided by NetEase'),
  neteaseRomaji('Lyric provided by NetEase Romaji'),
  kugou('Lyric provided by KuGou'),
  simpmusic('Lyric provided by SimpMusic'),
  unison('Lyric provided by Unison'),
  romanize('Lyric provided by Romanize');

  const LyricsSource(this.label);
  final String label;
}

/// Lyrics result with source information.
class LyricsResult {
  const LyricsResult({required this.lrc, required this.source});
  final Lrc lrc;
  final LyricsSource source;
}

/// A minimal LRC parser. Handles single timestamp lines like:
///   `[mm:ss.xx] lyric text`
/// Multi-timestamp lines (`[00:12.34][00:25.67] text`) are expanded.
/// Bracketed metadata (`[ti:Track Title]`) is collected into [Lrc.meta].
Lrc parseLrc(String src) {
  final lines = <LrcLine>[];
  final meta = <String, String>{};
  final lineRegex = RegExp(r'^(.*?)$', multiLine: true);
  final tagRegex = RegExp(r'\[(\d{1,2}):(\d{2})(?:\.(\d{1,3}))?\]');
  final metaRegex = RegExp(r'^\[([a-zA-Z]+):(.+)\]$');

  for (final m in lineRegex.allMatches(src)) {
    final raw = m.group(1)?.trim() ?? '';
    if (raw.isEmpty) continue;

    final metaMatch = metaRegex.firstMatch(raw);
    if (metaMatch != null && tagRegex.firstMatch(raw) == null) {
      meta[metaMatch.group(1)!.toLowerCase()] = metaMatch.group(2)!.trim();
      continue;
    }

    final tags = tagRegex.allMatches(raw).toList();
    if (tags.isEmpty) continue;

    final text = raw.replaceAll(tagRegex, '').trim();
    for (final tag in tags) {
      // tryParse keeps a malformed-but-regex-matching LRC (e.g. a tag with
      // a stray non-ASCII digit slipping past the engine's NFD/NFC pass)
      // from crashing the whole parser. We simply drop the offending tag.
      final mm = int.tryParse(tag.group(1) ?? '');
      final ss = int.tryParse(tag.group(2) ?? '');
      if (mm == null || ss == null) continue;
      final fragRaw = tag.group(3) ?? '0';
      final fragInt = int.tryParse(fragRaw);
      if (fragInt == null) continue;
      final ms =
          (fragInt *
                  (fragRaw.length == 3
                      ? 1
                      : fragRaw.length == 2
                      ? 10
                      : 100))
              .clamp(0, 999);
      lines.add(
        LrcLine(Duration(minutes: mm, seconds: ss, milliseconds: ms), text),
      );
    }
  }
  lines.sort((a, b) => a.start.compareTo(b.start));
  return Lrc(lines: lines, meta: meta);
}
