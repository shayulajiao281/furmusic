import 'dart:async';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

class AudioCache {
  static Directory? _cacheDir;

  static final Map<String, int> _completeIndex = {};
  static final Map<String, String> _pathIndex = {};

  static final Set<String> _downloading = {};
  static final Map<String, Future<void>> _downloadFutures = {};

  static final Map<String, double> _progressMap = {};
  static final StreamController<String> _progressUpdates =
      StreamController<String>.broadcast();
  static final Set<String> _pendingNotify = {};

  // ═══════════════════════════════════════════
  // 工具
  // ═══════════════════════════════════════════

  static String _keyOf(String songId) {
    return songId
        .replaceAll(':', '_')
        .replaceAll('/', '_')
        .replaceAll('\\', '_')
        .replaceAll('?', '_')
        .replaceAll('*', '_');
  }

  static bool _hasExt(String path) {
    final name = path.split(Platform.pathSeparator).last;
    final dot = name.lastIndexOf('.');
    return dot > 0 && dot < name.length - 1;
  }

  static String _keyFromPath(String path) {
    final name = path.split(Platform.pathSeparator).last;
    final dot = name.lastIndexOf('.');
    return dot > 0 ? name.substring(0, dot) : name;
  }

  static String _extFrom(String? contentType, String url) {
    final ct = (contentType ?? '').toLowerCase();
    if (ct.contains('mpeg') || ct.contains('mp3')) return '.mp3';
    if (ct.contains('mp4') || ct.contains('m4a') || ct.contains('aac')) {
      return '.m4a';
    }
    if (ct.contains('flac')) return '.flac';
    if (ct.contains('ogg')) return '.ogg';
    if (ct.contains('wav')) return '.wav';

    final lower = url.toLowerCase();
    if (lower.contains('.mp3')) return '.mp3';
    if (lower.contains('.m4a')) return '.m4a';
    if (lower.contains('.flac')) return '.flac';
    if (lower.contains('.ogg')) return '.ogg';
    if (lower.contains('.wav')) return '.wav';
    if (lower.contains('.aac')) return '.aac';

    return '.m4a';
  }

  // ═══════════════════════════════════════════
  // 目录
  // ═══════════════════════════════════════════

  static Future<Directory> _dir() async {
    if (_cacheDir != null) return _cacheDir!;
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/audio_cache');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    _cacheDir = dir;
    return dir;
  }

  static Future<void> _cleanupLegacyDir() async {
    try {
      final support = await getApplicationSupportDirectory();
      final legacy = Directory('${support.path}/audio_cache');
      if (legacy.existsSync()) {
        legacy.deleteSync(recursive: true);
        print('🧹 [cache] 已清理旧版缓存目录');
      }
    } catch (_) {}
  }

  // ═══════════════════════════════════════════
  // 初始化
  // ═══════════════════════════════════════════

  static Future<void> init() async {
    await _cleanupLegacyDir();

    final dir = await _dir();
    _completeIndex.clear();
    _pathIndex.clear();

    final allFiles = <File>[];
    await for (final e in dir.list()) {
      if (e is! File) continue;
      if (e.path.endsWith('.part')) {
        try {
          e.deleteSync();
        } catch (_) {}
        continue;
      }
      allFiles.add(e);
    }

    allFiles.sort((a, b) {
      final aHas = _hasExt(a.path);
      final bHas = _hasExt(b.path);
      if (aHas && !bHas) return -1;
      if (!aHas && bHas) return 1;
      return 0;
    });

    int count = 0;
    int removed = 0;

    for (final f in allFiles) {
      try {
        final len = f.statSync().size;
        if (len < 1024) {
          f.deleteSync();
          removed++;
          continue;
        }
        if (!_isAudioHead(f)) {
          print('⚠️ [cache] 删除坏文件: ${f.path}');
          f.deleteSync();
          removed++;
          continue;
        }

        final key = _keyFromPath(f.path);
        if (_pathIndex.containsKey(key)) {
          try {
            f.deleteSync();
            removed++;
          } catch (_) {}
          continue;
        }

        _completeIndex[key] = len;
        _pathIndex[key] = f.path;
        count++;
      } catch (_) {}
    }

    print(
      '📦 [cache] 已索引 $count 个有效缓存'
      '${removed > 0 ? "（清理 $removed 个冗余/损坏）" : ""}',
    );
  }

  // ═══════════════════════════════════════════
  // 文件头校验
  // ═══════════════════════════════════════════

