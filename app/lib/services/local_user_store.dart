import 'package:shared_preferences/shared_preferences.dart';

/// Persists the local PayFlex user id across app launches so we never
/// re-run user creation on relaunch — per the build brief, recreating a
/// BMONI user forks wallet history. This is checked before ever calling
/// the backend's POST /users endpoint.
class LocalUserStore {
  static const _appUserIdKey = 'payflex.appUserId';
  static const _introSeenKey = 'payflex.introSeen';

  Future<String?> getAppUserId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_appUserIdKey);
  }

  Future<void> setAppUserId(String appUserId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_appUserIdKey, appUserId);
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_appUserIdKey);
    await prefs.remove(_introSeenKey);
  }

  /// Intro carousel: shown once per install (before account creation).
  /// Cleared on sign-out so a fresh start re-introduces the app.
  Future<bool> hasSeenIntro() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_introSeenKey) ?? false;
  }

  Future<void> setIntroSeen() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_introSeenKey, true);
  }
}
