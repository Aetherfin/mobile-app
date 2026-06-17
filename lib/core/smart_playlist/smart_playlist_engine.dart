import 'dart:math';

import 'package:drift/drift.dart' show Variable;

import '../../utils/sql.dart';
import '../jellyfin/models/items.dart';
import '../local/local_db.dart';
import 'smart_playlist_model.dart';

/// Whitelist mapping smart playlist rule field names to SQLite column names.
/// Unknown fields return null (rejected by the query builder), preventing
/// injection via unexpected field values.
const _kFieldToColumn = <String, String>{
  'title': 'title',
  'artist': 'artist',
  'album': 'album',
  'genre': 'genre',
  'year': 'year',
  'duration': 'duration_ms',
  'codec': 'codec',
  'bitrate': 'bitrate',
  'dateAdded': 'last_modified',
  'playCount': 'play_count',
  'lastPlayed': 'last_played',
};

/// Typed operator for smart playlist rules, replacing raw string comparisons.
enum SmartPlaylistOperator {
  is_('is'),
  isNot('isNot'),
  contains('contains'),
  notContains('notContains'),
  gt('gt'),
  lt('lt'),
  inTheRange('inTheRange'),
  inTheLast('inTheLast');

  const SmartPlaylistOperator(this.value);

  final String value;

  static SmartPlaylistOperator? fromString(String s) => values
      .cast<SmartPlaylistOperator?>()
      .firstWhere((o) => o?.value == s, orElse: () => null);
}

/// Resolves a [SmartPlaylist] into a list of matching tracks.
///
/// Strategy depends on the source:
/// - Local mode: builds SQL WHERE clause for direct DB query
/// - Server mode: filters a pre-fetched track list client-side
class SmartPlaylistEngine {
  /// Resolve against the local SQLite database (fastest path).
  Future<List<AfTrack>> resolveLocal(SmartPlaylist playlist, LocalDb db) async {
    final d = db.db;
    final where = _buildSqlWhere(playlist);
    final orderBy = _buildSqlOrderBy(playlist);

    // Column projection: only select columns needed for AfTrack construction
    // and rule matching, skipping file_path, file_size, last_modified.
    const trackCols =
        'id, title, artist, album, album_artist, track_number, '
        'duration_ms, year, genre, cover_path, codec, bitrate, sample_rate';

    var sql = 'SELECT $trackCols FROM tracks';
    final hasHistoryRules =
        playlist.rules.any(
          (r) => r.field == 'playCount' || r.field == 'lastPlayed',
        ) ||
        playlist.sort == 'playCount' ||
        playlist.sort == 'lastPlayed';
    if (hasHistoryRules) {
      sql =
          '''
        SELECT * FROM (
          SELECT $trackCols,
            COALESCE(h.play_count, 0) AS play_count,
            h.last_played
          FROM tracks
          LEFT JOIN (
            SELECT track_id,
              COUNT(*) AS play_count,
              MAX(played_at) AS last_played
            FROM playback_history
            WHERE skipped = 0
            GROUP BY track_id
          ) h ON h.track_id = tracks.id
        )
      ''';
    }

    if (where.clause.isNotEmpty) {
      sql += ' WHERE ${where.clause}';
    }
    sql += ' ORDER BY $orderBy';
    if (playlist.limit != null) {
      sql += ' LIMIT ?';
      where.args.add(playlist.limit);
    }

    final rows = await d
        .customSelect(sql, variables: where.args.map(Variable.new).toList())
        .get();

    // Parse directly to AfTrack using the raw row helper.
    return rows.map((r) => db.tracks.rawRowToTrack(r)).toList();
  }

  /// Resolve against a pre-fetched list of tracks (server mode).
  /// Filters client-side using the rules, then sorts and limits.
  List<AfTrack> resolveFromList(
    SmartPlaylist playlist,
    List<AfTrack> allTracks, {
    Map<String, ({int playCount, DateTime? lastPlayed})> playHistoryMap =
        const {},
  }) {
    var filtered = allTracks
        .where((t) => _matchesRules(t, playlist, playHistoryMap))
        .toList();
    filtered = _sortTracks(filtered, playlist, playHistoryMap);
    if (playlist.limit != null && filtered.length > playlist.limit!) {
      filtered = filtered.sublist(0, playlist.limit!);
    }
    return filtered;
  }

