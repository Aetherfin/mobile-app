import 'dart:async';
import 'dart:collection' show UnmodifiableListView;

import '../jellyfin/models/items.dart';
import 'queue_engine.dart';

/// Thin stream-broadcasting wrapper around [AfQueueEngine].
///
/// Owns the track/queue/shuffle broadcast streams so the UI
/// (via [AfPlayerService]) always sees a consistent view.
/// All state lives in [AfQueueEngine]; this class only adds
/// stream emission on top of engine mutations.
class AfQueueManager {
  AfQueueManager({AfQueueEngine? engine}) : _engine = engine ?? AfQueueEngine();

  final AfQueueEngine _engine;
  final _shuffleController = StreamController<bool>.broadcast();
  final _trackController = StreamController<AfTrack?>.broadcast();
  final _queueController = StreamController<List<AfTrack>>.broadcast();

  // ── Engine access ────────────────────────────────────────────────

  AfQueueEngine get engine => _engine;

  // ── Streams ──────────────────────────────────────────────────────

  Stream<AfTrack?> get currentTrackStream => _trackController.stream;
  Stream<List<AfTrack>> get queueStream => _queueController.stream;
  Stream<bool> get shuffleModeStream => _shuffleController.stream;

  // ── State queries (delegated to engine) ──────────────────────────

  bool get isShuffleEnabled => _engine.isShuffleEnabled;
  bool get isTailShuffle => _engine.isTailShuffle;
  List<AfTrack> get currentQueue =>
      UnmodifiableListView<AfTrack>(_engine.tracks);
  int get currentIndex => _engine.currentIndex;
  AfTrack? get currentTrack => _engine.currentTrack;
  bool get isAtQueueEnd => _engine.isAtQueueEnd;
  bool get playbackEnded => _engine.playbackEnded;

  // ── forNtimes passthrough ────────────────────────────────────────

  bool get isForNtimes => _engine.isForNtimes;
  int get remainingRepeats => _engine.remainingRepeats;
  int get ntimesCount => _engine.ntimesCount;

  void setNtimesCount(int count) => _engine.setNtimesCount(count);
  void decrementRepeats() => _engine.decrementRepeats();
  void resetRepeats() => _engine.resetRepeats();

  // ── Track change ────────────────────────────────────────────────

  void emitCurrentTrack(AfTrack track) {
    _trackController.add(track);
  }

  void emitQueue() {
    _queueController.add(_engine.tracks);
  }

  // ── Queue lifecycle ─────────────────────────────────────────────

  void replaceQueue(List<AfTrack> tracks, int startIndex) {
    _engine.replaceAll(tracks, startIndex);
    _shuffleController.add(false);
    _queueController.add(_engine.tracks);
  }

  void setShuffle(bool enabled) {
    _engine.setShuffle(enabled);
    _shuffleController.add(enabled);
    _queueController.add(_engine.tracks);
  }

  void shuffleTail() {
    _engine.shuffleTail();
    _shuffleController.add(true);
    _queueController.add(_engine.tracks);
  }

  void clear() {
    _engine.clear();
    _shuffleController.add(false);
    _queueController.add(const <AfTrack>[]);
    _trackController.add(null);
  }

  void endPlayback() {
    _engine.endPlayback();
    _trackController.add(null);
  }

  // ── Queue mutations (delegate + emit) ───────────────────────────

  bool canReorder(int oldIndex, int newIndex) =>
      _engine.canReorder(oldIndex, newIndex);

  int reorder(int oldIndex, int newIndex) {
    final result = _engine.reorder(oldIndex, newIndex);
    _queueController.add(_engine.tracks);
    return result;
  }

  bool canRemove(int index) => _engine.canRemove(index);

  void remove(int index) {
    _engine.remove(index);
    _queueController.add(_engine.tracks);
  }

  void insert(int index, AfTrack track, [String? url]) {
    _engine.insert(index, track);
    _queueController.add(_engine.tracks);
  }

  void append(AfTrack track, [String? url]) {
    _engine.append(track);
    _queueController.add(_engine.tracks);
  }

  void appendAll(List<AfTrack> tracks) {
    _engine.appendAll(tracks);
    _queueController.add(_engine.tracks);
  }

  void updateTrackFavorite(String trackId, bool isFavorite) {
    _engine.updateTrackFavorite(trackId, isFavorite);
    if (_engine.currentTrack?.id == trackId) {
      _trackController.add(_engine.currentTrack);
    }
    _queueController.add(_engine.tracks);
  }

  void dispose() {
    _trackController.close();
    _queueController.close();
    _shuffleController.close();
  }
}
