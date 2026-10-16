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
  final _scrollCtrl = ScrollController();

  List<Song> _results = [];
  String _currentKeyword = '';
  int _currentPage = 0;
  bool _hasMore = true;
  bool _loading = false;
  bool _loadingMore = false;
  bool _searched = false;

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(_onScroll);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  /// 滚动到底部自动加载
  void _onScroll() {
    if (!_scrollCtrl.hasClients) return;
    final pos = _scrollCtrl.position;
    // 距离底部 < 300px → 加载下一页
    if (pos.pixels >= pos.maxScrollExtent - 300) {
      _loadMore();
    }
  }

  /// 首次搜索
  Future<void> _search() async {
    final kw = _searchCtrl.text.trim();
    if (kw.isEmpty) return;
    FocusScope.of(context).unfocus();

    setState(() {
      _loading = true;
      _searched = true;
      _results = [];
      _currentKeyword = kw;
      _currentPage = 0;
      _hasMore = true;
    });

    final result = await MusicApi.search(kw, page: 1);
    if (!mounted) return;

    setState(() {
      _results = result.songs;
      _currentPage = 1;
      _hasMore = result.hasMore;
      _loading = false;
    });
  }

  /// 加载下一页
  Future<void> _loadMore() async {
    if (_loadingMore || _loading || !_hasMore) return;
    if (_currentKeyword.isEmpty) return;

    setState(() => _loadingMore = true);

    final nextPage = _currentPage + 1;
    final result = await MusicApi.search(_currentKeyword, page: nextPage);
    if (!mounted) return;

    setState(() {
      final existIds = _results.map((s) => s.id).toSet();
      final newSongs = result.songs
          .where((s) => !existIds.contains(s.id))
          .toList();
      _results.addAll(newSongs);
      _currentPage = nextPage;
      _hasMore = result.hasMore;
      _loadingMore = false;
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

    final isFav = ref.read(favoriteSongsProvider).any((s) => s.id == song.id);
    setState(() {
      final idx = _results.indexWhere((s) => s.id == song.id);
      if (idx >= 0) {
        _results[idx] = _results[idx].copyWith(isFavorite: isFav);
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
        child: Stack(
          children: [
            Column(
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

                // 结果列表
                Expanded(
                  child: _loading
                      ? const Center(child: CupertinoActivityIndicator())
                      : _results.isEmpty
                      ? _empty()
                      : ListView.builder(
                          controller: _scrollCtrl,
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                          itemCount: _results.length + (_hasMore ? 1 : 0),
                          itemBuilder: (_, i) {
                            if (i == _results.length) {
                              return _loadMoreFooter();
                            }

                            final s = _results[i];
                            final isFav = favorites.any((f) => f.id == s.id);
                            final displaySong = s.copyWith(isFavorite: isFav);
                            final isLoadingThis =
                                player.isLoading && player.current?.id == s.id;

                            return SongTile(
                              song: displaySong,
                              active: player.current?.id == s.id,
                              loading: isLoadingThis,
                              onTap: () => _playSong(s),
                              onFavorite: () => _toggleFav(displaySong),
                            );
                          },
                        ),
                ),
              ],
            ),

            // 悬浮加载条
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: IgnorePointer(
                ignoring: !player.isLoading,
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 200),
                  opacity: player.isLoading ? 1.0 : 0.0,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: const BoxDecoration(color: Color(0xED1E2231)),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CupertinoActivityIndicator(
                          radius: 8,
                          color: CupertinoColors.white,
                        ),
                        SizedBox(width: 10),
                        Text(
                          '正在加载…',
                          style: TextStyle(
                            color: CupertinoColors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 底部"加载更多"提示
  Widget _loadMoreFooter() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Center(
        child: _loadingMore
            ? const CupertinoActivityIndicator(radius: 8)
            : const Text(
                '上拉加载更多',
                style: TextStyle(fontSize: 12, color: AppColors.muted),
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
