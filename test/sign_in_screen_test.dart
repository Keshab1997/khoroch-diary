import 'dart:async';

// Flutter 3.50 deprecates this import; migrate with the app's dependency update.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:khoroch_diary/core/l10n/app_strings.dart' show AppLanguage;
import 'package:khoroch_diary/core/theme/app_theme.dart';
import 'package:khoroch_diary/features/sync/cloud_backend.dart';
import 'package:khoroch_diary/features/sync/sign_in_screen.dart';

import 'support/fake_cloud_backend.dart';

Future<void> _pumpSignIn(
  WidgetTester tester,
  SignInScreen screen, {
  Size size = const Size(360, 720),
  double textScale = 1.0,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      builder: (BuildContext context, Widget? child) {
        final MediaQueryData media = MediaQuery.of(context);
        return MediaQuery(
          data: media.copyWith(textScaler: TextScaler.linear(textScale)),
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: screen,
    ),
  );
  await tester.pumpAndSettle();
}

/// Scrolls the Continue button into view, then taps it — the card grew past
/// a 720 dp viewport after the design-polish pass, so a bare tap misses.
Future<void> _tapContinue(WidgetTester tester) async {
  await tester.scrollUntilVisible(
    find.byKey(const Key('continue-with-google-button')),
    120,
  );
  await tester.ensureVisible(
    find.byKey(const Key('continue-with-google-button')),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('continue-with-google-button')));
}

void main() {
  group('SignInScreen (S11)', () {
    testWidgets(
      'explains optional cloud backup and local data staying on phone, handles progress, cancel, error, and success',
      (WidgetTester tester) async {
        final FakeCloudBackend backend = FakeCloudBackend();
        CloudUser? signedInUser;

        final Completer<CloudUser?> pendingSignIn = Completer<CloudUser?>();
        backend.onSignInWithGoogle = () => pendingSignIn.future;

        await _pumpSignIn(
          tester,
          SignInScreen(
            backend: backend,
            onSignedIn: (CloudUser u) => signedInUser = u,
          ),
        );

        expect(find.text('Optional Cloud Backup'), findsOneWidget);
        expect(find.text('Local data stays on this phone'), findsOneWidget);
        expect(find.text('Continue with Google'), findsOneWidget);

        // Start sign-in -> shows inline progress and disables duplicate tap.
        await _tapContinue(tester);
        await tester.pump();
        expect(find.byKey(const Key('sign-in-progress')), findsOneWidget);
        expect(find.text('Signing in…'), findsOneWidget);

        // 1. User cancels Google picker -> null returned, cancel notice shown.
        pendingSignIn.complete(null);
        await tester.pumpAndSettle();
        expect(signedInUser, isNull);
        expect(
          find.text('Sign-in cancelled. Your local data is untouched.'),
          findsOneWidget,
        );

        // 2. Backend throws an error -> error banner shown.
        backend.onSignInWithGoogle = () async =>
            throw Exception('OAuth provider unavailable');
        await _tapContinue(tester);
        await tester.pumpAndSettle();
        expect(
          find.text('Could not sign in with Google. Please try again.'),
          findsOneWidget,
        );
        expect(find.text('OAuth provider unavailable'), findsOneWidget);

        // 3. Successful Google sign-in -> returns CloudUser.
        final CloudUser alice = CloudUser(
          id: 'u-alice',
          email: 'alice@example.com',
        );
        backend.onSignInWithGoogle = () async => alice;
        await _tapContinue(tester);
        await tester.pumpAndSettle();
        expect(signedInUser, alice);
        expect(backend.currentUser, alice);

        await backend.dispose();
      },
    );

    testWidgets('renders Bengali copy cleanly at 320dp and 200% text scale', (
      WidgetTester tester,
    ) async {
      final FakeCloudBackend backend = FakeCloudBackend();
      backend.onSignInWithGoogle = () async => null;

      await _pumpSignIn(
        tester,
        SignInScreen(backend: backend, language: AppLanguage.bn),
        size: const Size(320, 640),
        textScale: 2.0,
      );

      expect(find.text('ঐচ্ছিক ক্লাউড ব্যাকআপ'), findsOneWidget);
      expect(find.text('স্থানীয় তথ্য এই ফোনেই থাকে'), findsOneWidget);

      await tester.scrollUntilVisible(
        find.byKey(const Key('continue-with-google-button')),
        120,
      );
      // scrollUntilVisible stops once the button is partly on screen; bring
      // all of it into view so the tap lands on it.
      await tester.ensureVisible(
        find.byKey(const Key('continue-with-google-button')),
      );
      await tester.pumpAndSettle();
      await _tapContinue(tester);
      await tester.pumpAndSettle();

      expect(
        find.text('সাইন ইন বাতিল করা হয়েছে। আপনার ফোনের তথ্য অক্ষত আছে।'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);

      await backend.dispose();
    });
  });

  group('SignInScreen design polish', () {
    testWidgets('hero, checklist and action card share one card style', (
      WidgetTester tester,
    ) async {
      final FakeCloudBackend backend = FakeCloudBackend();
      await _pumpSignIn(tester, SignInScreen(backend: backend));

      expect(find.text('Optional Cloud Backup'), findsOneWidget);
      expect(find.text('What signing in does'), findsOneWidget);
      expect(find.text('Local data stays on this phone'), findsOneWidget);
      expect(
        find.byKey(const Key('continue-with-google-button')),
        findsOneWidget,
      );
      // Not pushed here, so there is nothing to go back to and no quiet exit.
      expect(find.byKey(const Key('sign-in-not-now-button')), findsNothing);
      expect(tester.takeException(), isNull);

      await backend.dispose();
    });

    testWidgets('progress is inline and never a dialog', (
      WidgetTester tester,
    ) async {
      final FakeCloudBackend backend = FakeCloudBackend();
      final Completer<CloudUser?> pending = Completer<CloudUser?>();
      backend.onSignInWithGoogle = () => pending.future;
      await _pumpSignIn(tester, SignInScreen(backend: backend));

      await tester.ensureVisible(
        find.byKey(const Key('continue-with-google-button')),
      );
      await tester.pumpAndSettle();
      await _tapContinue(tester);
      await tester.pump();

      expect(find.byKey(const Key('sign-in-progress')), findsOneWidget);
      expect(find.text('Signing in…'), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(Dialog), findsNothing);

      pending.complete(null);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('sign-in-progress')), findsNothing);

      await backend.dispose();
    });
  });
}
