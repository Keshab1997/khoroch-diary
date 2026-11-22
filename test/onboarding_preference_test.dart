import 'package:flutter_test/flutter_test.dart';
import 'package:khoroch_diary/core/l10n/onboarding_preference.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('a fresh install is considered not onboarded', () async {
    expect(await loadOnboardingCompleted(), isFalse);
  });

  test('completion persists on this device', () async {
    expect(await saveOnboardingCompleted(), isTrue);
    expect(await loadOnboardingCompleted(), isTrue);
  });
}
