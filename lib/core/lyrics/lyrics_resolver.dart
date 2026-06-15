import 'package:romanize/romanize.dart' show TextRomanizer;

import '../backend/music_backend.dart';
import '../jellyfin/models/items.dart';
import 'lrc_parser.dart';
import 'netease_client.dart';
import 'lrclib_client.dart';
import '../../utils/text_utils.dart';
import '../../utils/log.dart';

/// Encapsulates the lyrics resolution flow.
///
/// Flow:
/// 1. Check cache first → if contains romanizable text → romanize
/// 2. If embedded lyrics: check language → if Japanese, try NetEase romaji → if still romanizable, romanize → if non-Japanese romanizable, romanize directly → if no romanizable text, use as-is
/// 3. If no embedded: NetEase → romanize if needed → LRCLib → romanize if needed
class LyricsResolver {
  LyricsResolver({
    required MusicBackend backend,
    NetEaseClient? netease,
    LrcLibClient? lrclib,
  }) : _backend = backend,
       _netease = netease ?? NetEaseClient(),
       _lrclib = lrclib ?? LrcLibClient();

  final MusicBackend _backend;
  final NetEaseClient _netease;
  final LrcLibClient _lrclib;

  /// In-memory cache for lyrics: trackId → (raw lyrics, source)
  final Map<String, ({String raw, LyricsSource source})> _cache = {};

  /// Number of tracks currently cached.
  int get cacheSize => _cache.length;

  /// Whether a given [trackId] is in the cache.
  bool isCached(String trackId) => _cache.containsKey(trackId);

  /// Cache lyrics for a track. Used to pre-populate or update cache.
  void cacheLyrics(String trackId, String raw, LyricsSource source) {
    _cache[trackId] = (raw: raw, source: source);
  }

  /// Resolve lyrics for [trackId] using the cascading flow.
  ///
  /// 1. Check cache first → if contains romanizable text, romanize
  /// 2. If embedded lyrics: check language → romanize if needed
  /// 3. If no embedded: NetEase → romanize if needed → LRCLib → romanize if needed
  Future<LyricsResult?> resolve({
    required String trackId,
    required AfTrack track,
  }) async {
    // ── Step 1: Check cache first ─────────────────────────────────────
    final cached = _cache[trackId];
    if (cached != null) {
      afLog('lyrics', 'Cache hit for $trackId');
      // If cached lyrics contain romanizable text, romanize them
      if (containsRomanizableText(cached.raw)) {
        return await _romanizeLrc(
          cached.raw,
          trackId,
          source: LyricsSource.cache,
        );
      }
      // Non-romanizable cached lyrics → return directly
      final parsed = parseLrc(cached.raw);
      return LyricsResult(lrc: parsed, source: LyricsSource.cache);
    }

    // ── Step 2: No cache → check embedded lyrics ──────────────────────
    String? embedded;
    try {
      embedded = await _backend.lyrics(trackId);
    } on Exception catch (e) {
      afLog('lyrics', 'Backend lyrics() failed for $trackId', error: e);
      return null;
    }

    if (embedded != null && embedded.trim().isNotEmpty) {
      // Cache the embedded lyrics for future use
      cacheLyrics(trackId, embedded, LyricsSource.server);
      return await _resolveEmbedded(
        trackId: trackId,
        track: track,
        raw: embedded,
      );
    }

    // ── Step 3: No embedded → NetEase → LRCLib ───────────────────────
    return await _resolveFromNetwork(trackId: trackId, track: track);
  }

  /// Handle embedded lyrics: check language, try NetEase romaji, romanize.
  Future<LyricsResult?> _resolveEmbedded({
    required String trackId,
    required AfTrack track,
    required String raw,
  }) async {
    if (!containsRomanizableText(raw)) {
      // Non-romanizable embedded → use directly
      final parsed = parseLrc(raw);
      afLog(
        'lyrics',
        'Embedded lyrics (server) for $trackId: ${parsed.lines.length} lines',
      );
      return LyricsResult(lrc: parsed, source: LyricsSource.server);
    }

    // Japanese embedded → try NetEase romaji (NetEase only provides romaji
    // for Japanese songs, so only attempt this path for Japanese text)
    if (containsJapanese(raw)) {
      final romajiResult = await _tryNeteaseRomaji(track);
      if (romajiResult != null) {
        return romajiResult;
      }
    }

    // Romanizable text (any language) → romanize locally
    return await _romanizeLrc(raw, trackId);
  }

  /// Try fetching romaji from NetEase. Returns null if unavailable or
  /// if the result still contains Japanese characters.
  Future<LyricsResult?> _tryNeteaseRomaji(AfTrack track) async {
    try {
      final result = await _netease.fetchLyrics(
        trackName: track.title,
        artistName: track.artistName,
        albumName: track.albumName,
        duration: track.duration,
      );

      if (result?.romaji != null && result!.romaji!.trim().isNotEmpty) {
        final romajiText = result.romaji!.trim();
        // Only use if it's actually Latin (no romanizable text)
        if (!containsRomanizableText(romajiText)) {
          final parsed = parseLrc(romajiText);
          afLog(
            'lyrics',
            'NetEase romaji for ${track.id}: ${parsed.lines.length} lines',
          );
          return LyricsResult(lrc: parsed, source: LyricsSource.neteaseRomaji);
        }
      }
    } on Exception catch (e) {
      afLog('lyrics', 'NetEase romaji fetch failed for ${track.id}', error: e);
    }
    return null;
  }

