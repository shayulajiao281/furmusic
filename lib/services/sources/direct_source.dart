import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../models/song.dart';
import '../music_source.dart';

/// 所有"直接请求"音源的基类
abstract class DirectSource implements MusicSource {
  /// ★ public，子类可直接用
  final http.Client client = http.Client();

  /// 子类必须提供请求头（User-Agent / Referer / Cookie 等）
  Map<String, String> get headers;

  /// 子类实现具体的搜索 URL
  Uri searchUri(String keyword, int page, int pageSize);

  /// 子类实现具体的歌曲 URL 获取逻辑
  Future<String?> getSongUrlById(String songId);

  /// 子类实现具体的歌词获取逻辑
  Future<List<MapEntry<double, String>>> getLyricById(String songId);

  @override
  Future<SearchResult> search(
    String keyword, {
    int page = 1,
    int pageSize = 20,
  }) async {
    final sw = Stopwatch()..start();
    try {
      final res = await client
          .get(searchUri(keyword, page, pageSize), headers: headers)
          .timeout(const Duration(seconds: 15));
      sw.stop();

      if (res.statusCode != 200) {
        print(
          '❌ [$id] 搜索 HTTP ${res.statusCode} (${sw.elapsedMilliseconds}ms)',
        );
        return const SearchResult(songs: []);
      }

      final json = jsonDecode(utf8.decode(res.bodyBytes));
      final result = parseSearchResult(json);
      print(
        '✅ [$id] 搜索 "${keyword}" → ${result.songs.length} 条 (${sw.elapsedMilliseconds}ms)',
      );
      return result;
    } catch (e) {
      sw.stop();
      print('❌ [$id] 搜索异常: $e (${sw.elapsedMilliseconds}ms)');
      return const SearchResult(songs: []);
    }
  }

  /// 子类解析 JSON 并返回统一格式
  SearchResult parseSearchResult(Map<String, dynamic> json);

  @override
  Future<String?> getSongUrl(String songId) async {
    final sw = Stopwatch()..start();
    final url = await getSongUrlById(songId);
    sw.stop();
    if (url == null || url.isEmpty) {
      print('❌ [$id] 解析 url 失败: $songId (${sw.elapsedMilliseconds}ms)');
      return null;
    }
    print('✅ [$id] 解析 url 成功: $songId (${sw.elapsedMilliseconds}ms)');
    return url;
  }

  @override
  Future<List<MapEntry<double, String>>> getLyric(String songId) async {
    final sw = Stopwatch()..start();
    final lyric = await getLyricById(songId);
    sw.stop();
    print(
      '🎤 [$id] 歌词 $songId → ${lyric.length} 行 (${sw.elapsedMilliseconds}ms)',
    );
    return lyric;
  }

  @override
  Map<String, String> get audioHeaders => headers;

  /// LRC 解析工具（子类可以直接调用）
  List<MapEntry<double, String>> parseLrc(String lrc) {
    final lines = <MapEntry<double, String>>[];
    final regex = RegExp(r'\[(\d{2}):(\d{2})\.(\d{2,3})\](.*)');
    for (final line in lrc.split('\n')) {
      final match = regex.firstMatch(line);
      if (match != null) {
        final min = int.parse(match.group(1)!);
        final sec = int.parse(match.group(2)!);
        final ms = int.parse(match.group(3)!.padRight(3, '0'));
        final time = min * 60 + sec + ms / 1000;
        final text = match.group(4)!.trim();
        if (text.isNotEmpty) lines.add(MapEntry(time, text));
      }
    }
    return lines;
  }
}
