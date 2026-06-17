import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:aetherfin/core/audio/track_scorer.dart';
import 'package:aetherfin/core/jellyfin/models/items.dart';

AfTrack _seed() => const AfTrack(
  id: 'seed-1',
  title: 'Seed Track',
  artistName: 'Seed Artist',
  albumName: 'Seed Album',
  genre: 'Rock',
);

double _score(
  AfTrack candidate, {
  AfTrack? seed,
  List<String> recentlyPlayedIds = const [],
  SimpleTrackStats? stats,
  int coCount = 0,
  int maxCo = 0,
  Random? random,
}) {
  return scoreOneTrack(
    candidate,
    seed ?? _seed(),
    recentlyPlayedIds,
    stats: stats,
    coCount: coCount,
    maxCo: maxCo,
    random: random ?? Random(42),
  );
}

void main() {
  test('same artist scores higher than different artist', () {
    final seed = _seed();
    const sameArtist = AfTrack(
      id: 'c1',
      title: 'Other Song',
      artistName: 'Seed Artist',
      albumName: 'Other Album',
      genre: 'Pop',
    );
    const diffArtist = AfTrack(
      id: 'c2',
      title: 'Another Song',
      artistName: 'Different Artist',
      albumName: 'Another Album',
      genre: 'Pop',
    );
    final r = Random(42);
    final s1 = _score(sameArtist, seed: seed, random: r);
    final s2 = _score(diffArtist, seed: seed, random: r);
    expect(s1, greaterThan(s2));
  });

  test('same genre scores higher than different genre', () {
    final seed = _seed();
    const sameGenre = AfTrack(
      id: 'g1',
      title: 'Rock Song',
      artistName: 'Other Artist',
      albumName: 'Album',
      genre: 'Rock',
    );
    const diffGenre = AfTrack(
      id: 'g2',
      title: 'Pop Song',
      artistName: 'Other Artist',
      albumName: 'Album',
      genre: 'Pop',
    );
    final r = Random(42);
    final s1 = _score(sameGenre, seed: seed, random: r);
    final s2 = _score(diffGenre, seed: seed, random: r);
    expect(s1, greaterThan(s2));
  });

  test('higher co-occurrence scores higher', () {
    const lowCo = AfTrack(
      id: 'low',
      title: 'Low Co',
      artistName: 'X',
      albumName: 'A',
    );
    const highCo = AfTrack(
      id: 'high',
      title: 'High Co',
      artistName: 'X',
      albumName: 'A',
    );
    final r = Random(42);
    final sLow = _score(lowCo, coCount: 2, maxCo: 10, random: r);
    final sHigh = _score(highCo, coCount: 9, maxCo: 10, random: r);
    expect(sHigh, greaterThan(sLow));
  });

  test('recently played tracks score lower', () {
    const candidate = AfTrack(
      id: 'rec',
      title: 'Recent',
      artistName: 'X',
      albumName: 'A',
    );
    final r = Random(42);
    final sRecent = _score(
      candidate,
      recentlyPlayedIds: [candidate.id],
      random: r,
    );
    final sNever = _score(candidate, recentlyPlayedIds: const [], random: r);
    expect(sRecent, lessThan(sNever));
  });

  test('all scores are between 0.0 and 1.0 inclusive', () {
    final rng = Random(123);
    final candidates = [
      const AfTrack(
        id: 'a',
        title: 'A',
        artistName: 'Art1',
        albumName: 'Alb',
        genre: 'Rock',
      ),
      const AfTrack(
        id: 'b',
        title: 'B',
        artistName: 'Art2',
        albumName: 'Alb',
        genre: 'Pop',
      ),
    ];
    final recentlyPlayed = ['a', 'b'];
    final statsMap = {'a': const SimpleTrackStats(0.8, 1)};
    for (final c in candidates) {
      final score = _score(
        c,
        recentlyPlayedIds: recentlyPlayed,
        stats: statsMap[c.id],
        coCount: rng.nextInt(20),
        maxCo: 15,
        random: rng,
      );
      expect(score, greaterThanOrEqualTo(0.0));
      expect(score, lessThanOrEqualTo(1.0));
    }
  });
}
