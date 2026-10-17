import 'dart:math' as math;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:palette_generator/palette_generator.dart';
import '../providers/app_state.dart';
import '../providers/player_state.dart';
import '../providers/audio_cache_state.dart';
import '../services/image_cache.dart';
import '../theme/app_colors.dart';
import '../widgets/song_cover.dart';
import '../widgets/song_source_badge.dart';
import '../widgets/lyric_view.dart';

class PlayerPage extends ConsumerStatefulWidget {
  const PlayerPage({super.key});
  @override
  ConsumerState<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends ConsumerState<PlayerPage> {
  double _dragOffset = 0.0;
  double _screenHeight = 0;
  double? _dragProgress;
  bool _showLyric = false;
  static const double _lyricAnchor = 0.667;

  List<Color> _paletteColors = const [AppColors.primary];
  String? _extractedFor;

  Future<void> _extractColor(String coverUrl, String songId) async {
    if (coverUrl.isEmpty) return;
    if (_extractedFor == songId) return;
    _extractedFor = songId;
    try {
      final file = ImageCacheManager.getCached(coverUrl) ??
          await ImageCacheManager.get(coverUrl);
      if (file == null) return;

      final palette = await PaletteGenerator.fromImageProvider(
        FileImage(file),
        maximumColorCount: 16,
      );

      final colors = <Color>[];
      final vibrant = palette.vibrantColor?.color;
      final dominant = palette.dominantColor?.color;
      final muted = palette.mutedColor?.color;
      final lightVibrant = palette.lightVibrantColor?.color;
      final darkVibrant = palette.darkVibrantColor?.color;
      final lightMuted = palette.lightMutedColor?.color;

      for (final c in [
        vibrant,
        lightVibrant,
        dominant,
        muted,
        lightMuted,
        darkVibrant,
      ]) {
        if (c != null && !colors.any((e) => _colorDist(e, c) < 0.15)) {
          colors.add(c);
        }
      }

      if (colors.isEmpty) colors.add(AppColors.primary);
      if (colors.length > 4) colors.removeRange(4, colors.length);

      if (mounted) {
        setState(() => _paletteColors = colors);
      }
    } catch (_) {}
  }

  double _colorDist(Color a, Color b) {
    final dr = a.red - b.red;
    final dg = a.green - b.green;
    final db = a.blue - b.blue;
    return math.sqrt((dr * dr + dg * dg + db * db).toDouble()) / 255.0;
  }

  String _fmt(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  IconData _modeIcon(PlayMode m) {
    switch (m) {
      case PlayMode.repeatAll:
        return CupertinoIcons.repeat;
      case PlayMode.repeatOne:
        return CupertinoIcons.repeat_1;
      case PlayMode.shuffle:
        return CupertinoIcons.shuffle;
    }
  }

  String _modeName(PlayMode m) {
    switch (m) {
      case PlayMode.repeatAll:
        return '列表循环';
      case PlayMode.repeatOne:
        return '单曲循环';
      case PlayMode.shuffle:
        return '随机播放';
    }
  }

  void _close() {
    HapticFeedback.selectionClick();
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    _screenHeight = MediaQuery.of(context).size.height;

    final player = ref.watch(playerStateProvider);
    final notifier = ref.read(playerStateProvider.notifier);
    final song = player.current;

    if (song == null) {
      return const CupertinoPageScaffold(
        child: Center(child: Text('没有正在播放的歌曲')),
      );
    }

    if (_extractedFor != song.id) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _extractColor(song.coverPath, song.id);
      });
    }

    final favorites = ref.watch(favoriteSongsProvider);
    final isFav = favorites.any((s) => s.globalId == song.globalId);

    // ★ 缓存进度
    final cacheProgress =
        ref.watch(audioCacheProgressProvider(song.globalId)).asData?.value ??
            0.0;

