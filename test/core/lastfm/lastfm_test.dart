import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:aetherfin/core/audio/lastfm_playback_reporter.dart';
import 'package:aetherfin/core/audio/player_service.dart';
import 'package:aetherfin/core/jellyfin/models/items.dart';
import 'package:aetherfin/core/lastfm/lastfm_client.dart';

class MockPlayerService extends Mock implements AfPlayerService {}

class MockLastFmClient extends Mock implements LastFmClient {}

void main() {
  late MockPlayerService player;
  late MockLastFmClient client;
  late StreamController<AfTrack?> trackController;

  setUpAll(() {
    registerFallbackValue(Duration.zero);
  });

  setUp(() {
    player = MockPlayerService();
    client = MockLastFmClient();
    trackController = StreamController<AfTrack?>.broadcast();

    when(
      () => player.currentTrackStream,
    ).thenAnswer((_) => trackController.stream);
    when(() => player.listenedDuration).thenReturn(Duration.zero);

    when(
      () => client.updateNowPlaying(
        artist: any(named: 'artist'),
        track: any(named: 'track'),
        album: any(named: 'album'),
        duration: any(named: 'duration'),
      ),
    ).thenAnswer((_) => Future.value());

    when(
      () => client.scrobble(
        artist: any(named: 'artist'),
        track: any(named: 'track'),
        timestamp: any(named: 'timestamp'),
        album: any(named: 'album'),
        duration: any(named: 'duration'),
      ),
    ).thenAnswer((_) => Future.value());
  });

  tearDown(() {
    trackController.close();
  });

  const trackA = AfTrack(
    id: '1',
    title: 'Track A',
    artistName: 'Artist A',
    albumName: 'Album A',
    duration: Duration(minutes: 3),
  );

  const trackB = AfTrack(
    id: '2',
    title: 'Track B',
    artistName: 'Artist B',
    albumName: 'Album B',
    duration: Duration(minutes: 4),
  );

  group('Now Playing', () {
    test('updates now playing on Last.fm when track starts', () async {
      final reporter = LastFmPlaybackReporter(player, () => client, () => true);

      trackController.add(trackA);
      await Future.delayed(Duration.zero);

      verify(
        () => client.updateNowPlaying(
          artist: 'Artist A',
          track: 'Track A',
          album: 'Album A',
          duration: const Duration(minutes: 3),
        ),
      ).called(1);

      await reporter.dispose();
    });
  });

  group('Scrobbling Eligibility', () {
    test('does not scrobble if listened duration is too short', () async {
      final reporter = LastFmPlaybackReporter(player, () => client, () => true);

      trackController.add(trackA);
      await Future.delayed(Duration.zero);

      when(
        () => player.listenedDuration,
      ).thenReturn(const Duration(seconds: 30));

      trackController.add(trackB);
      await Future.delayed(Duration.zero);

      verifyNever(
        () => client.scrobble(
          artist: any(named: 'artist'),
          track: any(named: 'track'),
          timestamp: any(named: 'timestamp'),
          album: any(named: 'album'),
          duration: any(named: 'duration'),
        ),
      );

      await reporter.dispose();
    });

    test(
      'scrobbles if listened duration meets 50% of track duration',
      () async {
        final reporter = LastFmPlaybackReporter(
          player,
          () => client,
          () => true,
        );

        trackController.add(trackA);
        await Future.delayed(Duration.zero);

        when(
          () => player.listenedDuration,
        ).thenReturn(const Duration(seconds: 95));

        trackController.add(trackB);
        await Future.delayed(Duration.zero);

        verify(
          () => client.scrobble(
            artist: 'Artist A',
            track: 'Track A',
            timestamp: any(named: 'timestamp'),
            album: 'Album A',
            duration: const Duration(minutes: 3),
          ),
        ).called(1);

        await reporter.dispose();
      },
    );
  });

  group('Extended API Endpoints', () {
    late MockDio mockDio;
    late LastFmClient lastFmClient;

    setUp(() {
      mockDio = MockDio();
      lastFmClient = LastFmClient(
        apiKey: 'test_key',
        apiSecret: 'test_secret',
        sessionKey: 'test_session',
        dio: mockDio,
      );
    });

    test('love submits POST with signature', () async {
      when(
        () => mockDio.post(
          any(),
          data: any(named: 'data'),
          options: any(named: 'options'),
        ),
      ).thenAnswer(
        (_) async => Response(
          requestOptions: RequestOptions(path: '/'),
          data: {},
        ),
      );

      await lastFmClient.love(artist: 'Artist A', track: 'Track A');

      verify(
        () => mockDio.post(
          '/',
          data: any(
            named: 'data',
            that: isA<Map<String, String>>()
                .having((m) => m['method'], 'method', 'track.love')
                .having((m) => m['artist'], 'artist', 'Artist A')
                .having((m) => m['track'], 'track', 'Track A')
                .having((m) => m['sk'], 'session key', 'test_session'),
          ),
          options: any(named: 'options'),
        ),
      ).called(1);
    });

    test('getArtistInfo queries artist.getInfo', () async {
      when(
        () =>
            mockDio.get(any(), queryParameters: any(named: 'queryParameters')),
      ).thenAnswer(
        (_) async => Response(
          requestOptions: RequestOptions(path: '/'),
          data: {
            'artist': {
              'name': 'Artist A',
              'bio': {'content': 'Biography content'},
            },
          },
        ),
      );

      final result = await lastFmClient.getArtistInfo(artistName: 'Artist A');
      expect(result?['name'], 'Artist A');
      expect(result?['bio']?['content'], 'Biography content');
    });
  });
}

class MockDio extends Mock implements Dio {}
