import 'dart:ui' show Tristate;

import 'package:aetherfin/core/audio/af_loop_mode.dart';
import 'package:aetherfin/core/audio/shuffle_mode.dart';
import 'package:aetherfin/core/jellyfin/models/items.dart';
import 'package:aetherfin/design_tokens/colors.dart';
import 'package:aetherfin/features/now_playing/transport_row.dart';
import 'package:aetherfin/features/settings/settings_widgets.dart';
import 'package:aetherfin/state/favorite_providers.dart';
import 'package:aetherfin/state/music_backend_providers.dart';
import 'package:aetherfin/state/player_providers.dart';
import 'package:aetherfin/state/spectral_providers.dart';
import 'package:aetherfin/state/state_holder.dart';
import 'package:aetherfin/widgets/bottom_nav.dart';
import 'package:aetherfin/widgets/track_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// Wraps [child] in a [ProviderScope] with overrides needed by
/// widgets that touch Riverpod during build.
Widget _wrapWithProviders(Widget child) => ProviderScope(
  overrides: [
    isBufferingProvider.overrideWithValue(false),
    currentSpectralProvider.overrideWith((_) => Spectral.fallback),
    musicBackendProvider.overrideWithValue(null),
    trackFavoriteOverridesProvider.overrideWith(
      () => StateHolder<Map<String, bool>>((ref) => {}),
    ),
    playingStreamProvider.overrideWith((ref) => Stream.value(false)),
  ],
  child: MaterialApp(home: Scaffold(body: child)),
);

AfTrack _testTrack({
  String id = 't1',
  String title = 'Test Song',
  String artist = 'Test Artist',
  String album = 'Test Album',
}) => AfTrack(
  id: id,
  title: title,
  artistName: artist,
  albumName: album,
  duration: const Duration(minutes: 3, seconds: 42),
);

/// Default TransportRow props — only vary what each test needs.
TransportRow _transportRow({
  bool isPlaying = false,
  ShuffleMode shuffleMode = ShuffleMode.off,
  AfLoopMode loopMode = AfLoopMode.off,
}) => TransportRow(
  isPlaying: isPlaying,
  shuffleOn: shuffleMode != ShuffleMode.off,
  shuffleMode: shuffleMode,
  loopMode: loopMode,
  repeatCount: 0,
  accent: Spectral.fallback.primary,
  muted: Spectral.fallback.muted,
  onPlayPause: () {},
  onPrev: () {},
  onNext: () {},
  onShuffle: () {},
  onShuffleLongPress: () {},
  onRepeat: () {},
);

