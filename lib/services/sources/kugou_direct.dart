import 'dart:convert';
import 'package:crypto/crypto.dart';
import '../../models/song.dart';
import '../music_source.dart';
import '../auth_store.dart';
import 'direct_source.dart';

class KugouDirect extends DirectSource {
  @override
  String get id => 'kugou';
  @override
  String get name => '酷狗音乐';
  @override
  int get weight => 6;

  @override
  Map<String, String> get headers {
    final cookie = AuthStore.cookieFor('kugou');
    return {
      'User-Agent':
          'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
      'Referer': 'https://www.kugou.com/',
      if (cookie.isNotEmpty) 'Cookie': cookie,
    };
  }

  // ═══════════════════════════════════════════
  // 搜索
  // ═══════════════════════════════════════════
  @override
  Uri searchUri(String keyword, int page, int pageSize) {
    return Uri.parse('http://mobilecdn.kugou.com/api/v3/search/song')
        .replace(queryParameters: {
      'format': 'json',
      'keyword': keyword,
      'page': '$page',
      'pagesize': '$pageSize',
      'showtype': '1',
    });
  }

  @override
  SearchResult parseSearchResult(
    Map<String, dynamic> json,
    int page,
    int pageSize,
  ) {
    try {
      final data = json['data'];
      final total = (data?['total'] as int?) ?? 0;
      final rawList = (data?['info'] as List?) ?? [];

      final songs = rawList.map<Song?>((item) {
        if (item is! Map) return null;
        final m = Map<String, dynamic>.from(item);

        final hash = m['hash']?.toString() ?? '';
        if (hash.isEmpty) return null;

        final singerName = m['singername']?.toString() ??
            m['singer_name']?.toString() ??
            '';
        final songName = m['songname']?.toString() ??
            m['song_name']?.toString() ??
            '';
        if (songName.isEmpty) return null;

        final albumId = m['album_id']?.toString() ?? '';
        final cover = albumId.isEmpty
            ? ''
            : 'https://imge.kugou.com/stdmusic/240/$albumId.jpg';

        final durationSec = (m['duration'] as int?) ?? 0;
        final privilege =
            m['privilege'] as int? ?? m['pay_type'] as int? ?? 0;
        final isVip = privilege == 10 || privilege == 5;

        return Song(
          id: hash,
          source: id,
          title: songName,
          artist: singerName.isEmpty ? '未知歌手' : singerName,
          album: m['album_name']?.toString() ?? '',
          coverPath: cover,
          audioPath: '',
          duration: Duration(seconds: durationSec),
          isVip: isVip,
        );
      }).whereType<Song>().toList();

      final offset = (page - 1) * pageSize;
      final hasMore = offset + songs.length < total;

      return SearchResult(songs: songs, hasMore: hasMore);
    } catch (e) {
      print('❌ [kugou] 解析搜索 JSON 出错: $e');
      return const SearchResult(songs: [], hasMore: false);
    }
  }

  // ═══════════════════════════════════════════
  // ★ 播放地址：换用 trackercdn 接口（无需 mid/dfid）
  // ═══════════════════════════════════════════
  @override
  Future<String?> getSongUrlById(String songId) async {
    try {
      // 计算签名：md5(hash + 'kgcloudv2')
      final key =
          md5.convert(utf8.encode('${songId}kgcloudv2')).toString();

      final uri = Uri.parse('https://trackercdn.kugou.com/i/v2/')
          .replace(queryParameters: {
        'key': key,
        'hash': songId,
        'br': 'hq',
        'appid': '1005',
        'pid': '2',
        'cmd': '25',
        'behavior': 'play',
      });

      print('🔗 [kugou] 请求播放地址: $uri');
      final res = await client
          .get(uri, headers: headers)
          .timeout(const Duration(seconds: 12));

      if (res.statusCode != 200) {
        print('❌ [kugou] HTTP ${res.statusCode}');
        return null;
      }

      final text = utf8.decode(res.bodyBytes);

      // 成功返回结构：
      // {"url":["https://.../xxx.mp3"],"fileSize":...,"extName":"mp3"}
      // 失败：
      // {"status":0,"error":"..."}
      try {
        final json = jsonDecode(text);
        if (json is Map) {
          final status = json['status'];
          final error = json['error'];
          if (status != null && status != 1 && status != 200) {
            print('❌ [kugou] 接口返回 status=$status error=$error');
            return null;
          }

          final urlField = json['url'];
          if (urlField is List && urlField.isNotEmpty) {
            final u = urlField[0]?.toString() ?? '';
            if (u.isNotEmpty) {
              print('✅ [kugou] 解析成功');
              return u;
            }
          } else if (urlField is String && urlField.isNotEmpty) {
            print('✅ [kugou] 解析成功');
            return urlField;
          }

          print('❌ [kugou] 未找到 url 字段: $text');
          return null;
        }
      } catch (_) {
        print('❌ [kugou] 非 JSON 返回: ${text.substring(0, text.length.clamp(0, 200))}');
        return null;
      }

      return null;
    } catch (e) {
      print('❌ [kugou] url 异常: $e');
      return null;
    }
  }

  // ═══════════════════════════════════════════
  // 歌词
  // ═══════════════════════════════════════════
  @override
  Future<List<MapEntry<double, String>>> getLyricById(String songId) async {
    try {
      final searchUri = Uri.parse(
        'http://krcs.kugou.com/search',
      ).replace(queryParameters: {
        'ver': '1',
        'man': 'yes',
        'client': 'mobi',
        'keyword': '',
        'hash': songId,
      });

      final searchRes = await client
          .get(searchUri, headers: headers)
          .timeout(const Duration(seconds: 10));
      if (searchRes.statusCode != 200) return [];

      final searchJson =
          jsonDecode(utf8.decode(searchRes.bodyBytes));
      final candidates = searchJson['candidates'] as List? ?? [];
      if (candidates.isEmpty) return [];

      final cand = Map<String, dynamic>.from(candidates[0] as Map);
      final id = cand['id']?.toString();
      final accesskey = cand['accesskey']?.toString();
      if (id == null || accesskey == null) return [];

      final lyricUri = Uri.parse(
        'http://lyrics.kugou.com/download',
      ).replace(queryParameters: {
        'ver': '1',
        'client': 'pc',
        'id': id,
        'accesskey': accesskey,
        'fmt': 'lrc',
        'charset': 'utf8',
      });

      final lyricRes = await client
          .get(lyricUri, headers: headers)
          .timeout(const Duration(seconds: 10));
      if (lyricRes.statusCode != 200) return [];

      final lyricJson =
          jsonDecode(utf8.decode(lyricRes.bodyBytes));
      final content = lyricJson['content']?.toString() ?? '';
      if (content.isEmpty) return [];

      try {
        final lrc = utf8.decode(base64.decode(content));
        return parseLrc(lrc);
      } catch (_) {
        return parseLrc(content);
      }
    } catch (e) {
      print('❌ [kugou] lyric 异常: $e');
      return [];
    }
  }
}