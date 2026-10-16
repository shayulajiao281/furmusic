import 'package:flutter/cupertino.dart';
import '../theme/app_colors.dart';

class LyricView extends StatefulWidget {
  final List<MapEntry<double, String>> lyric;
  final int currentIndex;
  final ValueChanged<Duration> onSeek;
  final Color? activeColor;
  final Color? inactiveColor;

  const LyricView({
    super.key,
    required this.lyric,
    required this.currentIndex,
    required this.onSeek,
    this.activeColor,
    this.inactiveColor,
  });

  @override
  State<LyricView> createState() => _LyricViewState();
}

class _LyricViewState extends State<LyricView> {
  late ScrollController _scroll;
  static const double _itemHeight = 44;

  @override
  void initState() {
    super.initState();
    _scroll = ScrollController();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _scrollToCurrent(animate: false),
    );
  }

  @override
  void didUpdateWidget(covariant LyricView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 歌词内容换了（换歌）→ 立刻回顶
    if (oldWidget.lyric != widget.lyric) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _scrollToCurrent(animate: false),
      );
      return;
    }
    if (oldWidget.currentIndex != widget.currentIndex) {
      _scrollToCurrent(animate: true);
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _scrollToCurrent({required bool animate}) {
    if (!_scroll.hasClients) return;
    if (widget.lyric.isEmpty) return;

    final idx = widget.currentIndex.clamp(0, widget.lyric.length - 1);
    final target = idx * _itemHeight;
    final viewport = _scroll.position.viewportDimension;
    final offset = (target - viewport / 2 + _itemHeight / 2).clamp(
      0.0,
      _scroll.position.maxScrollExtent,
    );

    if (animate) {
      _scroll.animateTo(
        offset,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      );
    } else {
      _scroll.jumpTo(offset);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.lyric.isEmpty) {
      return const Center(
        child: Text(
          '暂无歌词',
          style: TextStyle(fontSize: 14, color: AppColors.muted),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final halfViewport = constraints.maxHeight / 2;
        return ListView.builder(
          controller: _scroll,
          physics: const BouncingScrollPhysics(),
          // 上下留白，让首行和末行也能滚到中间
          padding: EdgeInsets.symmetric(
            vertical: halfViewport - _itemHeight / 2,
          ),
          itemCount: widget.lyric.length,
          itemExtent: _itemHeight,
          itemBuilder: (_, i) {
            final line = widget.lyric[i];
            final active = i == widget.currentIndex;

            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                widget.onSeek(
                  Duration(milliseconds: (line.key * 1000).round()),
                );
              },
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: AnimatedDefaultTextStyle(
                    duration: const Duration(milliseconds: 200),
                    style: TextStyle(
                      fontSize: active ? 17 : 14,
                      fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                      color: active
                          ? (widget.activeColor ?? AppColors.primary)
                          : (widget.inactiveColor ?? AppColors.muted),
                      height: 1.3,
                    ),
                    child: Text(
                      line.value,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