    return CupertinoPageScaffold(
      child: GestureDetector(
        onVerticalDragUpdate: (details) {
          if (details.delta.dy > 0 || _dragOffset > 0) {
            setState(() {
              _dragOffset += details.delta.dy;
              if (_dragOffset < 0) _dragOffset = 0;
            });
          }
        },
        onVerticalDragEnd: (details) {
          if (_dragOffset > _screenHeight * 0.25 ||
              (details.primaryVelocity != null &&
                  details.primaryVelocity! > 800)) {
            _close();
          } else {
            setState(() => _dragOffset = 0);
          }
        },
        child: Transform.translate(
          offset: Offset(0, _dragOffset),
          child: _PulseBackground(
            playing: player.isPlaying,
            colors: _paletteColors,
            child: SafeArea(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                    child: Column(
                      children: [
                        Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: AppColors.line,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            CupertinoButton(
                              padding: EdgeInsets.zero,
                              minSize: 0,
                              onPressed: _close,
                              child: const Icon(
                                CupertinoIcons.chevron_down,
                                size: 26,
                                color: AppColors.text,
                              ),
                            ),
                            const Spacer(),
                            Text(
                              _modeName(player.mode),
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.muted,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const Spacer(),
                            CupertinoButton(
                              padding: EdgeInsets.zero,
                              minSize: 0,
                              onPressed: () =>
                                  setState(() => _showLyric = !_showLyric),
                              child: Icon(
                                _showLyric
                                    ? CupertinoIcons.music_note
                                    : CupertinoIcons.text_quote,
                                size: 22,
                                color: AppColors.text,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () =>
                          setState(() => _showLyric = !_showLyric),
                      child: _showLyric
                          ? _buildLyric(player, notifier)
                          : Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 48, vertical: 12),
                              child: AspectRatio(
                                aspectRatio: 1,
                                child: _buildCover(song.coverPath),
                              ),
                            ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(32, 8, 32, 4),
                    child: Column(
                      children: [
                        Text(
                          song.title,
                          maxLines: 2,
                          textAlign: TextAlign.center,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: AppColors.text,
                            height: 1.3,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SongSourceBadge(
                              source: song.source,
                              showVip: song.isVip,
                            ),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                song.artist,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 14,
                                  color: AppColors.muted,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Builder(
                      builder: (_) {
                        final displayProgress =
                            _dragProgress ?? player.progress.clamp(0.0, 1.0);
                        final displayPos = _dragProgress != null
                            ? Duration(
                                milliseconds:
                                    (player.duration.inMilliseconds *
                                            _dragProgress!)
                                        .round(),
                              )
                            : player.position;

                        return Column(
                          children: [
                            QQSlider(
                              value: displayProgress,
                              buffer: cacheProgress,
                              onChangeStart: (v) {
                                setState(() => _dragProgress = v);
                                HapticFeedback.selectionClick();
                              },
                              onChanged: (v) {
                                setState(() => _dragProgress = v);
                              },
                              onChangeEnd: (v) async {
                                final pos = Duration(
                                  milliseconds:
                                      (player.duration.inMilliseconds * v)
                                          .round(),
                                );
                                await notifier.seek(pos);
                                if (!player.isPlaying) {
                                  await notifier.togglePlay();
                                }
                                if (mounted) {
                                  setState(() => _dragProgress = null);
                                }
                                HapticFeedback.lightImpact();
                              },
                            ),
                            const SizedBox(height: 6),
                            // ★ 进度条下方的时间与缓存状态
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 2),
                              child: Row(
                                children: [
                                  Text(
                                    _fmt(displayPos),
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: AppColors.muted,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  
                                  // ★ 缓存状态提示
                                  if (cacheProgress > 0.0 && cacheProgress < 0.99)
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        SizedBox(
                                          width: 8,
                                          height: 8,
                                          child:
                                              CircularProgressIndicator(
                                            strokeWidth: 1.5,
                                            value: cacheProgress,
                                            color: AppColors.primary,
                                            backgroundColor: AppColors.line,
                                          ),
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          '缓存中 ${(cacheProgress * 100).toInt()}%',
                                          style: const TextStyle(
                                            fontSize: 10,
                                            color: AppColors.primary,
                                          ),
                                        ),
                                      ],
                                    )
                                  else if (cacheProgress >= 0.99)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 4, vertical: 1),
                                      decoration: BoxDecoration(
                                        color: AppColors.green
                                            .withValues(alpha: 0.1),
                                        borderRadius:
                                            BorderRadius.circular(4),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: const [
                                          Icon(
                                            CupertinoIcons
                                                .checkmark_circle_fill,
                                            size: 10,
                                            color: AppColors.green,
                                          ),
                                          SizedBox(width: 2),
                                          Text(
                                            '已缓存',
                                            style: TextStyle(
                                              fontSize: 9,
                                              color: AppColors.green,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),

                                  const Spacer(),
                                  Text(
                                    _fmt(player.duration),
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: AppColors.muted,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        GestureDetector(
                          onTap: () {
                            HapticFeedback.selectionClick();
                            notifier.nextPlayMode();
                          },
                          child: Padding(
                            padding: const EdgeInsets.all(8),
                            child: Icon(
                              _modeIcon(player.mode),
                              size: 24,
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                        GestureDetector(
                          onTap: () {
                            HapticFeedback.selectionClick();
                            notifier.previous();
                          },
                          child: const Padding(
                            padding: EdgeInsets.all(8),
                            child: Icon(
                              CupertinoIcons.backward_fill,
                              size: 32,
                              color: AppColors.text,
                            ),
                          ),
                        ),
                        GestureDetector(
                          onTap: () {
                            HapticFeedback.mediumImpact();
                            notifier.togglePlay();
                          },
                          child: Container(
                            width: 64,
                            height: 64,
                            decoration: const BoxDecoration(
                              color: AppColors.primary,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: Color(0x52FF7A59),
                                  blurRadius: 18,
                                  offset: Offset(0, 8),
                                ),
                              ],
                            ),
                            child: Icon(
                              player.isPlaying
                                  ? CupertinoIcons.pause_fill
                                  : CupertinoIcons.play_fill,
                              size: 30,
                              color: CupertinoColors.white,
                            ),
                          ),
                        ),
                        GestureDetector(
                          onTap: () {
                            HapticFeedback.selectionClick();
                            notifier.next();
                          },
                          child: const Padding(
                            padding: EdgeInsets.all(8),
                            child: Icon(
                              CupertinoIcons.forward_fill,
                              size: 32,
                              color: AppColors.text,
                            ),
                          ),
                        ),
                        GestureDetector(
                          onTap: () {
                            HapticFeedback.selectionClick();
                            ref
                                .read(appStateProvider.notifier)
                                .toggleFavorite(song);
                          },
                          child: Padding(
                            padding: const EdgeInsets.all(8),
                            child: Icon(
                              isFav
                                  ? CupertinoIcons.heart_fill
                                  : CupertinoIcons.heart,
                              size: 24,
                              color:
                                  isFav ? AppColors.red : AppColors.text,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCover(String path) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.coverBg,
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1A1E2231),
            blurRadius: 40,
            offset: Offset(0, 16),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: path.isEmpty
            ? const Center(
                child: Icon(
                  CupertinoIcons.music_note,
                  size: 80,
                  color: AppColors.muted,
                ),
              )
            : SongCover(path: path, size: double.infinity, radius: 0),
      ),
    );
  }

  Widget _buildLyric(PlayerState player, PlayerNotifier notifier) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: LyricView(
        lyric: player.lyric,
        currentIndex: player.lyricIndex,
        anchor: _lyricAnchor,
        onSeek: (d) async {
          await notifier.seek(d);
          if (!player.isPlaying) await notifier.togglePlay();
          HapticFeedback.selectionClick();
        },
      ),
    );
  }
}

class _PulseBackground extends StatefulWidget {
  final bool playing;
  final List<Color> colors;
  final Widget child;

  const _PulseBackground({
    required this.playing,
    required this.colors,
    required this.child,
  });

  @override
  State<_PulseBackground> createState() => _PulseBackgroundState();
}

class _PulseBackgroundState extends State<_PulseBackground>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3200),
    );
    if (widget.playing) {
      _ctrl.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(covariant _PulseBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.playing != oldWidget.playing) {
      if (widget.playing) {
        _ctrl.repeat(reverse: true);
      } else {
        _ctrl.stop();
      }
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
        final t = _ctrl.value;
        final colors = widget.colors;

        return Stack(
          children: [
            Container(color: AppColors.bg),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment(
                      -0.7 + 0.35 * math.sin(t * 2 * math.pi),
                      -0.65 + 0.3 * math.cos(t * 2 * math.pi),
                    ),
                    radius: 1.15 + 0.35 * t,
                    colors: [
                      _c(colors, 0).withValues(alpha: 0.55 + 0.25 * t),
                      AppColors.bg.withValues(alpha: 0.0),
                    ],
                    stops: const [0.0, 1.0],
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment(
                      0.8 - 0.3 * math.cos(t * 2 * math.pi),
                      0.9 - 0.3 * math.sin(t * 2 * math.pi),
                    ),
                    radius: 1.0 + 0.4 * t,
                    colors: [
                      _c(colors, 1).withValues(alpha: 0.45 + 0.25 * (1 - t)),
                      AppColors.bg.withValues(alpha: 0.0),
                    ],
                    stops: const [0.0, 1.0],
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment(
                      0.7 + 0.2 * math.sin(t * 2 * math.pi + 1.5),
                      -0.5 + 0.25 * math.cos(t * 2 * math.pi + 1.5),
                    ),
                    radius: 0.9 + 0.35 * (1 - t),
                    colors: [
                      _c(colors, 2).withValues(alpha: 0.35 + 0.3 * t),
                      AppColors.bg.withValues(alpha: 0.0),
                    ],
                    stops: const [0.0, 1.0],
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment(
                      -0.5 + 0.25 * math.cos(t * 2 * math.pi + 3.0),
                      0.8 + 0.25 * math.sin(t * 2 * math.pi + 3.0),
                    ),
                    radius: 0.85 + 0.3 * (1 - t),
                    colors: [
                      _c(colors, 3).withValues(alpha: 0.3 + 0.25 * t),
                      AppColors.bg.withValues(alpha: 0.0),
                    ],
                    stops: const [0.0, 1.0],
                  ),
                ),
              ),
            ),
            widget.child,
          ],
        );
      },
    );
  }

  Color _c(List<Color> list, int i) {
    if (list.isEmpty) return AppColors.primary;
    return list[i % list.length];
  }
}

// ═══════════════════════════════════════════════════════════
// QQ 音乐风格进度条（带缓存层，对比度加强）
// ═══════════════════════════════════════════════════════════
class QQSlider extends StatefulWidget {
  final double value;
  final double buffer;
  final ValueChanged<double>? onChangeStart;
  final ValueChanged<double>? onChanged;
  final ValueChanged<double>? onChangeEnd;

  const QQSlider({
    super.key,
    required this.value,
    this.buffer = 0.0,
    this.onChangeStart,
    this.onChanged,
    this.onChangeEnd,
  });

  @override
  State<QQSlider> createState() => _QQSliderState();
}

class _QQSliderState extends State<QQSlider> {
  bool _dragging = false;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final trackHeight = _dragging ? 5.0 : 3.0;
        final thumbSize = _dragging ? 16.0 : 12.0;

        final valueRatio = widget.value.clamp(0.0, 1.0);
        final bufferRatio = widget.buffer.clamp(0.0, 1.0);

        final renderBuffer = math.max(bufferRatio, valueRatio);
        final thumbX = width * valueRatio;

        void handleDx(double dx) {
          final v = (dx / width).clamp(0.0, 1.0);
          widget.onChanged?.call(v);
        }

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragStart: (d) {
            setState(() => _dragging = true);
            final v = (d.localPosition.dx / width).clamp(0.0, 1.0);
            widget.onChangeStart?.call(v);
          },
          onHorizontalDragUpdate: (d) {
            handleDx(d.localPosition.dx);
          },
          onHorizontalDragEnd: (d) {
            widget.onChangeEnd?.call(widget.value);
            setState(() => _dragging = false);
          },
          onHorizontalDragCancel: () {
            setState(() => _dragging = false);
          },
          onTapDown: (d) {
            final v = (d.localPosition.dx / width).clamp(0.0, 1.0);
            widget.onChangeStart?.call(v);
            widget.onChanged?.call(v);
            widget.onChangeEnd?.call(v);
          },
          child: SizedBox(
            height: 28,
            width: width,
            child: Stack(
              alignment: Alignment.centerLeft,
              children: [
                // ① 背景（完全未缓存）- 略微加深，提高对比度
                Container(
                  height: trackHeight,
                  width: width,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE0E4EF),
                    borderRadius: BorderRadius.circular(trackHeight / 2),
                  ),
                ),

                // ② 缓存层（透明度拉高到 0.4，明显可见）
                if (renderBuffer > 0.001)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeOut,
                    height: trackHeight,
                    width: width * renderBuffer,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.40),
                      borderRadius: BorderRadius.circular(trackHeight / 2),
                    ),
                  ),

                // ③ 播放进度层（主色）
                AnimatedContainer(
                  duration: const Duration(milliseconds: 100),
                  height: trackHeight,
                  width: thumbX,
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(trackHeight / 2),
                  ),
                ),

                // ④ 播放头滑块
                Positioned(
                  left: (thumbX - thumbSize / 2)
                      .clamp(0.0, width - thumbSize),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    curve: Curves.easeOut,
                    width: thumbSize,
                    height: thumbSize,
                    decoration: BoxDecoration(
                      color: CupertinoColors.white,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: AppColors.primary,
                        width: _dragging ? 3 : 2.5,
                      ),
                      boxShadow: _dragging
                          ? [
                              BoxShadow(
                                color: AppColors.primary.withValues(
                                  alpha: 0.35,
                                ),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ]
                          : [
                              const BoxShadow(
                                color: Color(0x1A000000),
                                blurRadius: 4,
                                offset: Offset(0, 1),
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
}