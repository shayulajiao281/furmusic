import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/app_state.dart';
import '../providers/player_state.dart';
import '../theme/app_colors.dart';
import '../widgets/song_tile.dart';

class ProfilePage extends ConsumerWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appNotifier = ref.read(appStateProvider.notifier);
    final playerNotifier = ref.read(playerStateProvider.notifier);
    final player = ref.watch(playerStateProvider);
    final favorites = appNotifier.favoriteSongs;

    return Container(
      color: AppColors.bg,
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // 标题
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 14),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '我的',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                    color: AppColors.text,
                  ),
                ),
              ),
            ),

            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
                children: [
                  // ★ 本地音乐入口
                  GestureDetector(
                    onTap: () => context.push('/local-music'),
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 14),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.card,
                        borderRadius: BorderRadius.circular(18),
                        boxShadow: AppColors.cardShadow,
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: AppColors.primarySoft,
                              borderRadius: BorderRadius.circular(13),
                            ),
                            child: const Icon(
                              CupertinoIcons.music_note_list,
                              size: 22,
                              color: AppColors.primary,
                            ),
                          ),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '本地音乐',
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.text,
                                    height: 1.3,
                                  ),
                                ),
                                SizedBox(height: 3),
                                Text(
                                  '扫描手机里已下载的歌曲',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: AppColors.muted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Icon(
                            CupertinoIcons.chevron_forward,
                            size: 18,
                            color: AppColors.muted,
                          ),
                        ],
                      ),
                    ),
                  ),

                  // 我的收藏
                  _sectionTitle('我的收藏 · ${favorites.length}'),
                  if (favorites.isEmpty)
                    _emptyHint('还没有收藏的歌曲')
                  else
                    ...favorites.map(
                      (s) => SongTile(
                        song: s,
                        active: player.current?.id == s.id,
                        onTap: () =>
                            playerNotifier.playSong(s, queue: favorites),
                        onFavorite: () => appNotifier.toggleFavorite(s),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String text) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 4, 4, 10),
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        color: AppColors.muted,
        letterSpacing: 0.3,
      ),
    ),
  );

  Widget _emptyHint(String text) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 20),
    child: Center(
      child: Text(
        text,
        style: const TextStyle(fontSize: 12.5, color: AppColors.muted),
      ),
    ),
  );
}
