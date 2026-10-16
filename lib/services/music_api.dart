import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import '../models/song.dart';

const _navUrl = 'https://api.bilibili.com/x/web-interface/nav';
const _searchUrl = 'https://api.bilibili.com/x/web-interface/wbi/search/type';
const _viewUrl = 'https://api.bilibili.com/x/web-interface/view';
const _playUrl = 'https://api.bilibili.com/x/player/wbi/playurl';
const _playerV2Url = 'https://api.bilibili.com/x/player/wbi/v2';

const _ua =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

const _mixinKeyEncTab = [
  46,
  47,
  18,
  2,
  53,
  8,
  23,
  32,
  15,
  50,
  10,
  31,
  58,
  3,
  45,
  35,
  27,
  43,
  5,
  49,
  33,
  9,
  42,
  19,
  29,
  28,
  14,
  39,
  12,
  38,
  41,
  13,
  37,
  48,
  7,
  16,
  24,
  55,
  40,
  61,
  26,
  17,
  0,
  1,
  60,
  51,
  30,
  4,
  22,
  25,
  54,
  21,
  56,
  59,
  6,
  63,
  57,
  62,
  11,
  36,
  20,
  34,
  44,
  52,
];

/// 搜索结果
class SearchResult {
  final List<Song> songs;
  final int page;
  final bool hasMore;

  const SearchResult({
    required this.songs,
    required this.page,
    required this.hasMore,
  });
}

class MusicApi {
  static String? _imgKey;
  static String? _subKey;
  static String _cookies = '';

  /// 供播放器使用（音频流需要 Referer + Cookie）
  static Map<String, String> get audioHeaders => {
    'User-Agent': _ua,
    'Referer': 'https://www.bilibili.com',
    if (_cookies.isNotEmpty) 'Cookie': _cookies,
  };

  // ═══════════════════════════════════════════
  // WBI 签名 + Cookie
  // ═══════════════════════════════════════════
  static Future<void> _ensureWbi() async {
    if (_imgKey != null && _subKey != null) return;
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
        print('⚠️ nav 未返回 wbi_img');
        return;
      }

      _imgKey = (wbiImg['img_url'] as String).split('/').last.split('.').first;
      _subKey = (wbiImg['sub_url'] as String).split('/').last.split('.').first;
      print('✅ WBI 密钥获取成功 (cookies: ${_cookies.length} 字符)');
    } catch (e) {
      print('⚠️ WBI 获取失败: $e');
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
    if (_cookies.isNotEmpty) 'Cookie': _cookies,
  };

  // ═══════════════════════════════════════════
  // 搜索（支持分页）
  // ═══════════════════════════════════════════
  /// [page] 从 1 开始
  static Future<SearchResult> search(
    String keyword, {
    int page = 1,
    int pageSize = 20,
  }) async {
    if (keyword.trim().isEmpty) {
      return SearchResult(songs: [], page: page, hasMore: false);
    }

    await _ensureWbi();
    if (_imgKey == null) {
      return SearchResult(songs: [], page: page, hasMore: false);
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
        print('❌ 搜索失败: ${json['message']} (code: ${json['code']})');
        return SearchResult(songs: [], page: page, hasMore: false);
      }

      final data = json['data'];
      final results = data?['result'] as List? ?? [];
      final numPages = data?['numPages'] as int? ?? 1;
      final numResults = data?['numResults'] as int? ?? 0;

      print('📋 第 $page 页：${results.length} 条 / 共 $numPages 页 $numResults 条');

      final songs = results
          .where((item) => item['type'] == 'video')
          .map((item) {
            return Song(
              id: item['bvid']?.toString() ?? '',
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

      return SearchResult(songs: songs, page: page, hasMore: page < numPages);
    } catch (e) {
      print('❌ 搜索异常: $e');
      return SearchResult(songs: [], page: page, hasMore: false);
    }
  }

  // ═══════════════════════════════════════════
  // 解析音频流
  // ═══════════════════════════════════════════
  static Future<String?> getSongUrl(String bvid) async {
    await _ensureWbi();

    try {
      final viewRes = await http
          .get(Uri.parse('$_viewUrl?bvid=$bvid'), headers: _headers())
          .timeout(const Duration(seconds: 10));

      final viewJson = jsonDecode(utf8.decode(viewRes.bodyBytes));
      if (viewJson['code'] != 0) {
        print('❌ 获取视频信息失败: ${viewJson['message']}');
        return null;
      }
      final cid = viewJson['data']?['cid'];
      if (cid == null) return null;

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
      if (json['code'] != 0) {
        print('❌ playurl 失败: ${json['message']} (code: ${json['code']})');
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
            print('✅ 解析成功 (durl)');
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
              print('✅ 解析成功 (dash)');
              return url;
            }
          }
        }
      }

      print('❌ 无可用音频流');
      return null;
    } catch (e) {
      print('❌ 解析异常: $e');
      return null;
    }
  }

  // ═══════════════════════════════════════════
  // 获取字幕/歌词
  // ═══════════════════════════════════════════
  static Future<List<MapEntry<double, String>>> getLyric(String bvid) async {
    await _ensureWbi();

    try {
      final viewRes = await http
          .get(Uri.parse('$_viewUrl?bvid=$bvid'), headers: _headers())
          .timeout(const Duration(seconds: 10));

      final viewJson = jsonDecode(utf8.decode(viewRes.bodyBytes));
      if (viewJson['code'] != 0) return [];
      final aid = viewJson['data']?['aid'];
      final cid = viewJson['data']?['cid'];
      if (aid == null || cid == null) return [];

      final params = <String, String>{
        'aid': aid.toString(),
        'cid': cid.toString(),
      };
      _signParams(params);

      final uri = Uri.parse(_playerV2Url).replace(queryParameters: params);
      final res = await http
          .get(uri, headers: _headers())
          .timeout(const Duration(seconds: 10));

      final json = jsonDecode(utf8.decode(res.bodyBytes));
      final subtitles = json['data']?['subtitle']?['subtitles'] as List?;
      if (subtitles == null || subtitles.isEmpty) {
        print('ℹ️ 该视频无字幕');
        return [];
      }

      String? subUrl = subtitles[0]['subtitle_url']?.toString();
      if (subUrl == null || subUrl.isEmpty) return [];
      if (subUrl.startsWith('//')) subUrl = 'https:$subUrl';

      final subRes = await http
          .get(Uri.parse(subUrl), headers: _headers())
          .timeout(const Duration(seconds: 10));

      final subJson = jsonDecode(utf8.decode(subRes.bodyBytes));
      final body = subJson['body'] as List? ?? [];

      return body.map<MapEntry<double, String>>((line) {
        final from = (line['from'] as num?)?.toDouble() ?? 0;
        final content = line['content']?.toString() ?? '';
        return MapEntry(from, content);
      }).toList();
    } catch (e) {
      print('❌ 获取字幕失败: $e');
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
