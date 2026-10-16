import '../models/song.dart';

class SearchResult {
  final List<Song> songs;
  final bool hasMore;
  const SearchResult({required this.songs, this.hasMore = false});
}

/// 所有音乐平台的统一接口
abstract class MusicSource {
  /// 唯一标识，'bilibili' / 'netease' / 'qq' / 'kugou'
  String get id;

  /// 显示名
  String get name;

  /// 排序权重（越大越靠前）
  int get weight;

  /// 搜索。返回的每条 Song.source 必须填成 [id]
  Future<SearchResult> search(
    String keyword, {
    int page = 1,
    int pageSize = 20,
  });

  /// 解析音频直链
  Future<String?> getSongUrl(String songId);

  /// 歌词
  Future<List<MapEntry<double, String>>> getLyric(String songId);

  /// 音频流请求头
  Map<String, String> get audioHeaders;
}
