import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/app_state.dart';
import '../providers/player_state.dart';
import '../theme/app_colors.dart';
import '../widgets/song_tile.dart';

class MusicPage extends ConsumerWidget {
  const MusicPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appNotifier = ref.read(appStateProvider.notifier);
    final playerNotifier = ref.read(playerStateProvider.notifier);
    final player = ref.watch(playerStateProvider);
    final recent = appNotifier.recentSongs;

    return Container(
      color: AppColors.bg,
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // 标题
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '音乐',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.5,
                            height: 1.25,
                            color: AppColors.text,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          recent.isEmpty
                              ? '还没有播放记录'
                              : '最近播放 ${recent.length} 首',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // 列表
            Expanded(
              child: recent.isEmpty
                  ? _empty()
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
                      itemCount: recent.length,
                      itemBuilder: (_, i) {
                        final s = recent[i];
                        return SongTile(
                          song: s,
                          active: player.current?.id == s.id,
                          onTap: () =>
                              playerNotifier.playSong(s, queue: recent),
                          onFavorite: () => appNotifier.toggleFavorite(s),
                        );
                      },
                    ),
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
          '还没有播放记录\n去「发现」页搜歌试试',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13.5, color: AppColors.muted, height: 1.7),
        ),
      ],
    ),
  );
}
