import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aetherfin/core/jellyfin/client.dart';
import 'package:aetherfin/core/jellyfin/models/server.dart';
import 'package:aetherfin/core/network/shared_dio_client.dart';

/// Mock adapter that controls response per endpoint and call count.
class _MockAdapter implements HttpClientAdapter {
  int _callCount = 0;

  /// Track how many non-auth requests were made.
  int get callCount => _callCount;

  /// If true, retry request also returns 401 (for infinite-loop test).
  bool retryFails = false;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final path = options.path;

    // Always authenticate successfully when asked.
    if (path.contains('AuthenticateByName')) {
      return ResponseBody.fromString(
        jsonEncode({
          'User': {'Id': 'u-456', 'Name': 'testuser'},
          'AccessToken': 'rotated-token-abc',
        }),
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    }

    _callCount++;

    // A 401 response with valid JSON body so Dio's transformer handles it.
    if (_callCount == 1 || retryFails) {
      return ResponseBody.fromString(
        jsonEncode({'error': 'unauthorized'}),
        401,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    }

    return ResponseBody.fromString(
      jsonEncode({'Items': []}),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  group('JellyfinClient 401 token rotation', () {
    late JellyfinClient client;
    late _MockAdapter adapter;

    setUp(() {
      adapter = _MockAdapter();
      client = JellyfinClient(
        server: const JellyfinServer(baseUrl: 'http://srv:8096', name: 'srv'),
        deviceId: 'dev-1',
        clientVersion: '9.9.9-test',
        accessToken: 'original-token',
        userId: 'u-456',
        username: 'testuser',
        password: 'pass123',
      );
      // Replace the real adapter with our mock.
      client.dio.httpClientAdapter = adapter;
    });

    tearDown(() {
      client.close();
      // Clear shared cache so cached 200 responses from previous
      // tests don't pollute subsequent tests via DioCacheInterceptor.
      SharedDioClient().clearCache();
    });

    test('401 triggers re-auth and retry succeeds', () async {
      // First call returns 401, authenticate returns 200, retry returns 200.
      await client.allAlbums(limit: 5);

      // 1 original failed call + 1 retry = 2 non-auth calls.
      expect(adapter.callCount, equals(2));
    });

    test('401 with failed re-auth passes original error', () async {
      adapter.retryFails = true;

      // The retry also returns 401, so the interceptor should
      // pass the original error through.
      await expectLater(
        client.allAlbums(limit: 5),
        throwsA(isA<DioException>()),
      );
    });

    test('infinite loop prevention on repeated 401', () async {
      adapter.retryFails = true;

      // Both original and retry fail with 401.
      // Interceptor must NOT loop infinitely — limit to 1 retry.
      await expectLater(
        client.allAlbums(limit: 5),
        throwsA(isA<DioException>()),
      );

      // Only original + 1 retry, no infinite loop.
      expect(adapter.callCount, equals(2));
    });
  });
}
