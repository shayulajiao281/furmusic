import 'dart:convert';
import 'dart:math';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/song.dart';
import '../providers/app_state.dart';
import '../providers/player_state.dart';
import '../providers/music_sources.dart';
import '../theme/app_colors.dart';
import '../utils/play_or_open.dart';
import '../widgets/song_cover.dart';
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
    '热门华语歌曲', '抖音热歌', '2026 热门歌曲', '华语热歌',
    '网络热歌', '流行金曲', '热歌榜',
  ]),
  RecommendCategory('chinese', '华语流行', '🎤', [
    '华语经典', '周杰伦', '林俊杰', '陈奕迅', '薛之谦',
    '邓紫棋', '李荣浩', '毛不易', '许嵩', '五月天', '华语情歌',
  ]),
  RecommendCategory('cantonese', '粤语经典', '🎵', [
    '粤语经典', 'Beyond', '张国荣', '张学友 粤语', '陈奕迅 粤语',
    '刘德华', '梅艳芳', '谭咏麟', '粤语金曲',
  ]),
  RecommendCategory('english', '英文歌曲', '🌍', [
    '英文流行', 'Taylor Swift', 'Ed Sheeran', 'Adele',
    'Bruno Mars', '英文经典', '欧美热歌',
  ]),
  RecommendCategory('pure', '纯音乐', '🎹', [
    '钢琴曲', '轻音乐 助眠', '纯音乐 治愈', '古风纯音乐',
    '吉他指弹', '治愈系 纯音乐', '八音盒',
  ]),
  RecommendCategory('folk', '民谣', '🎸', [
    '民谣', '赵雷', '房东的猫', '陈粒', '宋冬野',
    '朴树', '民谣 治愈', '独立民谣',
  ]),
];

