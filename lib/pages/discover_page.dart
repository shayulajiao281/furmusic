import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/song.dart';
import '../providers/app_state.dart';
import '../providers/player_state.dart';
import '../providers/music_sources.dart';
import '../services/music_source.dart';
import '../theme/app_colors.dart';
import '../utils/play_or_open.dart';
import '../widgets/song_tile.dart';

class DiscoverPage extends ConsumerStatefulWidget {
  const DiscoverPage({super.key});
  @override
  ConsumerState<DiscoverPage> createState() => _DiscoverPageState();
}

class _DiscoverPageState extends ConsumerState<DiscoverPage> {
  final _searchCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();

  final List<Song> _results = [];
  final Set<String> _seenIds = {};

  String _currentKeyword = '';
  bool _loading = false;
  bool _loadingMore = false;
  bool _searched = false;

  final Map<String, int> _srcPage = {};
  final Map<String, bool> _srcHasMore = {};

  String? _filterSource;

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

  void _onScroll() {
    if (!_scrollCtrl.hasClients) return;
    final pos = _scrollCtrl.position;
    if (pos.pixels >= pos.maxScrollExtent - 300) {
      _loadMore();
    }
  }

  List<Song> _displayResults(bool hideVip) {
    var list = _results;
    if (_filterSource != null) {
      list = list.where((s) => s.source == _filterSource).toList();
    }
    if (hideVip) {
      list = list.where((s) => !s.isVip).toList();
    }
    return list;
  }

  bool get _shouldShowFooter {
    if (!_searched) return false;
    if (_filterSource == null) {
      return _srcHasMore.values.any((v) => v);
    }
    return _srcHasMore[_filterSource] ?? false;
  }

  Future<void> _search() async {
    final kw = _searchCtrl.text.trim();
    if (kw.isEmpty) return;
    FocusScope.of(context).unfocus();

    setState(() {
      _loading = true;
      _searched = true;
      _results.clear();
      _seenIds.clear();
      _currentKeyword = kw;
      _srcPage.clear();
      _srcHasMore.clear();
    });

    final sources = ref.read(allSourcesProvider);
    final futures = sources.map((s) => _fetchPage(s, 1)).toList();

    try {
      // 等待全部并发结束，设置 10 秒全局兜底防卡死
      await Future.wait(futures).timeout(const Duration(seconds: 10));
    } catch (e) {
      print('⚠️ [discover] 搜索整体超时或部分出错: $e');
    }

    if (!mounted) return;
    setState(() => _loading = false);
  }

  Future<void> _loadMore() async {
    if (_loadingMore || _loading) return;
    if (_currentKeyword.isEmpty) return;
    if (!_shouldShowFooter) return;

    final allSources = ref.read(allSourcesProvider);
    final pool = _filterSource == null
        ? allSources
        : allSources.where((s) => s.id == _filterSource).toList();

    final targets = pool.where((s) => _srcHasMore[s.id] ?? false).toList();
    if (targets.isEmpty) return;

    setState(() => _loadingMore = true);

    final futures = targets.map((s) {
      final next = (_srcPage[s.id] ?? 1) + 1;
      return _fetchPage(s, next);
    }).toList();

    try {
      await Future.wait(futures).timeout(const Duration(seconds: 10));
    } catch (e) {
      print('⚠️ [discover] 加载更多超时: $e');
    }

    if (!mounted) return;
    setState(() => _loadingMore = false);
  }

  Future<void> _fetchPage(MusicSource source, int page) async {
    try {
      final r = await source.search(_currentKeyword, page: page, pageSize: 20);
      if (!mounted) return;
      setState(() {
        for (final s in r.songs) {
          if (_seenIds.add(s.globalId)) {
            _results.add(s);
          }
        }
        _srcPage[source.id] = page;
        _srcHasMore[source.id] = r.hasMore;
      });
    } catch (e) {
      print('❌ [discover] ${source.name} 搜索失败: $e');
      if (mounted) {
        setState(() {
          _srcHasMore[source.id] = false;
        });
      }
    }
  }

  void _toggleFav(Song song) {
    ref.read(appStateProvider.notifier).toggleFavorite(song);
    final isFav = ref
        .read(favoriteSongsProvider)
        .any((s) => s.globalId == song.globalId);
    setState(() {
      final idx = _results.indexWhere((s) => s.globalId == song.globalId);
      if (idx >= 0) {
        _results[idx] = _results[idx].copyWith(isFavorite: isFav);
      }
    });
  }

  void _selectSource(String? source) {
    if (_filterSource == source) return;
    setState(() => _filterSource = source);
  }

  @override
  Widget build(BuildContext context) {
    final favorites = ref.watch(favoriteSongsProvider);
    final hideVip = ref.watch(hideVipProvider);
    final results = _displayResults(hideVip);
    final showFooter = _shouldShowFooter;

    final currentId = ref.watch(
      playerStateProvider.select((s) => s.current?.globalId),
    );
    final loadingId = ref.watch(
      playerStateProvider.select((s) => s.isLoading ? s.current?.globalId : null),
    );

    final favIds = favorites.map((s) => s.globalId).toSet();

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
                        placeholder: '搜索音乐（B站 / 网易 / QQ / 酷狗）',
                        placeholderStyle: const TextStyle(
                          fontSize: 14,
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

            // 源筛选 chips
            if (_searched)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
                child: SizedBox(
                  height: 30,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      _chip('全部', null),
                      _chip('B站', 'bilibili'),
                      _chip('网易云', 'netease'),
                      _chip('QQ音乐', 'qq'),
                      _chip('酷狗', 'kugou'),
                    ],
                  ),
                ),
              ),

            const SizedBox(height: 8),

            // 结果列表
            Expanded(
              child: _loading
                  ? const Center(child: CupertinoActivityIndicator())
                  : results.isEmpty
                  ? _empty()
                  : ListView.builder(
                      controller: _scrollCtrl,
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                      itemCount: results.length + (showFooter ? 1 : 0),
                      itemBuilder: (_, i) {
                        if (i >= results.length) {
                          return _footer();
                        }

                        final s = results[i];
                        final displaySong = s.copyWith(isFavorite: favIds.contains(s.globalId));
                        final active = currentId == s.globalId;
                        final isLoadingThis = loadingId == s.globalId;

                        return SongTile(
                          song: displaySong,
                          active: active,
                          loading: isLoadingThis,
                          onTap: () => playOrOpen(
                            context,
                            ref,
                            s,
                            appendToQueue: true,
                          ),
                          onFavorite: () => _toggleFav(displaySong),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _footer() {
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

  Widget _chip(String label, String? source) {
    final selected = _filterSource == source;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: () => _selectSource(source),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? AppColors.primary : CupertinoColors.white,
            borderRadius: BorderRadius.circular(15),
            border: Border.all(
              color: selected ? AppColors.primary : AppColors.line,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: selected ? CupertinoColors.white : AppColors.muted,
            ),
          ),
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
          _searched ? '没有找到相关歌曲' : '搜索全网音乐',
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