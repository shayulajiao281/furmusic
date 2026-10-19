import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/app_state.dart';
import '../providers/player_state.dart';
import '../theme/app_colors.dart';
import 'song_tile.dart';

void showPlaylistSheet(BuildContext context) {
  showCupertinoModalPopup(
    context: context,
    barrierColor: const Color(0x6B0C0F19),
    builder: (_) => const PlaylistSheet(),
  );
}

class PlaylistSheet extends ConsumerWidget {
  const PlaylistSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final player = ref.watch(playerStateProvider);
    final notifier = ref.read(playerStateProvider.notifier);
    final favorites = ref.watch(favoriteSongsProvider);
    final queue = player.queue;
    final currentId = player.current?.globalId;

    final bottomInset = MediaQuery.of(context).padding.bottom;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.7,
      ),
      decoration: const BoxDecoration(
        color: CupertinoColors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // handle
          Container(
            width: 38,
            height: 4,
            margin: const EdgeInsets.only(top: 14, bottom: 14),
            decoration: BoxDecoration(
              color: const Color(0xFFE2E5EE),
              borderRadius: BorderRadius.circular(4),
            ),
          ),

          // 标题
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Row(
              children: [
                const Text(
                  '当前播放列表',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                    color: AppColors.text,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${queue.length} 首',
                  style: const TextStyle(fontSize: 12, color: AppColors.muted),
                ),
                const Spacer(),
                CupertinoButton(
                  padding: EdgeInsets.zero,
                  minSize: 0,
                  onPressed: () => Navigator.pop(context),
                  child: const Icon(
                    CupertinoIcons.xmark_circle_fill,
                    size: 22,
                    color: Color(0xFFCCD1E0),
                  ),
                ),
              ],
            ),
          ),

          // 提示
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '左滑删除 · 长按也可删除',
                style: TextStyle(
                  fontSize: 11,
                  color: AppColors.muted.withValues(alpha: 0.8),
                ),
              ),
            ),
          ),

          // 列表
          Flexible(
            child: queue.isEmpty
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 60),
                    child: Center(
                      child: Text(
                        '播放列表为空',
                        style: TextStyle(fontSize: 13, color: AppColors.muted),
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: EdgeInsets.fromLTRB(16, 0, 16, 20 + bottomInset),
                    itemCount: queue.length,
                    itemBuilder: (_, i) {
                      final s = queue[i];
                      final isFav = favorites.any(
                        (f) => f.globalId == s.globalId,
                      );
                      final displaySong = s.copyWith(isFavorite: isFav);
                      final active = s.globalId == currentId;

                      return Dismissible(
                        key: ValueKey('pl_${s.globalId}'),
                        direction: DismissDirection.endToStart,
                        background: Container(
                          margin: const EdgeInsets.only(bottom: 9),
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          alignment: Alignment.centerRight,
                          decoration: BoxDecoration(
                            color: AppColors.red,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: const Icon(
                            CupertinoIcons.delete,
                            color: CupertinoColors.white,
                            size: 22,
                          ),
                        ),
                        onDismissed: (_) {
                          notifier.removeFromQueue(s);
                        },
                        child: GestureDetector(
                          // 长按也可删除
                          onLongPress: () async {
                            final ok = await showCupertinoDialog<bool>(
                              context: context,
                              builder: (_) => CupertinoAlertDialog(
                                title: const Text('移出播放列表'),
                                content: Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: Text('确定要把《${s.title}》从播放列表移除吗？'),
                                ),
                                actions: [
                                  CupertinoDialogAction(
                                    onPressed: () =>
                                        Navigator.pop(context, false),
                                    child: const Text('取消'),
                                  ),
                                  CupertinoDialogAction(
                                    isDestructiveAction: true,
                                    onPressed: () =>
                                        Navigator.pop(context, true),
                                    child: const Text('移除'),
                                  ),
                                ],
                              ),
                            );
                            if (ok == true) {
                              notifier.removeFromQueue(s);
                            }
                          },
                          child: SongTile(
                            song: displaySong,
                            active: active,
                            onTap: () {
                              notifier.playFromQueue(i);
                            },
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}