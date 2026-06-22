import 'dart:collection';

/// LRU cache for resolved stream URLs, keyed by track ID.
///
/// Avoids repeated (potentially async) URL resolution for tracks
/// that have already been played in the current session. Evicts
/// the least-recently-used entry when the cache exceeds [maxSize].
class StreamUrlCache {
  StreamUrlCache({int maxSize = 100})
    : _maxSize = maxSize,
      _cache = LinkedHashMap<String, String>(
        equals: (a, b) => a == b,
        hashCode: (a) => a.hashCode,
      );

  final int _maxSize;
  final LinkedHashMap<String, String> _cache;

  /// Returns the cached URL for [trackId], or `null` if not cached.
  ///
  /// Updates the access order to move the retrieved item to the
  /// most-recently-used position.
  String? get(String trackId) {
    final value = _cache[trackId];
    if (value != null) {
      _cache.remove(trackId);
      _cache[trackId] = value;
    }
    return value;
  }

  /// Caches a resolved [url] for the given [trackId].
  ///
  /// If the entry already exists it is moved to the most-recently-used
  /// end. When the cache exceeds [maxSize] the oldest entry is evicted.
  void put(String trackId, String url) {
    // Move to end (most recently used) if already present.
    if (_cache.containsKey(trackId)) {
      _cache.remove(trackId);
    }

    _cache[trackId] = url;

    // Evict oldest (first) entry if over capacity.
    if (_cache.length > _maxSize) {
      _cache.remove(_cache.keys.first);
    }
  }

  /// Removes a single entry.
  void remove(String trackId) => _cache.remove(trackId);

  /// Clears the entire cache.
  void clear() => _cache.clear();
}
