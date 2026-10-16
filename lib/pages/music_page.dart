import 'dart:math';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/song.dart';
import '../providers/app_state.dart';
import '../providers/player_state.dart';
import '../providers/music_sources.dart';
import '../theme/app_colors.dart';
import '../widgets/song_tile.dart';

class RecommendCategory {
  final String id;
  final String label;
  final String emoji;
  final List<String> keywords;
  const RecommendCategory(this.id, this.label, this.emoji, this.keywords);
}

const _categories = [
  RecommendCategory('hot', '热门推荐', '🔥', [
    '热门华语歌曲',
    '抖音热歌',
    '2026 热门歌曲',
    '华语热歌',
    '网络热歌',
    '流行金曲',
    '热歌榜',
  ]),
  RecommendCategory('chinese', '华语流行', '🎤', [
    '华语经典',
    '周杰伦',
    '林俊杰',
    '陈奕迅',
    '薛之谦',
    '邓紫棋',
    '李荣浩',
    '毛不易',
    '许嵩',
    '五月天',
    '华语情歌',
  ]),
  RecommendCategory('cantonese', '粤语经典', '🎵', [
    '粤语经典',
    'Beyond',
    '张国荣',
    '张学友 粤语',
    '陈奕迅 粤语',
    '刘德华',
    '梅艳芳',
    '谭咏麟',
    '粤语金曲',
  ]),
  RecommendCategory('english', '英文歌曲', '🌍', [
    '英文流行',
    'Taylor Swift',
    'Ed Sheeran',
    'Adele',
    'Bruno Mars',
    '英文经典',
    '欧美热歌',
  ]),
  RecommendCategory('pure', '纯音乐', '🎹', [
    '钢琴曲',
    '轻音乐 助眠',
    '纯音乐 治愈',
    '古风纯音乐',
    '吉他指弹',
    '治愈系 纯音乐',
    '八音盒',
  ]),
  RecommendCategory('folk', '民谣', '🎸', [
    '民谣',
    '赵雷',
    '房东的猫',
    '陈粒',
    '宋冬野',
    '朴树',
    '民谣 治愈',
    '独立民谣',
  ]),
];

const int _perCategory = 6;

class MusicPage extends ConsumerStatefulWidget {
  const MusicPage({super.key});
  @override
  ConsumerState<MusicPage> createState() => _MusicPageState();
}

class _MusicPageState extends ConsumerState<MusicPage> {
  final Map<String, List<Song>> _recommendsByCategory = {};
  final Map<String, String> _keywordByCategory = {};
  bool _loading = false;
  final Set<String> _shownKeys = {};

  @override
  void initState() {
    super.initState();
    _loadAllCategories();
  }

  String _keyOf(Song s) =>
      '${s.title.toLowerCase().trim()}|${s.artist.toLowerCase().trim()}';

