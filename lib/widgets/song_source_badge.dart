import 'package:flutter/cupertino.dart';

class SongSourceBadge extends StatelessWidget {
  final String source;
  final bool showVip;
  const SongSourceBadge({
    super.key,
    required this.source,
    this.showVip = false,
  });

  static const _meta = {
    'bilibili': ('B站', Color(0xFFFB7299)),
    'netease': ('网易', Color(0xFFC20C0C)),
    'qq': ('QQ', Color(0xFF31C27C)),
    'kugou': ('酷狗', Color(0xFF2CA2F9)),
    'local': ('本地', Color(0xFF8D94A8)),
  };

  @override
  Widget build(BuildContext context) {
    final meta = _meta[source];
    if (meta == null && !showVip) return const SizedBox.shrink();

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (meta != null) _badge(meta.$1, meta.$2),
        if (meta != null && showVip) const SizedBox(width: 4),
        if (showVip) _vipBadge(),
      ],
    );
  }

  Widget _badge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 9.5,
          fontWeight: FontWeight.w700,
          color: color,
          height: 1.2,
        ),
      ),
    );
  }

  /// ★ VIP 徽章：金色渐变 + 星形图标
  Widget _vipBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFFE0A3), Color(0xFFFFC24B)],
        ),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: const [
          // ★ 用 star_fill 代替不存在的 crown_fill
          Icon(CupertinoIcons.star_fill, size: 8, color: Color(0xFF7A4A00)),
          SizedBox(width: 2),
          Text(
            'VIP',
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w800,
              color: Color(0xFF7A4A00),
              height: 1.2,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}
