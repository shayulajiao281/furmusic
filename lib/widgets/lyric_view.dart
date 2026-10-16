import 'package:flutter/cupertino.dart';
import '../theme/app_colors.dart';

class LyricView extends StatefulWidget {
  final List<MapEntry<double, String>> lyric;
  final int currentIndex;
  final ValueChanged<Duration> onSeek;
  final Color? activeColor;
  final Color? inactiveColor;

  /// 当前行在视图中的位置（0.5 居中，0.667 = 2/3）
  final double anchor;

  const LyricView({
    super.key,
    required this.lyric,
    required this.currentIndex,
    required this.onSeek,
    this.activeColor,
    this.inactiveColor,
    this.anchor = 0.667,
  });

  @override
  State<LyricView> createState() => _LyricViewState();
}

class _LyricViewState extends State<LyricView> {
  late ScrollController _scroll;
  static const double _itemHeight = 48;

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
    // ★ 正确算法：第 idx 行中心点要落在 anchor 位置
    //   padding.top 已经让第 0 行中心在 h*anchor 处
    //   所以滚动到 idx * itemHeight 即可
    final target = idx * _itemHeight;
    final max = _scroll.position.maxScrollExtent;
    final offset = target.clamp(0.0, max);

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
        final h = constraints.maxHeight;
        // padding.top 让第一行中心落在 anchor 位置
        final topPad = h * widget.anchor - _itemHeight / 2;
        final bottomPad = h * (1 - widget.anchor) - _itemHeight / 2;

        return ListView.builder(
          controller: _scroll,
          physics: const BouncingScrollPhysics(),
          padding: EdgeInsets.only(
            top: topPad < 0 ? 0 : topPad,
            bottom: bottomPad < 0 ? 0 : bottomPad,
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
                      // ★ 当前行：加大、加粗、主题色
                      fontSize: active ? 18 : 15,
                      fontWeight:
                          active ? FontWeight.w800 : FontWeight.w500,
                      color: active
                          ? (widget.activeColor ?? AppColors.primary)
                          : (widget.inactiveColor ??
                              AppColors.muted.withValues(alpha: 0.7)),
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