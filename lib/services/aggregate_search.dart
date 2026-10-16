import 'dart:async';
import '../models/song.dart';
import 'music_source.dart';

class AggregateSearch {
  final List<MusicSource> sources;
  AggregateSearch(this.sources);

  Future<List<Song>> search(
    String keyword, {
    int page = 1,
    void Function(List<Song> merged)? onPartial,
  }) async {
    print('🔎 [聚合] 开始搜索 "${keyword}" (${sources.length} 个源)');
    final merged = <Song>[];
    final seen = <String>{};

    void addAll(List<Song> list) {
      for (final s in list) {
        if (seen.add(s.globalId)) merged.add(s);
      }
    }

    final futures = sources.map((src) async {
      try {
        final r = await src
            .search(keyword, page: page)
            .timeout(const Duration(seconds: 12));
        return MapEntry(src, r.songs);
      } catch (e) {
        // 每个源失败都单独打日志，不吞掉
        print('❌ [聚合] ${src.name} 失败: $e');
        return MapEntry(src, <Song>[]);
      }
    }).toList();

    await for (final entry in _asCompleted(futures)) {
      print('📦 [聚合] ${entry.key.name} 返回 ${entry.value.length} 条');
      addAll(entry.value);
      onPartial?.call(List.unmodifiable(merged));
    }

    print('🔎 [聚合] 完成 "${keyword}" → 共 ${merged.length} 条');

    merged.sort((a, b) {
      final wa = _weightOf(a.source);
      final wb = _weightOf(b.source);
      return wb.compareTo(wa);
    });

    return merged;
  }

  int _weightOf(String sourceId) {
    for (final s in sources) {
      if (s.id == sourceId) return s.weight;
    }
    return 0;
  }

  Stream<T> _asCompleted<T>(List<Future<T>> futures) {
    final controller = StreamController<T>();
    int remaining = futures.length;
    if (remaining == 0) {
      controller.close();
      return controller.stream;
    }
    for (final f in futures) {
      f.then((v) {
        controller.add(v);
        if (--remaining == 0) controller.close();
      });
    }
    return controller.stream;
  }
}
