import 'package:shared_preferences/shared_preferences.dart';

/// Device-only preference. Onboarding never contains or syncs ledger data.
const String kOnboardingCompletedPreferenceKey = 'onboarding_completed';

/// A missing or unreadable preference means a first launch.
Future<bool> loadOnboardingCompleted() async {
  try {
    final SharedPreferences preferences = await SharedPreferences.getInstance();
    return preferences.getBool(kOnboardingCompletedPreferenceKey) ?? false;
  } catch (_) {
    return false;
  }
}

/// Persist completion after Skip or Start. Returns false if local storage fails.
Future<bool> saveOnboardingCompleted() async {
  try {
    final SharedPreferences preferences = await SharedPreferences.getInstance();
    return await preferences.setBool(kOnboardingCompletedPreferenceKey, true);
  } catch (_) {
    return false;
  }
}
