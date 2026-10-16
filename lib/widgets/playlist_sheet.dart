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
    final currentId = player.current?.id;

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
                      final isFav = favorites.any((f) => f.id == s.id);
                      final displaySong = s.copyWith(isFavorite: isFav);
                      final active = s.id == currentId;

                      return SongTile(
                        song: displaySong,
                        active: active,
                        onTap: () {
                          // 播放队列里的第 i 首
                          notifier.playFromQueue(i);
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
