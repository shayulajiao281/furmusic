import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/app_state.dart';
import '../providers/auth_state.dart';
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
    final favorites = ref.watch(favoriteSongsProvider);
    final recent = ref.watch(recentSongsProvider);
    final hideVip = ref.watch(hideVipProvider);
    final auth = ref.watch(authProvider);

    final visibleFavorites = hideVip
        ? favorites.where((s) => !s.isVip).toList()
        : favorites;

    final loggedCount = [
      auth.bilibili,
      auth.netease,
      auth.qq,
    ].where((e) => e != null).length;

    return Container(
      color: AppColors.bg,
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
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
                  // ★ 账号入口
                  _entryCard(
                    icon: CupertinoIcons.person_crop_circle_fill,
                    title: '账号',
                    subtitle: loggedCount == 0
                        ? '登录 B站 / 网易云 / QQ音乐'
                        : '已登录 $loggedCount 个平台',
                    onTap: () => context.push('/account'),
                  ),
                  const SizedBox(height: 10),

                  // 本地音乐
                  _entryCard(
                    icon: CupertinoIcons.music_note_list,
                    title: '本地音乐',
                    subtitle: '扫描手机里已下载的歌曲',
                    onTap: () => context.push('/local-music'),
                  ),
                  const SizedBox(height: 10),

                  // 播放历史
                  _entryCard(
                    icon: CupertinoIcons.clock,
                    title: '播放历史',
                    subtitle: recent.isEmpty
                        ? '还没有播放记录'
                        : '共 ${recent.length} 首',
                    onTap: () => context.push('/play-history'),
                  ),
                  const SizedBox(height: 10),

                  // 隐藏 VIP
                  _switchCard(
                    icon: CupertinoIcons.eye_slash,
                    title: '隐藏 VIP 歌曲',
                    subtitle: hideVip ? '已隐藏需要会员的歌曲' : '显示全部歌曲',
                    value: hideVip,
                    onChanged: (v) => appNotifier.setHideVip(v),
                  ),

                  const SizedBox(height: 20),

                  // 我的收藏
                  _sectionTitle('我的收藏 · ${visibleFavorites.length}'),
                  if (visibleFavorites.isEmpty)
                    _emptyHint(
                      favorites.isEmpty ? '还没有收藏的歌曲' : '当前隐藏了所有 VIP 收藏',
                    )
                  else
                    ...visibleFavorites.map(
                      (s) => SongTile(
                        song: s,
                        active: player.current?.globalId == s.globalId,
                        onTap: () {
                          playerNotifier.playSong(s, queue: visibleFavorites);
                          appNotifier.addRecent(s);
                        },
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

  Widget _entryCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
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
              child: Icon(icon, size: 22, color: AppColors.primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppColors.text,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: const TextStyle(
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
    );
  }

  Widget _switchCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onChanged(!value),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
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
              child: Icon(icon, size: 22, color: AppColors.primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppColors.text,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.muted,
                    ),
                  ),
                ],
              ),
            ),
            CupertinoSwitch(
              value: value,
              activeTrackColor: AppColors.primary,
              onChanged: onChanged,
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
