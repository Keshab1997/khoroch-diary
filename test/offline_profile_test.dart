import 'package:drift/native.dart';
// Flutter 3.50 deprecates this import; migrate with the app's dependency update.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:khoroch_diary/core/l10n/app_strings.dart';
import 'package:khoroch_diary/features/ledger/data/local_ledger.dart';
import 'package:khoroch_diary/features/profile/profile_screen.dart';
import 'package:khoroch_diary/features/profile/profile_store.dart';
import 'package:khoroch_diary/features/profile/settings_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('profile forwards language and callback to settings', (
    tester,
  ) async {
    Future<bool> change(AppLanguage language) async => true;
    await tester.pumpWidget(
      MaterialApp(
        home: ProfileScreen(
          language: AppLanguage.bn,
          onLanguageChanged: change,
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('profile-app-settings-gear')));
    await tester.pumpAndSettle();
    final settings = tester.widget<SettingsScreen>(find.byType(SettingsScreen));
    expect(settings.language, AppLanguage.bn);
    expect(settings.onLanguageChanged, same(change));
  });

  test('name persists in the same local database', () async {
    final ledger = LocalLedger(NativeDatabase.memory());
    addTearDown(ledger.close);
    final first = ProfileStore(ledger);
    await first.save(LocalProfile(name: '  বাংলা  '));
    final second = ProfileStore(ledger);
    expect((await second.load()).name, 'বাংলা');
  });

  testWidgets('Bengali profile shows localized profile and menu copy', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      const MaterialApp(home: ProfileScreen(language: AppLanguage.bn)),
    );
    expect(find.text('স্থানীয় প্রোফাইল'), findsOneWidget);
    expect(find.text('এই ডিভাইসে সংরক্ষিত'), findsOneWidget);
    expect(find.text('অ্যাপ সেটিংস'), findsOneWidget);
    expect(find.text('খরচের ডায়েরি সম্পর্কে'), findsOneWidget);
  });
}
