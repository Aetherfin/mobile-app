import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/backend/music_backend.dart';
import '../core/jellyfin/client.dart';
import '../core/local/local_backend.dart';
import '../core/subsonic/navidrome_client.dart';
import '../core/youtube/youtube_music_client.dart';
import '../utils/log.dart';
import 'app_mode_providers.dart';
import 'auth_providers.dart';
import 'local_library_providers.dart';
import 'youtube_music_providers.dart';

final musicBackendProvider = Provider<MusicBackend?>((ref) {
  final auth = ref.watch(authProvider);
  final appMode = ref.watch(appModeProvider);

  // YouTube Music mode — works without JellyfinAuth.
  if (appMode == AppMode.youtubeMusic) {
    final youtubeAuth = ref.watch(youtubeAuthProvider);
    logData(
      'musicBackend',
      source: 'live',
      extra: 'type=youtubeMusic auth=${youtubeAuth != null ? 'yes' : 'no'}',
    );
    final clientVersion = ref.watch(aetherfinVersionProvider);
    final client = YouTubeMusicClient(
      auth: youtubeAuth,
      clientVersion: clientVersion,
    );
    ref.onDispose(client.close);
    return client;
  }

  if (auth == null) {
    if (appMode == AppMode.local) {
      final lib = ref.watch(localLibraryProvider);
      logData('musicBackend', source: 'live', extra: 'type=local');
      final client = LocalBackend(library: lib, db: lib.db);
      ref.onDispose(client.close);
      return client;
    }
    logData('musicBackend', source: 'demo', extra: '(signed out)');
    return null;
  }

  logData(
    'musicBackend',
    source: 'live',
    extra:
        'type=${auth.serverType.name} '
        'server=${kReleaseMode ? '<redacted>' : auth.server.baseUrl} '
        'user=${kReleaseMode ? '<redacted>' : auth.userName}',
  );

  final clientVersion = ref.watch(aetherfinVersionProvider);

  switch (auth.serverType) {
    case ServerType.subsonic:
      {
        final client = NavidromeClient(
          server: auth.server,
          username: auth.userName,
          password: auth.accessToken,
          clientVersion: clientVersion,
        );
        ref.onDispose(client.close);
        return client;
      }
    case ServerType.jellyfin:
      {
        final client = JellyfinClient(
          server: auth.server,
          deviceId: ref.watch(deviceIdProvider),
          accessToken: auth.accessToken,
          userId: auth.userId,
          clientVersion: clientVersion,
        );
        ref.onDispose(client.close);
        return client;
      }
    case ServerType.local:
      {
        final lib = ref.watch(localLibraryProvider);
        final client = LocalBackend(library: lib, db: lib.db);
        ref.onDispose(client.close);
        return client;
      }
    case ServerType.youtubeMusic:
      {
        final youtubeAuth = ref.watch(youtubeAuthProvider);
        final clientVersion = ref.watch(aetherfinVersionProvider);
        final client = YouTubeMusicClient(
          auth: youtubeAuth,
          clientVersion: clientVersion,
        );
        ref.onDispose(client.close);
        return client;
      }
  }
});

final jellyfinClientProvider = Provider<JellyfinClient?>((ref) {
  final backend = ref.watch(musicBackendProvider);
  if (backend is JellyfinClient) return backend;
  return null;
});
