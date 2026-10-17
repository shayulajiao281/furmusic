import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

class LyricCache {
  static Directory? _dir;

  static Future<Directory> _ensureDir() async {
    if (_dir != null) return _dir!;
    final support = await getApplicationSupportDirectory();
    final dir = Directory('${support.path}/lyric_cache');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    _dir = dir;
    return dir;
  }

  static String _safe(String id) => id
      .replaceAll(':', '_')
      .replaceAll('/', '_')
      .replaceAll('\\', '_')
      .replaceAll('?', '_')
      .replaceAll('*', '_');

  static Future<void> save(
    String songId,
    List<MapEntry<double, String>> lyric,
  ) async {
    if (lyric.isEmpty) return;
    try {
      final dir = await _ensureDir();
      final file = File('${dir.path}/${_safe(songId)}.json');
      final data = lyric.map((e) => [e.key, e.value]).toList();
      await file.writeAsString(jsonEncode(data));
    } catch (_) {}
  }

  static Future<List<MapEntry<double, String>>> load(String songId) async {
    try {
      final dir = await _ensureDir();
      final file = File('${dir.path}/${_safe(songId)}.json');
      if (!file.existsSync()) return [];
      final raw = await file.readAsString();
      final data = jsonDecode(raw) as List;
      return data.map((e) {
        final list = e as List;
        return MapEntry((list[0] as num).toDouble(), list[1] as String);
      }).toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> clear() async {
    final dir = await _ensureDir();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
    _dir = null;
  }
}