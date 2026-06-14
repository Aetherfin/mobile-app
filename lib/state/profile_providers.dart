import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/backend/music_backend.dart';
import '../core/jellyfin/client.dart';
import '../utils/log.dart';
import 'auth_providers.dart';
import 'music_backend_providers.dart';

class ProfilePhotoState {
  ProfilePhotoState({
    this.localPath,
    this.networkUrl,
    required this.version,
    this.isUploading = false,
  });

  final String? localPath;
  final String? networkUrl;
  final int version;
  final bool isUploading;

  ProfilePhotoState copyWith({
    String? localPath,
    String? networkUrl,
    int? version,
    bool? isUploading,
    bool clearLocalPath = false,
    bool clearNetworkUrl = false,
  }) {
    return ProfilePhotoState(
      localPath: clearLocalPath ? null : (localPath ?? this.localPath),
      networkUrl: clearNetworkUrl ? null : (networkUrl ?? this.networkUrl),
      version: version ?? this.version,
      isUploading: isUploading ?? this.isUploading,
    );
  }
}

class ProfilePhotoNotifier extends Notifier<ProfilePhotoState> {
  @override
  ProfilePhotoState build() {
    _init();
    return ProfilePhotoState(version: 0);
  }

  String _getLocalKey(String userId) => 'af.profile_photo_local_$userId';
  String _getVersionKey(String userId) => 'af.profile_photo_version_$userId';

  Future<void> _init() async {
    final auth = ref.read(authProvider);
    final userId = auth?.userId ?? 'local';
    final prefs = await SharedPreferences.getInstance();

    final localPath = prefs.getString(_getLocalKey(userId));
    final version = prefs.getInt(_getVersionKey(userId)) ?? 0;

    String? networkUrl;
    if (auth != null && auth.serverType == ServerType.jellyfin) {
      networkUrl =
          '${auth.server.baseUrl}/Users/${auth.userId}/Images/Primary?v=$version';
    }

    state = ProfilePhotoState(
      localPath: localPath,
      networkUrl: networkUrl,
      version: version,
    );
  }

  Future<void> updatePhoto(List<int> bytes, String mimeType) async {
    state = state.copyWith(isUploading: true);
    try {
      final auth = ref.read(authProvider);
      final userId = auth?.userId ?? 'local';
      final prefs = await SharedPreferences.getInstance();

      // 1. Upload to Jellyfin if in Jellyfin mode
      final backend = ref.read(musicBackendProvider);
      if (backend is JellyfinClient) {
        await backend.uploadUserAvatar(bytes, mimeType);
      }

      // 2. Save locally to documents directory
      final docDir = await getApplicationDocumentsDirectory();
      final filename = 'profile_avatar_$userId.png';
      final file = File('${docDir.path}/$filename');
      await file.writeAsBytes(bytes);

      // Evict old file image from cache if it exists
      if (state.localPath != null) {
        try {
          await FileImage(File(state.localPath!)).evict();
        } on Exception catch (e) {
          afLog('profile', 'Failed to evict old avatar from cache', error: e);
        }
      }

      // Evict network image from cache if it exists
      if (state.networkUrl != null) {
        try {
          await CachedNetworkImage.evictFromCache(state.networkUrl!);
        } on Exception catch (e) {
          afLog(
            'profile',
            'Failed to evict network avatar from cache',
            error: e,
          );
        }
      }

      // 3. Update local settings & version
      final nextVersion = state.version + 1;
      await prefs.setString(_getLocalKey(userId), file.path);
      await prefs.setInt(_getVersionKey(userId), nextVersion);

      String? networkUrl;
      if (auth != null && auth.serverType == ServerType.jellyfin) {
        networkUrl =
            '${auth.server.baseUrl}/Users/${auth.userId}/Images/Primary?v=$nextVersion';
      }

      state = ProfilePhotoState(
        localPath: file.path,
        networkUrl: networkUrl,
        version: nextVersion,
        isUploading: false,
      );
    } on Exception catch (e, stack) {
      afLog(
        'error',
        'Profile photo upload failed',
        error: e,
        stackTrace: stack,
      );
      state = state.copyWith(isUploading: false);
      rethrow;
    }
  }

  Future<void> removePhoto() async {
    state = state.copyWith(isUploading: true);
    try {
      final auth = ref.read(authProvider);
      final userId = auth?.userId ?? 'local';
      final prefs = await SharedPreferences.getInstance();

      // 1. Delete from Jellyfin if in Jellyfin mode
      final backend = ref.read(musicBackendProvider);
      if (backend is JellyfinClient) {
        try {
          await backend.deleteUserAvatar();
        } on Exception catch (e) {
          afLog(
            'profile',
            'Server avatar delete failed (continuing locally)',
            error: e,
          );
        }
      }

      // 2. Delete local file
      if (state.localPath != null) {
        final file = File(state.localPath!);
        if (file.existsSync()) {
          try {
            await file.delete();
          } on Exception catch (e) {
            afLog('profile', 'Local avatar delete failed', error: e);
          }
        }
        try {
          await FileImage(file).evict();
        } on Exception catch (e) {
          afLog('profile', 'Avatar cache eviction failed', error: e);
        }
      }

      // Evict network image
      if (state.networkUrl != null) {
        try {
          await CachedNetworkImage.evictFromCache(state.networkUrl!);
        } on Exception catch (e) {
          afLog('profile', 'Network avatar cache eviction failed', error: e);
        }
      }

      // 3. Clear from prefs
      await prefs.remove(_getLocalKey(userId));
      await prefs.remove(_getVersionKey(userId));

      state = ProfilePhotoState(version: 0, isUploading: false);
    } on Exception catch (e, stack) {
      afLog(
        'error',
        'Profile photo removal failed',
        error: e,
        stackTrace: stack,
      );
      state = state.copyWith(isUploading: false);
      rethrow;
    }
  }
}

final profilePhotoProvider =
    NotifierProvider<ProfilePhotoNotifier, ProfilePhotoState>(
      ProfilePhotoNotifier.new,
    );