  static bool _isAudioHead(File f) {
    try {
      final raf = f.openSync();
      final len = f.lengthSync();
      final readLen = len > 64 ? 64 : len;
      final bytes = raf.readSync(readLen);
      raf.closeSync();
      if (bytes.isEmpty) return false;

      final head = String.fromCharCodes(bytes).toLowerCase();
      if (head.contains('<html') ||
          head.contains('<!doctype') ||
          head.contains('<?xml') ||
          head.contains('{"') ||
          head.contains('{"code"') ||
          head.contains('{"error"')) {
        return false;
      }

      if (bytes.length >= 4) {
        final b0 = bytes[0];
        final b1 = bytes[1];
        final b2 = bytes[2];
        final b3 = bytes[3];

        if (b0 == 0x66 && b1 == 0x4C && b2 == 0x61 && b3 == 0x43) return true;
        if (b0 == 0x4F && b1 == 0x67 && b2 == 0x67 && b3 == 0x53) return true;
        if (b0 == 0x52 && b1 == 0x49 && b2 == 0x46 && b3 == 0x46) return true;
        if (bytes.length >= 8) {
          if (bytes[4] == 0x66 &&
              bytes[5] == 0x74 &&
              bytes[6] == 0x79 &&
              bytes[7] == 0x70) {
            return true;
          }
        }
        if (b0 == 0x49 && b1 == 0x44 && b2 == 0x33) return true;
        if (b0 == 0xFF && (b1 & 0xE0) == 0xE0) return true;
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  // ═══════════════════════════════════════════
  // 查询
  // ═══════════════════════════════════════════

  static Future<String?> get(String songId) async {
    final key = _keyOf(songId);

    final path = _pathIndex[key];
    if (path != null) {
      final f = File(path);
      if (f.existsSync() && f.lengthSync() > 1024) {
        return path;
      }
      _pathIndex.remove(key);
      _completeIndex.remove(key);
    }

    final dir = await _dir();
    final candidates = <File>[];
    await for (final e in dir.list()) {
      if (e is! File) continue;
      final name = e.path.split(Platform.pathSeparator).last;
      if (name == key || name.startsWith('$key.')) {
        candidates.add(e);
      }
    }

    for (final f in candidates) {
      try {
        final len = f.lengthSync();
        if (len < 1024) {
          try {
            f.deleteSync();
          } catch (_) {}
          continue;
        }
        if (!_isAudioHead(f)) {
          try {
            f.deleteSync();
          } catch (_) {}
          continue;
        }
        _completeIndex[key] = len;
        _pathIndex[key] = f.path;
        return f.path;
      } catch (_) {}
    }

    return null;
  }

  static bool isComplete(String songId) {
    return _pathIndex.containsKey(_keyOf(songId));
  }

  static bool isDownloading(String songId) {
    return _downloading.contains(songId);
  }

  // ═══════════════════════════════════════════
  // 进度
  // ═══════════════════════════════════════════

  static double progressOf(String songId) {
    if (isComplete(songId)) return 1.0;
    return (_progressMap[songId] ?? 0.0).clamp(0.0, 1.0);
  }

  static Stream<double> watchProgress(String songId) async* {
    final initial = progressOf(songId);
    yield initial;
    if (initial >= 1.0) return;

    await for (final id in _progressUpdates.stream) {
      if (id != songId) continue;
      final p = progressOf(songId);
      yield p;
      if (p >= 1.0) return;
    }
  }

  static void _reportProgress(String songId, double p) {
    _progressMap[songId] = p.clamp(0.0, 1.0);
    if (!_pendingNotify.add(songId)) return;
    Future.delayed(const Duration(milliseconds: 200), () {
      _pendingNotify.remove(songId);
      if (!_progressUpdates.isClosed) _progressUpdates.add(songId);
    });
  }

  static void _notifyNow(String songId) {
    _pendingNotify.remove(songId);
    if (!_progressUpdates.isClosed) _progressUpdates.add(songId);
  }

  // ═══════════════════════════════════════════
  // 下载
  // ═══════════════════════════════════════════

  static Future<void> download(
    String songId,
    String url, {
    Map<String, String>? headers,
  }) {
    if (isComplete(songId)) return Future.value();

    final existing = _downloadFutures[songId];
    if (existing != null) return existing;

    final future = _doDownloadWithRetry(songId, url, headers: headers);
    _downloadFutures[songId] = future;
    future.whenComplete(() => _downloadFutures.remove(songId));
    return future;
  }

  static Future<String?> downloadAndWait(
    String songId,
    String url, {
    Map<String, String>? headers,
    Duration timeout = const Duration(seconds: 8),
  }) async {
    final existing = await get(songId);
    if (existing != null) return existing;

    final dl = download(songId, url, headers: headers);
    try {
      await Future.any([dl, Future.delayed(timeout)]);
    } catch (_) {}

    return await get(songId);
  }

  static Future<void> _doDownloadWithRetry(
    String songId,
    String url, {
    Map<String, String>? headers,
    int maxAttempts = 3,
  }) async {
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      final ok = await _doDownloadOnce(songId, url, headers: headers);
      if (ok) return;
      if (attempt < maxAttempts) {
        print('🔄 [cache] 第 $attempt 次失败，${attempt * 2}s 后重试: $songId');
        await Future.delayed(Duration(seconds: attempt * 2));
      }
    }
    _progressMap.remove(songId);
    _notifyNow(songId);
  }

  static Future<bool> _doDownloadOnce(
    String songId,
    String url, {
    Map<String, String>? headers,
  }) async {
    _downloading.add(songId);

    final key = _keyOf(songId);
    final dir = await _dir();
    final tmpFile = File('${dir.path}/$key.part');

    try {
      if (tmpFile.existsSync()) tmpFile.deleteSync();
    } catch (_) {}

    final client = http.Client();
    try {
      final request = http.Request('GET', Uri.parse(url));
      if (headers != null) request.headers.addAll(headers);

      final response = await client
          .send(request)
          .timeout(const Duration(minutes: 5));

      if (response.statusCode != 200) {
        print('❌ [cache] HTTP ${response.statusCode}: $songId');
        return false;
      }

      final ext = _extFrom(response.headers['content-type'], url);
      final finalFile = File('${dir.path}/$key$ext');

      final total = response.contentLength ?? 0;
      int received = 0;
      _reportProgress(songId, 0.0);

      final sink = tmpFile.openWrite();
      await for (final chunk in response.stream) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0) {
          _reportProgress(songId, received / total);
        }
      }
      await sink.close();

      final len = tmpFile.lengthSync();
      if (len < 1024) {
        print('❌ [cache] 文件太小 ($len): $songId');
        try {
          tmpFile.deleteSync();
        } catch (_) {}
        _progressMap.remove(songId);
        _notifyNow(songId);
        return false;
      }

      if (!_isAudioHead(tmpFile)) {
        print('❌ [cache] 文件头非音频，删除: $songId');
        try {
          tmpFile.deleteSync();
        } catch (_) {}
        _progressMap.remove(songId);
        _notifyNow(songId);
        return false;
      }

      // ★ 修复：删除同 key 旧文件时，必须跳过 .part 和 finalFile 本身
      await for (final e in dir.list()) {
        if (e is! File) continue;
        if (e.path == finalFile.path) continue;
        if (e.path == tmpFile.path) continue;
        // ★ 跳过所有 .part 临时文件（包括其它 key 正在下载的）
        if (e.path.endsWith('.part')) continue;
        final name = e.path.split(Platform.pathSeparator).last;
        if (name == key || name.startsWith('$key.')) {
          try {
            e.deleteSync();
          } catch (_) {}
        }
      }

      await tmpFile.rename(finalFile.path);

      _completeIndex[key] = len;
      _pathIndex[key] = finalFile.path;
      _progressMap[songId] = 1.0;
      _notifyNow(songId);

      print(
        '📥 [cache] 已缓存: $songId → '
        '${finalFile.path.split(Platform.pathSeparator).last} (${len ~/ 1024} KB)',
      );
      return true;
    } catch (e) {
      print('❌ [cache] 下载异常: $e');
      try {
        if (tmpFile.existsSync()) tmpFile.deleteSync();
      } catch (_) {}
      return false;
    } finally {
      client.close();
      _downloading.remove(songId);
    }
  }

