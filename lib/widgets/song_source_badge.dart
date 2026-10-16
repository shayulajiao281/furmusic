import 'package:flutter/cupertino.dart';

class SongSourceBadge extends StatelessWidget {
  final String source;
  const SongSourceBadge({super.key, required this.source});

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
    if (meta == null) return const SizedBox.shrink();
    final (label, color) = meta;

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
}
