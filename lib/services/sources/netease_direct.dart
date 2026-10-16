import 'dart:convert';
import '../../models/song.dart';
import '../music_source.dart';
import 'direct_source.dart';

class NeteaseDirect extends DirectSource {
  @override
  String get id => 'netease';
  @override
  String get name => '网易云';
  @override
  int get weight => 8;

  @override
  Map<String, String> get headers => {
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
    'Referer': 'https://music.163.com/',
    'Cookie': 'appver=8.7.01; os=pc;',
  };

  @override
  Uri searchUri(String keyword, int page, int pageSize) {
    return Uri.parse('https://music.163.com/api/search/get/web').replace(
      queryParameters: {
        's': keyword,
        'type': '1',
        'offset': '${(page - 1) * pageSize}',
        'limit': '$pageSize',
      },
    );
  }

  @override
  SearchResult parseSearchResult(Map<String, dynamic> json) {
    try {
      final songs = (json['result']?['songs'] as List? ?? [])
          .map(
            (item) => Song(
              id: item['id'].toString(),
              source: id,
              title: item['name'] ?? '',
              artist:
                  (item['artists'] as List?)
                      ?.map((a) => a['name'])
                      .join(', ') ??
                  '',
              album: item['album']?['name'] ?? '',
              coverPath: item['album']?['picUrl'] ?? '',
              audioPath: '',
              duration: Duration(milliseconds: (item['duration'] as int?) ?? 0),
            ),
          )
          .toList();
      return SearchResult(songs: songs, hasMore: false);
    } catch (e) {
      print('❌ [netease] 解析搜索 JSON 出错: $e');
      return const SearchResult(songs: []);
    }
  }

  @override
  Future<String?> getSongUrlById(String songId) async {
    try {
      final uri = Uri.parse(
        'https://music.163.com/api/song/enhance/player/url',
      ).replace(queryParameters: {'ids': '[$songId]', 'br': '320000'});
      final res = await client
          .get(uri, headers: headers)
          .timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) {
        print('❌ [netease] url 请求 HTTP ${res.statusCode}');
        return null;
      }

      final json = jsonDecode(utf8.decode(res.bodyBytes));
      final data = json['data']?[0];
      final url = data?['url'] as String?;
      final code = data?['code'];
      final fee = data?['fee'];

      if (url == null || url.isEmpty) {
        // ★ 打印服务端真实 code，方便判断是 VIP 还是无版权
        print('❌ [netease] url 为空 (code=$code, fee=$fee)');
        return null;
      }
      return url;
    } catch (e) {
      print('❌ [netease] url 异常: $e');
      return null;
    }
  }

  @override
  Future<List<MapEntry<double, String>>> getLyricById(String songId) async {
    try {
      final uri = Uri.parse(
        'https://music.163.com/api/song/lyric',
      ).replace(queryParameters: {'id': songId, 'lv': '-1', 'kv': '-1'});
      final res = await client
          .get(uri, headers: headers)
          .timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) {
        print('❌ [netease] lyric HTTP ${res.statusCode}');
        return [];
      }

      final json = jsonDecode(utf8.decode(res.bodyBytes));
      final lrc = json['lrc']?['lyric'] as String? ?? '';
      return parseLrc(lrc);
    } catch (e) {
      print('❌ [netease] lyric 异常: $e');
      return [];
    }
  }
}
