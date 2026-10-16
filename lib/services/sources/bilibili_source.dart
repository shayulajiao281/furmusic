import '../../models/song.dart';
import '../music_source.dart';
import 'bilibili/bili_api.dart';

class BilibiliSource implements MusicSource {
  @override
  String get id => 'bilibili';

  @override
  String get name => 'B站';

  @override
  int get weight => 10;

  @override
  Future<SearchResult> search(
    String keyword, {
    int page = 1,
    int pageSize = 20,
  }) async {
    final r = await BiliApi.search(keyword, page: page, pageSize: pageSize);
    return SearchResult(songs: r.songs, hasMore: r.hasMore);
  }

  @override
  Future<String?> getSongUrl(String songId) => BiliApi.getSongUrl(songId);

  @override
  Future<List<MapEntry<double, String>>> getLyric(String songId) =>
      BiliApi.getLyric(songId);

  @override
  Map<String, String> get audioHeaders => BiliApi.audioHeaders;
}
