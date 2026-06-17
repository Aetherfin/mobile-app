// ignore_for_file: depend_on_referenced_packages
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:path/path.dart' as p;

import 'package:aetherfin/core/audio/stream_prefetcher.dart';

class MockDio extends Mock implements Dio {}

class MockResponse<T> extends Mock implements Response<T> {}

class MockResponseBody extends Mock implements ResponseBody {}

class MockPathProviderPlatform extends Fake
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  @override
  Future<String?> getTemporaryPath() async {
    return Directory.systemTemp.path;
  }

  @override
  Future<String?> getApplicationSupportPath() async {
    return Directory.systemTemp.path;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MockDio mockDio;
  late StreamPrefetcher prefetcher;
  late Directory tempDir;

  setUpAll(() {
    PathProviderPlatform.instance = MockPathProviderPlatform();
    registerFallbackValue(CancelToken());
    registerFallbackValue(Options());
  });

  setUp(() async {
    mockDio = MockDio();
    prefetcher = StreamPrefetcher(dio: mockDio);
    tempDir = await getApplicationSupportDirectory();
  });

  tearDown(() async {
    prefetcher.cancelCurrentPrefetch();
    // Clean up files in temp directory
    if (tempDir.existsSync()) {
      final files = tempDir.listSync();
      for (final f in files) {
        if (f is File && p.basename(f.path).startsWith('prefetch_')) {
          try {
            f.deleteSync();
          } catch (_) {}
        }
      }
    }
  });

  group('StreamPrefetcher', () {
    test('prefetch successful download', () async {
      final mockResponse = MockResponse<ResponseBody>();
      final mockResponseBody = MockResponseBody();

      final dataStream = Stream<Uint8List>.fromIterable([
        Uint8List.fromList([1, 2, 3, 4]),
      ]);

      when(() => mockResponseBody.stream).thenAnswer((_) => dataStream);
      when(() => mockResponse.data).thenReturn(mockResponseBody);
      when(
        () => mockDio.get<ResponseBody>(
          any(),
          options: any(named: 'options'),
          cancelToken: any(named: 'cancelToken'),
        ),
      ).thenAnswer((_) async => mockResponse);

      final file = await prefetcher.prefetch(
        'https://example.com/stream.flac',
        {'Auth': 'Bearer Token'},
        trackId: 'track_123',
      );

      expect(file, isNotNull);
      expect(file!.existsSync(), isTrue);
      expect(file.readAsBytesSync(), equals([1, 2, 3, 4]));
      expect(await prefetcher.getCachedFile('track_123'), equals(file));
    });

    test('prefetch handles failure and cancels correctly', () async {
      when(
        () => mockDio.get<ResponseBody>(
          any(),
          options: any(named: 'options'),
          cancelToken: any(named: 'cancelToken'),
        ),
      ).thenThrow(
        DioException(
          requestOptions: RequestOptions(path: ''),
          type: DioExceptionType.cancel,
          error: 'Cancelled',
        ),
      );

      final future = prefetcher.prefetch(
        'https://example.com/stream.flac',
        {},
        trackId: 'track_456',
      );

      prefetcher.cancelCurrentPrefetch();

      final file = await future;
      expect(file, isNull);
      expect(await prefetcher.getCachedFile('track_456'), isNull);
    });

    test('dispose prevents new prefetches', () async {
      // After dispose, prefetch should return null immediately
      prefetcher.dispose();

      final file = await prefetcher.prefetch(
        'https://example.com/stream.flac',
        {},
        trackId: 'track_disposed',
      );

      expect(file, isNull);
      // Verify no Dio request was made
      verifyNever(
        () => mockDio.get<ResponseBody>(
          any(),
          options: any(named: 'options'),
          cancelToken: any(named: 'cancelToken'),
        ),
      );
    });

    test(
      'clearStaleTempFiles deletes old files and keeps fresh ones',
      () async {
        final freshFile = File(
          p.join(
            tempDir.path,
            'prefetch_fresh_${DateTime.now().millisecondsSinceEpoch}.tmp',
          ),
        );
        freshFile.writeAsBytesSync([1]);

        final staleFile = File(
          p.join(
            tempDir.path,
            'prefetch_stale_${DateTime.now().millisecondsSinceEpoch}.tmp',
          ),
        );
        staleFile.writeAsBytesSync([2]);

        // Backdate the stale file
        final fiveMinsAgo = DateTime.now().subtract(const Duration(minutes: 6));
        staleFile.setLastModifiedSync(fiveMinsAgo);

        await prefetcher.clearStaleTempFiles();

        expect(freshFile.existsSync(), isTrue);
        expect(staleFile.existsSync(), isFalse);
      },
    );
  });
}
