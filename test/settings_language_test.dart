import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
// Flutter 3.50 deprecates this import; migrate with the app's dependency update.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:khoroch_diary/core/l10n/app_strings.dart';
import 'package:khoroch_diary/features/profile/settings_screen.dart';

const _changeKey = Key('settings-change-language');
const _backupKey = Key('settings-storage-row');
const _en = AppStrings();
const _bn = AppStrings(AppLanguage.bn);

Future<void> _pump(
  WidgetTester tester,
  Widget screen, {
  bool small = false,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = small
      ? const Size(320, 568)
      : const Size(400, 1600);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(small ? 2 : 1)),
        child: child!,
      ),
      home: screen,
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _open(WidgetTester tester) async {
  final change = find.byKey(_changeKey);
  await tester.ensureVisible(change);
  await tester.pumpAndSettle();
  await tester.tap(change);
  await tester.pumpAndSettle();
}

Future<void> _selectBengali(WidgetTester tester) async {
  await _open(tester);
  await tester.tap(find.text('বাংলা'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('web preview is read-only even with a callback', (tester) async {
    var calls = 0;
    await _pump(
      tester,
      SettingsScreen(
        onLanguageChanged: (_) async {
          calls++;
          return true;
        },
      ),
      small: true,
    );
    expect(find.text(_en.text(AppString.webSettings)), findsOneWidget);
    expect(find.byKey(_changeKey), findsNothing);
    expect(find.byKey(_backupKey), findsNothing);
    expect(calls, 0);
    expect(tester.takeException(), isNull);
  }, skip: !kIsWeb);

  testWidgets(
    'unwired settings show concise fixed values and backup guidance',
    (tester) async {
      await _pump(tester, const SettingsScreen());
      expect(find.text('English'), findsOneWidget);
      expect(find.text('Read-only in this build'), findsNothing);
      expect(find.byKey(_changeKey), findsNothing);
      expect(find.text('INR (₹)'), findsOneWidget);
      expect(find.text('Light'), findsOneWidget);
      expect(find.text('Fixed in v1'), findsNothing);
      expect(find.textContaining('cloud sync are unavailable'), findsNothing);
      expect(find.byKey(_backupKey), findsOneWidget);
      expect(find.text('Your data'), findsOneWidget);
      expect(find.text('Back up or restore from Profile.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
    skip: kIsWeb,
  );

  testWidgets(
    'only the caller can change the committed language after saving',
    (tester) async {
      final save = Completer<bool>();
      final choices = <AppLanguage>[];
      var committed = AppLanguage.en;
      await _pump(
        tester,
        StatefulBuilder(
          builder: (context, setState) {
            return SettingsScreen(
              language: committed,
              onLanguageChanged: (choice) async {
                choices.add(choice);
                final saved = await save.future;
                if (saved) setState(() => committed = choice);
                return saved;
              },
            );
          },
        ),
      );
      await _selectBengali(tester);
      expect(choices, [AppLanguage.bn]);
      expect(find.text('English'), findsOneWidget);
      expect(find.text(_en.text(AppString.languagePending)), findsOneWidget);
      expect(
        tester.widget<OutlinedButton>(find.byKey(_changeKey)).onPressed,
        isNull,
      );
      save.complete(true);
      await tester.pumpAndSettle();
      expect(find.text(_bn.text(AppString.appSettings)), findsOneWidget);
      expect(find.text('বাংলা'), findsOneWidget);
      expect(find.text(_en.text(AppString.languagePending)), findsNothing);
    },
    skip: kIsWeb,
  );

  testWidgets(
    'picker cancellation and current choice never invoke the callback',
    (tester) async {
      var calls = 0;
      await _pump(
        tester,
        SettingsScreen(
          onLanguageChanged: (_) async {
            calls++;
            return true;
          },
        ),
      );
      await _open(tester);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await _open(tester);
      await tester.tap(
        find.descendant(
          of: find.byType(SimpleDialog),
          matching: find.text('English'),
        ),
      );
      await tester.pumpAndSettle();
      expect(calls, 0);
      expect(find.text('English'), findsOneWidget);
    },
    skip: kIsWeb,
  );

  testWidgets(
    'cancelled and failed callbacks keep the last language and allow retry',
    (tester) async {
      var calls = 0;
      await _pump(
        tester,
        SettingsScreen(
          onLanguageChanged: (_) async {
            if (++calls == 1) return false;
            throw StateError('raw persistence detail');
          },
        ),
      );
      await _selectBengali(tester);
      expect(find.text('English'), findsOneWidget);
      expect(find.text(_en.text(AppString.languageFailed)), findsNothing);
      await _selectBengali(tester);
      expect(calls, 2);
      expect(find.text('English'), findsOneWidget);
      expect(find.text(_en.text(AppString.languageFailed)), findsOneWidget);
      expect(find.textContaining('raw persistence detail'), findsNothing);
      expect(
        tester.widget<OutlinedButton>(find.byKey(_changeKey)).onPressed,
        isNotNull,
      );
    },
    skip: kIsWeb,
  );

  testWidgets('320dp at 200% text: language picker stays usable', (
    tester,
  ) async {
    await _pump(
      tester,
      SettingsScreen(onLanguageChanged: (_) async => false),
      small: true,
    );
    await tester.scrollUntilVisible(find.byKey(_changeKey), 120);
    await _selectBengali(tester);
    expect(find.text(_en.text(AppString.appSettings)), findsOneWidget);
    expect(find.text('English'), findsOneWidget);
    expect(tester.takeException(), isNull);
  }, skip: kIsWeb);
}
