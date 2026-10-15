import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/app_state.dart';
import '../providers/player_state.dart';
import '../theme/app_colors.dart';
import 'song_cover.dart';

class MiniPlayer extends ConsumerWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final player = ref.watch(playerStateProvider);
    final song = player.current;
    if (song == null) return const SizedBox.shrink();

    // 从 app_state 拿实时收藏状态
    final allSongs = ref.watch(allSongsProvider);
    final live = allSongs.where((s) => s.id == song.id).toList();
    final isFav = live.isNotEmpty ? live.first.isFavorite : false;

    return GestureDetector(
      onTap: () => context.push('/player'),
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(16),
          boxShadow: AppColors.cardShadow,
        ),
        child: Row(
          children: [
            SongCover(path: song.coverPath, size: 40, radius: 10),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    song.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.text,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    song.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.muted,
                      height: 1.2,
                    ),
                  ),
                ],
              ),
            ),
            // 收藏
            GestureDetector(
              onTap: () =>
                  ref.read(appStateProvider.notifier).toggleFavorite(song),
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Icon(
                  isFav ? CupertinoIcons.heart_fill : CupertinoIcons.heart,
                  size: 20,
                  color: isFav ? AppColors.red : AppColors.muted,
                ),
              ),
            ),
            // 播放/暂停
            GestureDetector(
              onTap: () => ref.read(playerStateProvider.notifier).togglePlay(),
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Icon(
                  player.isPlaying
                      ? CupertinoIcons.pause_fill
                      : CupertinoIcons.play_fill,
                  size: 26,
                  color: AppColors.primary,
                ),
              ),
            ),
            // 下一首
            GestureDetector(
              onTap: () => ref.read(playerStateProvider.notifier).next(),
              child: const Padding(
                padding: EdgeInsets.all(6),
                child: Icon(
                  CupertinoIcons.forward_fill,
                  size: 20,
                  color: AppColors.text,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