  // ── Client-side matching ────────────────────────────────────────────────

  bool _matchesRules(
    AfTrack track,
    SmartPlaylist playlist,
    Map<String, ({int playCount, DateTime? lastPlayed})> playHistoryMap,
  ) {
    if (playlist.rules.isEmpty) return true;
    if (playlist.combinator == 'any') {
      return playlist.rules.any((r) => _matchRule(track, r, playHistoryMap));
    }
    return playlist.rules.every((r) => _matchRule(track, r, playHistoryMap));
  }

  bool _matchRule(
    AfTrack track,
    SmartRule rule,
    Map<String, ({int playCount, DateTime? lastPlayed})> playHistoryMap,
  ) {
    final fieldValue = _getField(track, rule.field, playHistoryMap);
    final ruleValue = rule.value;

    final op = SmartPlaylistOperator.fromString(rule.operator);
    return switch (op) {
      SmartPlaylistOperator.is_ => _eq(fieldValue, ruleValue),
      SmartPlaylistOperator.isNot => !_eq(fieldValue, ruleValue),
      SmartPlaylistOperator.contains => _contains(fieldValue, ruleValue),
      SmartPlaylistOperator.notContains => !_contains(fieldValue, ruleValue),
      SmartPlaylistOperator.gt => _gt(fieldValue, ruleValue),
      SmartPlaylistOperator.lt => _lt(fieldValue, ruleValue),
      SmartPlaylistOperator.inTheRange => _inRange(fieldValue, ruleValue),
      SmartPlaylistOperator.inTheLast => _inTheLast(fieldValue, ruleValue),
      _ => true,
    };
  }

  dynamic _getField(
    AfTrack track,
    String field,
    Map<String, ({int playCount, DateTime? lastPlayed})> playHistoryMap,
  ) => switch (field) {
    'title' => track.title,
    'artist' => track.artistName,
    'album' => track.albumName,
    'genre' => '', // Genre not on AfTrack model — always matches
    'year' => track.dateAdded?.year,
    'duration' => track.duration.inSeconds,
    'codec' => track.quality?.sourceCodec ?? '',
    'bitrate' => track.quality?.bitrateKbps,
    'dateAdded' => track.dateAdded,
    'isFavorite' => track.isFavorite,
    'playCount' => playHistoryMap[track.id]?.playCount ?? 0,
    'lastPlayed' => playHistoryMap[track.id]?.lastPlayed,
    _ => null,
  };

  bool _eq(dynamic field, dynamic value) {
    if (field is String && value is String) {
      return field.toLowerCase() == value.toLowerCase();
    }
    if (field is bool && value is bool) return field == value;
    if (field is num && value is num) return field == value;
    return '$field' == '$value';
  }

  bool _contains(dynamic field, dynamic value) {
    if (field is String && value is String) {
      return field.toLowerCase().contains(value.toLowerCase());
    }
    return false;
  }

  bool _gt(dynamic field, dynamic value) {
    if (field is num && value is num) return field > value;
    return false;
  }

  bool _lt(dynamic field, dynamic value) {
    if (field is num && value is num) return field < value;
    return false;
  }

  bool _inRange(dynamic field, dynamic value) {
    if (field is num && value is List && value.length == 2) {
      final low = (value[0] as num);
      final high = (value[1] as num);
      return field >= low && field <= high;
    }
    return false;
  }

  bool _inTheLast(dynamic field, dynamic value) {
    if (field is DateTime && value is num) {
      final cutoff = DateTime.now().subtract(Duration(days: value.toInt()));
      return field.isAfter(cutoff);
    }
    return false;
  }

  // ── Sorting ─────────────────────────────────────────────────────────────

