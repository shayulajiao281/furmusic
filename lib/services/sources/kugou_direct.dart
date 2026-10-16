import 'dart:convert';
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
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
      'Referer': 'https://www.kugou.com/',
      if (cookie.isNotEmpty) 'Cookie': cookie,
    };
  }

  // ═══════════════════════════════════════════
  // 搜索（HTTP，避开酷狗 CDN 的证书主机名不匹配）
  // ═══════════════════════════════════════════
  @override
  Uri searchUri(String keyword, int page, int pageSize) {
    return Uri.parse('http://mobilecdn.kugou.com/api/v3/search/song').replace(
      queryParameters: {
        'format': 'json',
        'keyword': keyword,
        'page': '$page',
        'pagesize': '$pageSize',
        'showtype': '1',
      },
    );
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

      final songs = rawList
          .map<Song?>((item) {
            if (item is! Map) return null;
            final m = Map<String, dynamic>.from(item);

            final hash = m['hash']?.toString() ?? '';
            if (hash.isEmpty) return null;

            final singerName =
                m['singername']?.toString() ??
                m['singer_name']?.toString() ??
                '';
            final songName =
                m['songname']?.toString() ?? m['song_name']?.toString() ?? '';
            if (songName.isEmpty) return null;

            final albumId = m['album_id']?.toString() ?? '';
            final cover = albumId.isEmpty
                ? ''
                : 'https://imge.kugou.com/stdmusic/240/$albumId.jpg';

            final durationSec = (m['duration'] as int?) ?? 0;

            // privilege: 0/8 免费; 10 会员; 5 付费
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
          })
          .whereType<Song>()
          .toList();

      final offset = (page - 1) * pageSize;
      final hasMore = offset + songs.length < total;

      return SearchResult(songs: songs, hasMore: hasMore);
    } catch (e) {
      print('❌ [kugou] 解析搜索 JSON 出错: $e');
      return const SearchResult(songs: [], hasMore: false);
    }
  }

  // ═══════════════════════════════════════════
  // 拿播放直链
  // ═══════════════════════════════════════════
  @override
  Future<String?> getSongUrlById(String songId) async {
    try {
      final uri = Uri.parse('http://wwwapi.kugou.com/yy/index.php').replace(
        queryParameters: {
          'r': 'play/getdata',
          'hash': songId,
          'dfid': '2qGyqq0CxV2w3n0iC0W0K2Ne',
          'mid': 'b3b9a5f0a2c88f47b3b9a5f0a2c88f47',
          'platid': '4',
          'album_id': '0',
          '_': '${DateTime.now().millisecondsSinceEpoch}',
        },
      );

      final res = await client
          .get(uri, headers: headers)
          .timeout(const Duration(seconds: 12));

      if (res.statusCode != 200) {
        print('❌ [kugou] url HTTP ${res.statusCode}');
        return null;
      }

      final json = jsonDecode(utf8.decode(res.bodyBytes));
      final data = json['data'];
      final playUrl = data?['play_url']?.toString();
      final errCode = json['err_code'];

      if (playUrl == null || playUrl.isEmpty) {
        print(
          '❌ [kugou] play_url 为空 (err_code=$errCode, msg=${data?['fail_process'] ?? json['error']})',
        );
        return null;
      }

      return playUrl;
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
      // 查歌词候选
      final searchUri = Uri.parse('http://krcs.kugou.com/search').replace(
        queryParameters: {
          'ver': '1',
          'man': 'yes',
          'client': 'mobi',
          'keyword': '',
          'hash': songId,
        },
      );

      final searchRes = await client
          .get(searchUri, headers: headers)
          .timeout(const Duration(seconds: 10));
      if (searchRes.statusCode != 200) return [];

      final searchJson = jsonDecode(utf8.decode(searchRes.bodyBytes));
      final candidates = searchJson['candidates'] as List? ?? [];
      if (candidates.isEmpty) return [];

      final cand = Map<String, dynamic>.from(candidates[0] as Map);
      final id = cand['id']?.toString();
      final accesskey = cand['accesskey']?.toString();
      if (id == null || accesskey == null) return [];

      // 拿歌词内容
      final lyricUri = Uri.parse('http://lyrics.kugou.com/download').replace(
        queryParameters: {
          'ver': '1',
          'client': 'pc',
          'id': id,
          'accesskey': accesskey,
          'fmt': 'lrc',
          'charset': 'utf8',
        },
      );

      final lyricRes = await client
          .get(lyricUri, headers: headers)
          .timeout(const Duration(seconds: 10));
      if (lyricRes.statusCode != 200) return [];

      final lyricJson = jsonDecode(utf8.decode(lyricRes.bodyBytes));
      final content = lyricJson['content']?.toString() ?? '';
      if (content.isEmpty) return [];

      // content 是 base64 编码的 LRC
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
