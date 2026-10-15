import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:furkid_music/services/music_api.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import '../models/song.dart';

class PlayerState {
  final Song? current;
  final bool isPlaying;
  final Duration position;
  final Duration duration;

  PlayerState({
    this.current,
    this.isPlaying = false,
    this.position = Duration.zero,
    this.duration = Duration.zero,
  });

  PlayerState copyWith({
    Song? current,
    bool? isPlaying,
    Duration? position,
    Duration? duration,
  }) => PlayerState(
    current: current ?? this.current,
    isPlaying: isPlaying ?? this.isPlaying,
    position: position ?? this.position,
    duration: duration ?? this.duration,
  );

  double get progress {
    if (duration.inMilliseconds == 0) return 0;
    return position.inMilliseconds / duration.inMilliseconds;
  }
}

class PlayerNotifier extends Notifier<PlayerState> {
  final AudioPlayer _player = AudioPlayer();

  @override
  PlayerState build() {
    // 监听当前歌曲
    _player.currentIndexStream.listen((idx) {
      if (idx == null) return;
      final tag = _player.sequenceState?.currentSource?.tag;
      if (tag is MediaItem) {
        state = state.copyWith(
          current: Song(
            id: tag.id,
            title: tag.title,
            artist: tag.artist ?? '未知歌手',
            album: tag.album ?? '',
            audioPath: tag.extras?['audioPath'] as String? ?? tag.id,
            duration: tag.duration ?? Duration.zero,
            coverPath: tag.artUri?.toString() ?? '',
          ),
        );
      }
    });

    // 播放/暂停
    _player.playingStream.listen((p) {
      state = state.copyWith(isPlaying: p);
    });

    // 进度
    _player.positionStream.listen((pos) {
      state = state.copyWith(position: pos);
    });

    // 时长
    _player.durationStream.listen((d) {
      if (d != null) state = state.copyWith(duration: d);
    });

    return PlayerState();
  }

  /// 播放歌曲（支持本地文件 + 网络 URL）
  Future<void> playSong(Song song, {List<Song>? queue}) async {
    final list = queue ?? [song];
    final idx = list.indexWhere((s) => s.id == song.id);

    await _player.setAudioSources(
      list.map((s) {
        final uri = s.audioPath.startsWith('http')
            ? Uri.parse(s.audioPath)
            : Uri.file(s.audioPath);

        return AudioSource.uri(
          uri,
          tag: s.toMediaItem(),
          headers: MusicApi.audioHeaders, // ★ 带 Cookie 的 headers
        );
      }).toList(),
      initialIndex: idx < 0 ? 0 : idx,
    );
    await _player.play();
  }

  Future<void> togglePlay() async {
    if (state.isPlaying) {
      await _player.pause();
    } else {
      await _player.play();
    }
  }

  Future<void> next() async {
    if (_player.hasNext) await _player.seekToNext();
  }

  Future<void> previous() async {
    if (_player.hasPrevious) await _player.seekToPrevious();
  }

  Future<void> seek(Duration pos) => _player.seek(pos);
}

final playerStateProvider = NotifierProvider<PlayerNotifier, PlayerState>(
  PlayerNotifier.new,
);
