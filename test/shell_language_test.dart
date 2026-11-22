import 'package:drift/native.dart';
// Flutter 3.50 deprecates this import; migrate with the app's dependency update.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:khoroch_diary/app.dart';
import 'package:khoroch_diary/core/l10n/app_strings.dart';
import 'package:khoroch_diary/core/l10n/language_preference.dart';
import 'package:khoroch_diary/features/calculator/calculator_screen.dart';
import 'package:khoroch_diary/features/home/home_screen.dart';
import 'package:khoroch_diary/features/ledger/data/local_ledger.dart';
import 'package:khoroch_diary/features/profile/profile_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('a saved Bengali choice reaches the tabs and every screen', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      kLanguagePreferenceKey: 'bn',
    });
    final AppLanguage language = await loadLanguagePreference();
    expect(language, AppLanguage.bn);

    final LocalLedger ledger = LocalLedger(NativeDatabase.memory());
    await tester.runAsync(() => ledger.initialize());
    await tester.pumpWidget(
      KhorochDiaryApp(ledger: ledger, initialLanguage: language),
    );
    await tester.pumpAndSettle();

    final NavigationBar bar = tester.widget(find.byType(NavigationBar));
    expect(
      bar.destinations.map((Widget d) => (d as NavigationDestination).label),
      <String>['মূল পাতা', 'ক্যালকুলেটর', 'গণনা', 'প্রোফাইল'],
    );
    expect(
      tester.widget<HomeScreen>(find.byType(HomeScreen)).language,
      AppLanguage.bn,
    );
    expect(
      tester
          .widget<CalculatorScreen>(
            find.byType(CalculatorScreen, skipOffstage: false),
          )
          .language,
      AppLanguage.bn,
    );
    final ProfileScreen profile = tester.widget(
      find.byType(ProfileScreen, skipOffstage: false),
    );
    expect(profile.language, AppLanguage.bn);
    expect(profile.profileStore, isNotNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('choosing a language saves it before the shell switches', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final LocalLedger ledger = LocalLedger(NativeDatabase.memory());
    await tester.runAsync(() => ledger.initialize());
    await tester.pumpWidget(KhorochDiaryApp(ledger: ledger));
    await tester.pumpAndSettle();
    final NavigationBar before = tester.widget(find.byType(NavigationBar));
    expect((before.destinations.first as NavigationDestination).label, 'Home');

    final ProfileScreen profile = tester.widget(
      find.byType(ProfileScreen, skipOffstage: false),
    );
    final Future<bool> committed = profile.onLanguageChanged!(AppLanguage.bn);
    await tester.pumpAndSettle();
    expect(await committed, isTrue);

    final SharedPreferences prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(kLanguagePreferenceKey), 'bn');
    final NavigationBar after = tester.widget(find.byType(NavigationBar));
    expect(
      (after.destinations.first as NavigationDestination).label,
      'মূল পাতা',
    );
    expect(
      tester
          .widget<ProfileScreen>(
            find.byType(ProfileScreen, skipOffstage: false),
          )
          .language,
      AppLanguage.bn,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test('an unknown saved code falls back to English', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{
      kLanguagePreferenceKey: 'xx',
    });
    expect(await loadLanguagePreference(), AppLanguage.en);
  });
}
