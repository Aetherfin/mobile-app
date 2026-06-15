import 'package:flutter_riverpod/legacy.dart';

enum AppMode { server, local, youtubeMusic }

final appModeProvider = StateProvider<AppMode?>((ref) => null);

final localScanProgressProvider = StateProvider<({int completed, int total})?>(
  (ref) => null,
);

final localOnboardingCompletedProvider = StateProvider<bool>((ref) => false);
