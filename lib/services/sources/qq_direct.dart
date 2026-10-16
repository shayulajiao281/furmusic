import 'dart:convert';
import '../../models/song.dart';
import '../music_source.dart';
import '../auth_store.dart';
import 'direct_source.dart';

class QQDirect extends DirectSource {
  @override
  String get id => 'qq';
  @override
  String get name => 'QQ音乐';
  @override
  int get weight => 7;

  @override
  Map<String, String> get headers {
    final cookie = AuthStore.cookieFor('qq');
    return {
      'User-Agent':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
      'Referer': 'https://y.qq.com/',
      if (cookie.isNotEmpty) 'Cookie': cookie,
    };
  }

  @override
  Uri searchUri(String keyword, int page, int pageSize) {
    return Uri.parse(
      'https://c.y.qq.com/soso/fcgi-bin/client_search_cp',
    ).replace(
      queryParameters: {
        'w': keyword,
        'p': '$page',
        'n': '$pageSize',
        'format': 'json',
      },
    );
  }

  @override
  SearchResult parseSearchResult(Map<String, dynamic> json) {
    try {
      final list = json['data']?['song']?['list'] as List? ?? [];
      final songs = list.map((item) {
        final singers =
            (item['singer'] as List?)?.map((s) => s['name']).join(', ') ?? '';
        final albumMid = item['albummid']?.toString() ?? '';
        final cover = albumMid.isEmpty
            ? ''
            : 'https://y.gtimg.cn/music/photo_new/T002R300x300M000$albumMid.jpg';

        final pay = item['pay'] as Map?;
        final payplay = (pay?['payplay'] as int?) ?? 0;
        final isVip = payplay == 1;

        return Song(
          id: item['songmid'].toString(),
          source: id,
          title: item['songname'] ?? '',
          artist: singers,
          album: item['albumname'] ?? '',
          coverPath: cover,
          audioPath: '',
          duration: Duration(seconds: (item['interval'] as int?) ?? 0),
          isVip: isVip,
        );
      }).toList();
      return SearchResult(songs: songs, hasMore: false);
    } catch (e) {
      print('❌ [qq] 解析搜索 JSON 出错: $e');
      return const SearchResult(songs: []);
    }
  }

  @override
  Future<String?> getSongUrlById(String songId) async {
    try {
      // 如果已登录，uin 用真实 cookie 里的；否则 0
      String uin = '0';
      final c = AuthStore.getCookie('qq');
      if (c != null) {
        final m = RegExp(r'(?:^|;\s*)uin=o?(\d+)').firstMatch(c);
        if (m != null) uin = m.group(1)!;
      }

      final body = jsonEncode({
        'req_0': {
          'module': 'vkey.GetVkeyServer',
          'method': 'CgiGetVkey',
          'param': {
            'guid': '10000',
            'songmid': [songId],
            'songtype': [0],
            'uin': uin,
            'loginflag': 1,
            'platform': '20',
          },
        },
      });

      final res = await client
          .post(
            Uri.parse('https://u.y.qq.com/cgi-bin/musicu.fcg'),
            headers: {...headers, 'Content-Type': 'application/json'},
            body: body,
          )
          .timeout(const Duration(seconds: 10));

      if (res.statusCode != 200) {
        print('❌ [qq] url 请求 HTTP ${res.statusCode}');
        return null;
      }

      final json = jsonDecode(utf8.decode(res.bodyBytes));
      final data = json['req_0']?['data'];
      final purl = data?['midurlinfo']?[0]?['purl'] as String?;
      final errCode = json['req_0']?['code'];

      if (purl == null || purl.isEmpty) {
        print(
          '❌ [qq] purl 为空 (req_0.code=$errCode, result=${data?['midurlinfo']?[0]?['result']})',
        );
        return null;
      }

      return 'https://ws.stream.qqmusic.qq.com/$purl';
    } catch (e) {
      print('❌ [qq] url 异常: $e');
      return null;
    }
  }

  @override
  Future<List<MapEntry<double, String>>> getLyricById(String songId) async {
    try {
      final uri =
          Uri.parse(
            'https://c.y.qq.com/lyric/fcgi-bin/fcg_query_lyric_new.fcg',
          ).replace(
            queryParameters: {
              'songmid': songId,
              'format': 'json',
              'nobase64': '1',
            },
          );
      final res = await client
          .get(uri, headers: headers)
          .timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) {
        print('❌ [qq] lyric HTTP ${res.statusCode}');
        return [];
      }

      final text = utf8.decode(res.bodyBytes);
      final start = text.indexOf('{');
      final end = text.lastIndexOf('}');
      if (start < 0 || end < 0) return [];

      final json = jsonDecode(text.substring(start, end + 1));
      final lrc = json['lyric'] as String? ?? '';
      return parseLrc(lrc);
    } catch (e) {
      print('❌ [qq] lyric 异常: $e');
      return [];
    }
  }
}
