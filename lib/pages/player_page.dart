import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/app_state.dart';
import '../providers/player_state.dart';
import '../theme/app_colors.dart';
import '../widgets/song_cover.dart';

class PlayerPage extends ConsumerStatefulWidget {
  const PlayerPage({super.key});
  @override
  ConsumerState<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends ConsumerState<PlayerPage> {
  double _dragOffset = 0.0;
  double _screenHeight = 0;

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

    final allSongs = ref.watch(allSongsProvider);
    final live = allSongs.where((s) => s.id == song.id).toList();
    final isFav = live.isNotEmpty ? live.first.isFavorite : false;

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
                  // 顶部：handle + 模式名
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
                            const SizedBox(width: 26),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const Spacer(),

                  // 封面
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 48),
                    child: AspectRatio(
                      aspectRatio: 1,
                      child: Container(
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
                          child: _buildCover(song.coverPath),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 28),

                  // 标题
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

                  const SizedBox(height: 20),

                  // 进度条
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Column(
                      children: [
                        CupertinoSlider(
                          value: player.progress.clamp(0.0, 1.0),
                          activeColor: AppColors.primary,
                          onChanged: (v) {
                            final pos = Duration(
                              milliseconds: (player.duration.inMilliseconds * v)
                                  .round(),
                            );
                            notifier.seek(pos);
                          },
                        ),
                        const SizedBox(height: 4),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Row(
                            children: [
                              Text(
                                _fmt(player.position),
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: AppColors.muted,
                                ),
                              ),
                              const Spacer(),
                              Text(
                                _fmt(player.duration),
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: AppColors.muted,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 12),

                  // 控制按钮
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // 播放模式（三种都高亮）
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
                        // 上一首
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
                        // 播放/暂停
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
                        // 下一首
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
                        // 收藏
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

  Widget _buildCover(String path) {
    if (path.isEmpty) {
      return const Center(
        child: Icon(
          CupertinoIcons.music_note,
          size: 80,
          color: AppColors.muted,
        ),
      );
    }
    return SongCover(path: path, size: double.infinity, radius: 0);
  }
}
