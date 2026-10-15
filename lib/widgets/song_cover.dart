import 'dart:io';
import 'package:flutter/cupertino.dart';
import '../theme/app_colors.dart';

class SongCover extends StatelessWidget {
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
  Widget build(BuildContext context) {
    ImageProvider? image;

    if (path.startsWith('http')) {
      image = NetworkImage(path);
    } else if (path.isNotEmpty && File(path).existsSync()) {
      image = FileImage(File(path));
    }

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppColors.coverBg,
        borderRadius: BorderRadius.circular(radius),
        image: image != null
            ? DecorationImage(image: image, fit: BoxFit.cover)
            : null,
      ),
      child: image == null
          ? Icon(
              CupertinoIcons.music_note,
              size: size * 0.42,
              color: AppColors.muted,
            )
          : null,
    );
  }
}