  // ═══════════════════════════════════════════
  // 清理
  // ═══════════════════════════════════════════

  static Future<void> clear() async {
    final dir = await _dir();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
    _cacheDir = null;
    _completeIndex.clear();
    _pathIndex.clear();
    _downloading.clear();
    _downloadFutures.clear();
    _progressMap.clear();
    _pendingNotify.clear();
  }

  static Future<int> size() async {
    final dir = await _dir();
    if (!dir.existsSync()) return 0;
    int total = 0;
    await for (final e in dir.list()) {
      if (e is File) total += await e.length();
    }
    return total;
  }

  static Future<void> trim({int maxBytes = 1024 * 1024 * 1024}) async {
    final dir = await _dir();
    if (!dir.existsSync()) return;

    final files = <File>[];
    await for (final e in dir.list()) {
      if (e is File) files.add(e);
    }

    files.sort(
      (a, b) => a.statSync().modified.compareTo(b.statSync().modified),
    );

    int total = 0;
    for (final f in files) {
      total += f.statSync().size;
    }

    int idx = 0;
    while (total > maxBytes && idx < files.length) {
      final f = files[idx];
      total -= f.statSync().size;
      try {
        final key = _keyFromPath(f.path);
        f.deleteSync();
        _completeIndex.remove(key);
        _pathIndex.remove(key);
      } catch (_) {}
      idx++;
    }
  }
}