  /// Fetch lyrics from network: NetEase → LRCLib.
  Future<LyricsResult?> _resolveFromNetwork({
    required String trackId,
    required AfTrack track,
  }) async {
    // ── Try NetEase first ─────────────────────────────────────────────
    try {
      final neteaseResult = await _netease.fetchLyrics(
        trackName: track.title,
        artistName: track.artistName,
        albumName: track.albumName,
        duration: track.duration,
      );

      if (neteaseResult != null) {
        // Prefer romaji if available and non-romanizable
        if (neteaseResult.romaji != null &&
            neteaseResult.romaji!.trim().isNotEmpty) {
          final romajiText = neteaseResult.romaji!.trim();
          if (!containsRomanizableText(romajiText)) {
            final parsed = parseLrc(romajiText);
            afLog(
              'lyrics',
              'NetEase romaji for $trackId: ${parsed.lines.length} lines',
            );
            return LyricsResult(
              lrc: parsed,
              source: LyricsSource.neteaseRomaji,
            );
          }
          // Romaji still has romanizable text → romanize it
          return await _romanizeLrc(
            romajiText,
            trackId,
            source: LyricsSource.neteaseRomaji,
          );
        }

        // No romaji → try synced or plain
        final raw = neteaseResult.synced ?? neteaseResult.plain;
        if (raw != null && raw.trim().isNotEmpty) {
          if (containsRomanizableText(raw)) {
            // Romanizable NetEase lyrics → romanize
            return await _romanizeLrc(
              raw,
              trackId,
              source: LyricsSource.romanize,
            );
          }
          final parsed = parseLrc(raw);
          afLog('lyrics', 'NetEase for $trackId: ${parsed.lines.length} lines');
          return LyricsResult(lrc: parsed, source: LyricsSource.netease);
        }
      }
    } on Exception catch (e) {
      afLog('lyrics', 'NetEase fetch failed for $trackId', error: e);
    }

    // ── Try LRCLib as last resort ─────────────────────────────────────
    try {
      final lrclibResult = await _lrclib.fetchLyrics(
        trackName: track.title,
        artistName: track.artistName,
        albumName: track.albumName,
        duration: track.duration,
      );

      if (lrclibResult != null) {
        final raw = lrclibResult.synced ?? lrclibResult.plain;
        if (raw != null && raw.trim().isNotEmpty) {
          // Romanize LRCLib results if they contain romanizable text
          if (containsRomanizableText(raw)) {
            return await _romanizeLrc(
              raw,
              trackId,
              source: LyricsSource.lrclib,
            );
          }
          final parsed = parseLrc(raw);
          afLog('lyrics', 'LRCLib for $trackId: ${parsed.lines.length} lines');
          return LyricsResult(lrc: parsed, source: LyricsSource.lrclib);
        }
      }
    } on Exception catch (e) {
      afLog('lyrics', 'LRCLib fetch failed for $trackId', error: e);
    }

    return null;
  }

  /// Romanize LRC text locally using the romanize package.
  ///
  /// Supports all languages: Japanese, Korean, Chinese, Cyrillic, Arabic,
  /// and Hebrew. Uses [TextRomanizer.romanize] which auto-detects the
  /// language of each word and applies the appropriate romanizer.
  ///
  /// If romanization fails, falls back to returning the original text
  /// with a warning.
  Future<LyricsResult> _romanizeLrc(
    String rawLrc,
    String trackId, {
    LyricsSource source = LyricsSource.romanize,
  }) async {
    // Ensure romanize dictionaries are loaded (e.g. Japanese kanji → reading).
    // This is a no-op if already initialized.
    try {
      await TextRomanizer.ensureInitialized();
    } on Exception catch (e) {
      afLog(
        'lyrics',
        'TextRomanizer.ensureInitialized failed for $trackId',
        error: e,
      );
    }

    final lines = rawLrc.split('\n');
    final buffer = StringBuffer();
    for (final line in lines) {
      final timestampMatch = RegExp(
        r'^(\[\d{1,2}:\d{2}(?:\.\d{1,3})?\])',
      ).firstMatch(line);
      if (timestampMatch != null) {
        final timestamp = timestampMatch.group(1)!;
        final text = line.substring(timestamp.length);
        final romanized = TextRomanizer.romanize(text);
        // Safety: if romanization didn't convert (e.g. dictionary not loaded),
        // log a warning.
        if (containsRomanizableText(romanized) &&
            containsRomanizableText(text)) {
          afLog(
            'lyrics',
            'Romanization incomplete for line in $trackId — '
                'non-Latin characters may remain',
          );
        }
        buffer.writeln('$timestamp$romanized');
      } else if (RegExp(r'^\[[a-zA-Z]+:.+\]$').hasMatch(line)) {
        buffer.writeln(line);
      } else {
        final romanized = TextRomanizer.romanize(line);
        if (containsRomanizableText(romanized) &&
            containsRomanizableText(line)) {
          afLog(
            'lyrics',
            'Romanization incomplete for line in $trackId — '
                'non-Latin characters may remain',
          );
        }
        buffer.writeln(romanized);
      }
    }
    final parsed = parseLrc(buffer.toString());
    afLog(
      'lyrics',
      'Romanized lyrics for $trackId: ${parsed.lines.length} lines',
    );
    return LyricsResult(lrc: parsed, source: source);
  }
}
