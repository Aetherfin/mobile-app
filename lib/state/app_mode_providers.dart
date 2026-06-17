import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/models/app_mode.dart';
import 'state_holder.dart';

export '../core/models/app_mode.dart' show AppMode;

final appModeProvider = NotifierProvider<StateHolder<AppMode?>, AppMode?>(
  () => StateHolder<AppMode?>((ref) => null),
);

final localScanProgressProvider =
    NotifierProvider<
      StateHolder<({int completed, int total})?>,
      ({int completed, int total})?
    >(() => StateHolder<({int completed, int total})?>((ref) => null));

final localOnboardingCompletedProvider =
    NotifierProvider<StateHolder<bool>, bool>(
      () => StateHolder<bool>((ref) => false),
    );
