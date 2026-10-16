import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

class AudioCache {
  static Directory? _cacheDir;

  /// 正在下载中的歌曲 id（防重复下载）
  static final Set<String> _downloading = {};

  /// ★ 把 songId 里的非法字符转掉
  ///   songId 形如 "qq:003ggnKE2wLuAx"、"bilibili:BVxxx"、"local:12345"
  ///   冒号在某些 Uri 解析里会被当成 scheme 分隔符，导致 "No host specified"
  static String _safeName(String songId) {
    return songId
        .replaceAll(':', '_')
        .replaceAll('/', '_')
        .replaceAll('\\', '_')
        .replaceAll('?', '_')
        .replaceAll('*', '_');
  }

  /// 初始化缓存目录
  static Future<Directory> _dir() async {
    if (_cacheDir != null) return _cacheDir!;
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/audio_cache');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    _cacheDir = dir;
    return dir;
  }

  /// 查缓存：有返回本地路径，没有返回 null
  static Future<String?> get(String songId) async {
    final dir = await _dir();
    final file = File('${dir.path}/${_safeName(songId)}');
    if (file.existsSync() && file.lengthSync() > 1024) {
      return file.path;
    }
    return null;
  }

  /// 后台下载并缓存（不阻塞播放）
  static Future<void> download(
    String songId,
    String url, {
    Map<String, String>? headers,
  }) async {
    if (_downloading.contains(songId)) return;
    _downloading.add(songId);

    try {
      final dir = await _dir();
      final safe = _safeName(songId);
      final tmpFile = File('${dir.path}/$safe.part');
      final finalFile = File('${dir.path}/$safe');

      final request = http.Request('GET', Uri.parse(url));
      if (headers != null) request.headers.addAll(headers);

      final response = await http.Client()
          .send(request)
          .timeout(const Duration(minutes: 5));

      if (response.statusCode != 200) {
        print('❌ 缓存下载失败: HTTP ${response.statusCode}');
        return;
      }

      final sink = tmpFile.openWrite();
      await response.stream.pipe(sink);
      await sink.close();

      if (await tmpFile.length() > 1024) {
        await tmpFile.rename(finalFile.path);
        print('📥 已缓存: $songId (${(await finalFile.length() ~/ 1024)} KB)');
      } else {
        await tmpFile.delete();
      }
    } catch (e) {
      print('❌ 缓存异常: $e');
    } finally {
      _downloading.remove(songId);
    }
  }

  /// 清空所有缓存
  static Future<void> clear() async {
    final dir = await _dir();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
    _cacheDir = null;
  }

  /// 缓存占用大小（字节）
  static Future<int> size() async {
    final dir = await _dir();
    if (!dir.existsSync()) return 0;
    int total = 0;
    await for (final e in dir.list()) {
      if (e is File) total += await e.length();
    }
    return total;
  }

  /// 按大小限制清理（超过 maxBytes 时删最老的文件）
  static Future<void> trim({int maxBytes = 500 * 1024 * 1024}) async {
    final dir = await _dir();
    if (!dir.existsSync()) return;

    final files = <FileSystemEntity>[];
    await for (final e in dir.list()) {
      if (e is File) files.add(e);
    }

    final fileList = files.cast<File>().toList()
      ..sort((a, b) => a.statSync().modified.compareTo(b.statSync().modified));

    int total = 0;
    for (final f in fileList) {
      total += f.statSync().size;
    }

    int idx = 0;
    while (total > maxBytes && idx < fileList.length) {
      total -= fileList[idx].statSync().size;
      fileList[idx].deleteSync();
      idx++;
    }
  }
}