  List<AfTrack> _sortTracks(
    List<AfTrack> tracks,
    SmartPlaylist playlist,
    Map<String, ({int playCount, DateTime? lastPlayed})> playHistoryMap,
  ) {
    if (playlist.sort == 'random') {
      return tracks..shuffle(Random());
    }
    final asc = playlist.sortOrder == 'asc';
    tracks.sort((a, b) {
      final va = _getField(a, playlist.sort, playHistoryMap);
      final vb = _getField(b, playlist.sort, playHistoryMap);
      final cmp = _compare(va, vb);
      return asc ? cmp : -cmp;
    });
    return tracks;
  }

  int _compare(dynamic a, dynamic b) {
    if (a == null && b == null) return 0;
    if (a == null) return -1;
    if (b == null) return 1;
    if (a is String && b is String) {
      return a.toLowerCase().compareTo(b.toLowerCase());
    }
    if (a is num && b is num) return a.compareTo(b);
    if (a is DateTime && b is DateTime) return a.compareTo(b);
    return '$a'.compareTo('$b');
  }

  // ── SQL builder (Local mode) ────────────────────────────────────────────

  ({String clause, List<dynamic> args}) _buildSqlWhere(SmartPlaylist playlist) {
    if (playlist.rules.isEmpty) return (clause: '', args: <dynamic>[]);

    final clauses = <String>[];
    final args = <dynamic>[];

    for (final rule in playlist.rules) {
      final col = _fieldToColumn(rule.field);
      if (col == null) continue;

      switch (SmartPlaylistOperator.fromString(rule.operator)) {
        case SmartPlaylistOperator.is_:
          if (rule.value is bool) {
            clauses.add('$col = ?');
            args.add(rule.value == true ? 1 : 0);
          } else {
            clauses.add('$col = ? COLLATE NOCASE');
            args.add(rule.value);
          }
        case SmartPlaylistOperator.isNot:
          clauses.add('$col != ? COLLATE NOCASE');
          args.add(rule.value);
        case SmartPlaylistOperator.contains:
          // Escape `%`, `_`, `\` so a rule value of `100%` matches that
          // exact substring instead of acting as a wildcard. The
          // `ESCAPE '\'` clause must be declared on the SQL side.
          clauses.add("$col LIKE ? COLLATE NOCASE ESCAPE '\\'");
          args.add('%${escapeSqlLike('${rule.value}')}%');
        case SmartPlaylistOperator.notContains:
          clauses.add("$col NOT LIKE ? COLLATE NOCASE ESCAPE '\\'");
          args.add('%${escapeSqlLike('${rule.value}')}%');
        case SmartPlaylistOperator.gt:
          clauses.add('$col > ?');
          args.add(rule.value);
        case SmartPlaylistOperator.lt:
          clauses.add('$col < ?');
          args.add(rule.value);
        case SmartPlaylistOperator.inTheRange:
          if (rule.value is List && (rule.value as List).length == 2) {
            clauses.add('$col BETWEEN ? AND ?');
            args.add((rule.value as List)[0]);
            args.add((rule.value as List)[1]);
          }
        case SmartPlaylistOperator.inTheLast:
          if (rule.value is num) {
            final cutoff = DateTime.now()
                .subtract(Duration(days: (rule.value as num).toInt()))
                .millisecondsSinceEpoch;
            clauses.add('$col >= ?');
            args.add(cutoff);
          }
        default:
          break;
      }
    }

    if (clauses.isEmpty) return (clause: '', args: <dynamic>[]);
    final joiner = playlist.combinator == 'any' ? ' OR ' : ' AND ';
    return (clause: clauses.join(joiner), args: args);
  }

  String _buildSqlOrderBy(SmartPlaylist playlist) {
    if (playlist.sort == 'random') return 'RANDOM()';
    final col = _fieldToColumn(playlist.sort) ?? 'title';
    final dir = playlist.sortOrder == 'desc' ? 'DESC' : 'ASC';
    return '$col COLLATE NOCASE $dir';
  }

  String? _fieldToColumn(String field) => _kFieldToColumn[field];
}
