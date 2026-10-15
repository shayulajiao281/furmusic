import 'package:just_audio_background/just_audio_background.dart';

class Song {
  final String id;
  String title;
  String artist;
  String album;
  String coverPath;
  String audioPath;
  Duration duration;
  bool isFavorite;

  Song({
    required this.id,
    required this.title,
    required this.artist,
    this.album = '',
    this.coverPath = '',
    required this.audioPath,
    this.duration = Duration.zero,
    this.isFavorite = false,
  });

  /// 转成 just_audio_background 需要的 MediaItem
  MediaItem toMediaItem() => MediaItem(
    id: id,
    title: title,
    artist: artist,
    album: album,
    duration: duration,
    artUri: coverPath.isNotEmpty ? Uri.tryParse(coverPath) : null,
    extras: {'audioPath': audioPath},
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'artist': artist,
    'album': album,
    'coverPath': coverPath,
    'audioPath': audioPath,
    'duration': duration.inMilliseconds,
    'isFavorite': isFavorite,
  };

  factory Song.fromJson(Map<String, dynamic> j) => Song(
    id: j['id'] as String,
    title: j['title'] as String,
    artist: j['artist'] as String? ?? '未知歌手',
    album: j['album'] as String? ?? '',
    coverPath: j['coverPath'] as String? ?? '',
    audioPath: j['audioPath'] as String? ?? '',
    duration: Duration(milliseconds: (j['duration'] as int?) ?? 0),
    isFavorite: j['isFavorite'] as bool? ?? false,
  );

  Song copyWith({bool? isFavorite, String? coverPath, String? audioPath}) =>
      Song(
        id: id,
        title: title,
        artist: artist,
        album: album,
        coverPath: coverPath ?? this.coverPath,
        audioPath: audioPath ?? this.audioPath,
        duration: duration,
        isFavorite: isFavorite ?? this.isFavorite,
      );
}
