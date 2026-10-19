import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../models/song.dart';
import '../music_source.dart';
import '../auth_store.dart';
import '../device_fingerprint.dart';

class QQDirect implements MusicSource {
  final http.Client client = http.Client();

  @override
  String get id => 'qq';
  @override
  String get name => 'QQ音乐';
  @override
  int get weight => 7;

  Map<String, String> get _headers {
    final cookie = AuthStore.cookieFor('qq');
    return {
      'User-Agent':
          'QQMusic/18.0.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
      'Referer': 'https://y.qq.com/',
      'Origin': 'https://y.qq.com',
      'Accept': 'application/json, text/plain, */*',
      'Accept-Language': 'zh-CN,zh;q=0.9',
      'Accept-Encoding': 'gzip, deflate',
      'Connection': 'keep-alive',
      'QIMEI': DeviceFingerprint.qimei,
      'QIMEI36': DeviceFingerprint.qimei36,
      'guid': DeviceFingerprint.guid,
      if (cookie.isNotEmpty) 'Cookie': cookie,
    };
  }

  @override
  Map<String, String> get audioHeaders => _headers;

  @override
  Future<SearchResult> search(
    String keyword, {
    int page = 1,
    int pageSize = 20,
  }) async {
    final cookie = AuthStore.getCookie('qq');
    final hasLogin = cookie != null && cookie.isNotEmpty;

    if (hasLogin) {
      final r = await _searchNewApi(keyword, page, pageSize);
      if (r.songs.isNotEmpty) return r;
      print('⚠️ [qq] 新接口空结果，尝试旧接口');
    } else {
      print('👤 [qq] 未登录，走旧接口 client_search_cp');
    }

    return _searchOldApi(keyword, page, pageSize);
  }

  Future<SearchResult> _searchNewApi(
    String keyword,
    int page,
    int pageSize,
  ) async {
    try {
      final body = jsonEncode({
        'comm': {'ct': 24, 'cv': 0},
        'req_1': {
          'method': 'DoSearchForQQMusicDesktop',
          'module': 'music.search.SearchCgiService',
          'param': {
            'num_per_page': pageSize,
            'page_num': page,
            'query': keyword,
            'search_type': 0,
          },
        },
      });

      final res = await client
          .post(
            Uri.parse('https://u.y.qq.com/cgi-bin/musicu.fcg'),
            headers: {..._headers, 'Content-Type': 'application/json'},
            body: body,
          )
          .timeout(const Duration(seconds: 8));

      if (res.statusCode != 200) {
        return const SearchResult(songs: [], hasMore: false);
      }

      final json = jsonDecode(utf8.decode(res.bodyBytes));
      return _parseNewApi(json, page, pageSize);
    } catch (e) {
      print('❌ [qq-new] 异常: $e');
      return const SearchResult(songs: [], hasMore: false);
    }
  }

  SearchResult _parseNewApi(Map<String, dynamic> json, int page, int pageSize) {
    try {
      final body = json['req_1']?['data']?['body'];
      final songData = body?['song'];
      if (songData == null) return const SearchResult(songs: [], hasMore: false);

      final total = (songData['totalnum'] as int?) ?? 0;
      final rawList = songData['list'] as List? ?? [];

      final songs = rawList.map<Song?>(_mapSong).whereType<Song>().toList();
      final offset = (page - 1) * pageSize;
      return SearchResult(songs: songs, hasMore: offset + songs.length < total);
    } catch (e) {
      return const SearchResult(songs: [], hasMore: false);
    }
  }

  Future<SearchResult> _searchOldApi(
    String keyword,
    int page,
    int pageSize,
  ) async {
    final uri = Uri.parse('https://c.y.qq.com/soso/fcgi-bin/client_search_cp')
        .replace(
          queryParameters: {
            'w': keyword,
            'p': '$page',
            'n': '$pageSize',
            'format': 'json',
          },
        );

    try {
      final res = await client
          .get(uri, headers: _headers)
          .timeout(const Duration(seconds: 8));

      if (res.statusCode != 200) {
        return const SearchResult(songs: [], hasMore: false);
      }

      final text = utf8.decode(res.bodyBytes);
      final start = text.indexOf('{');
      final end = text.lastIndexOf('}');
      if (start < 0 || end < 0) {
        return const SearchResult(songs: [], hasMore: false);
      }

      final json = jsonDecode(text.substring(start, end + 1));
      return _parseOldApi(json, page, pageSize);
    } catch (e) {
      print('❌ [qq-old] 异常: $e');
      return const SearchResult(songs: [], hasMore: false);
    }
  }

  SearchResult _parseOldApi(Map<String, dynamic> json, int page, int pageSize) {
    try {
      final songData = json['data']?['song'];
      if (songData == null) return const SearchResult(songs: [], hasMore: false);

      final total = (songData['totalnum'] as int?) ?? 0;
      final rawList = songData['list'] as List? ?? [];

      final songs = rawList.map<Song?>(_mapSong).whereType<Song>().toList();
      final offset = (page - 1) * pageSize;
      return SearchResult(songs: songs, hasMore: offset + songs.length < total);
    } catch (e) {
      return const SearchResult(songs: [], hasMore: false);
    }
  }

  Song? _mapSong(dynamic item) {
    if (item is! Map) return null;
    final m = Map<String, dynamic>.from(item);

    final songMid = m['songmid']?.toString() ?? '';
    if (songMid.isEmpty) return null;

    final singers =
        (m['singer'] as List?)?.map((s) => (s as Map)['name']).join(', ') ?? '';
    final albumMid = m['albummid']?.toString() ?? '';
    final cover = albumMid.isEmpty
        ? ''
        : 'https://y.gtimg.cn/music/photo_new/T002R300x300M000$albumMid.jpg';

    final pay = m['pay'] as Map?;
    final payplay = (pay?['payplay'] as int?) ?? 0;

    return Song(
      id: songMid,
      source: id,
      title: m['songname']?.toString() ?? '',
      artist: singers.isEmpty ? '未知歌手' : singers,
      album: m['albumname']?.toString() ?? '',
      coverPath: cover,
      audioPath: '',
      duration: Duration(seconds: (m['interval'] as int?) ?? 0),
      isVip: payplay == 1,
    );
  }

  @override
  Future<String?> getSongUrl(String songId) async {
    try {
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
            'guid': DeviceFingerprint.guid,
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
            headers: {..._headers, 'Content-Type': 'application/json'},
            body: body,
          )
          .timeout(const Duration(seconds: 10));

      if (res.statusCode != 200) return null;

      final json = jsonDecode(utf8.decode(res.bodyBytes));
      final data = json['req_0']?['data'];
      final purl = data?['midurlinfo']?[0]?['purl'] as String?;

      if (purl == null || purl.isEmpty) return null;

      return 'https://ws.stream.qqmusic.qq.com/$purl';
    } catch (e) {
      return null;
    }
  }

  @override
  Future<List<MapEntry<double, String>>> getLyric(String songId) async {
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
          .get(uri, headers: _headers)
          .timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return [];

      final text = utf8.decode(res.bodyBytes);
      final start = text.indexOf('{');
      final end = text.lastIndexOf('}');
      if (start < 0 || end < 0) return [];

      final json = jsonDecode(text.substring(start, end + 1));
      final lrc = json['lyric'] as String? ?? '';
      return _parseLrc(lrc);
    } catch (e) {
      return [];
    }
  }

  List<MapEntry<double, String>> _parseLrc(String lrc) {
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