import 'package:just_audio_background/just_audio_background.dart';

class Song {
  final String id;

  /// ★ 音源：'bilibili' | 'netease' | 'qq' | 'kugou' | 'local'
  String source;

  String title;
  String artist;
  String album;
  String coverPath;
  String audioPath;
  Duration duration;
  bool isFavorite;

  Song({
    required this.id,
    this.source = 'bilibili',
    required this.title,
    required this.artist,
    this.album = '',
    this.coverPath = '',
    required this.audioPath,
    this.duration = Duration.zero,
    this.isFavorite = false,
  });

  /// 全局唯一 id：`source:id`（用于缓存、去重、active 判定）
  String get globalId => '$source:$id';

  MediaItem toMediaItem() => MediaItem(
    id: globalId,
    title: title,
    artist: artist,
    album: album,
    duration: duration,
    artUri: coverPath.isNotEmpty ? Uri.tryParse(coverPath) : null,
    extras: {'audioPath': audioPath, 'source': source},
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'source': source,
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
    source: j['source'] as String? ?? 'bilibili',
    title: j['title'] as String,
    artist: j['artist'] as String? ?? '未知歌手',
    album: j['album'] as String? ?? '',
    coverPath: j['coverPath'] as String? ?? '',
    audioPath: j['audioPath'] as String? ?? '',
    duration: Duration(milliseconds: (j['duration'] as int?) ?? 0),
    isFavorite: j['isFavorite'] as bool? ?? false,
  );

  Song copyWith({
    String? id,
    String? source,
    String? title,
    String? artist,
    String? album,
    String? coverPath,
    String? audioPath,
    Duration? duration,
    bool? isFavorite,
  }) => Song(
    id: id ?? this.id,
    source: source ?? this.source,
    title: title ?? this.title,
    artist: artist ?? this.artist,
    album: album ?? this.album,
    coverPath: coverPath ?? this.coverPath,
    audioPath: audioPath ?? this.audioPath,
    duration: duration ?? this.duration,
    isFavorite: isFavorite ?? this.isFavorite,
  );
}
