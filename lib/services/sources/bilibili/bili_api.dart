import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import '../../../models/song.dart';
import '../../auth_store.dart';

const _navUrl = 'https://api.bilibili.com/x/web-interface/nav';
const _searchUrl = 'https://api.bilibili.com/x/web-interface/wbi/search/type';
const _viewUrl = 'https://api.bilibili.com/x/web-interface/view';
const _playUrl = 'https://api.bilibili.com/x/player/wbi/playurl';
const _playerV2Url = 'https://api.bilibili.com/x/player/wbi/v2';

const _ua =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

const _mixinKeyEncTab = [
  46, 47, 18, 2, 53, 8, 23, 32, 15, 50, 10, 31, 58, 3, 45, 35, 27, 43, 5, 49,
  33, 9, 42, 19, 29, 28, 14, 39, 12, 38, 41, 13, 37, 48, 7, 16, 24, 55, 40,
  61, 26, 17, 0, 1, 60, 51, 30, 4, 22, 25, 54, 21, 56, 59, 6, 63, 57, 62, 11,
  36, 20, 34, 44, 52,
];

class BiliSearchResult {
  final List<Song> songs;
  final int page;
  final bool hasMore;

  const BiliSearchResult({
    required this.songs,
    required this.page,
    required this.hasMore,
  });
}

class BiliApi {
  static String? _imgKey;
  static String? _subKey;
  static String _cookies = '';
  static DateTime? _lastWbiTime;

  /// 统一 Cookie：用户登录优先，否则匿名
  static String _cookie() {
    final custom = AuthStore.getCookie('bilibili');
    if (custom != null && custom.isNotEmpty) {
      return custom;
    }
    return _cookies;
  }

  static Map<String, String> get audioHeaders => {
    'User-Agent': _ua,
    'Referer': 'https://www.bilibili.com',
    if (_cookie().isNotEmpty) 'Cookie': _cookie(),
  };

  /// 强制刷新 WBI
  static Future<void> _refreshWbi() async {
    _imgKey = null;
    _subKey = null;
    await _ensureWbi();
  }

  static Future<void> _ensureWbi() async {
    // 10 分钟内不重复抓
    if (_imgKey != null && _subKey != null && _lastWbiTime != null) {
      final elapsed = DateTime.now().difference(_lastWbiTime!);
      if (elapsed < const Duration(minutes: 10)) return;
    }

    try {
      final res = await http
          .get(
            Uri.parse(_navUrl),
            headers: {'User-Agent': _ua, 'Referer': 'https://www.bilibili.com'},
          )
          .timeout(const Duration(seconds: 10));

      final setCookies = res.headers['set-cookie'];
      if (setCookies != null) {
        _cookies = setCookies
            .split(',')
            .map((s) => s.split(';').first.trim())
            .where((s) => s.isNotEmpty)
            .join('; ');
      }

      final json = jsonDecode(utf8.decode(res.bodyBytes));
      final wbiImg = json['data']?['wbi_img'];
      if (wbiImg == null) {
        print('⚠️ [bili] nav 未返回 wbi_img');
        return;
      }

      _imgKey = (wbiImg['img_url'] as String).split('/').last.split('.').first;
      _subKey = (wbiImg['sub_url'] as String).split('/').last.split('.').first;
      _lastWbiTime = DateTime.now();
      print('✅ [bili] WBI 刷新成功 (匿名 cookies: ${_cookies.length} 字符)');
    } catch (e) {
      print('⚠️ [bili] WBI 获取失败: $e');
    }
  }

  static String _getMixinKey() {
    final raw = '$_imgKey$_subKey';
    final b = StringBuffer();
    for (final i in _mixinKeyEncTab) {
      if (i < raw.length) b.write(raw[i]);
    }
    return b.toString().substring(0, 32);
  }

