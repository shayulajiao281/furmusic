import 'dart:math' as math;
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:palette_generator/palette_generator.dart';
import '../models/song.dart';
import '../providers/app_state.dart';
import '../providers/player_state.dart';
import '../theme/app_colors.dart';
import 'playlist_sheet.dart';
import 'song_cover.dart';

// ★ 全局颜色缓存
final Map<String, Color> _colorCache = {};

class MiniPlayer extends ConsumerStatefulWidget {
  /// 是否开启底部安全区（子页面开启，主 Tab 页关闭）
  final bool useSafeArea;
  const MiniPlayer({super.key, this.useSafeArea = false});

  @override
  ConsumerState<MiniPlayer> createState() => _MiniPlayerState();
}

class _MiniPlayerState extends ConsumerState<MiniPlayer> {
  static const _duration = Duration(milliseconds: 320);
  static const _curve = Curves.easeOutCubic;
  static const double _rowHeight = 56;

  Color _dominantColor = AppColors.primary;
  String? _extractedFor;
  double? _dragProgress;

  Future<void> _extractColor(String coverUrl, String songId) async {
    if (coverUrl.isEmpty) return;
    if (_extractedFor == songId) return;
    
    // ★ 查缓存
    if (_colorCache.containsKey(songId)) {
      if (mounted) setState(() => _dominantColor = _colorCache[songId]!);
      return;
    }

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
      if (color != null) {
        _colorCache[songId] = color;
        if (mounted) setState(() => _dominantColor = color);
      }
    } catch (_) {
      if (mounted) setState(() => _dominantColor = AppColors.primary);
    }
  }

  Color _shift(Color c, double dL, [double satMul = 1.0]) {
    final hsl = HSLColor.fromColor(c);
    return hsl
        .withLightness((hsl.lightness + dL).clamp(0.0, 1.0))
        .withSaturation((hsl.saturation * satMul).clamp(0.0, 1.0))
        .toColor();
  }

  String _fmt(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final player = ref.watch(playerStateProvider);
    final song = player.current;

    if (song == null) return const SizedBox.shrink();

    final expanded = player.expanded;
    final favorites = ref.watch(favoriteSongsProvider);
    final isFav = favorites.any((s) => s.globalId == song.globalId);
    final notifier = ref.read(playerStateProvider.notifier);
    final loading = player.isLoading;

    if (_extractedFor != song.id) {
      // ★ 延迟到首帧渲染后提取，绝不阻塞路由动画
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _extractColor(song.coverPath, song.id);
      });
    }

    final baseColor = _shift(_dominantColor, expanded ? 0.18 : -0.06, 0.92);
    final endColor = _shift(_dominantColor, expanded ? 0.30 : -0.22, 0.88);

    final radius = expanded
        ? BorderRadius.circular(22)
        : const BorderRadius.vertical(top: Radius.circular(14));

    return AnimatedContainer(
      duration: _duration,
      curve: _curve,
      margin: expanded
          ? const EdgeInsets.fromLTRB(10, 0, 10, 8)
          : EdgeInsets.zero,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [baseColor, endColor],
        ),
        borderRadius: radius,
        boxShadow: [
          BoxShadow(
            color: endColor.withValues(alpha: expanded ? 0.35 : 0.18),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: loading ? null : () => context.push('/player'),
          // ★ 安全区 Padding
          child: Padding(
            padding: EdgeInsets.only(
              bottom: widget.useSafeArea
                  ? MediaQuery.of(context).padding.bottom
                  : 0,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  height: _rowHeight,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Row(
                      children: [
                        SongCover(path: song.coverPath, size: 40, radius: 10),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                song.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w600,
                                  color: expanded
                                      ? _shift(_dominantColor, -0.45, 0.7)
                                      : CupertinoColors.white,
                                  height: 1.2,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                loading ? '正在加载…' : song.artist,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: expanded
                                      ? _shift(_dominantColor, -0.45, 0.7)
                                          .withValues(alpha: 0.6)
                                      : CupertinoColors.white
                                          .withValues(alpha: 0.85),
                                  height: 1.2,
                                ),
                              ),
                            ],
                          ),
                        ),
                        SizedBox(
                          width: 96,
                          child: AnimatedSwitcher(
                            duration: _duration,
                            switchInCurve: _curve,
                            switchOutCurve: _curve,
                            transitionBuilder: (child, animation) =>
                                FadeTransition(
                                    opacity: animation, child: child),
                            child: expanded
                                ? Row(
                                    key: const ValueKey('collapse'),
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    children: [
                                      GestureDetector(
                                        behavior: HitTestBehavior.opaque,
                                        onTap: notifier.collapse,
                                        child: Padding(
                                          padding: const EdgeInsets.all(6),
                                          child: Icon(
                                            CupertinoIcons.chevron_down,
                                            size: 22,
                                            color: _shift(
                                                    _dominantColor, -0.45, 0.7)
                                                .withValues(alpha: 0.85),
                                          ),
                                        ),
                                      ),
                                    ],
                                  )
                                : Row(
                                    key: const ValueKey('actions'),
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    children: [
                                      _smallPlayButton(
                                          loading, player, notifier),
                                      _smallIconBtn(
                                        icon: CupertinoIcons.list_bullet,
                                        enabled: !loading,
                                        onTap: () =>
                                            showPlaylistSheet(context),
                                      ),
                                    ],
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                ClipRect(
                  child: AnimatedAlign(
                    duration: _duration,
                    curve: _curve,
                    alignment: Alignment.topCenter,
                    heightFactor: expanded ? 1.0 : 0.0,
                    child: AnimatedOpacity(
                      duration: _duration,
                      curve: _curve,
                      opacity: expanded ? 1.0 : 0.0,
                      child: _buildExpandedPanel(
                        song: song,
                        player: player,
                        notifier: notifier,
                        isFav: isFav,
                        loading: loading,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildExpandedPanel({
    required Song song,
    required PlayerState player,
    required PlayerNotifier notifier,
    required bool isFav,
    required bool loading,
  }) {
    final textColor = _shift(_dominantColor, -0.45, 0.7);
    final subColor = textColor.withValues(alpha: 0.6);

    final displayProgress = _dragProgress ?? player.progress.clamp(0.0, 1.0);
    final displayPos = _dragProgress != null
        ? Duration(
            milliseconds:
                (player.duration.inMilliseconds * _dragProgress!).round(),
          )
        : player.position;

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _progressBar(
            value: displayProgress,
            color: textColor,
            enabled: !loading && player.duration > Duration.zero,
            onStart: (v) => setState(() => _dragProgress = v),
            onUpdate: (v) => setState(() => _dragProgress = v),
            onEnd: (v) async {
              final pos = Duration(
                milliseconds: (player.duration.inMilliseconds * v).round(),
              );
              await notifier.seek(pos);
              if (!player.isPlaying) await notifier.togglePlay();
              if (mounted) setState(() => _dragProgress = null);
            },
          ),
          const SizedBox(height: 2),
          Row(
            children: [
              Text(
                _fmt(displayPos),
                style: TextStyle(
                  fontSize: 11,
                  color: subColor,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const Spacer(),
              Text(
                _fmt(player.duration),
                style: TextStyle(
                  fontSize: 11,
                  color: subColor,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _bigIconBtn(
                icon: isFav ? CupertinoIcons.heart_fill : CupertinoIcons.heart,
                color: isFav ? AppColors.red : textColor,
                enabled: !loading,
                onTap: () =>
                    ref.read(appStateProvider.notifier).toggleFavorite(song),
              ),
              _bigIconBtn(
                icon: CupertinoIcons.backward_fill,
                color: textColor,
                enabled: !loading,
                onTap: notifier.previous,
              ),
              _bigPlayButton(loading, player, notifier, textColor),
              _bigIconBtn(
                icon: CupertinoIcons.forward_fill,
                color: textColor,
                enabled: !loading,
                onTap: notifier.next,
              ),
              _bigIconBtn(
                icon: CupertinoIcons.list_bullet,
                color: textColor,
                enabled: !loading,
                onTap: () => showPlaylistSheet(context),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _progressBar({
    required double value,
    required Color color,
    required bool enabled,
    required ValueChanged<double> onStart,
    required ValueChanged<double> onUpdate,
    required ValueChanged<double> onEnd,
  }) {
    return LayoutBuilder(
      builder: (context, c) {
        final width = c.maxWidth;
        final ratio = value.clamp(0.0, 1.0);
        final thumbX = width * ratio;

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: enabled
              ? (d) {
                  final v = (d.localPosition.dx / width).clamp(0.0, 1.0);
                  onStart(v);
                  onUpdate(v);
                  onEnd(v);
                }
              : null,
          onHorizontalDragStart: enabled
              ? (d) {
                  final v = (d.localPosition.dx / width).clamp(0.0, 1.0);
                  onStart(v);
                }
              : null,
          onHorizontalDragUpdate: enabled
              ? (d) {
                  final v = (d.localPosition.dx / width).clamp(0.0, 1.0);
                  onUpdate(v);
                }
              : null,
          onHorizontalDragEnd: enabled ? (_) => onEnd(value) : null,
          child: SizedBox(
            height: 20,
            child: Stack(
              alignment: Alignment.centerLeft,
              children: [
                Container(
                  height: 3,
                  width: width,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Container(
                  height: 3,
                  width: thumbX,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Positioned(
                  left: (thumbX - 6).clamp(0.0, width - 12),
                  child: Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: color.withValues(alpha: 0.35),
                          blurRadius: 6,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _bigIconBtn({
    required IconData icon,
    required Color color,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: enabled ? onTap : null,
      child: SizedBox(
        width: 44,
        height: 44,
        child: Icon(icon, size: 24, color: color),
      ),
    );
  }

  Widget _bigPlayButton(
    bool loading,
    PlayerState player,
    PlayerNotifier notifier,
    Color color,
  ) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: loading ? null : notifier.togglePlay,
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: color, width: 2),
        ),
        child: Center(
          child: loading
              ? _LoadingBars(size: 18, color: color)
              : Icon(
                  player.isPlaying
                      ? CupertinoIcons.pause_fill
                      : CupertinoIcons.play_fill,
                  size: 24,
                  color: color,
                ),
        ),
      ),
    );
  }

  Widget _smallIconBtn({
    required IconData icon,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: enabled ? onTap : null,
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Icon(
          icon,
          size: 22,
          color: CupertinoColors.white.withValues(alpha: 0.95),
        ),
      ),
    );
  }

  Widget _smallPlayButton(
    bool loading,
    PlayerState player,
    PlayerNotifier notifier,
  ) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: loading ? null : notifier.togglePlay,
      child: SizedBox(
        width: 36,
        height: 36,
        child: Center(
          child: loading
              ? const _LoadingBars(size: 18, color: CupertinoColors.white)
              : Icon(
                  player.isPlaying
                      ? CupertinoIcons.pause_fill
                      : CupertinoIcons.play_fill,
                  size: 26,
                  color: CupertinoColors.white,
                ),
        ),
      ),
    );
  }
}

class _LoadingBars extends StatefulWidget {
  final double size;
  final Color color;

  const _LoadingBars({required this.size, required this.color});

  @override
  State<_LoadingBars> createState() => _LoadingBarsState();
}

class _LoadingBarsState extends State<_LoadingBars>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const barCount = 3;
    const barWidth = 3.0;
    const gap = 3.0;

    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: List.generate(barCount, (i) {
            final phase = i / barCount;
            final t = (_ctrl.value + phase) % 1.0;
            final amp = 0.25 + 0.75 * (0.5 - 0.5 * math.cos(t * 2 * math.pi));
            return Padding(
              padding: EdgeInsets.only(right: i == barCount - 1 ? 0 : gap),
              child: Container(
                width: barWidth,
                height: widget.size * amp,
                decoration: BoxDecoration(
                  color: widget.color,
                  borderRadius: BorderRadius.circular(barWidth / 2),
                ),
              ),
            );
          }),
        );
      },
    );
  }
}