import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_mode.dart';

/// Persists and restores the user's chosen app mode (server | local).
class AppModeStore {
  static const _kAppMode = 'af.app_mode';

  /// Save the selected mode.
  static Future<void> save(AppMode mode) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kAppMode, mode.name);
  }

  /// Load the persisted mode. Returns null on first launch.
  static Future<AppMode?> load() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_kAppMode);
    if (raw == null) return null;
    return AppMode.values.where((m) => m.name == raw).firstOrNull;
  }

  /// Clear the mode (used when switching modes / signing out).
  static Future<void> clear() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_kAppMode);
  }
}