const int _perCategory = 6;
const _kCacheKey = 'furkid_recommend_cache_v1';
const _kCacheTimeKey = 'furkid_recommend_cache_time';
const _cacheValidMs = 60 * 60 * 1000;

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
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final loadedFromCache = await _tryLoadCache();
    if (loadedFromCache) {
      print('📦 [推荐] 命中缓存，跳过网络请求');
      return;
    }
    await _loadAllCategories(saveCache: true);
  }

  Future<bool> _tryLoadCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kCacheKey);
      final t = prefs.getInt(_kCacheTimeKey) ?? 0;
      if (raw == null || raw.isEmpty) return false;
      if (DateTime.now().millisecondsSinceEpoch - t > _cacheValidMs) {
        return false;
      }

      final json = jsonDecode(raw) as Map<String, dynamic>;
      final keywordsRaw = json['keywords'] as Map<String, dynamic>? ?? {};
      final songsRaw = json['songs'] as Map<String, dynamic>? ?? {};

      setState(() {
        _recommendsByCategory.clear();
        _keywordByCategory.clear();
        songsRaw.forEach((catId, list) {
          _recommendsByCategory[catId] = (list as List)
              .map((e) => Song.fromJson(e as Map<String, dynamic>))
              .toList();
        });
        keywordsRaw.forEach((k, v) {
          _keywordByCategory[k] = v.toString();
        });
      });
      return true;
    } catch (e) {
      print('⚠️ [推荐] 缓存解析失败: $e');
      return false;
    }
  }

  Future<void> _saveCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = jsonEncode({
        'keywords': _keywordByCategory,
        'songs': _recommendsByCategory.map(
          (k, v) => MapEntry(k, v.map((s) => s.toJson()).toList()),
        ),
      });
      await prefs.setString(_kCacheKey, json);
      await prefs.setInt(
        _kCacheTimeKey,
        DateTime.now().millisecondsSinceEpoch,
      );
    } catch (e) {
      print('⚠️ [推荐] 缓存保存失败: $e');
    }
  }

  String _keyOf(Song s) =>
      '${s.title.toLowerCase().trim()}|${s.artist.toLowerCase().trim()}';

  Future<void> _loadAllCategories({bool saveCache = false}) async {
    if (mounted) setState(() => _loading = true);
    _shownKeys.clear();
    for (final cat in _categories) {
      await _loadCategory(cat.id);
      await Future.delayed(const Duration(milliseconds: 300));
    }
    if (mounted) setState(() => _loading = false);
    if (saveCache) await _saveCache();
  }

  Future<void> _loadCategory(String categoryId) async {
    final cat = _categories.firstWhere((c) => c.id == categoryId);
    final kw = cat.keywords[Random().nextInt(cat.keywords.length)];
    final page = 1 + Random().nextInt(3);

    final netease = ref.read(sourceByIdProvider)('netease');
    final kugou = ref.read(sourceByIdProvider)('kugou');

    final neFuture = netease
        .search(kw, page: page, pageSize: 30)
        .then((r) => r.songs)
        .catchError((e) {
      print('❌ [推荐] 网易搜索 "$kw" 失败: $e');
      return <Song>[];
    });

    await Future.delayed(const Duration(milliseconds: 200));

    final kgFuture = kugou
        .search(kw, page: page, pageSize: 30)
        .then((r) => r.songs)
        .catchError((e) {
      print('❌ [推荐] 酷狗搜索 "$kw" 失败: $e');
      return <Song>[];
    });

    final results = await Future.wait([neFuture, kgFuture]);
    final neSongs = results[0];
    final kgSongs = results[1];

    print('📋 [推荐:$categoryId] "$kw" → 网易 ${neSongs.length} / 酷狗 ${kgSongs.length}');

    final interleaved = <Song>[];
    final maxLen = max(neSongs.length, kgSongs.length);
    for (var i = 0; i < maxLen; i++) {
      if (i < neSongs.length) interleaved.add(neSongs[i]);
      if (i < kgSongs.length) interleaved.add(kgSongs[i]);
    }

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

  Future<void> _forceRefresh() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kCacheKey);
    await prefs.remove(_kCacheTimeKey);
    await _loadAllCategories(saveCache: true);
  }

  @override
  Widget build(BuildContext context) {
    final appNotifier = ref.read(appStateProvider.notifier);
    final recent = ref.watch(recentSongsProvider);
    final favorites = ref.watch(favoriteSongsProvider);
    final hideVip = ref.watch(hideVipProvider);

    final currentId = ref.watch(
      playerStateProvider.select((s) => s.current?.globalId),
    );
    final loadingId = ref.watch(
      playerStateProvider.select((s) => s.isLoading ? s.current?.globalId : null),
    );

    final favIds = favorites.map((s) => s.globalId).toSet();
    final visibleRecent =
        hideVip ? recent.where((s) => !s.isVip).toList() : recent;

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
              onRefresh: _forceRefresh,
              builder: (context, refreshState, pulledExtent,
                  refreshTriggerPullDistance, refreshIndicatorExtent) {
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
                delegate: SliverChildBuilderDelegate((_, i) {
                  final s = visibleRecent[i];
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: SongTile(
                      song: s.copyWith(isFavorite: favIds.contains(s.globalId)),
                      active: currentId == s.globalId,
                      loading: loadingId == s.globalId,
                      onTap: () => playOrOpen(
                        context,
                        ref,
                        s,
                        queue: visibleRecent,
                      ),
                      onFavorite: () => appNotifier.toggleFavorite(s),
                    ),
                  );
                },
                    childCount:
                        visibleRecent.length > 3 ? 3 : visibleRecent.length),
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
                  currentId,
                  loadingId,
                  favIds,
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
    String? currentId,
    String? loadingId,
    Set<String> favIds,
    AppStateNotifier appNotifier,
    bool hideVip,
  ) {
    final rawSongs = _recommendsByCategory[cat.id] ?? [];
    final songs =
        hideVip ? rawSongs.where((s) => !s.isVip).toList() : rawSongs;
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
                  final displaySong = s.copyWith(isFavorite: favIds.contains(s.globalId));
                  final active = currentId == s.globalId;
                  final isLoadingThis = loadingId == s.globalId;

                  return _songCard(
                    displaySong,
                    active,
                    isLoadingThis,
                    onTap: () => playOrOpen(
                      context,
                      ref,
                      displaySong,
                      queue: songs,
                    ),
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
                    child: SongCover(
                      path: song.coverPath,
                      size: 132,
                      radius: 0,
                    ),
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