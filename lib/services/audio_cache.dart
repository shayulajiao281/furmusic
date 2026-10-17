import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

class AudioCache {
  static Directory? _cacheDir;

  /// 正在下载中的 songId
  static final Set<String> _downloading = {};

  /// songId → 已完成缓存（内存索引，加速 get）
  static final Map<String, int> _completeIndex = {};

  /// songId → 缓存完整文件路径（避免重复 statSync）
  static final Map<String, String> _pathIndex = {};

  /// 把 songId 里的非法字符转掉
  static String _safeName(String songId) {
    return songId
        .replaceAll(':', '_')
        .replaceAll('/', '_')
        .replaceAll('\\', '_')
        .replaceAll('?', '_')
        .replaceAll('*', '_');
  }

  static Future<Directory> _dir() async {
    if (_cacheDir != null) return _cacheDir!;
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/audio_cache');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    _cacheDir = dir;
    return dir;
  }

  /// ★ 启动时扫一遍已有缓存，建立内存索引
  ///   在 main.dart 里调一次
  static Future<void> init() async {
    final dir = await _dir();
    _completeIndex.clear();
    _pathIndex.clear();

    int count = 0;
    await for (final e in dir.list()) {
      if (e is! File) continue;
      if (e.path.endsWith('.part')) continue;

      try {
        final len = e.statSync().size;
        if (len < 1024) {
          e.deleteSync();
          continue;
        }
        // 文件头校验
        if (!_isAudioHead(e)) {
          print('⚠️ [cache] 删除坏文件: ${e.path}');
          e.deleteSync();
          continue;
        }
        final name = e.path.split(Platform.pathSeparator).last;
        _completeIndex[name] = len;
        _pathIndex[name] = e.path;
        count++;
      } catch (_) {}
    }
    print('📦 [cache] 已索引 $count 个有效缓存');
  }