  Future<void> _loadAllCategories() async {
    if (mounted) setState(() => _loading = true);
    _shownKeys.clear();
    for (final cat in _categories) {
      await _loadCategory(cat.id);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadCategory(String categoryId) async {
    final cat = _categories.firstWhere((c) => c.id == categoryId);
    final kw = cat.keywords[Random().nextInt(cat.keywords.length)];
    final page = 1 + Random().nextInt(3);

    final netease = ref.read(sourceByIdProvider)('netease');
    final qq = ref.read(sourceByIdProvider)('qq');
    final kugou = ref.read(sourceByIdProvider)('kugou');

    // 三源并发，单源失败不影响其他
    final results = await Future.wait<List<Song>>([
      netease
          .search(kw, page: page, pageSize: 30)
          .then((r) => r.songs)
          .catchError((e) {
            print('❌ [推荐] 网易云搜索 "$kw" 失败: $e');
            return <Song>[];
          }),
      qq.search(kw, page: page, pageSize: 30).then((r) => r.songs).catchError((
        e,
      ) {
        print('❌ [推荐] QQ搜索 "$kw" 失败: $e');
        return <Song>[];
      }),
      kugou
          .search(kw, page: page, pageSize: 30)
          .then((r) => r.songs)
          .catchError((e) {
            print('❌ [推荐] 酷狗搜索 "$kw" 失败: $e');
            return <Song>[];
          }),
    ]);

    final neSongs = results[0];
    final qqSongs = results[1];
    final kgSongs = results[2];

    print(
      '📋 [推荐:$categoryId] "$kw" → 网易 ${neSongs.length} / QQ ${qqSongs.length} / 酷狗 ${kgSongs.length}',
    );

    // 三源交替混合：ne[0], qq[0], kg[0], ne[1], qq[1], kg[1]...
    final interleaved = <Song>[];
    final maxLen = max(max(neSongs.length, qqSongs.length), kgSongs.length);
    for (var i = 0; i < maxLen; i++) {
      if (i < neSongs.length) interleaved.add(neSongs[i]);
      if (i < qqSongs.length) interleaved.add(qqSongs[i]);
      if (i < kgSongs.length) interleaved.add(kgSongs[i]);
    }

    // 去重 + 排除已经显示过的
    final picked = <Song>[];
    for (final s in interleaved) {
      if (picked.length >= _perCategory) break;
      final key = _keyOf(s);
      if (_shownKeys.contains(key)) continue;
      _shownKeys.add(key);
      picked.add(s);
    }

    if (!mounted) return;
    setState(() {
      _keywordByCategory[categoryId] = kw;
      _recommendsByCategory[categoryId] = picked;
    });
  }

  @override
  Widget build(BuildContext context) {
    final appNotifier = ref.read(appStateProvider.notifier);
    final playerNotifier = ref.read(playerStateProvider.notifier);
    final player = ref.watch(playerStateProvider);
    final recent = ref.watch(recentSongsProvider);
    final favorites = ref.watch(favoriteSongsProvider);
    final hideVip = ref.watch(hideVipProvider);

    final visibleRecent = hideVip
        ? recent.where((s) => !s.isVip).toList()
        : recent;

    return Container(
      color: AppColors.bg,
      child: SafeArea(
        bottom: false,
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics(),
          ),
          slivers: [
            CupertinoSliverRefreshControl(
              onRefresh: _loadAllCategories,
              builder:
                  (
                    context,
                    refreshState,
                    pulledExtent,
                    refreshTriggerPullDistance,
                    refreshIndicatorExtent,
                  ) {
                    return const Center(
                      child: CupertinoActivityIndicator(
                        radius: 10,
                        color: AppColors.primary,
                      ),
                    );
                  },
            ),
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(20, 20, 20, 16),
                child: Text(
                  '音乐',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.8,
                    height: 1.15,
                    color: AppColors.text,
                  ),
                ),
              ),
            ),
            if (visibleRecent.isNotEmpty) ...[
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 10),
                  child: Row(
                    children: [
                      const Text(
                        '最近播放',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.3,
                          color: AppColors.text,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${visibleRecent.length} 首',
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: AppColors.muted,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (_, i) {
                    final s = visibleRecent[i];
                    final isFav = favorites.any(
                      (f) => f.globalId == s.globalId,
                    );
                    final displaySong = s.copyWith(isFavorite: isFav);
                    final active = player.current?.globalId == s.globalId;
                    final isLoadingThis = player.isLoading && active;

                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: SongTile(
                        song: displaySong,
                        active: active,
                        loading: isLoadingThis,
                        onTap: () {
                          playerNotifier.playSong(s, queue: visibleRecent);
                          appNotifier.addRecent(s);
                        },
                        onFavorite: () => appNotifier.toggleFavorite(s),
                      ),
                    );
                  },
                  childCount: visibleRecent.length > 3
                      ? 3
                      : visibleRecent.length,
                ),
              ),
            ],
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(20, 18, 20, 12),
                child: Text(
                  '为你推荐',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                    color: AppColors.text,
                  ),
                ),
              ),
            ),
            ..._categories.map(
              (cat) => SliverToBoxAdapter(
                child: _categoryCard(
                  context,
                  cat,
                  player,
                  favorites,
                  playerNotifier,
                  appNotifier,
                  hideVip,
                ),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 20)),
          ],
        ),
      ),
    );
  }

  Widget _categoryCard(
    BuildContext context,
    RecommendCategory cat,
    PlayerState player,
    List<Song> favorites,
    PlayerNotifier playerNotifier,
    AppStateNotifier appNotifier,
    bool hideVip,
  ) {
    final rawSongs = _recommendsByCategory[cat.id] ?? [];
    final songs = hideVip ? rawSongs.where((s) => !s.isVip).toList() : rawSongs;
    final keyword = _keywordByCategory[cat.id] ?? '';

    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Row(
              children: [
                Text(cat.emoji, style: const TextStyle(fontSize: 15)),
                const SizedBox(width: 6),
                Text(
                  cat.label,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                    color: AppColors.text,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    keyword,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.muted,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                GestureDetector(
                  onTap: () => _loadCategory(cat.id),
                  child: Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: AppColors.card,
                      shape: BoxShape.circle,
                      boxShadow: AppColors.cardShadow,
                    ),
                    child: const Icon(
                      CupertinoIcons.arrow_clockwise,
                      size: 12,
                      color: AppColors.muted,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (songs.isEmpty)
            _cardSkeleton()
          else
            SizedBox(
              height: 172,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: songs.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (_, i) {
                  final s = songs[i];
                  final isFav = favorites.any((f) => f.globalId == s.globalId);
                  final displaySong = s.copyWith(isFavorite: isFav);
                  final active = player.current?.globalId == s.globalId;
                  final isLoadingThis = player.isLoading && active;

                  return _songCard(
                    displaySong,
                    active,
                    isLoadingThis,
                    onTap: () {
                      playerNotifier.playSong(displaySong, queue: songs);
                      appNotifier.addRecent(displaySong);
                    },
                    onFavorite: () => appNotifier.toggleFavorite(displaySong),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _songCard(
    Song song,
    bool active,
    bool isLoadingThis, {
    required VoidCallback onTap,
    required VoidCallback onFavorite,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 132,
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(18),
          boxShadow: AppColors.cardShadow,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(18),
                  ),
                  child: SizedBox(
                    width: 132,
                    height: 100,
                    child: _buildCover(song.coverPath),
                  ),
                ),
                if (isLoadingThis)
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        color: CupertinoColors.black.withValues(alpha: 0.45),
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(18),
                        ),
                      ),
                      child: const Center(
                        child: CupertinoActivityIndicator(
                          radius: 10,
                          color: CupertinoColors.white,
                        ),
                      ),
                    ),
                  ),
                Positioned(
                  top: 6,
                  right: 6,
                  child: GestureDetector(
                    onTap: onFavorite,
                    child: Container(
                      padding: const EdgeInsets.all(5),
                      decoration: BoxDecoration(
                        color: CupertinoColors.black.withValues(alpha: 0.32),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        song.isFavorite
                            ? CupertinoIcons.heart_fill
                            : CupertinoIcons.heart,
                        size: 13,
                        color: song.isFavorite
                            ? AppColors.red
                            : CupertinoColors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(11, 9, 11, 11),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    song.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: active ? AppColors.primary : AppColors.text,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    song.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 10.5,
                      color: AppColors.muted,
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

  Widget _buildCover(String path) {
    if (path.isEmpty) {
      return Container(
        color: AppColors.coverBg,
        child: const Center(
          child: Icon(
            CupertinoIcons.music_note,
            size: 32,
            color: AppColors.muted,
          ),
        ),
      );
    }
    return Image.network(
      path,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => Container(
        color: AppColors.coverBg,
        child: const Center(
          child: Icon(
            CupertinoIcons.music_note,
            size: 32,
            color: AppColors.muted,
          ),
        ),
      ),
    );
  }

  Widget _cardSkeleton() {
    return SizedBox(
      height: 172,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: 3,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (_, __) => Container(
          width: 132,
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(18),
            boxShadow: AppColors.cardShadow,
          ),
        ),
      ),
    );
  }
}
