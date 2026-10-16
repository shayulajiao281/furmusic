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

  // ═══════════════════════════════════════════
  // 请求头（伪装成官方客户端）
  // ═══════════════════════════════════════════
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

  // ═══════════════════════════════════════════
  // 搜索：登录 → 新接口；未登录 → 旧接口
  // ═══════════════════════════════════════════
  @override
  Future<SearchResult> search(
    String keyword, {
    int page = 1,
    int pageSize = 20,
  }) async {
    final cookie = AuthStore.getCookie('qq');
    final hasLogin = cookie != null && cookie.isNotEmpty;

    if (hasLogin) {
      print('🔐 [qq] 已登录，走新接口 musicu.fcg');
      final r = await _searchNewApi(keyword, page, pageSize);
      if (r.songs.isNotEmpty) return r;
      print('⚠️ [qq] 新接口空结果，尝试旧接口');
    } else {
      print('👤 [qq] 未登录，走旧接口 client_search_cp');
    }

    return _searchOldApi(keyword, page, pageSize);
  }

  // ─── 新接口（需要登录）───
  Future<SearchResult> _searchNewApi(
    String keyword,
    int page,
    int pageSize,
  ) async {
    const maxAttempts = 3;
    for (int attempt = 0; attempt < maxAttempts; attempt++) {
      final sw = Stopwatch()..start();
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
            .timeout(const Duration(seconds: 15));
        sw.stop();

        if (res.statusCode != 200) {
          print('❌ [qq-new] HTTP ${res.statusCode} (attempt ${attempt + 1})');
          if (res.statusCode >= 500) {
            await Future.delayed(Duration(seconds: attempt + 1));
            continue;
          }
          return const SearchResult(songs: [], hasMore: false);
        }

        final json = jsonDecode(utf8.decode(res.bodyBytes));
        final result = _parseNewApi(json, page, pageSize);
        print(
          '✅ [qq-new] "$keyword" p$page → ${result.songs.length} 条 (${sw.elapsedMilliseconds}ms)',
        );
        return result;
      } catch (e) {
        sw.stop();
        print('❌ [qq-new] 异常: $e (attempt ${attempt + 1})');
        if (attempt < maxAttempts - 1) {
          await Future.delayed(Duration(seconds: attempt + 1));
        }
      }
    }
    return const SearchResult(songs: [], hasMore: false);
  }

  SearchResult _parseNewApi(Map<String, dynamic> json, int page, int pageSize) {
    try {
      final body = json['req_1']?['data']?['body'];
      final songData = body?['song'];
      if (songData == null)
        return const SearchResult(songs: [], hasMore: false);

      final total = (songData['totalnum'] as int?) ?? 0;
      final rawList = songData['list'] as List? ?? [];

      final songs = rawList.map<Song?>(_mapSong).whereType<Song>().toList();
      final offset = (page - 1) * pageSize;
      return SearchResult(songs: songs, hasMore: offset + songs.length < total);
    } catch (e) {
      print('❌ [qq-new] 解析出错: $e');
      return const SearchResult(songs: [], hasMore: false);
    }
  }

  // ─── 旧接口（无需登录）───
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

    const maxAttempts = 3;
    for (int attempt = 0; attempt < maxAttempts; attempt++) {
      final sw = Stopwatch()..start();
      try {
        final res = await client
            .get(uri, headers: _headers)
            .timeout(const Duration(seconds: 15));
        sw.stop();

        if (res.statusCode != 200) {
          print(
            '❌ [qq-old] HTTP ${res.statusCode} (attempt ${attempt + 1}/$maxAttempts)',
          );
          if (res.statusCode >= 500) {
            await Future.delayed(Duration(seconds: attempt + 1));
            continue;
          }
          return const SearchResult(songs: [], hasMore: false);
        }

        final text = utf8.decode(res.bodyBytes);
        final start = text.indexOf('{');
        final end = text.lastIndexOf('}');
        if (start < 0 || end < 0) {
          return const SearchResult(songs: [], hasMore: false);
        }

        final json = jsonDecode(text.substring(start, end + 1));
        final result = _parseOldApi(json, page, pageSize);
        print(
          '✅ [qq-old] "$keyword" p$page → ${result.songs.length} 条 (${sw.elapsedMilliseconds}ms)',
        );
        return result;
      } catch (e) {
        sw.stop();
        print('❌ [qq-old] 异常: $e (attempt ${attempt + 1}/$maxAttempts)');
        if (attempt < maxAttempts - 1) {
          await Future.delayed(Duration(seconds: attempt + 1));
        }
      }
    }
    print('❌ [qq] 两个接口都没成功');
    return const SearchResult(songs: [], hasMore: false);
  }

  SearchResult _parseOldApi(Map<String, dynamic> json, int page, int pageSize) {
    try {
      final songData = json['data']?['song'];
      if (songData == null)
        return const SearchResult(songs: [], hasMore: false);

      final total = (songData['totalnum'] as int?) ?? 0;
      final rawList = songData['list'] as List? ?? [];

      final songs = rawList.map<Song?>(_mapSong).whereType<Song>().toList();
      final offset = (page - 1) * pageSize;
      return SearchResult(songs: songs, hasMore: offset + songs.length < total);
    } catch (e) {
      print('❌ [qq-old] 解析出错: $e');
      return const SearchResult(songs: [], hasMore: false);
    }
  }

  // ─── 通用：把一条原始数据映射成 Song ───
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

  // ═══════════════════════════════════════════
  // 播放直链
  // ═══════════════════════════════════════════
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

      if (res.statusCode != 200) {
        print('❌ [qq] url HTTP ${res.statusCode}');
        return null;
      }

      final json = jsonDecode(utf8.decode(res.bodyBytes));
      final data = json['req_0']?['data'];
      final purl = data?['midurlinfo']?[0]?['purl'] as String?;
      final errCode = json['req_0']?['code'];

      if (purl == null || purl.isEmpty) {
        print('❌ [qq] purl 空 (code=$errCode)');
        return null;
      }

      return 'https://ws.stream.qqmusic.qq.com/$purl';
    } catch (e) {
      print('❌ [qq] url 异常: $e');
      return null;
    }
  }

  // ═══════════════════════════════════════════
  // 歌词
  // ═══════════════════════════════════════════
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
      print('❌ [qq] lyric 异常: $e');
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