  /// 读文件头，判断是不是音频
  static bool _isAudioHead(File f) {
    try {
      final raf = f.openSync();
      final len = f.lengthSync();
      final readLen = len > 64 ? 64 : len;
      final bytes = raf.readSync(readLen);
      raf.closeSync();
      if (bytes.isEmpty) return false;

      final head = String.fromCharCodes(bytes).toLowerCase();
      // HTML / JSON 明显不是音频
      if (head.contains('<html') ||
          head.contains('<!doctype') ||
          head.contains('<?xml') ||
          head.contains('{"') ||
          head.contains('{"code"') ||
          head.contains('{"error"')) {
        return false;
      }

      // 常见音频格式的 magic number
      // MP3: ID3 或 0xFF 0xFB/0xF3/0xF2/0xFA
      // M4A/MP4: 00 00 00 xx 66 74 79 70 ('ftyp')
      // FLAC: 'fLaC'
      // WAV: 'RIFF'
      // OGG: 'OggS'
      if (bytes.length >= 4) {
        final b0 = bytes[0];
        final b1 = bytes[1];
        final b2 = bytes[2];
        final b3 = bytes[3];

        // fLaC
        if (b0 == 0x66 && b1 == 0x4C && b2 == 0x61 && b3 == 0x43) return true;
        // OggS
        if (b0 == 0x4F && b1 == 0x67 && b2 == 0x67 && b3 == 0x53) return true;
        // RIFF
        if (b0 == 0x52 && b1 == 0x49 && b2 == 0x46 && b3 == 0x46) return true;
        // ftyp (M4A/MP4)
        if (bytes.length >= 8) {
          if (bytes[4] == 0x66 && bytes[5] == 0x74 && bytes[6] == 0x79 && bytes[7] == 0x70) {
            return true;
          }
        }
        // ID3 (MP3)
        if (b0 == 0x49 && b1 == 0x44 && b2 == 0x33) return true;
        // MP3 sync word
        if (b0 == 0xFF && (b1 & 0xE0) == 0xE0) return true;
      }

      // 拿不准就当能用
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 查缓存：只返回**已完整下载**的
  static Future<String?> get(String songId) async {
    final safe = _safeName(songId);

    // 内存索引命中
    final path = _pathIndex[safe];
    if (path != null) {
      final f = File(path);
      if (f.existsSync() && f.lengthSync() > 1024) {
        return path;
      }
      // 索引失效
      _pathIndex.remove(safe);
      _completeIndex.remove(safe);
    }

    // 磁盘查找
    final dir = await _dir();
    final file = File('${dir.path}/$safe');
    if (!file.existsSync()) return null;

    final len = file.lengthSync();
    if (len < 1024) {
      try { file.deleteSync(); } catch (_) {}
      return null;
    }

    if (!_isAudioHead(file)) {
      print('⚠️ [cache] 文件头非音频，删除: $safe');
      try { file.deleteSync(); } catch (_) {}
      return null;
    }

    _completeIndex[safe] = len;
    _pathIndex[safe] = file.path;
    return file.path;
  }

  /// 检查是否已完整缓存
  static bool isComplete(String songId) {
    return _pathIndex.containsKey(_safeName(songId));
  }

  /// 检查是否正在下载
  static bool isDownloading(String songId) {
    return _downloading.contains(songId);
  }

  /// 后台下载（原子：先 .part，完成后 rename）
  static Future<void> download(
    String songId,
    String url, {
    Map<String, String>? headers,
  }) async {
    if (_downloading.contains(songId)) return;
    if (isComplete(songId)) return; // 已完整缓存，不重复下

    _downloading.add(songId);

    final safe = _safeName(songId);
    final dir = await _dir();
    final tmpFile = File('${dir.path}/$safe.part');
    final finalFile = File('${dir.path}/$safe');

    // 清掉可能残留的 .part
    try {
      if (tmpFile.existsSync()) tmpFile.deleteSync();
    } catch (_) {}

    try {
      final request = http.Request('GET', Uri.parse(url));
      if (headers != null) request.headers.addAll(headers);

      final response = await http.Client()
          .send(request)
          .timeout(const Duration(minutes: 5));

      if (response.statusCode != 200) {
        print('❌ [cache] HTTP ${response.statusCode}: $songId');
        return;
      }

      final sink = tmpFile.openWrite();
      await response.stream.pipe(sink);
      await sink.close();

      final len = tmpFile.lengthSync();
      if (len < 1024) {
        print('❌ [cache] 文件太小 ($len): $songId');
        try { tmpFile.deleteSync(); } catch (_) {}
        return;
      }

      // 校验文件头
      if (!_isAudioHead(tmpFile)) {
        print('❌ [cache] 文件头非音频，删除: $songId');
        try { tmpFile.deleteSync(); } catch (_) {}
        return;
      }

      // 原子重命名
      await tmpFile.rename(finalFile.path);

      _completeIndex[safe] = len;
      _pathIndex[safe] = finalFile.path;

      print('📥 [cache] 已缓存: $songId (${len ~/ 1024} KB)');
    } catch (e) {
      print('❌ [cache] 下载异常: $e');
      try {
        if (tmpFile.existsSync()) tmpFile.deleteSync();
      } catch (_) {}
    } finally {
      _downloading.remove(songId);
    }
  }

  /// 清空所有缓存
  static Future<void> clear() async {
    final dir = await _dir();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
    _cacheDir = null;
    _completeIndex.clear();
    _pathIndex.clear();
    _downloading.clear();
  }

  /// 缓存占用大小
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

    final files = <File>[];
    await for (final e in dir.list()) {
      if (e is File) files.add(e);
    }

    files.sort((a, b) =>
        a.statSync().modified.compareTo(b.statSync().modified));

    int total = 0;
    for (final f in files) {
      total += f.statSync().size;
    }

    int idx = 0;
    while (total > maxBytes && idx < files.length) {
      final f = files[idx];
      total -= f.statSync().size;
      try {
        f.deleteSync();
        final name = f.path.split(Platform.pathSeparator).last;
        _completeIndex.remove(name);
        _pathIndex.remove(name);
      } catch (_) {}
      idx++;
    }
  }
}