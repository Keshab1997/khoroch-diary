// Flutter 3.50 deprecates this import; migrate with the app's dependency update.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:khoroch_diary/app.dart';
import 'package:khoroch_diary/core/l10n/onboarding_preference.dart';
import 'package:khoroch_diary/features/ledger/data/local_ledger.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('first-run gate opens the app after Skip and remembers it', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final LocalLedger ledger = LocalLedger(NativeDatabase.memory());
    await ledger.initialize();

    await tester.pumpWidget(
      KhorochDiaryApp(ledger: ledger, showOnboarding: true),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('onboarding-screen')), findsOneWidget);

    await tester.tap(find.byKey(const Key('onboarding-skip-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('onboarding-screen')), findsNothing);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(await loadOnboardingCompleted(), isTrue);

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
