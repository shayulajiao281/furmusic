import 'dart:math';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

/// 生成并持久化设备指纹，模拟真实设备的稳定标识
class DeviceFingerprint {
  static const _kGuidKey = 'device_guid';
  static const _kQimeiKey = 'device_qimei';
  static const _kQimei36Key = 'device_qimei36';

  static String? _guid;
  static String? _qimei;
  static String? _qimei36;

  /// App 启动时调用一次
  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();

    _guid = prefs.getString(_kGuidKey);
    _qimei = prefs.getString(_kQimeiKey);
    _qimei36 = prefs.getString(_kQimei36Key);

    bool dirty = false;

    if (_guid == null || _guid!.isEmpty) {
      _guid = const Uuid().v4().replaceAll('-', '');
      await prefs.setString(_kGuidKey, _guid!);
      dirty = true;
    }

    if (_qimei == null || _qimei!.isEmpty) {
      _qimei = _randomHex(32);
      await prefs.setString(_kQimeiKey, _qimei!);
      dirty = true;
    }

    if (_qimei36 == null || _qimei36!.isEmpty) {
      _qimei36 = _randomHex(36);
      await prefs.setString(_kQimei36Key, _qimei36!);
      dirty = true;
    }

    if (dirty) {
      print('📱 [指纹] 已生成并持久化: guid=$_guid');
    } else {
      print('📱 [指纹] 已加载: guid=$_guid');
    }
  }

  static String get guid => _guid ?? '';
  static String get qimei => _qimei ?? '';
  static String get qimei36 => _qimei36 ?? '';

  /// 获取 Android ID（如果能拿到，更真实）
  static Future<String?> androidId() async {
    try {
      final info = DeviceInfoPlugin();
      final android = await info.androidInfo;
      return android.id;
    } catch (_) {
      return null;
    }
  }

  static String _randomHex(int length) {
    final random = Random.secure();
    final sb = StringBuffer();
    for (var i = 0; i < length; i++) {
      sb.write(random.nextInt(16).toRadixString(16));
    }
    return sb.toString();
  }
}
