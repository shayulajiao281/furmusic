import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:palette_generator/palette_generator.dart';
import '../providers/app_state.dart';
import '../providers/player_state.dart';
import '../theme/app_colors.dart';
import 'playlist_sheet.dart';
import 'song_cover.dart';

class MiniPlayer extends ConsumerStatefulWidget {
  const MiniPlayer({super.key});
  @override
  ConsumerState<MiniPlayer> createState() => _MiniPlayerState();
}

class _MiniPlayerState extends ConsumerState<MiniPlayer> {
  /// 封面主色调
  Color _dominantColor = AppColors.primary;

  /// 已提取过色调的歌曲 id（避免重复计算）
  String? _extractedFor;

  /// 提取封面主色调
  Future<void> _extractColor(String coverUrl, String songId) async {
    if (coverUrl.isEmpty) return;
    if (_extractedFor == songId) return;
    _extractedFor = songId;

    try {
      final palette = await PaletteGenerator.fromImageProvider(
        NetworkImage(coverUrl),
        maximumColorCount: 8,
      );
      final color =
          palette.dominantColor?.color ??
          palette.vibrantColor?.color ??
          palette.mutedColor?.color;
      if (color != null && mounted) {
        setState(() => _dominantColor = color);
      }
    } catch (_) {
      // 提取失败就用默认色
      if (mounted) {
        setState(() => _dominantColor = AppColors.primary);
      }
    }
  }

  /// 把颜色调暗一些，避免太亮刺眼
  Color _darken(Color c, [double amount = 0.15]) {
    final hsl = HSLColor.fromColor(c);
    return hsl
        .withLightness((hsl.lightness - amount).clamp(0.0, 1.0))
        .withSaturation((hsl.saturation * 0.9).clamp(0.0, 1.0))
        .toColor();
  }

  @override
  Widget build(BuildContext context) {
    final player = ref.watch(playerStateProvider);
    final song = player.current;

    if (song == null) return const SizedBox.shrink();

    // 切歌时提取主色调
    if (_extractedFor != song.id) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _extractColor(song.coverPath, song.id);
      });
    }

    final favorites = ref.watch(favoriteSongsProvider);
    final isFav = favorites.any((s) => s.id == song.id);
    final notifier = ref.read(playerStateProvider.notifier);

    final baseColor = _darken(_dominantColor, 0.12);
    final darkColor = _darken(_dominantColor, 0.28);

    return GestureDetector(
      onTap: () => context.push('/player'),
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 0),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [baseColor, darkColor],
          ),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          boxShadow: [
            BoxShadow(
              color: darkColor.withValues(alpha: 0.35),
              blurRadius: 16,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: Row(
          children: [
            SongCover(path: song.coverPath, size: 40, radius: 10),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    song.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: CupertinoColors.white,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    song.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      color: CupertinoColors.white.withValues(alpha: 0.85),
                      height: 1.2,
                    ),
                  ),
                ],
              ),
            ),
            // 收藏
            GestureDetector(
              onTap: () =>
                  ref.read(appStateProvider.notifier).toggleFavorite(song),
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Icon(
                  isFav ? CupertinoIcons.heart_fill : CupertinoIcons.heart,
                  size: 20,
                  color: isFav
                      ? const Color(0xFFFF4D4F)
                      : CupertinoColors.white.withValues(alpha: 0.9),
                ),
              ),
            ),
            // 播放/暂停
            GestureDetector(
              onTap: notifier.togglePlay,
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Icon(
                  player.isPlaying
                      ? CupertinoIcons.pause_fill
                      : CupertinoIcons.play_fill,
                  size: 26,
                  color: CupertinoColors.white,
                ),
              ),
            ),
            // ★ 播放列表（替代原来的下一首）
            GestureDetector(
              onTap: () => showPlaylistSheet(context),
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Icon(
                  CupertinoIcons.list_bullet,
                  size: 22,
                  color: CupertinoColors.white.withValues(alpha: 0.95),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
