import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

class ImageCacheManager {
  static Directory? _cacheDir;
  static final Map<String, File> _index = {};
  static final Set<String> _downloading = {};

  static String _hash(String url) => md5.convert(utf8.encode(url)).toString();

  static Future<Directory> _dir() async {
    if (_cacheDir != null) return _cacheDir!;
    final support = await getApplicationSupportDirectory();
    final dir = Directory('${support.path}/image_cache');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    _cacheDir = dir;
    return dir;
  }

  static Future<void> init() async {
    final dir = await _dir();
    _index.clear();
    await for (final e in dir.list()) {
      if (e is File && !e.path.endsWith('.part')) {
        final name = e.path.split(Platform.pathSeparator).last;
        _index[name] = e;
      }
    }
    print('🖼️ [imgcache] 已索引 ${_index.length} 张封面');
  }

  /// ★ 只查缓存，离线友好
  static File? getCached(String url) {
    if (url.isEmpty) return null;
    if (!url.startsWith('http')) {
      final f = File(url);
      return f.existsSync() ? f : null;
    }
    final hash = _hash(url);
    final f = _index[hash];
    if (f != null && f.existsSync() && f.lengthSync() > 128) return f;
    return null;
  }

  /// 加载：优先缓存，其次下载
  static Future<File?> get(String url) async {
    if (url.isEmpty) return null;
    if (!url.startsWith('http')) {
      final f = File(url);
      return f.existsSync() ? f : null;
    }

    final hash = _hash(url);
    final cached = _index[hash];
    if (cached != null && cached.existsSync() && cached.lengthSync() > 128) {
      return cached;
    }

    final dir = await _dir();
    final file = File('${dir.path}/$hash');
    if (file.existsSync() && file.lengthSync() > 128) {
      _index[hash] = file;
      return file;
    }

    if (_downloading.contains(hash)) return null;
    _downloading.add(hash);

    try {
      final res = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 20));
      if (res.statusCode != 200) {
        print('❌ [imgcache] HTTP ${res.statusCode}');
        return null;
      }
      if (res.bodyBytes.length < 128) return null;
      await file.writeAsBytes(res.bodyBytes);
      _index[hash] = file;
      print('🖼️ [imgcache] 已缓存: ${url.split("/").last}');
      return file;
    } catch (e) {
      print('❌ [imgcache] 下载失败: $e');
      return null;
    } finally {
      _downloading.remove(hash);
    }
  }

  /// 后台预缓存
  static void prefetch(String url) {
    if (url.isEmpty || !url.startsWith('http')) return;
    get(url).catchError((_) => null);
  }

  static Future<void> trim({int maxBytes = 200 * 1024 * 1024}) async {
    final dir = await _dir();
    if (!dir.existsSync()) return;
    final files = <File>[];
    await for (final e in dir.list()) {
      if (e is File) files.add(e);
    }
    files.sort(
      (a, b) => a.statSync().modified.compareTo(b.statSync().modified),
    );
    int total = files.fold(0, (s, f) => s + f.statSync().size);
    int idx = 0;
    while (total > maxBytes && idx < files.length) {
      final f = files[idx];
      total -= f.statSync().size;
      try {
        final name = f.path.split(Platform.pathSeparator).last;
        f.deleteSync();
        _index.remove(name);
      } catch (_) {}
      idx++;
    }
  }
}