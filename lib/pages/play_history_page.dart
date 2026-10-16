import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
    final recent = ref.watch(recentSongsProvider);
    final favorites = ref.watch(favoriteSongsProvider);
    final player = ref.watch(playerStateProvider);
    final appNotifier = ref.read(appStateProvider.notifier);

    final hasSong = ref.watch(
      playerStateProvider.select((s) => s.current != null),
    );

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
                          padding:
                              const EdgeInsets.fromLTRB(16, 12, 16, 20),
                          itemCount: recent.length,
                          itemBuilder: (_, i) {
                            final s = recent[i];
                            final isFav = favorites.any(
                              (f) => f.globalId == s.globalId,
                            );
                            final displaySong =
                                s.copyWith(isFavorite: isFav);
                            final active =
                                player.current?.globalId == s.globalId;
                            final isLoadingThis = player.isLoading && active;

                            return SongTile(
                              song: displaySong,
                              active: active,
                              loading: isLoadingThis,
                              // ★ 用 playOrOpen
                              onTap: () => playOrOpen(
                                context,
                                ref,
                                s,
                                queue: recent,
                              ),
                              onFavorite: () =>
                                  appNotifier.toggleFavorite(s),
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