import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../core/audio/smart_queue_manager.dart';
import '../core/jellyfin/models/items.dart';
import 'local_library_providers.dart';
import 'music_backend_providers.dart';
import 'settings_providers.dart';

final smartQueueEnabledProvider = StateProvider<bool>((ref) => true);

final smartQueueManagerProvider = Provider<SmartQueueManager>((ref) {
  final localLib = ref.watch(localLibraryProvider);
  final backend = ref.watch(musicBackendProvider);
  final lastfmClient = ref.watch(lastFmClientProvider);
  return SmartQueueManager(
    localDb: localLib.db,
    backend: backend,
    lastfmClient: lastfmClient,
  );
});

final smartQueueBufferProvider = StateProvider<List<AfTrack>>((ref) => []);
