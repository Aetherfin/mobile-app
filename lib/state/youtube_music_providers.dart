import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'state_holder.dart';

import '../core/youtube/youtube_auth.dart';
import '../core/youtube/youtube_home_content.dart';
import '../core/youtube/youtube_music_client.dart';
import '../core/youtube/innertube_client.dart';
import 'music_backend_providers.dart';

/// YouTube Music auth storage provider.
final youtubeAuthStorageProvider = Provider<YouTubeAuthStorage>(
  (ref) => YouTubeAuthStorage(),
);

/// Current YouTube Music auth state.
final youtubeAuthProvider =
    NotifierProvider<YouTubeAuthNotifier, YouTubeAuthBundle?>(
      YouTubeAuthNotifier.new,
    );

class YouTubeAuthNotifier extends Notifier<YouTubeAuthBundle?> {
  @override
  YouTubeAuthBundle? build() => null;

  Future<void> init() async {
    final stored = await ref.read(youtubeAuthStorageProvider).load();
    state = stored;
  }

  Future<void> save(YouTubeAuthBundle auth) async {
    await ref.read(youtubeAuthStorageProvider).save(auth);
    state = auth;
  }

  Future<void> clear() async {
    await ref.read(youtubeAuthStorageProvider).clear();
    state = null;
  }

  bool get isLoggedIn => state?.isValid == true;
}

/// Selected YouTube home chip parameters.
final youtubeHomeParamsProvider =
    NotifierProvider.autoDispose<StateHolder<String?>, String?>(
      () => StateHolder<String?>((ref) => null),
    );

/// Selected chip (if any).
final youtubeSelectedChipProvider =
    NotifierProvider.autoDispose<StateHolder<InnerTubeChip?>, InnerTubeChip?>(
      () => StateHolder<InnerTubeChip?>((ref) => null),
    );

/// YouTube Music home page content (trending, popular, etc.).
class YouTubeHomeNotifier extends AsyncNotifier<YouTubeHomeContent> {
  bool _isLoadingMore = false;

  @override
  Future<YouTubeHomeContent> build() async {
    final backend = ref.watch(musicBackendProvider);
    if (backend is! YouTubeMusicClient) {
      return YouTubeHomeContent.empty();
    }
    final params = ref.watch(youtubeHomeParamsProvider);
    final content = await backend.browseHome(params: params);
    final sections = List<YouTubeHomeSection>.from(content.sections)
      ..shuffle(Random());
    return YouTubeHomeContent(
      sections: sections,
      chips: content.chips,
      region: content.region,
      continuation: content.continuation,
    );
  }

  Future<void> loadMore() async {
    if (_isLoadingMore) return;
    final current = state.value;
    if (current == null || current.continuation == null) {
      return;
    }

    final backend = ref.read(musicBackendProvider);
    if (backend is! YouTubeMusicClient) return;

    _isLoadingMore = true;
    try {
      final nextContent = await backend.browseHome(
        continuation: current.continuation,
      );
      if (nextContent.sections.isEmpty && nextContent.continuation == null) {
        return;
      }
      final newSections = List<YouTubeHomeSection>.from(nextContent.sections)
        ..shuffle(Random());
      state = AsyncValue.data(
        YouTubeHomeContent(
          sections: [...current.sections, ...newSections],
          chips: current.chips,
          region: current.region,
          continuation: nextContent.continuation,
        ),
      );
    } finally {
      _isLoadingMore = false;
    }
  }
}

final youtubeHomeProvider =
    AsyncNotifierProvider.autoDispose<YouTubeHomeNotifier, YouTubeHomeContent>(
      YouTubeHomeNotifier.new,
    );
