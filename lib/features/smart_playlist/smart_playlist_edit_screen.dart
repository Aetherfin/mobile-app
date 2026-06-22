import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:uuid/uuid.dart';

import '../../core/smart_playlist/smart_playlist_model.dart';
import '../../design_tokens/tokens.dart';
import '../../state/providers.dart';
import '../../utils/navigation.dart';
import '../../widgets/skeletons/track_row_skeleton.dart';

/// Create or edit a smart playlist — Dark Moody rule builder.
class SmartPlaylistEditScreen extends ConsumerStatefulWidget {
  // null = create new
  const SmartPlaylistEditScreen({super.key, this.playlistId});
  final String? playlistId;

  @override
  ConsumerState<SmartPlaylistEditScreen> createState() =>
      _SmartPlaylistEditScreenState();
}

class _SmartPlaylistEditScreenState
    extends ConsumerState<SmartPlaylistEditScreen> {
  final _nameController = TextEditingController();
  String _combinator = 'all';
  List<SmartRule> _rules = [];
  String _sort = 'title';
  String _sortOrder = 'asc';
  int? _limit;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadExisting();
  }

  Future<void> _loadExisting() async {
    if (widget.playlistId != null) {
      final db = ref.read(smartPlaylistDbProvider);
      final existing = await db.getById(widget.playlistId!);
      if (existing != null && mounted) {
        _nameController.text = existing.name;
        _combinator = existing.combinator;
        _rules = List.of(existing.rules);
        _sort = existing.sort;
        _sortOrder = existing.sortOrder;
        _limit = existing.limit;
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Name is required')));
      return;
    }
    if (_rules.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Add at least one rule')));
      return;
    }

    final db = ref.read(smartPlaylistDbProvider);
    final playlist = SmartPlaylist(
      id: widget.playlistId ?? const Uuid().v4(),
      name: name,
      combinator: _combinator,
      rules: _rules,
      sort: _sort,
      sortOrder: _sortOrder,
      limit: _limit,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    await db.save(playlist);
    ref.invalidate(smartPlaylistsProvider);
    if (mounted) context.safePop();
  }

  void _addRule() {
    setState(() {
      _rules.add(
        const SmartRule(field: 'artist', operator: 'contains', value: ''),
      );
    });
  }

  void _removeRule(int index) {
    setState(() => _rules.removeAt(index));
  }

  void _updateRule(int index, SmartRule rule) {
    setState(() => _rules[index] = rule);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: AfColors.surfaceCanvas,
        body: SingleChildScrollView(
          padding: AfSpacing.pageHorizontal,
          child: Column(
            children: [
              SizedBox(height: AfSpacing.s16),
              TrackRowSkeleton(),
              SizedBox(height: AfSpacing.s4),
              TrackRowSkeleton(),
              SizedBox(height: AfSpacing.s4),
              TrackRowSkeleton(),
              SizedBox(height: AfSpacing.s4),
              TrackRowSkeleton(),
              SizedBox(height: AfSpacing.s4),
              TrackRowSkeleton(),
              SizedBox(height: AfSpacing.s4),
              TrackRowSkeleton(),
            ],
          ),
        ),
      );
    }

    final isEdit = widget.playlistId != null;
    final spectral = ref.watch(
      currentSpectralProvider.select(
        (s) => (primary: s.primary, secondary: s.secondary),
      ),
    );

    return Scaffold(
      backgroundColor: AfColors.surfaceCanvas,
      appBar: AppBar(
        backgroundColor: AfColors.surfaceCanvas,
        surfaceTintColor: AfColors.transparent,
        leading: IconButton(
          icon: const Icon(LucideIcons.arrowLeft),
          tooltip: 'Back',
          onPressed: () => context.pop(),
        ),
        title: Text(
          isEdit ? 'Edit Playlist' : 'New Smart Playlist',
          style: AfTypography.display,
        ),
        centerTitle: false,
        titleSpacing: 0,
        actions: [
          TextButton(
            onPressed: _save,
            child: Text(
              'Save',
              style: AfTypography.bodyMedium.copyWith(
                color: spectral.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: AfSpacing.s16),
        children: [
          const SizedBox(height: AfSpacing.s8),

          // ── Name ─────────────────────────────────────────────────────
          const _SectionLabel('Name'),
          _SettingsGroup(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AfSpacing.s16,
                  vertical: AfSpacing.s12,
                ),
                child: TextField(
                  controller: _nameController,
                  style: AfTypography.bodyMedium,
                  decoration: InputDecoration(
                    labelText: 'Playlist name',
                    hintText: 'Playlist name',
                    hintStyle: AfTypography.bodyMedium.copyWith(
                      color: AfColors.textTertiary,
                    ),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: AfSpacing.s16),

          // ── Match mode ───────────────────────────────────────────────
          const _SectionLabel('Match mode'),
          _SettingsGroup(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AfSpacing.s16,
                  vertical: AfSpacing.s12,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: spectral.secondary.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        LucideIcons.filter,
                        size: 18,
                        color: spectral.secondary,
                      ),
                    ),
                    const SizedBox(width: AfSpacing.s12),
                    Text('Match', style: AfTypography.bodyMedium),
                    const Spacer(),
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(value: 'all', label: Text('All')),
                        ButtonSegment(value: 'any', label: Text('Any')),
                      ],
                      selected: {_combinator},
                      onSelectionChanged: (v) =>
                          setState(() => _combinator = v.first),
                      style: SegmentedButton.styleFrom(
                        backgroundColor: AfColors.surfaceHigh,
                        selectedBackgroundColor: spectral.primary,
                        selectedForegroundColor: AfColors.surfaceCanvas,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: AfSpacing.s16),

          // ── Rules ────────────────────────────────────────────────────
          const _SectionLabel('Rules'),
          if (_rules.isNotEmpty)
            _SettingsGroup(
              children: [
                for (int i = 0; i < _rules.length; i++) ...[
                  _RuleRow(
                    rule: _rules[i],
                    onChanged: (r) => _updateRule(i, r),
                    onDelete: () => _removeRule(i),
                  ),
                  if (i < _rules.length - 1)
                    const Divider(
                      height: 0,
                      thickness: 0.5,
                      indent: 16,
                      endIndent: 16,
                      color: AfColors.surfaceHigh,
                    ),
                ],
              ],
            ),
          const SizedBox(height: AfSpacing.s8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AfSpacing.s4),
            child: Tooltip(
              message: 'Add rule',
              child: OutlinedButton.icon(
                onPressed: _addRule,
                icon: const Icon(LucideIcons.plus, size: 18),
                label: const Text('Add rule'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: spectral.primary,
                  side: const BorderSide(color: AfColors.surfaceHigh),
                  shape: const RoundedRectangleBorder(
                    borderRadius: AfRadii.borderLg,
                  ),
                  padding: const EdgeInsets.symmetric(vertical: AfSpacing.s12),
                ),
              ),
            ),
          ),

          const SizedBox(height: AfSpacing.s16),

          // ── Sort & Limit ─────────────────────────────────────────────
          const _SectionLabel('Sort & limit'),
          _SettingsGroup(
            children: [
              // Sort row
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AfSpacing.s16,
                  vertical: AfSpacing.s12,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: AfColors.semanticSuccess.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        LucideIcons.arrowUpDown,
                        size: 18,
                        color: AfColors.semanticSuccess,
                      ),
                    ),
                    const SizedBox(width: AfSpacing.s12),
                    Text('Sort by', style: AfTypography.bodyMedium),
                    const Spacer(),
                    DropdownButton<String>(
                      value: _sort,
                      underline: const SizedBox.shrink(),
                      dropdownColor: AfColors.surfaceRaised,
                      style: AfTypography.bodySmall.copyWith(
                        color: spectral.primary,
                      ),
                      items: kSmartSortOptions.entries
                          .map(
                            (e) => DropdownMenuItem(
                              value: e.key,
                              child: Text(e.value),
                            ),
                          )
                          .toList(),
                      onChanged: (v) => setState(() => _sort = v ?? 'title'),
                    ),
                    IconButton(
                      icon: Icon(
                        _sortOrder == 'asc'
                            ? LucideIcons.arrowUp
                            : LucideIcons.arrowDown,
                        size: 18,
                        color: AfColors.textSecondary,
                      ),
                      onPressed: () => setState(
                        () => _sortOrder = _sortOrder == 'asc' ? 'desc' : 'asc',
                      ),
                      tooltip: _sortOrder == 'asc' ? 'Ascending' : 'Descending',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: AfSpacing.minHitTarget,
                        minHeight: AfSpacing.minHitTarget,
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(
                height: 0,
                thickness: 0.5,
                indent: 60,
                color: AfColors.surfaceHigh,
              ),
              // Limit row
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AfSpacing.s16,
                  vertical: AfSpacing.s12,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: AfColors.semanticWarning.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        LucideIcons.listX,
                        size: 18,
                        color: AfColors.semanticWarning,
                      ),
                    ),
                    const SizedBox(width: AfSpacing.s12),
                    Text('Limit to', style: AfTypography.bodyMedium),
                    const Spacer(),
                    SizedBox(
                      width: 64,
                      child: TextField(
                        keyboardType: TextInputType.number,
                        controller: TextEditingController(
                          text: _limit?.toString() ?? '',
                        ),
                        textAlign: TextAlign.center,
                        style: AfTypography.bodyMedium.copyWith(
                          color: spectral.primary,
                        ),
                        decoration: InputDecoration(
                          labelText: 'Value',
                          hintText: '\u221e',
                          hintStyle: AfTypography.bodyMedium.copyWith(
                            color: AfColors.textTertiary,
                          ),
                          filled: true,
                          fillColor: AfColors.surfaceHigh,
                          border: const OutlineInputBorder(
                            borderRadius: AfRadii.borderSm,
                            borderSide: BorderSide.none,
                          ),
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: AfSpacing.s8,
                            vertical: AfSpacing.s8,
                          ),
                        ),
                        onChanged: (v) => _limit = int.tryParse(v),
                      ),
                    ),
                    const SizedBox(width: AfSpacing.s8),
                    Text(
                      'tracks',
                      style: AfTypography.bodySmall.copyWith(
                        color: AfColors.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: AfSpacing.s32),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared settings UI components
// ─────────────────────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AfSpacing.s16,
        0,
        AfSpacing.s4,
        AfSpacing.s8,
      ),
      child: Text(
        label,
        style: AfTypography.label.copyWith(
          color: AfColors.textTertiary,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

class _SettingsGroup extends StatelessWidget {
  const _SettingsGroup({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: const BoxDecoration(
        color: AfColors.surfaceBase,
        borderRadius: AfRadii.borderLg,
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: children),
    );
  }
}

/// A single rule row inside the grouped card.
class _RuleRow extends ConsumerWidget {
  const _RuleRow({
    required this.rule,
    required this.onChanged,
    required this.onDelete,
  });
  final SmartRule rule;
  final ValueChanged<SmartRule> onChanged;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spectral = ref.watch(
      currentSpectralProvider.select((s) => s.primary),
    );
    final operators = operatorsForField(rule.field);
    final effectiveOp = operators.contains(rule.operator)
        ? rule.operator
        : operators.first;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AfSpacing.s16,
        vertical: AfSpacing.s12,
      ),
      child: Column(
        children: [
          // Field + Operator row
          Row(
            children: [
              // Field
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AfSpacing.s12,
                    vertical: AfSpacing.s4,
                  ),
                  decoration: const BoxDecoration(
                    color: AfColors.surfaceHigh,
                    borderRadius: AfRadii.borderSm,
                  ),
                  child: DropdownButton<String>(
                    value: rule.field,
                    isExpanded: true,
                    underline: const SizedBox.shrink(),
                    isDense: true,
                    dropdownColor: AfColors.surfaceRaised,
                    style: AfTypography.bodySmall,
                    items: kSmartFields.entries
                        .map(
                          (e) => DropdownMenuItem(
                            value: e.key,
                            child: Text(e.value),
                          ),
                        )
                        .toList(),
                    onChanged: (v) {
                      if (v == null) return;
                      final newOps = operatorsForField(v);
                      onChanged(
                        SmartRule(
                          field: v,
                          operator: newOps.first,
                          value: v == 'isFavorite' ? true : '',
                        ),
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(width: AfSpacing.s8),
              // Operator
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AfSpacing.s12,
                    vertical: AfSpacing.s4,
                  ),
                  decoration: const BoxDecoration(
                    color: AfColors.surfaceHigh,
                    borderRadius: AfRadii.borderSm,
                  ),
                  child: DropdownButton<String>(
                    value: effectiveOp,
                    isExpanded: true,
                    underline: const SizedBox.shrink(),
                    isDense: true,
                    dropdownColor: AfColors.surfaceRaised,
                    style: AfTypography.bodySmall,
                    items: operators
                        .map(
                          (op) => DropdownMenuItem(
                            value: op,
                            child: Text(_opLabel(op)),
                          ),
                        )
                        .toList(),
                    onChanged: (v) {
                      if (v == null) return;
                      onChanged(
                        SmartRule(
                          field: rule.field,
                          operator: v,
                          value: rule.value,
                        ),
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(width: AfSpacing.s8),
              // Delete button
              GestureDetector(
                onTap: onDelete,
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: AfColors.semanticError.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    LucideIcons.x,
                    size: 16,
                    color: AfColors.semanticError,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AfSpacing.s8),
          // Value row
          _buildValueInput(spectral),
        ],
      ),
    );
  }

  Widget _buildValueInput(Color spectral) {
    if (rule.field == 'isFavorite') {
      return Row(
        children: [
          Text('Favorited', style: AfTypography.bodySmall),
          const Spacer(),
          Switch.adaptive(
            value: rule.value == true,
            onChanged: (v) => onChanged(
              SmartRule(field: rule.field, operator: rule.operator, value: v),
            ),
            activeTrackColor: spectral,
          ),
        ],
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AfSpacing.s12,
        vertical: AfSpacing.s8,
      ),
      decoration: const BoxDecoration(
        color: AfColors.surfaceHigh,
        borderRadius: AfRadii.borderSm,
      ),
      child: TextField(
        controller: TextEditingController(text: '${rule.value}'),
        style: AfTypography.bodySmall,
        keyboardType: _isNumericField(rule.field)
            ? TextInputType.number
            : TextInputType.text,
        decoration: InputDecoration(
          labelText: 'Value',
          hintText: _isNumericField(rule.field) ? '0' : 'Enter value...',
          hintStyle: AfTypography.bodySmall.copyWith(
            color: AfColors.textTertiary,
          ),
          isDense: true,
          border: InputBorder.none,
          contentPadding: EdgeInsets.zero,
        ),
        onChanged: (v) {
          final parsed = _isNumericField(rule.field)
              ? (int.tryParse(v) ?? v)
              : v;
          onChanged(
            SmartRule(
              field: rule.field,
              operator: rule.operator,
              value: parsed,
            ),
          );
        },
      ),
    );
  }

  bool _isNumericField(String field) =>
      field == 'year' ||
      field == 'duration' ||
      field == 'bitrate' ||
      field == 'dateAdded' ||
      field == 'playCount' ||
      field == 'lastPlayed';

  String _opLabel(String op) => switch (op) {
    'is' => 'is',
    'isNot' => 'is not',
    'contains' => 'contains',
    'notContains' => 'not contains',
    'gt' => 'greater than',
    'lt' => 'less than',
    'inTheRange' => 'between',
    'inTheLast' => 'last N days',
    _ => op,
  };
}
