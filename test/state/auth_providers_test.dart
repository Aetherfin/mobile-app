import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderException;
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:aetherfin/core/jellyfin/auth_storage.dart';
import 'package:aetherfin/core/jellyfin/models/server.dart';
import 'package:aetherfin/state/auth_providers.dart';

// ── Mocks ────────────────────────────────────────────────────────────────────

class MockAuthStorage extends Mock implements AuthStorage {}

// ── Helpers ──────────────────────────────────────────────────────────────────

JellyfinAuth _fakeAuth({
  String baseUrl = 'https://jellyfin.example.com',
  String userId = 'user-1',
  String userName = 'TestUser',
  String accessToken = 'token-abc',
  ServerType serverType = ServerType.jellyfin,
}) => JellyfinAuth(
  server: JellyfinServer(baseUrl: baseUrl, name: 'TestServer'),
  userId: userId,
  userName: userName,
  accessToken: accessToken,
  serverType: serverType,
);

// ── Tests ────────────────────────────────────────────────────────────────────

void main() {
  setUpAll(() {
    registerFallbackValue(
      const JellyfinAuth(
        server: JellyfinServer(baseUrl: '', name: ''),
        userId: '',
        userName: '',
        accessToken: '',
      ),
    );
  });

  late MockAuthStorage mockStorage;

  setUp(() {
    mockStorage = MockAuthStorage();
    when(() => mockStorage.save(any())).thenAnswer((_) async {});
    when(() => mockStorage.clear()).thenAnswer((_) async {});
  });

  group('authProvider (AuthNotifier)', () {
    test('build returns initial auth from initialAuthProvider override', () {
      final auth = _fakeAuth();
      final container = ProviderContainer(
        overrides: [
          authStorageProvider.overrideWithValue(mockStorage),
          initialAuthProvider.overrideWithValue(auth),
        ],
      );
      addTearDown(container.dispose);

      expect(container.read(authProvider), auth);
    });

    test('build returns null when initialAuthProvider is null', () {
      final container = ProviderContainer(
        overrides: [
          authStorageProvider.overrideWithValue(mockStorage),
          initialAuthProvider.overrideWithValue(null),
        ],
      );
      addTearDown(container.dispose);

      expect(container.read(authProvider), isNull);
    });

    test('save persists to AuthStorage and updates state', () async {
      final auth = _fakeAuth();
      final container = ProviderContainer(
        overrides: [
          authStorageProvider.overrideWithValue(mockStorage),
          initialAuthProvider.overrideWithValue(null),
        ],
      );
      addTearDown(container.dispose);

      expect(container.read(authProvider), isNull);

      await container.read(authProvider.notifier).save(auth);

      expect(container.read(authProvider), auth);
      verify(() => mockStorage.save(auth)).called(1);
    });

    test('clear removes from AuthStorage and sets state to null', () async {
      final auth = _fakeAuth();
      final container = ProviderContainer(
        overrides: [
          authStorageProvider.overrideWithValue(mockStorage),
          initialAuthProvider.overrideWithValue(auth),
        ],
      );
      addTearDown(container.dispose);

      expect(container.read(authProvider), auth);

      await container.read(authProvider.notifier).clear();

      expect(container.read(authProvider), isNull);
      verify(() => mockStorage.clear()).called(1);
    });

    test('save then clear round-trips correctly', () async {
      final container = ProviderContainer(
        overrides: [
          authStorageProvider.overrideWithValue(mockStorage),
          initialAuthProvider.overrideWithValue(null),
        ],
      );
      addTearDown(container.dispose);

      final auth1 = _fakeAuth(baseUrl: 'https://server-a.com');
      final auth2 = _fakeAuth(baseUrl: 'https://server-b.com');

      await container.read(authProvider.notifier).save(auth1);
      expect(container.read(authProvider), auth1);

      await container.read(authProvider.notifier).save(auth2);
      expect(container.read(authProvider), auth2);
      expect(
        container.read(authProvider)!.server.baseUrl,
        'https://server-b.com',
      );

      await container.read(authProvider.notifier).clear();
      expect(container.read(authProvider), isNull);
    });

    test('save with Subsonic server type preserves serverType', () async {
      final auth = _fakeAuth(
        serverType: ServerType.subsonic,
        baseUrl: 'https://navidrome.example.com',
      );
      final container = ProviderContainer(
        overrides: [
          authStorageProvider.overrideWithValue(mockStorage),
          initialAuthProvider.overrideWithValue(null),
        ],
      );
      addTearDown(container.dispose);

      await container.read(authProvider.notifier).save(auth);

      final saved = container.read(authProvider);
      expect(saved!.serverType, ServerType.subsonic);
    });
  });

  group('static providers', () {
    test('deviceIdProvider throws when not overridden', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(
        () => container.read(deviceIdProvider),
        throwsA(
          isA<ProviderException>().having(
            (e) => e.exception,
            'inner',
            isA<StateError>(),
          ),
        ),
      );
    });

    test('aetherfinVersionProvider throws when not overridden', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(
        () => container.read(aetherfinVersionProvider),
        throwsA(
          isA<ProviderException>().having(
            (e) => e.exception,
            'inner',
            isA<StateError>(),
          ),
        ),
      );
    });

    test('initialAuthProvider throws when not overridden', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(
        () => container.read(initialAuthProvider),
        throwsA(
          isA<ProviderException>().having(
            (e) => e.exception,
            'inner',
            isA<StateError>(),
          ),
        ),
      );
    });

    test('deviceIdProvider returns overridden value', () {
      final container = ProviderContainer(
        overrides: [deviceIdProvider.overrideWithValue('test-device-id')],
      );
      addTearDown(container.dispose);

      expect(container.read(deviceIdProvider), 'test-device-id');
    });

    test('aetherfinVersionProvider returns overridden value', () {
      final container = ProviderContainer(
        overrides: [aetherfinVersionProvider.overrideWithValue('0.3.5')],
      );
      addTearDown(container.dispose);

      expect(container.read(aetherfinVersionProvider), '0.3.5');
    });
  });
}
