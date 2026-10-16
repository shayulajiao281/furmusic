import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/song.dart';
import '../providers/app_state.dart';
import '../providers/player_state.dart';
import '../providers/music_sources.dart';
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
  String _currentKeyword = '';
  bool _loading = false;
  bool _searched = false;

  String? _filterSource;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  /// 先按源筛选，再按是否隐藏 VIP 筛选
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

  Future<void> _search() async {
    final kw = _searchCtrl.text.trim();
    if (kw.isEmpty) return;
    FocusScope.of(context).unfocus();

    setState(() {
      _loading = true;
      _searched = true;
      _results = [];
      _currentKeyword = kw;
    });

    final aggregator = ref.read(aggregateSearchProvider);
    await aggregator.search(
      kw,
      page: 1,
      onPartial: (partial) {
        if (!mounted) return;
        setState(() {
          _results = partial;
          _loading = false;
        });
      },
    );
    if (mounted) setState(() => _loading = false);
  }

  void _playSong(Song song, List<Song> queue) {
    final notifier = ref.read(playerStateProvider.notifier);
    final appNotifier = ref.read(appStateProvider.notifier);
    notifier.playSong(song, queue: queue);
    appNotifier.addRecent(song);
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

  @override
  Widget build(BuildContext context) {
    final player = ref.watch(playerStateProvider);
    final favorites = ref.watch(favoriteSongsProvider);
    final hideVip = ref.watch(hideVipProvider);
    final results = _displayResults(hideVip);

    // 隐藏后如果原结果里全是 VIP，提示用户
    final allHiddenByVip =
        _results.isNotEmpty &&
        results.isEmpty &&
        _filterSource == null &&
        hideVip;

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
                        placeholder: '搜索音乐（B站 / 网易 / QQ）',
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

            // 音源筛选 chips
            if (_searched && _results.isNotEmpty)
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
                  ? _empty(allHiddenByVip: allHiddenByVip)
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                      itemCount: results.length,
                      itemBuilder: (_, i) {
                        final s = results[i];
                        final isFav = favorites.any(
                          (f) => f.globalId == s.globalId,
                        );
                        final displaySong = s.copyWith(isFavorite: isFav);
                        final active = player.current?.globalId == s.globalId;
                        final isLoadingThis =
                            player.isLoading &&
                            player.current?.globalId == s.globalId;

                        return SongTile(
                          song: displaySong,
                          active: active,
                          loading: isLoadingThis,
                          onTap: () => _playSong(s, results),
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

  Widget _chip(String label, String? source) {
    final selected = _filterSource == source;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: () => setState(() => _filterSource = source),
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

  Widget _empty({required bool allHiddenByVip}) => Center(
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
          allHiddenByVip
              ? '搜到的都是 VIP 歌曲\n（可在「我的」里关闭隐藏 VIP）'
              : (_searched ? '没有找到相关歌曲' : '搜索全网音乐'),
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
