import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/app_state.dart';
import '../providers/player_state.dart';
import '../services/music_scanner.dart';
import '../theme/app_colors.dart';
import '../widgets/song_tile.dart';

class MusicPage extends ConsumerStatefulWidget {
  const MusicPage({super.key});
  @override
  ConsumerState<MusicPage> createState() => _MusicPageState();
}

class _MusicPageState extends ConsumerState<MusicPage> {
  bool _scanning = false;

  @override
  void initState() {
    super.initState();
    _scan();
  }

  Future<void> _scan() async {
    setState(() => _scanning = true);
    final songs = await MusicScanner.scanLocal();
    if (!mounted) return;
    ref.read(appStateProvider.notifier).setSongs(songs);
    setState(() => _scanning = false);
  }

  @override
  Widget build(BuildContext context) {
    final songs = ref.watch(allSongsProvider);
    final player = ref.watch(playerStateProvider);
    final notifier = ref.read(playerStateProvider.notifier);
    final appNotifier = ref.read(appStateProvider.notifier);

    return Container(
      color: AppColors.bg,
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
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
                          songs.isEmpty ? '还没有歌曲' : '共 ${songs.length} 首',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  GestureDetector(
                    onTap: _scan,
                    child: Container(
                      width: 36,
                      height: 36,
                      margin: const EdgeInsets.only(top: 2),
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x66FF7A59),
                            blurRadius: 15,
                            offset: Offset(0, 6),
                          ),
                        ],
                      ),
                      child: _scanning
                          ? const Padding(
                              padding: EdgeInsets.all(9),
                              child: CupertinoActivityIndicator(
                                color: CupertinoColors.white,
                              ),
                            )
                          : const Icon(
                              CupertinoIcons.arrow_clockwise,
                              size: 18,
                              color: CupertinoColors.white,
                            ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: songs.isEmpty
                  ? _empty()
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
                      itemCount: songs.length,
                      itemBuilder: (_, i) {
                        final s = songs[i];
                        return SongTile(
                          song: s,
                          active: player.current?.id == s.id,
                          onTap: () {
                            notifier.playSong(s, queue: songs);
                            appNotifier.addRecent(s.id);
                          },
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
          '还没有歌曲\n点右上角扫描本地音乐',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13.5, color: AppColors.muted, height: 1.7),
        ),
      ],
    ),
  );
}