void main() {
  group('Accessibility — Transport controls', () {
    testWidgets('play button has Play label when paused', (tester) async {
      await tester.pumpWidget(_wrapWithProviders(_transportRow()));
      await tester.pump();

      // TransportRow's Play Semantics wraps an icon (no text child),
      // so the label is not merged and exact match works.
      final node = tester.getSemantics(find.bySemanticsLabel('Play'));
      expect(node.label, 'Play');
    });

    testWidgets('play button has Pause label when playing', (tester) async {
      await tester.pumpWidget(
        _wrapWithProviders(_transportRow(isPlaying: true)),
      );
      await tester.pump();

      final node = tester.getSemantics(find.bySemanticsLabel('Pause'));
      expect(node.label, 'Pause');
    });

    testWidgets('previous track button has label', (tester) async {
      await tester.pumpWidget(_wrapWithProviders(_transportRow()));
      await tester.pump();

      final node = tester.getSemantics(find.bySemanticsLabel('Previous track'));
      expect(node.label, 'Previous track');
    });

    testWidgets('next track button has label', (tester) async {
      await tester.pumpWidget(_wrapWithProviders(_transportRow()));
      await tester.pump();

      final node = tester.getSemantics(find.bySemanticsLabel('Next track'));
      expect(node.label, 'Next track');
    });

    testWidgets('shuffle button has Semantics with button flag', (
      tester,
    ) async {
      await tester.pumpWidget(_wrapWithProviders(_transportRow()));
      await tester.pump();

      final node = tester.getSemantics(find.bySemanticsLabel('Shuffle'));
      expect(node.label, 'Shuffle');

      final data = node.getSemanticsData();
      expect(data.flagsCollection.isButton, isTrue);
    });

    testWidgets('repeat button has label when active', (tester) async {
      await tester.pumpWidget(
        _wrapWithProviders(_transportRow(loopMode: AfLoopMode.playlist)),
      );
      await tester.pump();

      final node = tester.getSemantics(find.bySemanticsLabel('Repeat'));
      expect(node.label, 'Repeat');

      final data = node.getSemanticsData();
      expect(data.flagsCollection.isButton, isTrue);
    });

    testWidgets('repeat off has correct label', (tester) async {
      await tester.pumpWidget(_wrapWithProviders(_transportRow()));
      await tester.pump();

      final node = tester.getSemantics(find.bySemanticsLabel('Repeat off'));
      expect(node.label, 'Repeat off');

      final data = node.getSemanticsData();
      expect(data.flagsCollection.isButton, isTrue);
    });
  });

  group('Accessibility — Track row', () {
    testWidgets('has label with title and artist', (tester) async {
      await tester.pumpWidget(
        _wrapWithProviders(
          TrackRow(
            track: _testTrack(title: 'Echoes', artist: 'Pink Floyd'),
          ),
        ),
      );
      await tester.pump();

      // TrackRow's Semantics wraps Text widgets, so child text merges into
      // the label. Use RegExp prefix match to find the node.
      final node = tester.getSemantics(
        find.bySemanticsLabel(RegExp('^Echoes by Pink Floyd')),
      );
      expect(node.label, contains('Echoes by Pink Floyd'));

      final data = node.getSemanticsData();
      expect(data.flagsCollection.isButton, isTrue);
    });

    testWidgets('has hint for double tap to play', (tester) async {
      await tester.pumpWidget(
        _wrapWithProviders(
          TrackRow(
            track: _testTrack(title: 'Echoes', artist: 'Pink Floyd'),
          ),
        ),
      );
      await tester.pump();

      final node = tester.getSemantics(
        find.bySemanticsLabel(RegExp('^Echoes by Pink Floyd')),
      );
      expect(node.hint, 'Double tap to play');
    });

    testWidgets('appends ", now playing" when active', (tester) async {
      await tester.pumpWidget(
        _wrapWithProviders(
          TrackRow(
            track: _testTrack(title: 'Time', artist: 'Pink Floyd'),
            isActive: true,
          ),
        ),
      );
      await tester.pump();

      final node = tester.getSemantics(
        find.bySemanticsLabel(RegExp('^Time by Pink Floyd, now playing')),
      );
      expect(node.label, contains('Time by Pink Floyd, now playing'));
    });
  });

  group('Accessibility — Bottom navigation', () {
    testWidgets('active tab has selected true', (tester) async {
      final items = [
        const AfBottomNavItem(icon: LucideIcons.house, label: 'Home'),
        const AfBottomNavItem(icon: LucideIcons.libraryBig, label: 'Library'),
      ];

      await tester.pumpWidget(
        _wrapWithProviders(
          AfBottomNav(currentIndex: 0, onSelect: (_) {}, items: items),
        ),
      );
      await tester.pump();

      // BottomNav's Semantics wraps PressScale with Text child,
      // so use RegExp prefix match.
      final homeNode = tester.getSemantics(
        find.bySemanticsLabel(RegExp('^Home')),
      );
      expect(homeNode.label, contains('Home'));
      expect(
        homeNode.getSemanticsData().flagsCollection.isSelected,
        Tristate.isTrue,
      );

      final libNode = tester.getSemantics(
        find.bySemanticsLabel(RegExp('^Library')),
      );
      expect(libNode.label, contains('Library'));
      expect(
        libNode.getSemanticsData().flagsCollection.isSelected,
        Tristate.isFalse,
      );
    });

    testWidgets('selected state switches on tab change', (tester) async {
      final items = [
        const AfBottomNavItem(icon: LucideIcons.house, label: 'Home'),
        const AfBottomNavItem(icon: LucideIcons.libraryBig, label: 'Library'),
        const AfBottomNavItem(icon: LucideIcons.listMusic, label: 'Playlists'),
      ];

      int selectedIndex = 0;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentSpectralProvider.overrideWith((_) => Spectral.fallback),
          ],
          child: MaterialApp(
            home: StatefulBuilder(
              builder: (context, setState) {
                return Scaffold(
                  bottomNavigationBar: AfBottomNav(
                    currentIndex: selectedIndex,
                    onSelect: (i) => setState(() => selectedIndex = i),
                    items: items,
                  ),
                );
              },
            ),
          ),
        ),
      );
      await tester.pump();

      // Initially Home is selected
      expect(
        tester
            .getSemantics(find.bySemanticsLabel(RegExp('^Home')))
            .getSemanticsData()
            .flagsCollection
            .isSelected,
        Tristate.isTrue,
      );

      // Tap Library
      await tester.tap(find.bySemanticsLabel(RegExp('^Library')));
      await tester.pump();

      expect(
        tester
            .getSemantics(find.bySemanticsLabel(RegExp('^Home')))
            .getSemanticsData()
            .flagsCollection
            .isSelected,
        Tristate.isFalse,
      );
      expect(
        tester
            .getSemantics(find.bySemanticsLabel(RegExp('^Library')))
            .getSemanticsData()
            .flagsCollection
            .isSelected,
        Tristate.isTrue,
      );
    });

    testWidgets('all tabs have button flag', (tester) async {
      final items = [
        const AfBottomNavItem(icon: LucideIcons.house, label: 'Home'),
        const AfBottomNavItem(icon: LucideIcons.libraryBig, label: 'Library'),
      ];

      await tester.pumpWidget(
        _wrapWithProviders(
          AfBottomNav(currentIndex: 0, onSelect: (_) {}, items: items),
        ),
      );
      await tester.pump();

      expect(
        tester
            .getSemantics(find.bySemanticsLabel(RegExp('^Home')))
            .getSemanticsData()
            .flagsCollection
            .isButton,
        isTrue,
      );
      expect(
        tester
            .getSemantics(find.bySemanticsLabel(RegExp('^Library')))
            .getSemanticsData()
            .flagsCollection
            .isButton,
        isTrue,
      );
    });
  });

  group('Accessibility — Settings switch tile', () {
    testWidgets('has label and toggled false', (tester) async {
      await tester.pumpWidget(
        _wrapWithProviders(
          SettingsSwitchTile(
            icon: LucideIcons.moon,
            title: 'Dark mode',
            value: false,
            onChanged: (_) {},
          ),
        ),
      );
      await tester.pump();

      final node = tester.getSemantics(
        find.bySemanticsLabel(RegExp('^Dark mode')),
      );
      expect(node.label, contains('Dark mode'));
      expect(
        node.getSemanticsData().flagsCollection.isToggled,
        Tristate.isFalse,
      );
    });

    testWidgets('has toggled true when enabled', (tester) async {
      await tester.pumpWidget(
        _wrapWithProviders(
          SettingsSwitchTile(
            icon: LucideIcons.moon,
            title: 'Dark mode',
            value: true,
            onChanged: (_) {},
          ),
        ),
      );
      await tester.pump();

      final node = tester.getSemantics(
        find.bySemanticsLabel(RegExp('^Dark mode')),
      );
      expect(
        node.getSemanticsData().flagsCollection.isToggled,
        Tristate.isTrue,
      );
    });

    testWidgets('is marked as button', (tester) async {
      await tester.pumpWidget(
        _wrapWithProviders(
          SettingsSwitchTile(
            icon: LucideIcons.moon,
            title: 'Dark mode',
            value: false,
            onChanged: (_) {},
          ),
        ),
      );
      await tester.pump();

      final node = tester.getSemantics(
        find.bySemanticsLabel(RegExp('^Dark mode')),
      );
      expect(node.getSemanticsData().flagsCollection.isButton, isTrue);
    });
  });

  group('Accessibility — Settings tile', () {
    testWidgets('has label and button flag', (tester) async {
      await tester.pumpWidget(
        _wrapWithProviders(
          SettingsTile(icon: LucideIcons.info, title: 'About', onTap: () {}),
        ),
      );
      await tester.pump();

      final node = tester.getSemantics(find.bySemanticsLabel(RegExp('^About')));
      expect(node.label, contains('About'));
      expect(node.getSemanticsData().flagsCollection.isButton, isTrue);
    });
  });
}
