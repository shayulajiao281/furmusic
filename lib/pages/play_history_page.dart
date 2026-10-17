import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/song.dart';
import '../providers/app_state.dart';
import '../providers/player_state.dart';
import '../theme/app_colors.dart';
import '../utils/play_or_open.dart';
import '../widgets/mini_player.dart';
import '../widgets/song_tile.dart';

class PlayHistoryPage extends ConsumerWidget {
  const PlayHistoryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // ★ 只 watch 数据源，不 watch 整个 player
    final recent = ref.watch(recentSongsProvider);

    // ★ 收藏用 Set（O(1) 查找），不再用 List.any()（O(n)）
    final favIds = ref.watch(
      favoriteSongsProvider.select(
        (list) => list.map((s) => s.globalId).toSet(),
      ),
    );

    // ★ 只订阅"当前歌 id"和"哪首歌在 loading"
    //   position 每秒变几十次，但这两个值很少变 → 页面几乎不重建
    final currentId = ref.watch(
      playerStateProvider.select((s) => s.current?.globalId),
    );
    final loadingId = ref.watch(
      playerStateProvider.select(
        (s) => s.isLoading ? s.current?.globalId : null,
      ),
    );

    // ★ hasSong 独立 select，避免跟着 current 其他字段重建
    final hasSong = ref.watch(
      playerStateProvider.select((s) => s.current != null),
    );

    final appNotifier = ref.read(appStateProvider.notifier);

    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: const Text('播放历史'),
        trailing: recent.isEmpty
            ? null
            : CupertinoButton(
                padding: EdgeInsets.zero,
                minSize: 0,
                onPressed: () {
                  showCupertinoDialog(
                    context: context,
                    builder: (ctx) => CupertinoAlertDialog(
                      title: const Text('清空历史'),
                      content: const Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: Text('确定要清空所有播放历史吗？'),
                      ),
                      actions: [
                        CupertinoDialogAction(
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text('取消'),
                        ),
                        CupertinoDialogAction(
                          isDestructiveAction: true,
                          onPressed: () {
                            Navigator.pop(ctx);
                            appNotifier.clearRecent();
                          },
                          child: const Text('清空'),
                        ),
                      ],
                    ),
                  );
                },
                child: const Icon(
                  CupertinoIcons.trash,
                  size: 20,
                  color: AppColors.primary,
                ),
              ),
      ),
      child: Container(
        color: AppColors.bg,
        child: Stack(
          children: [
            Positioned.fill(
              child: SafeArea(
                top: true,
                bottom: false,
                child: Padding(
                  padding: EdgeInsets.only(bottom: hasSong ? 56 : 0),
                  child: recent.isEmpty
                      ? _empty()
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                          itemCount: recent.length,
                          itemBuilder: (_, i) {
                            final s = recent[i];
                            return _HistoryTile(
                              key: ValueKey(s.globalId),
                              song: s,
                              isFav: favIds.contains(s.globalId),
                              active: currentId == s.globalId,
                              loading: loadingId == s.globalId,
                            );
                          },
                        ),
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: const MiniPlayer(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _empty() => Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: const [
        Text('🎵', style: TextStyle(fontSize: 50, height: 1)),
        SizedBox(height: 14),
        Text(
          '还没有播放历史',
          style: TextStyle(fontSize: 13.5, color: AppColors.muted),
        ),
      ],
    ),
  );
}

/// ★ 每项独立，避免整列表重建
class _HistoryTile extends ConsumerWidget {
  final Song song;
  final bool isFav;
  final bool active;
  final bool loading;

  const _HistoryTile({
    super.key,
    required this.song,
    required this.isFav,
    required this.active,
    required this.loading,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SongTile(
      song: song.copyWith(isFavorite: isFav),
      active: active,
      loading: loading,
      onTap: () {
        // 队列 = 最新的最近播放列表
        final queue = ref.read(recentSongsProvider);
        playOrOpen(context, ref, song, queue: queue);
      },
      onFavorite: () {
        ref.read(appStateProvider.notifier).toggleFavorite(song);
      },
    );
  }
}