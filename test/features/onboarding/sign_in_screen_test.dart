import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aetherfin/core/jellyfin/models/server.dart';
import 'package:aetherfin/design_tokens/colors.dart';
import 'package:aetherfin/features/onboarding/sign_in_screen.dart';
import 'package:aetherfin/state/providers.dart';
import 'package:aetherfin/state/state_holder.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const testServer = JellyfinServer(
    baseUrl: 'http://192.168.1.10:8096',
    name: 'My Jellyfin',
  );

  ProviderContainer createContainer({AppMode? mode}) {
    return ProviderContainer(
      overrides: [
        currentSpectralProvider.overrideWith((ref) => Spectral.fallback),
        appModeProvider.overrideWith(
          () => StateHolder<AppMode?>((ref) => mode),
        ),
        deviceIdProvider.overrideWithValue('test-device-id'),
        aetherfinVersionProvider.overrideWithValue('0.2.4'),
      ],
    );
  }

  group('SignInScreen', () {
    testWidgets('renders without crashing', (tester) async {
      final container = createContainer(mode: AppMode.server);
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: SignInScreen(server: testServer)),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(SignInScreen), findsOneWidget);
    });

    testWidgets('username field exists', (tester) async {
      final container = createContainer(mode: AppMode.server);
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: SignInScreen(server: testServer)),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Username'), findsAtLeastNWidgets(1));
    });

    testWidgets('password field exists', (tester) async {
      final container = createContainer(mode: AppMode.server);
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: SignInScreen(server: testServer)),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Password'), findsAtLeastNWidgets(1));
    });

    testWidgets('sign in button exists', (tester) async {
      final container = createContainer(mode: AppMode.server);
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: SignInScreen(server: testServer)),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Sign in'), findsAtLeastNWidgets(1));
    });

    testWidgets('shows server name in header', (tester) async {
      final container = createContainer(mode: AppMode.server);
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: SignInScreen(server: testServer)),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('My Jellyfin'), findsOneWidget);
    });

    testWidgets('back button exists', (tester) async {
      final container = createContainer(mode: AppMode.server);
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: SignInScreen(server: testServer)),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byTooltip('Back'), findsOneWidget);
    });
  });
}
