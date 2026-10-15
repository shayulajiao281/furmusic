import 'dart:io';
import 'package:permission_handler/permission_handler.dart';
import '../models/song.dart';

class MusicScanner {
  static Future<List<Song>> scanLocal() async {
    final result = <Song>[];

    // ① 内置示例音乐（网络 URL，无需权限）
    result.addAll(_demoSongs());

    // ② 扫描本地音乐（如果权限允许）
    if (await _requestPermission()) {
      result.addAll(await _scanDirs());
    }

    return result;
  }

  /// 内置示例（用公开免费音频）
  static List<Song> _demoSongs() {
    return [];
  }

  static Future<List<Song>> _scanDirs() async {
    final result = <Song>[];
    final dirs = [
      '/storage/emulated/0/Music',
      '/storage/emulated/0/Download',
      '/storage/emulated/0/DCIM',
    ];

    for (final dirPath in dirs) {
      final dir = Directory(dirPath);
      if (!dir.existsSync()) continue;

      await for (final entity in dir.list(recursive: true)) {
        if (entity is File && _isAudio(entity.path)) {
          final name = entity.path.split('/').last;
          result.add(
            Song(
              id: entity.path.hashCode.toString(),
              title: name.replaceAll(RegExp(r'\.[^.]+$'), ''),
              artist: '本地音乐',
              audioPath: entity.path,
            ),
          );
        }
      }
    }
    return result;
  }

  static bool _isAudio(String path) {
    final lower = path.toLowerCase();
    return lower.endsWith('.mp3') ||
        lower.endsWith('.m4a') ||
        lower.endsWith('.flac') ||
        lower.endsWith('.wav') ||
        lower.endsWith('.aac');
  }

  static Future<bool> _requestPermission() async {
    if (await Permission.audio.isGranted) return true;
    final status = await Permission.audio.request();
    if (status.isPermanentlyDenied) return false;
    return status.isGranted;
  }
}