  static Map<String, String> _signParams(Map<String, String> params) {
    final mixinKey = _getMixinKey();
    params['wts'] = (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString();

    final sortedKeys = params.keys.toList()..sort();
    final query = sortedKeys
        .map((k) {
          final v = params[k]!.replaceAll(RegExp(r"[!'()*]"), '');
          return '${Uri.encodeComponent(k)}=${Uri.encodeComponent(v)}';
        })
        .join('&');

    params['w_rid'] = md5.convert(utf8.encode('$query$mixinKey')).toString();
    return params;
  }

  static Map<String, String> _headers() => {
    'User-Agent': _ua,
    'Referer': 'https://www.bilibili.com',
    if (_cookie().isNotEmpty) 'Cookie': _cookie(),
  };

  // ═══════════════════════════════════════════
  // 搜索
  // ═══════════════════════════════════════════
  static Future<BiliSearchResult> search(
    String keyword, {
    int page = 1,
    int pageSize = 20,
  }) async {
    if (keyword.trim().isEmpty) {
      return BiliSearchResult(songs: [], page: page, hasMore: false);
    }

    await _ensureWbi();
    if (_imgKey == null) {
      return BiliSearchResult(songs: [], page: page, hasMore: false);
    }

    try {
      final params = <String, String>{
        'search_type': 'video',
        'keyword': keyword,
        'page': page.toString(),
        'page_size': pageSize.toString(),
      };
      _signParams(params);

      final uri = Uri.parse(_searchUrl).replace(queryParameters: params);
      final res = await http
          .get(uri, headers: _headers())
          .timeout(const Duration(seconds: 15));

      final json = jsonDecode(utf8.decode(res.bodyBytes));
      if (json['code'] != 0) {
        print('❌ [bili] 搜索失败: ${json['message']} (code: ${json['code']})');
        return BiliSearchResult(songs: [], page: page, hasMore: false);
      }

      final data = json['data'];
      final results = data?['result'] as List? ?? [];
      final numPages = data?['numPages'] as int? ?? 1;

      final songs = results
          .where((item) => item['type'] == 'video')
          .map((item) {
            return Song(
              id: item['bvid']?.toString() ?? '',
              source: 'bilibili',
              title: _cleanTitle(item['title']?.toString() ?? ''),
              artist: item['author']?.toString() ?? '未知UP主',
              album: '',
              coverPath: _fixCoverUrl(item['pic']?.toString() ?? ''),
              audioPath: '',
              duration: _parseDuration(item['duration']),
            );
          })
          .where((s) => s.id.isNotEmpty)
          .toList();

      print('✅ [bili] 搜索 "$keyword" p$page → ${songs.length} 条');

      return BiliSearchResult(
        songs: songs,
        page: page,
        hasMore: page < numPages,
      );
    } catch (e) {
      print('❌ [bili] 搜索异常: $e');
      return BiliSearchResult(songs: [], page: page, hasMore: false);
    }
  }

  // ═══════════════════════════════════════════
  // 音频流
  // ═══════════════════════════════════════════
  static Future<String?> getSongUrl(String bvid) async {
    await _ensureWbi();
    if (_imgKey == null) {
      print('❌ [bili] getSongUrl: WBI 密钥为空');
      return null;
    }

    var url = await _tryGetSongUrl(bvid);
    if (url != null) return url;

    print('🔄 [bili] 首次失败，刷新 WBI 后重试');
    await _refreshWbi();
    url = await _tryGetSongUrl(bvid);
    if (url != null) return url;

    print('❌ [bili] getSongUrl 两次尝试都失败: $bvid');
    return null;
  }

  static Future<String?> _tryGetSongUrl(String bvid) async {
    try {
      final viewUri = Uri.parse(_viewUrl).replace(
        queryParameters: {'bvid': bvid},
      );
      print('🔍 [bili] 请求视频信息: $bvid');
      final viewRes = await http
          .get(viewUri, headers: _headers())
          .timeout(const Duration(seconds: 10));

      final viewJson = jsonDecode(utf8.decode(viewRes.bodyBytes));
      if (viewJson['code'] != 0) {
        print('❌ [bili] view 失败: ${viewJson['message']} (code: ${viewJson['code']})');
        return null;
      }
      final cid = viewJson['data']?['cid'];
      if (cid == null) {
        print('❌ [bili] cid 为空');
        return null;
      }
      print('✅ [bili] cid=$cid');

      final params = <String, String>{
        'bvid': bvid,
        'cid': cid.toString(),
        'fnval': '1',
        'fnver': '0',
        'fourk': '0',
        'platform': 'html5',
        'high_quality': '0',
      };
      _signParams(params);

      final uri = Uri.parse(_playUrl).replace(queryParameters: params);
      final res = await http
          .get(uri, headers: _headers())
          .timeout(const Duration(seconds: 15));

      final json = jsonDecode(utf8.decode(res.bodyBytes));
      print('🔍 [bili] playurl 返回: code=${json['code']} msg=${json['message']}');

      if (json['code'] != 0) {
        print('❌ [bili] playurl 失败 (code: ${json['code']})');
        return null;
      }

      final durl = json['data']?['durl'] as List?;
      if (durl != null && durl.isNotEmpty) {
        for (final item in durl) {
          final url = _pickBestUrl(
            item['url']?.toString() ?? '',
            (item['backup_url'] as List?)?.cast<String>() ?? [],
          );
          if (url != null) {
            print('✅ [bili] 拿到 durl 音频 URL');
            return url;
          }
        }
      }

      final dash = json['data']?['dash'];
      if (dash != null) {
        final audios = dash['audio'] as List?;
        if (audios != null && audios.isNotEmpty) {
          audios.sort(
            (a, b) => (b['bandwidth'] ?? 0).compareTo(a['bandwidth'] ?? 0),
          );
          for (final a in audios) {
            final url = _pickBestUrl(
              a['baseUrl']?.toString() ?? '',
              (a['backupUrl'] as List?)?.cast<String>() ?? [],
            );
            if (url != null) {
              print('✅ [bili] 拿到 dash 音频 URL');
              return url;
            }
          }
        }
      }

      print('❌ [bili] playurl 里没找到可用音频流');
      return null;
    } catch (e) {
      print('❌ [bili] _tryGetSongUrl 异常: $e');
      return null;
    }
  }

  // ═══════════════════════════════════════════
  // 歌词（详细日志版）
  // ═══════════════════════════════════════════
  static Future<List<MapEntry<double, String>>> getLyric(String bvid) async {
    await _ensureWbi();
    if (_imgKey == null) {
      print('❌ [bili] getLyric: WBI 密钥为空');
      return [];
    }

    try {
      // ─── 1. 拿 aid / cid ───
      final viewUri = Uri.parse(_viewUrl).replace(
        queryParameters: {'bvid': bvid},
      );
      print('🔍 [bili] lyric view: $bvid');
      final viewRes = await http
          .get(viewUri, headers: _headers())
          .timeout(const Duration(seconds: 10));

      final viewJson = jsonDecode(utf8.decode(viewRes.bodyBytes));
      final viewCode = viewJson['code'];
      if (viewCode != 0) {
        print('❌ [bili] lyric view 失败: code=$viewCode msg=${viewJson['message']}');
        return [];
      }
      final aid = viewJson['data']?['aid'];
      final cid = viewJson['data']?['cid'];
      if (aid == null || cid == null) {
        print('❌ [bili] lyric aid/cid 为空');
        return [];
      }
      print('✅ [bili] lyric aid=$aid cid=$cid');

      // ─── 2. 拿字幕列表 ───
      final params = <String, String>{
        'aid': aid.toString(),
        'cid': cid.toString(),
      };
      _signParams(params);

      final uri = Uri.parse(_playerV2Url).replace(queryParameters: params);
      print('🔍 [bili] lyric playerV2 请求');
      final res = await http
          .get(uri, headers: _headers())
          .timeout(const Duration(seconds: 10));

      final json = jsonDecode(utf8.decode(res.bodyBytes));
      final code = json['code'];
      print('🔍 [bili] lyric playerV2 返回: code=$code msg=${json['message']}');

      if (code != 0) {
        print('❌ [bili] playerV2 失败 (code=$code)');
        return [];
      }

      // 尝试多个位置取字幕
      final data = json['data'];
      List? subtitles = data?['subtitle']?['subtitles'] as List?;

      if (subtitles == null || subtitles.isEmpty) {
        final subtitleObj = data?['subtitle'];
        if (subtitleObj is Map) {
          print('🔍 [bili] subtitle keys: ${subtitleObj.keys.toList()}');
        }
        print('ℹ️ [bili] 该视频无字幕 (subtitles 为空)');
        return [];
      }

      print('✅ [bili] 字幕数: ${subtitles.length}');
      for (var i = 0; i < subtitles.length; i++) {
        final s = subtitles[i];
        print('   [$i] lan=${s['lan']} lan_doc=${s['lan_doc']} url=${s['subtitle_url']}');
      }

      // ─── 3. 优先中文，否则第一条 ───
      Map<String, dynamic>? chosen;
      for (final s in subtitles) {
        if (s is Map && s['lan']?.toString().startsWith('zh') == true) {
          chosen = Map<String, dynamic>.from(s);
          break;
        }
      }
      chosen ??= Map<String, dynamic>.from(subtitles[0] as Map);

      String? subUrl = chosen['subtitle_url']?.toString();
      if (subUrl == null || subUrl.isEmpty) {
        print('❌ [bili] subtitle_url 为空');
        return [];
      }
      if (subUrl.startsWith('//')) subUrl = 'https:$subUrl';
      print('✅ [bili] 使用字幕 URL: $subUrl');

      // ─── 4. 下载字幕 ───
      final subRes = await http
          .get(Uri.parse(subUrl), headers: _headers())
          .timeout(const Duration(seconds: 10));
      print('🔍 [bili] 字幕下载 HTTP ${subRes.statusCode}');

      final subJson = jsonDecode(utf8.decode(subRes.bodyBytes));
      final body = subJson['body'] as List? ?? [];
      print('✅ [bili] 字幕行数: ${body.length}');

      return body.map<MapEntry<double, String>>((line) {
        final from = (line['from'] as num?)?.toDouble() ?? 0;
        final content = line['content']?.toString() ?? '';
        return MapEntry(from, content);
      }).toList();
    } catch (e) {
      print('❌ [bili] getLyric 异常: $e');
      return [];
    }
  }

  // ═══════════════════════════════════════════
  // 工具
  // ═══════════════════════════════════════════
  static String? _pickBestUrl(String primary, List<String> backups) {
    bool isPcdn(String u) {
      if (u.isEmpty) return true;
      return u.contains('127.0.0.1') ||
          u.contains('://10.') ||
          u.contains('://192.168.') ||
          u.contains('://172.');
    }

    if (!isPcdn(primary)) return primary;
    for (final u in backups) {
      if (!isPcdn(u)) return u;
    }
    if (primary.isNotEmpty) return primary;
    return null;
  }

  static String _cleanTitle(String raw) => raw
      .replaceAll(RegExp(r'<[^>]+>'), '')
      .replaceAll('&quot;', '"')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>');

  static String _fixCoverUrl(String url) {
    if (url.isEmpty) return '';
    if (url.startsWith('//')) return 'https:$url';
    return url;
  }

  static Duration _parseDuration(dynamic raw) {
    if (raw == null) return Duration.zero;
    if (raw is int) return Duration(seconds: raw);

    final s = raw.toString().trim();
    if (s.isEmpty) return Duration.zero;

    final n = int.tryParse(s);
    if (n != null) return Duration(seconds: n);

    try {
      final parts = s.split(':');
      if (parts.length == 2) {
        return Duration(
          minutes: int.parse(parts[0]),
          seconds: int.parse(parts[1]),
        );
      } else if (parts.length == 3) {
        return Duration(
          hours: int.parse(parts[0]),
          minutes: int.parse(parts[1]),
          seconds: int.parse(parts[2]),
        );
      }
    } catch (_) {}
    return Duration.zero;
  }
}