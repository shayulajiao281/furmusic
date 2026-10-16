import 'dart:math';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/song.dart';
import '../providers/app_state.dart';
import '../providers/player_state.dart';
import '../services/music_api.dart';
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
    '2026 爆火',
    '华语热歌',
    '当下最火',
    '网络热歌',
    '流行金曲',
    '卡点神曲',
    '热搜榜',
    '热歌榜',
    '华语排行榜',
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
    '王力宏',
    '五月天',
    '张学友',
    '华语情歌',
    '经典老歌',
    '8090 后',
    '华语民谣',
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
    '林子祥',
    '郑秀文',
    '李克勤',
    '粤语金曲',
  ]),
  RecommendCategory('english', '英文歌曲', '🌍', [
    '英文流行',
    'Taylor Swift',
    'Ed Sheeran',
    'Adele',
    'Bruno Mars',
    'Billie Eilish',
    '英文经典',
    '欧美热歌',
    '英文情歌',
    '欧美排行榜',
    '英文摇滚',
    '英文民谣',
  ]),
  RecommendCategory('pure', '纯音乐', '🎹', [
    '钢琴曲',
    '轻音乐 助眠',
    '纯音乐 治愈',
    '古风纯音乐',
    '吉他指弹',
    '小提琴',
    '钢琴 舒缓',
    '音乐 学习',
    '轻音乐 咖啡',
    '治愈系 纯音乐',
    '八音盒',
    '尤克里里',
  ]),
  RecommendCategory('folk', '民谣', '🎸', [
    '民谣',
    '赵雷',
    '房东的猫',
    '陈粒',
    '宋冬野',
    '马頔',
    '朴树',
    '李志',
    '民谣 治愈',
    '民谣 吉他',
    '独立民谣',
    '中国民谣',
  ]),
];

class MusicPage extends ConsumerStatefulWidget {
  const MusicPage({super.key});
  @override
  ConsumerState<MusicPage> createState() => _MusicPageState();
}

class _MusicPageState extends ConsumerState<MusicPage> {
  final Map<String, List<Song>> _recommendsByCategory = {};
  final Map<String, String> _keywordByCategory = {};
  bool _loading = false;

  final Set<String> _shownIds = {};

  @override
  void initState() {
    super.initState();
    _loadAllCategories();
  }

  Future<void> _loadAllCategories() async {
    if (mounted) setState(() => _loading = true);
    // 清空去重记录，每次刷新都重新开始
    _shownIds.clear();
    for (final cat in _categories) {
      await _loadCategory(cat.id);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadCategory(String categoryId) async {
    final cat = _categories.firstWhere((c) => c.id == categoryId);
    final kw = cat.keywords[Random().nextInt(cat.keywords.length)];
    final page = 1 + Random().nextInt(3);

    final result = await MusicApi.search(kw, page: page, pageSize: 30);
    if (!mounted) return;

    final shuffled = [...result.songs]..shuffle();

    final fresh = shuffled.where((s) => !_shownIds.contains(s.id)).toList();
    final fallback = shuffled.where((s) => _shownIds.contains(s.id)).toList();

    final picked = [
      ...fresh.take(6),
      ...fallback.take((6 - fresh.length).clamp(0, 6)),
    ].take(6).toList();

    for (final s in picked) {
      _shownIds.add(s.id);
    }

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

    return Container(
      color: AppColors.bg,
      child: SafeArea(
        bottom: false,
        child: CustomScrollView(
          // ★ iOS 风格下拉刷新
          physics: const BouncingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics(),
          ),
          slivers: [
            // ═══════ 下拉刷新控件 ═══════
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
                    // 默认样式即可，也可自定义
                    return const Center(
                      child: CupertinoActivityIndicator(
                        radius: 10,
                        color: AppColors.primary,
                      ),
                    );
                  },
            ),

            // ═══════ 标题 ═══════
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

            // ═══════ 最近播放 ═══════
            if (recent.isNotEmpty) ...[
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
                        '${recent.length} 首',
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
                delegate: SliverChildBuilderDelegate((_, i) {
                  final s = recent[i];
                  final isFav = favorites.any((f) => f.id == s.id);
                  final displaySong = s.copyWith(isFavorite: isFav);
                  final isLoadingThis =
                      player.isLoading && player.current?.id == s.id;

                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: SongTile(
                      song: displaySong,
                      active: player.current?.id == s.id,
                      loading: isLoadingThis,
                      onTap: () {
                        playerNotifier.playSong(s, queue: recent);
                        appNotifier.addRecent(s);
                      },
                      onFavorite: () => appNotifier.toggleFavorite(s),
                    ),
                  );
                }, childCount: recent.length > 3 ? 3 : recent.length),
              ),
            ],

            // ═══════ 为你推荐 ═══════
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

            // 每个分类一行
            ..._categories.map(
              (cat) => SliverToBoxAdapter(
                child: _categoryCard(
                  context,
                  cat,
                  player,
                  favorites,
                  playerNotifier,
                  appNotifier,
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
  ) {
    final songs = _recommendsByCategory[cat.id] ?? [];
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
                // 每个分类单独刷新的小按钮
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
                  final isFav = favorites.any((f) => f.id == s.id);
                  final displaySong = s.copyWith(isFavorite: isFav);
                  final isLoadingThis =
                      player.isLoading && player.current?.id == s.id;

                  return _songCard(
                    displaySong,
                    player,
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
    PlayerState player,
    bool isLoadingThis, {
    required VoidCallback onTap,
    required VoidCallback onFavorite,
  }) {
    final active = player.current?.id == song.id;

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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 132,
                height: 100,
                decoration: const BoxDecoration(
                  color: Color(0xFFF6F7FB),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(11),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 90,
                      height: 10,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF0F1F6),
                        borderRadius: BorderRadius.circular(5),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      width: 60,
                      height: 8,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF0F1F6),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
