import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/app_state.dart';
import '../providers/player_state.dart';
import '../services/music_scanner.dart';
import '../theme/app_colors.dart';
import '../widgets/song_tile.dart';

class LocalMusicPage extends ConsumerStatefulWidget {
  const LocalMusicPage({super.key});
  @override
  ConsumerState<LocalMusicPage> createState() => _LocalMusicPageState();
}

class _LocalMusicPageState extends ConsumerState<LocalMusicPage> {
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
    ref.read(appStateProvider.notifier).setLocalSongs(songs);
    setState(() => _scanning = false);
  }

  @override
  Widget build(BuildContext context) {
    final songs = ref.watch(localSongsProvider);
    final favorites = ref.watch(favoriteSongsProvider);
    final player = ref.watch(playerStateProvider);
    final playerNotifier = ref.read(playerStateProvider.notifier);
    final appNotifier = ref.read(appStateProvider.notifier);

    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: const Text('本地音乐'),
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          minSize: 0,
          onPressed: _scan,
          child: _scanning
              ? const CupertinoActivityIndicator(radius: 8)
              : const Icon(
                  CupertinoIcons.arrow_clockwise,
                  size: 20,
                  color: AppColors.primary,
                ),
        ),
      ),
      child: Container(
        color: AppColors.bg,
        child: songs.isEmpty
            ? _empty()
            : ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                itemCount: songs.length,
                itemBuilder: (_, i) {
                  final s = songs[i];
                  final isFav = favorites.any((f) => f.id == s.id);
                  final displaySong = s.copyWith(isFavorite: isFav);

                  return SongTile(
                    song: displaySong,
                    active: player.current?.id == s.id,
                    onTap: () {
                      playerNotifier.playSong(s, queue: songs);
                      appNotifier.addRecent(s);
                    },
                    onFavorite: () => appNotifier.toggleFavorite(s),
                  );
                },
              ),
      ),
    );
  }

  Widget _empty() => Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          _scanning ? CupertinoIcons.hourglass : CupertinoIcons.music_note_list,
          size: 50,
          color: AppColors.muted,
        ),
        const SizedBox(height: 14),
        Text(
          _scanning ? '正在扫描…' : '还没有本地音乐\n点右上角图标重新扫描',
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 13.5,
            color: AppColors.muted,
            height: 1.7,
          ),
        ),
      ],
    ),
  );
}
