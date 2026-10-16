import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/app_state.dart';
import '../providers/player_state.dart';
import '../theme/app_colors.dart';
import '../widgets/song_cover.dart';
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

  /// ★ 是否显示歌词（false = 显示封面）
  bool _showLyric = false;

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

    final favorites = ref.watch(favoriteSongsProvider);
    final isFav = favorites.any((s) => s.globalId == song.globalId);

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
          child: Container(
            color: AppColors.bg,
            child: SafeArea(
              child: Column(
                children: [
                  // ─── 顶部 ───
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
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
                        const SizedBox(height: 12),
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
                            // ★ 手动切换歌词 / 封面
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

                  const Spacer(),

                  // ─── 封面 / 歌词切换区 ───
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: AspectRatio(
                      aspectRatio: 1,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        // 点空白处切换视图（点歌词行的 tap 会被内层消费）
                        onTap: () => setState(() => _showLyric = !_showLyric),
                        child: _showLyric
                            ? _buildLyric(player, notifier)
                            : _buildCover(song.coverPath),
                      ),
                    ),
                  ),

                  const SizedBox(height: 28),

                  // ─── 标题 ───
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
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
                        Text(
                          song.artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14,
                            color: AppColors.muted,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // ─── 进度条 ───
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
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 2,
                              ),
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

                  // ─── 控制按钮 ───
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
                              color: isFav ? AppColors.red : AppColors.text,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const Spacer(flex: 2),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ─── 封面 ───
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

  // ─── 歌词 ───
  Widget _buildLyric(PlayerState player, PlayerNotifier notifier) {
    return Container(
      decoration: BoxDecoration(
        color: CupertinoColors.white,
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
        child: LyricView(
          lyric: player.lyric,
          currentIndex: player.lyricIndex,
          onSeek: (d) async {
            await notifier.seek(d);
            if (!player.isPlaying) await notifier.togglePlay();
            HapticFeedback.selectionClick();
          },
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
// QQ 音乐风格进度条
// ═══════════════════════════════════════════════════════════
class QQSlider extends StatefulWidget {
  final double value;
  final ValueChanged<double>? onChangeStart;
  final ValueChanged<double>? onChanged;
  final ValueChanged<double>? onChangeEnd;

  const QQSlider({
    super.key,
    required this.value,
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

        final ratio = widget.value.clamp(0.0, 1.0);
        final thumbX = width * ratio;

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
                Container(
                  height: trackHeight,
                  width: width,
                  decoration: BoxDecoration(
                    color: AppColors.line,
                    borderRadius: BorderRadius.circular(trackHeight / 2),
                  ),
                ),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 100),
                  height: trackHeight,
                  width: thumbX,
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(trackHeight / 2),
                  ),
                ),
                Positioned(
                  left: (thumbX - thumbSize / 2).clamp(0.0, width - thumbSize),
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
