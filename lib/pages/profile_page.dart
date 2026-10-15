import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
    final recent = appNotifier.recentSongs;

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
                  _sectionTitle('最近播放 · ${recent.length}'),
                  if (recent.isEmpty)
                    _emptyHint('还没有播放记录')
                  else
                    ...recent.map(
                      (s) => SongTile(
                        song: s,
                        active: player.current?.id == s.id,
                        onTap: () => playerNotifier.playSong(s, queue: recent),
                        onFavorite: () => appNotifier.toggleFavorite(s.id),
                      ),
                    ),
                  const SizedBox(height: 8),
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
                        onFavorite: () => appNotifier.toggleFavorite(s.id),
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
    padding: const EdgeInsets.fromLTRB(4, 14, 4, 10),
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
