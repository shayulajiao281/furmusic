import 'dart:io';
import 'package:flutter/cupertino.dart';
import '../services/image_cache.dart';
import '../theme/app_colors.dart';

class SongCover extends StatefulWidget {
  final String path;
  final double size;
  final double radius;

  const SongCover({
    super.key,
    required this.path,
    this.size = 48,
    this.radius = 12,
  });

  @override
  State<SongCover> createState() => _SongCoverState();
}

class _SongCoverState extends State<SongCover> {
  File? _file;
  String? _loadedFor;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant SongCover oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path) {
      _load();
    }
  }

  Future<void> _load() async {
    final path = widget.path;
    if (path.isEmpty) {
      if (mounted) setState(() { _file = null; _loadedFor = path; });
      return;
    }

    // ★ 离线优先：先查本地缓存
    final cached = ImageCacheManager.getCached(path);
    if (cached != null) {
      if (mounted) setState(() { _file = cached; _loadedFor = path; });
      return;
    }

    if (mounted) setState(() { _file = null; _loadedFor = path; });

    final file = await ImageCacheManager.get(path);
    if (!mounted) return;
    if (widget.path != path) return;
    setState(() { _file = file; _loadedFor = path; });
  }

  double get _iconSize {
    if (widget.size.isFinite) return widget.size * 0.42;
    return 60;
  }

  Widget _placeholder() => Icon(
    CupertinoIcons.music_note,
    size: _iconSize,
    color: AppColors.muted,
  );

  @override
  Widget build(BuildContext context) {
    return Container(
      width: widget.size,
      height: widget.size,
      decoration: BoxDecoration(
        color: AppColors.coverBg,
        borderRadius: BorderRadius.circular(widget.radius),
      ),
      clipBehavior: Clip.antiAlias,
      child: _file != null
          ? Image.file(
              _file!,
              width: widget.size,
              height: widget.size,
              fit: BoxFit.cover,
              gaplessPlayback: true,
              errorBuilder: (_, __, ___) => _placeholder(),
            )
          : _placeholder(),
    );
  }
}