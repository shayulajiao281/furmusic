import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/music_source.dart';
import '../services/aggregate_search.dart';
import '../services/sources/bilibili_source.dart';
import '../services/sources/netease_direct.dart';
import '../services/sources/qq_direct.dart';

final allSourcesProvider = Provider<List<MusicSource>>(
  (ref) => [BilibiliSource(), NeteaseDirect(), QQDirect()],
);

final aggregateSearchProvider = Provider<AggregateSearch>((ref) {
  return AggregateSearch(ref.watch(allSourcesProvider));
});

final sourceByIdProvider = Provider<MusicSource Function(String)>((ref) {
  final list = ref.watch(allSourcesProvider);
  return (id) {
    for (final s in list) {
      if (s.id == id) return s;
    }
    return list.first;
  };
});
