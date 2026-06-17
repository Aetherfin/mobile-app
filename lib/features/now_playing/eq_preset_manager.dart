import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/audio/player_settings_store.dart';
import '../../design_tokens/tokens.dart';
import '../../state/providers.dart';
import '../../utils/log.dart';
import '../../widgets/af_dialog.dart';
import 'eq_band_logic.dart';
import 'eq_preset.dart';
import 'parametric_band.dart';
import 'parametric_presets.dart';

/// Manages EQ preset persistence and application.
class EqPresetManager {
  EqPresetManager._();

  /// Load all user presets from persistent storage.
  static Future<Map<String, EqPreset>> loadUserPresets() =>
      PlayerSettingsStore.loadEqPresetsAsync();

  /// Save a named EQ preset to persistent storage.
  static Future<void> savePreset(String name, EqPreset preset) =>
      PlayerSettingsStore.saveEqPreset(name, preset);

  /// Delete a named EQ preset from persistent storage.
  static Future<void> deletePreset(String name) =>
      PlayerSettingsStore.deleteEqPreset(name);

  /// Persist the currently active preset name (null to clear).
  static Future<void> saveActivePreset(String? name) =>
      PlayerSettingsStore.saveActivePreset(name);

  /// Create an [EqPreset] from the current DSP state.
  ///
  /// Graphic EQ presets are now managed separately; this only captures
  /// bass and treble from the DSP state.
  static EqPreset createPresetFromState(EqDspState state) {
    return EqPreset(bands: const {}, bass: state.bass, treble: state.treble);
  }

  /// Apply a preset's values to the DSP state.
  ///
  /// Only bass and treble are applied; graphic EQ bands are managed
  /// by the standalone GraphicEqState.
  static void applyPresetToState(EqDspState state, EqPreset preset) {
    state.bass = preset.bass;
    state.treble = preset.treble;
  }

