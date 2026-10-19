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
    // ★ 修改目录名称，直接抛弃历史损坏的图片缓存
    final dir = Directory('${support.path}/image_cache_v4');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    _cacheDir = dir;
    return dir;
  }

  static Future<void> init() async {
    final dir = await _dir();
    _index.clear();
    await for (final e in dir.list()) {
      if (e is File && !e.path.endsWith('.part')) {
        // 剔除小于 1KB 的无效文件
        if (e.lengthSync() > 1024) {
          final name = e.path.split(Platform.pathSeparator).last;
          _index[name] = e;
        } else {
          try { e.deleteSync(); } catch (_) {}
        }
      }
    }
    print('🖼️ [imgcache] 已索引 ${_index.length} 张封面');
  }

  static File? getCached(String url) {
    if (url.isEmpty) return null;
    if (!url.startsWith('http')) {
      final f = File(url);
      return f.existsSync() ? f : null;
    }
    final hash = _hash(url);
    final f = _index[hash];
    if (f != null && f.existsSync()) {
      // 校验大小，防止读到下载了一半的坏图
      if (f.lengthSync() > 1024) {
        return f;
      } else {
        try { f.deleteSync(); } catch (_) {}
        _index.remove(hash);
      }
    }
    return null;
  }

  static Future<File?> get(String url) async {
    if (url.isEmpty) return null;
    if (!url.startsWith('http')) {
      final f = File(url);
      return f.existsSync() ? f : null;
    }

    final hash = _hash(url);
    final cached = _index[hash];
    if (cached != null && cached.existsSync() && cached.lengthSync() > 1024) {
      return cached;
    }

    final dir = await _dir();
    final file = File('${dir.path}/$hash');
    if (file.existsSync() && file.lengthSync() > 1024) {
      _index[hash] = file;
      return file;
    }

    if (_downloading.contains(hash)) return null;
    _downloading.add(hash);

    final client = http.Client();
    try {
      final request = http.Request('GET', Uri.parse(url));
      request.headers.addAll({
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        'Accept': 'image/avif,image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8',
      });
      
      if (url.contains('126.net') || url.contains('163.com')) {
        request.headers['Referer'] = 'https://music.163.com/';
      } else if (url.contains('qq.com') || url.contains('gtimg.cn')) {
        request.headers['Referer'] = 'https://y.qq.com/';
      } else if (url.contains('kugou.com')) {
        request.headers['Referer'] = 'https://www.kugou.com/';
      } else if (url.contains('hdslb.com')) {
        request.headers['Referer'] = 'https://www.bilibili.com/';
      }

      final response = await client.send(request).timeout(const Duration(seconds: 15));
      
      if (response.statusCode != 200) {
        print('❌ [imgcache] HTTP ${response.statusCode} for $url');
        return null;
      }

      final contentType = response.headers['content-type']?.toLowerCase() ?? '';
      if (contentType.contains('text/html') || contentType.contains('application/json')) {
        print('❌ [imgcache] 返回内容不是图片 ($contentType): $url');
        return null;
      }

      final bytes = await response.stream.toBytes();
      
      if (bytes.length < 1024) {
        print('❌ [imgcache] 图片太小 (${bytes.length} bytes): $url');
        return null;
      }

      await file.writeAsBytes(bytes);
      _index[hash] = file;
      print('🖼️ [imgcache] 已缓存: ${url.split("/").last}');
      return file;
    } catch (e) {
      print('❌ [imgcache] 下载失败: $e');
      return null;
    } finally {
      client.close();
      _downloading.remove(hash);
    }
  }

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
    files.sort((a, b) => a.statSync().modified.compareTo(b.statSync().modified));
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