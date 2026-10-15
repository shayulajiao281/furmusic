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
  bool _resolving = false;
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

  Future<void> _playSong(Song song) async {
    if (_resolving) return;

    if (song.audioPath.isNotEmpty) {
      _doPlay(song);
      return;
    }

    setState(() => _resolving = true);

    final url = await MusicApi.getSongUrl(song.id);
    if (!mounted) return;

    setState(() => _resolving = false);

    if (url == null || url.isEmpty) {
      _alert('解析失败（可能是付费内容或区域限制）');
      return;
    }

    final playable = song.copyWith(audioPath: url);

    setState(() {
      final idx = _results.indexWhere((s) => s.id == song.id);
      if (idx >= 0) _results[idx] = playable;
    });

    _doPlay(playable);
  }

  void _doPlay(Song song) {
    final notifier = ref.read(playerStateProvider.notifier);
    final appNotifier = ref.read(appStateProvider.notifier);
    notifier.playSong(song, queue: _results);
    appNotifier.addRecent(song.id);
  }

  /// 收藏（点完后同步更新 _results，让心形变化）
  void _toggleFav(Song song) {
    final appNotifier = ref.read(appStateProvider.notifier);
    appNotifier.toggleFavorite(song);

    // ★ 从 state 里读最新的收藏状态，同步到 _results
    final latest = ref
        .read(appStateProvider)
        .songs
        .where((s) => s.id == song.id)
        .toList();
    if (latest.isNotEmpty) {
      setState(() {
        final idx = _results.indexWhere((s) => s.id == song.id);
        if (idx >= 0) _results[idx] = latest.first;
      });
    }
  }

  void _alert(String msg) {
    showCupertinoDialog(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        content: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(msg, style: const TextStyle(fontSize: 13)),
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('好的'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final player = ref.watch(playerStateProvider);
    final allSongs = ref.watch(allSongsProvider); // ★ watch，收藏变化时刷新

    return Container(
      color: AppColors.bg,
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // 标题
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

            // 结果列表
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
                        // ★ 从 state.songs 里查最新的收藏状态
                        final live = allSongs
                            .where((x) => x.id == s.id)
                            .toList();
                        final displaySong = live.isNotEmpty
                            ? s.copyWith(isFavorite: live.first.isFavorite)
                            : s;

                        return SongTile(
                          song: displaySong,
                          active: player.current?.id == s.id,
                          onTap: () => _playSong(s),
                          onFavorite: () => _toggleFav(displaySong),
                        );
                      },
                    ),
            ),

            // 底部"正在解析"提示条
            if (_resolving)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                color: const Color(0xED1E2231),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CupertinoActivityIndicator(
                      radius: 8,
                      color: CupertinoColors.white,
                    ),
                    SizedBox(width: 10),
                    Text(
                      '正在解析音频…',
                      style: TextStyle(
                        color: CupertinoColors.white,
                        fontSize: 13,
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