  /// Build the horizontal preset chips row.
  static Widget buildPresetChips({
    required String? activePreset,
    required Map<String, EqPreset> userPresets,
    required WidgetRef ref,
    required void Function(String name, EqPreset preset) onApply,
    required void Function(String name) onDelete,
  }) {
    final allPresets = <String, EqPreset>{...kBuiltInPresets, ...userPresets};
    final spectral = ref.watch(
      currentSpectralProvider.select(
        (s) => (primary: s.primary, secondary: s.secondary),
      ),
    );
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: allPresets.entries.map((entry) {
          final isActive = activePreset == entry.key;
          final isUserPreset = userPresets.containsKey(entry.key);
          return Padding(
            padding: const EdgeInsets.only(right: AfSpacing.s8),
            child: Semantics(
              button: true,
              selected: isActive,
              label: 'EQ preset: ${entry.key}',
              child: GestureDetector(
                onLongPress: isUserPreset ? () => onDelete(entry.key) : null,
                child: ChoiceChip(
                  label: Text(entry.key),
                  selected: isActive,
                  onSelected: (_) => onApply(entry.key, entry.value),
                  selectedColor: spectral.secondary.withValues(alpha: 0.3),
                  backgroundColor: AfColors.surfaceBase,
                  labelStyle: AfTypography.bodySmall.copyWith(
                    color: isActive ? spectral.primary : AfColors.textSecondary,
                  ),
                  side: isActive
                      ? BorderSide(color: spectral.primary, width: 1.5)
                      : const BorderSide(color: AfColors.surfaceHigh),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  /// Show the "save preset" dialog and return the chosen name, or null.
  static Future<String?> showSaveDialog(BuildContext context) {
    final controller = TextEditingController();
    final result = showBlurDialog<String>(
      context: context,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Save EQ Preset', style: AfTypography.titleMedium),
          const SizedBox(height: AfSpacing.s16),
          TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Preset name',
              hintText: 'Preset name',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: AfSpacing.s24),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => context.pop(),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => context.pop(controller.text.trim()),
                child: const Text('Save'),
              ),
            ],
          ),
        ],
      ),
    );
    result.whenComplete(controller.dispose);
    return result;
  }

  /// Show the "delete preset" confirmation dialog.
  static void showDeleteDialog({
    required BuildContext context,
    required String name,
    required VoidCallback onConfirm,
  }) {
    showBlurDialog<void>(
      context: context,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Delete "$name"?', style: AfTypography.titleMedium),
          const SizedBox(height: AfSpacing.s12),
          Text(
            'This preset will be permanently removed.',
            style: AfTypography.bodyMedium,
          ),
          const SizedBox(height: AfSpacing.s24),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => context.pop(),
                child: const Text('Cancel'),
              ),
              Focus(
                autofocus: true,
                child: TextButton(
                  onPressed: () {
                    context.pop();
                    onConfirm();
                  },
                  child: Text(
                    'Delete',
                    style: AfTypography.bodyMedium.copyWith(
                      color: AfColors.semanticError,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Parametric EQ Presets ────────────────────────────────────────────────

  static const _kParametricPresetsKey = 'af.parametric_presets_json';

  /// Load all user-saved parametric presets from persistent storage.
  static Future<Map<String, ParametricPreset>>
  loadUserParametricPresets() async {
    final p = await SharedPreferences.getInstance();
    final json = p.getString(_kParametricPresetsKey);
    if (json == null) return {};
    try {
      final raw = jsonDecode(json) as Map<String, dynamic>;
      return raw.map(
        (k, v) =>
            MapEntry(k, ParametricPreset.fromJson(v as Map<String, dynamic>)),
      );
    } on Exception catch (e, stack) {
      afLog(
        'error',
        'Parametric presets deserialization failed',
        error: e,
        stackTrace: stack,
      );
      return {};
    }
  }

  /// Save a named parametric preset to persistent storage.
  static Future<void> saveParametricPreset(
    String name,
    ParametricPreset preset,
  ) async {
    final presets = await loadUserParametricPresets();
    presets[name] = preset;
    final p = await SharedPreferences.getInstance();
    await p.setString(
      _kParametricPresetsKey,
      jsonEncode(presets.map((k, v) => MapEntry(k, v.toJson()))),
    );
  }

  /// Delete a named parametric preset from persistent storage.
  static Future<void> deleteParametricPreset(String name) async {
    final presets = await loadUserParametricPresets();
    presets.remove(name);
    final p = await SharedPreferences.getInstance();
    await p.setString(
      _kParametricPresetsKey,
      jsonEncode(presets.map((k, v) => MapEntry(k, v.toJson()))),
    );
  }

  /// Build the horizontal preset chips row for parametric EQ.
  static Widget buildParametricPresetChips({
    required String? activePreset,
    required Map<String, ParametricPreset> userPresets,
    required WidgetRef ref,
    required void Function(String name, ParametricPreset preset) onApply,
    required void Function(String name) onDelete,
  }) {
    final allPresets = <String, ParametricPreset>{
      ...kParametricPresets,
      ...userPresets,
    };
    final spectral = ref.watch(
      currentSpectralProvider.select(
        (s) => (primary: s.primary, secondary: s.secondary),
      ),
    );
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: allPresets.entries.map((entry) {
          final isActive = activePreset == entry.key;
          final isUserPreset = userPresets.containsKey(entry.key);
          return Padding(
            padding: const EdgeInsets.only(right: AfSpacing.s8),
            child: Semantics(
              button: true,
              selected: isActive,
              label: 'Parametric preset: ${entry.key}',
              child: GestureDetector(
                onLongPress: isUserPreset ? () => onDelete(entry.key) : null,
                child: ChoiceChip(
                  label: Text(entry.key),
                  selected: isActive,
                  onSelected: (_) => onApply(entry.key, entry.value),
                  selectedColor: spectral.secondary.withValues(alpha: 0.3),
                  backgroundColor: AfColors.surfaceBase,
                  labelStyle: AfTypography.bodySmall.copyWith(
                    color: isActive ? spectral.primary : AfColors.textSecondary,
                  ),
                  side: isActive
                      ? BorderSide(color: spectral.primary, width: 1.5)
                      : const BorderSide(color: AfColors.surfaceHigh),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
