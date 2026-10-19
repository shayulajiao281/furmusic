import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../models/song.dart';
import '../music_source.dart';

abstract class DirectSource implements MusicSource {
  final http.Client client = http.Client();

  Map<String, String> get headers;
  Uri searchUri(String keyword, int page, int pageSize);
  Future<String?> getSongUrlById(String songId);
  Future<List<MapEntry<double, String>>> getLyricById(String songId);

  @override
  Future<SearchResult> search(
    String keyword, {
    int page = 1,
    int pageSize = 20,
  }) async {
    try {
      final res = await client
          .get(searchUri(keyword, page, pageSize), headers: headers)
          .timeout(const Duration(seconds: 8));

      if (res.statusCode != 200) {
        return const SearchResult(songs: [], hasMore: false);
      }

      final json = jsonDecode(utf8.decode(res.bodyBytes));
      return parseSearchResult(json, page, pageSize);
    } catch (e) {
      print('❌ [$id] 搜索异常: $e');
      return const SearchResult(songs: [], hasMore: false);
    }
  }

  SearchResult parseSearchResult(
    Map<String, dynamic> json,
    int page,
    int pageSize,
  );

  @override
  Future<String?> getSongUrl(String songId) async {
    return await getSongUrlById(songId);
  }

  @override
  Future<List<MapEntry<double, String>>> getLyric(String songId) async {
    return await getLyricById(songId);
  }

  @override
  Map<String, String> get audioHeaders => headers;

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