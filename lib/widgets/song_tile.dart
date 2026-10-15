import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import '../models/song.dart';
import '../theme/app_colors.dart';
import 'song_cover.dart';

class SongTile extends StatelessWidget {
  final Song song;
  final bool active;
  final VoidCallback onTap;
  final VoidCallback? onFavorite;

  const SongTile({
    super.key,
    required this.song,
    this.active = false,
    required this.onTap,
    this.onFavorite,
  });

  String _fmt(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 9),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: active ? AppColors.primarySoft : AppColors.card,
          borderRadius: BorderRadius.circular(16),
          boxShadow: AppColors.cardShadow,
        ),
        child: Row(
          children: [
            SongCover(path: song.coverPath, size: 48, radius: 12),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    song.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: active ? AppColors.primary : AppColors.text,
                      height: 1.25,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${song.artist} · ${_fmt(song.duration)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: AppColors.muted,
                    ),
                  ),
                ],
              ),
            ),
            if (onFavorite != null)
              GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick();
                  onFavorite!();
                },
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: Icon(
                    song.isFavorite
                        ? CupertinoIcons.heart_fill
                        : CupertinoIcons.heart,
                    size: 20,
                    color: song.isFavorite ? AppColors.red : AppColors.muted,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
