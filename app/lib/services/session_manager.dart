import 'package:shared_preferences/shared_preferences.dart';
import 'api_client.dart';
import 'wallet_service.dart';

/// Owns the login lifecycle on top of the on-device owner key: performing
/// a full challenge-response login (needs the PIN, since it must sign with
/// WalletService), silently restoring a session from a persisted refresh
/// token (no PIN needed), and logging out. ApiClient.accessToken/
/// refreshToken are the in-memory session; this class is the only thing
/// that should read/write [_refreshTokenKey] in SharedPreferences.
class SessionManager {
  static const _refreshTokenKey = 'payflex.refreshToken';

  /// Full login: request a challenge, sign it on-device with [pin], submit
  /// it, then persist the resulting refresh token so the next cold start
  /// can skip straight to [tryRestoreSession].
  static Future<void> login(String appUserId, String pin) async {
    final api = ApiClient();
    final message = await api.requestLoginChallenge(appUserId);
    final signature = await WalletService.signChallenge(message, pin);
    await api.login(appUserId, signature);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_refreshTokenKey, ApiClient.refreshToken!);
  }

  /// Tries to resume a session from the refresh token persisted on a
  /// previous [login], with no PIN prompt. Returns false (and leaves
  /// ApiClient's tokens cleared) if there's no stored token or the backend
  /// rejects it (expired/revoked) — callers should fall back to a
  /// PIN-triggered [login] in that case.
  static Future<bool> tryRestoreSession() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_refreshTokenKey);
    if (stored == null) return false;
    ApiClient.refreshToken = stored;
    final api = ApiClient();
    final ok = await api.tryRefresh();
    if (!ok) {
      ApiClient.clearSession();
      await prefs.remove(_refreshTokenKey);
      return false;
    }
    await prefs.setString(_refreshTokenKey, ApiClient.refreshToken!);
    return true;
  }

  static Future<void> logout() async {
    ApiClient.clearSession();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_refreshTokenKey);
  }
}
