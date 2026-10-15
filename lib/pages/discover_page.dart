import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/song.dart';
import '../providers/app_state.dart';
import '../providers/player_state.dart';
import '../services/music_api.dart';
import '../theme/app_colors.dart';
import '../widgets/song_tile.dart';

class DiscoverPage extends ConsumerStatefulWidget {
  const DiscoverPage({super.key});
  @override
  ConsumerState<DiscoverPage> createState() => _DiscoverPageState();
}

class _DiscoverPageState extends ConsumerState<DiscoverPage> {
  final _searchCtrl = TextEditingController();
  List<Song> _results = [];
  bool _loading = false;
  bool _searched = false;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final kw = _searchCtrl.text.trim();
    if (kw.isEmpty) return;
    FocusScope.of(context).unfocus();

    setState(() {
      _loading = true;
      _searched = true;
    });

    final songs = await MusicApi.search(kw);
    if (!mounted) return;
    setState(() {
      _results = songs;
      _loading = false;
    });
  }

  void _playSong(Song song) {
    final notifier = ref.read(playerStateProvider.notifier);
    final appNotifier = ref.read(appStateProvider.notifier);
    notifier.playSong(song, queue: _results);
    appNotifier.addRecent(song);
  }

  void _toggleFav(Song song) {
    final appNotifier = ref.read(appStateProvider.notifier);
    appNotifier.toggleFavorite(song);

    // 从收藏列表里查最新状态，同步到 _results
    final latest = ref.read(favoriteSongsProvider).any((s) => s.id == song.id);
    setState(() {
      final idx = _results.indexWhere((s) => s.id == song.id);
      if (idx >= 0) {
        _results[idx] = _results[idx].copyWith(isFavorite: latest);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final player = ref.watch(playerStateProvider);
    final favorites = ref.watch(favoriteSongsProvider);

    return Container(
      color: AppColors.bg,
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 10),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '发现音乐',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                    color: AppColors.text,
                  ),
                ),
              ),
            ),

            // 搜索框
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                height: 46,
                decoration: BoxDecoration(
                  color: CupertinoColors.white,
                  borderRadius: BorderRadius.circular(13),
                  border: Border.all(color: AppColors.line, width: 1.5),
                ),
                child: Row(
                  children: [
                    const SizedBox(width: 12),
                    const Icon(
                      CupertinoIcons.search,
                      size: 18,
                      color: AppColors.muted,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: CupertinoTextField(
                        controller: _searchCtrl,
                        placeholder: '搜索 B站音乐',
                        placeholderStyle: const TextStyle(
                          fontSize: 14.5,
                          color: Color(0xFFC2C8D6),
                        ),
                        style: const TextStyle(
                          fontSize: 15,
                          color: AppColors.text,
                        ),
                        decoration: null,
                        clearButtonMode: OverlayVisibilityMode.editing,
                        onSubmitted: (_) => _search(),
                        onChanged: (_) => setState(() {}),
                        textInputAction: TextInputAction.search,
                      ),
                    ),
                    CupertinoButton(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      minSize: 0,
                      onPressed: _search,
                      child: const Text(
                        '搜索',
                        style: TextStyle(
                          fontSize: 14,
                          color: AppColors.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 14),

            Expanded(
              child: _loading
                  ? const Center(child: CupertinoActivityIndicator())
                  : _results.isEmpty
                  ? _empty()
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                      itemCount: _results.length,
                      itemBuilder: (_, i) {
                        final s = _results[i];
                        final isFav = favorites.any((f) => f.id == s.id);
                        final displaySong = s.copyWith(isFavorite: isFav);

                        return SongTile(
                          song: displaySong,
                          active: player.current?.id == s.id,
                          onTap: () => _playSong(s),
                          onFavorite: () => _toggleFav(displaySong),
                        );
                      },
                    ),
            ),

            if (player.isLoading)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 14),
                color: const Color(0xED1E2231),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CupertinoActivityIndicator(
                      radius: 9,
                      color: CupertinoColors.white,
                    ),
                    SizedBox(width: 12),
                    Text(
                      '正在加载队列…',
                      style: TextStyle(
                        color: CupertinoColors.white,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w500,
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

  Widget _empty() => Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          _searched ? CupertinoIcons.search : CupertinoIcons.compass,
          size: 50,
          color: AppColors.muted,
        ),
        const SizedBox(height: 14),
        Text(
          _searched ? '没有找到相关歌曲' : '搜索 B站音乐',
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
