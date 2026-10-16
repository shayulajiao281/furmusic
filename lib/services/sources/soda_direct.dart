import 'dart:convert';
import '../../models/song.dart';
import '../music_source.dart';
import 'direct_source.dart';

class SodaDirect extends DirectSource {
  @override
  String get id => 'soda';
  @override
  String get name => '抖音音乐';
  @override
  int get weight => 6;

  @override
  Map<String, String> get headers => {
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
    'Referer': 'https://music.douyin.com/',
  };

  @override
  Uri searchUri(String keyword, int page, int pageSize) {
    return Uri.parse(
      'https://api.suyanw.cn/api/qishuimusic.php',
    ).replace(queryParameters: {'msg': keyword, 'type': 'json'});
  }

  @override
  @override
  SearchResult parseSearchResult(
    Map<String, dynamic> json,
    int page,
    int pageSize,
  ) {
    try {
      // ★ 只从 json['data'] 里取列表；取不到就返回空
      final List rawList;
      if (json['data'] is List) {
        rawList = json['data'] as List;
      } else if (json['songs'] is List) {
        rawList = json['songs'] as List;
      } else {
        rawList = const [];
      }

      final songs = <Song>[];
      for (final item in rawList) {
        if (item is! Map) continue;
        final m = Map<String, dynamic>.from(item);

        final link = m['link']?.toString() ?? '';
        final trackId = _extractTrackId(link);
        if (trackId == null) continue;

        final title = m['title']?.toString() ?? '';
        final singer = m['singer']?.toString() ?? '';
        final coverRaw = m['cover']?.toString() ?? '';

        songs.add(
          Song(
            id: trackId,
            source: id,
            title: title.isEmpty ? '未知歌曲' : title,
            artist: singer.isEmpty ? '未知歌手' : singer,
            album: '',
            coverPath: _fixCover(coverRaw),
            audioPath: '',
            duration: Duration.zero,
            isVip: m['pay']?.toString() == 'vip',
          ),
        );
      }

      final start = (page - 1) * pageSize;
      final end = (start + pageSize).clamp(0, songs.length);
      final pageSongs = start < songs.length
          ? songs.sublist(start, end)
          : <Song>[];

      return SearchResult(songs: pageSongs, hasMore: end < songs.length);
    } catch (e) {
      print('❌ [soda] 解析搜索 JSON 出错: $e');
      return const SearchResult(songs: [], hasMore: false);
    }
  }

  String? _extractTrackId(String link) {
    final m = RegExp(r'track_id=(\d+)').firstMatch(link);
    return m?.group(1);
  }

  String _fixCover(String raw) {
    if (raw.isEmpty) return '';
    if (raw.startsWith('http')) return raw;
    // API 可能返回相对路径，按需补前缀
    if (raw.startsWith('//')) return 'https:$raw';
    return raw;
  }

  @override
  Future<String?> getSongUrlById(String songId) async {
    try {
      // 用 Meting 公共实例拿汽水音乐的播放直链
      final uri = Uri.parse('https://qqovo.top/api/meting').replace(
        queryParameters: {
          'server': 'qishui',
          'type': 'url',
          'id': songId,
          'quality': 'exhigh',
        },
      );

      final res = await client
          .get(uri, headers: headers)
          .timeout(const Duration(seconds: 12));
      if (res.statusCode != 200) {
        print('❌ [soda] url 请求 HTTP ${res.statusCode}');
        return null;
      }

      final text = utf8.decode(res.bodyBytes);
      // Meting 返回可能是 JSON 或纯文本 URL
      try {
        final json = jsonDecode(text);
        if (json is List && json.isNotEmpty) {
          final url = json[0]['url']?.toString();
          if (url != null && url.isNotEmpty) return url;
        }
        if (json is Map && json['url'] != null) {
          return json['url'].toString();
        }
      } catch (_) {
        // 不是 JSON，可能是纯 URL
        if (text.startsWith('http')) return text.trim();
      }

      print('❌ [soda] 未拿到有效 url');
      return null;
    } catch (e) {
      print('❌ [soda] url 异常: $e');
      return null;
    }
  }

  @override
  Future<List<MapEntry<double, String>>> getLyricById(String songId) async {
    try {
      final uri = Uri.parse(
        'https://api.suyanw.cn/api/qishuimusic.php',
      ).replace(queryParameters: {'track_id': songId, 'type': 'json'});

      final res = await client
          .get(uri, headers: headers)
          .timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) {
        print('❌ [soda] lyric HTTP ${res.statusCode}');
        return [];
      }

      final json = jsonDecode(utf8.decode(res.bodyBytes));
      final lrc = _extractLrc(json);
      if (lrc.isEmpty) return [];
      return parseLrc(lrc);
    } catch (e) {
      print('❌ [soda] lyric 异常: $e');
      return [];
    }
  }

  String _extractLrc(dynamic json) {
    if (json is Map) {
      final lrc = json['lrc']?.toString();
      if (lrc != null && lrc.isNotEmpty) return lrc;
      // 可能在 data 里
      final data = json['data'];
      if (data is Map) {
        final l2 = data['lrc']?.toString();
        if (l2 != null && l2.isNotEmpty) return l2;
      }
    } else if (json is List && json.isNotEmpty) {
      final first = json[0];
      if (first is Map) {
        return first['lrc']?.toString() ?? '';
      }
    }
    return '';
  }
}
