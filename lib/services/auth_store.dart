import 'package:shared_preferences/shared_preferences.dart';

class AuthStore {
  static SharedPreferences? _prefs;

  /// 在 main.dart 里调用一次
  static void attach(SharedPreferences prefs) {
    _prefs = prefs;
  }

  static String _key(String source) => 'cookie_$source';

  static String? getCookie(String source) {
    final raw = _prefs?.getString(_key(source));
    if (raw == null || raw.trim().isEmpty) return null;
    return raw.trim();
  }

  static bool isLoggedIn(String source) => getCookie(source) != null;

  static Future<void> saveCookie(String source, String cookie) async {
    final v = cookie.trim();
    if (v.isEmpty) {
      await _prefs?.remove(_key(source));
    } else {
      await _prefs?.setString(_key(source), v);
    }
  }

  static Future<void> clearCookie(String source) async {
    await _prefs?.remove(_key(source));
  }

  /// 未登录时的最小默认 cookie
  static String defaultCookie(String source) {
    switch (source) {
      case 'netease':
        return 'appver=8.7.01; os=pc;';
      default:
        return '';
    }
  }

  /// 各音源拿它当最终 cookie：用户登录优先，否则回落默认
  static String cookieFor(String source) {
    final custom = getCookie(source);
    if (custom != null && custom.isNotEmpty) return custom;
    return defaultCookie(source);
  }
}
