import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import '../models/song.dart';
import '../services/music_api.dart';

/// 播放模式
enum PlayMode {
  sequential, // 顺序播放（播完停）
  repeatAll, // 列表循环
  repeatOne, // 单曲循环
  shuffle, // 随机播放
}

class PlayerState {
  final Song? current;
  final bool isPlaying;
  final bool isLoading; // ★ 队列加载中
  final Duration position;
  final Duration duration;
  final List<MapEntry<double, String>> lyric;
  final int lyricIndex;
  final PlayMode mode;

  PlayerState({
    this.current,
    this.isPlaying = false,
    this.isLoading = false,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.lyric = const [],
    this.lyricIndex = -1,
    this.mode = PlayMode.sequential,
  });

  PlayerState copyWith({
    Song? current,
    bool? isPlaying,
    bool? isLoading,
    Duration? position,
    Duration? duration,
    List<MapEntry<double, String>>? lyric,
    int? lyricIndex,
    PlayMode? mode,
  }) => PlayerState(
    current: current ?? this.current,
    isPlaying: isPlaying ?? this.isPlaying,
    isLoading: isLoading ?? this.isLoading,
    position: position ?? this.position,
    duration: duration ?? this.duration,
    lyric: lyric ?? this.lyric,
    lyricIndex: lyricIndex ?? this.lyricIndex,
    mode: mode ?? this.mode,
  );

  double get progress {
    if (duration.inMilliseconds == 0) return 0;
    return position.inMilliseconds / duration.inMilliseconds;
  }
}

class PlayerNotifier extends Notifier<PlayerState> {
  final AudioPlayer _player = AudioPlayer();
  Duration _lastKnownDuration = Duration.zero;

  /// 内部队列（和 just_audio 的队列一一对应）
  List<Song> _queue = [];

  @override
  PlayerState build() {
    // ★ 切歌：just_audio 自己维护 currentIndex
    _player.currentIndexStream.listen((idx) {
      if (idx == null || idx < 0 || idx >= _queue.length) return;
      final song = _queue[idx];
      _lastKnownDuration = song.duration;
      state = state.copyWith(
        current: song,
        position: Duration.zero,
        duration: song.duration,
        lyric: const [],
        lyricIndex: -1,
      );
      _loadLyricAsync(song.id);
    });

    // 播放/暂停
    _player.playingStream.listen((p) {
      state = state.copyWith(isPlaying: p);
    });

    // 进度 + 歌词行
    _player.positionStream.listen((pos) {
      int idx = -1;
      final sec = pos.inMilliseconds / 1000.0;
      for (int i = 0; i < state.lyric.length; i++) {
        if (state.lyric[i].key <= sec) {
          idx = i;
        } else {
          break;
        }
      }
      state = state.copyWith(position: pos, lyricIndex: idx);
    });

    // 时长
    _player.durationStream.listen((d) {
      if (d != null && d > Duration.zero) {
        _lastKnownDuration = d;
        state = state.copyWith(duration: d);
      }
    });

    return PlayerState();
  }

  // ═══════════════════════════════════════════
  // 播放入口
  // ═══════════════════════════════════════════
  Future<void> playSong(Song song, {List<Song>? queue}) async {
    HapticFeedback.mediumImpact();

    final list = queue ?? [song];

    // 显示加载状态
    state = state.copyWith(
      current: song,
      isLoading: true,
      position: Duration.zero,
      duration: song.duration,
      lyric: const [],
      lyricIndex: -1,
    );

    // ★ 解析整个队列的 URL（并发限流 8）
    final resolved = await _resolveAll(list);

    if (resolved.isEmpty) {
      state = state.copyWith(isLoading: false);
      print('❌ 队列里没有任何歌能播放');
      return;
    }

    // 找当前歌在 resolved 里的索引
    final idx = resolved.indexWhere((s) => s.id == song.id);
    if (idx < 0) {
      state = state.copyWith(isLoading: false);
      print('❌ 当前歌解析失败');
      return;
    }

    _queue = resolved;
    state = state.copyWith(isLoading: false);

    try {
      // ★ 一次性加载整个队列（让锁屏上一曲/下一曲可用）
      await _player.setAudioSources(
        resolved.map(_toSource).toList(),
        initialIndex: idx,
      );
      await _player.play();
      HapticFeedback.lightImpact();
    } catch (e) {
      print('❌ 播放失败: $e');
    }
  }

  AudioSource _toSource(Song s) {
    return AudioSource.uri(
      Uri.parse(s.audioPath),
      tag: MediaItem(
        id: s.id,
        title: s.title,
        artist: s.artist,
        album: s.album,
        duration: s.duration,
        artUri: s.coverPath.isNotEmpty ? Uri.tryParse(s.coverPath) : null,
        extras: {
          'audioPath': s.audioPath,
          'duration': s.duration.inMilliseconds,
        },
      ),
      headers: MusicApi.audioHeaders,
    );
  }

  /// 并发解析整个队列，失败的直接过滤掉
  Future<List<Song>> _resolveAll(List<Song> list) async {
    final result = <Song>[];
    const concurrent = 8;

    for (int i = 0; i < list.length; i += concurrent) {
      final end = (i + concurrent < list.length) ? i + concurrent : list.length;
      final batch = <Future<Song?>>[];
      for (int j = i; j < end; j++) {
        final s = list[j];
        if (s.audioPath.isNotEmpty) {
          batch.add(Future.value(s));
        } else {
          batch.add(_resolveOne(s));
        }
      }
      final resolved = await Future.wait(batch);
      result.addAll(resolved.whereType<Song>());
    }

    return result;
  }

  Future<Song?> _resolveOne(Song song) async {
    final url = await MusicApi.getSongUrl(song.id);
    if (url == null || url.isEmpty) return null;
    return song.copyWith(audioPath: url);
  }

  /// 异步加载歌词
  void _loadLyricAsync(String songId) {
    MusicApi.getLyric(songId)
        .then((lyric) {
          if (state.current?.id == songId && lyric.isNotEmpty) {
            state = state.copyWith(lyric: lyric);
          }
        })
        .catchError((_) {});
  }

  // ═══════════════════════════════════════════
  // 播放模式
  // ═══════════════════════════════════════════
  Future<void> setPlayMode(PlayMode mode) async {
    state = state.copyWith(mode: mode);
    switch (mode) {
      case PlayMode.sequential:
        await _player.setLoopMode(LoopMode.off);
        await _player.setShuffleModeEnabled(false);
        break;
      case PlayMode.repeatAll:
        await _player.setLoopMode(LoopMode.all);
        await _player.setShuffleModeEnabled(false);
        break;
      case PlayMode.repeatOne:
        await _player.setLoopMode(LoopMode.one);
        await _player.setShuffleModeEnabled(false);
        break;
      case PlayMode.shuffle:
        await _player.setLoopMode(LoopMode.all);
        await _player.setShuffleModeEnabled(true);
        break;
    }
  }

  Future<void> nextPlayMode() async {
    final order = [
      PlayMode.sequential,
      PlayMode.repeatAll,
      PlayMode.repeatOne,
      PlayMode.shuffle,
    ];
    final idx = order.indexOf(state.mode);
    await setPlayMode(order[(idx + 1) % order.length]);
  }

  // ═══════════════════════════════════════════
  // 上一首 / 下一首
  // ═══════════════════════════════════════════
  Future<void> next() async {
    if (_player.hasNext) await _player.seekToNext();
  }

  Future<void> previous() async {
    if (_player.hasPrevious) await _player.seekToPrevious();
  }

  // ═══════════════════════════════════════════
  // 其他
  // ═══════════════════════════════════════════
  Future<void> togglePlay() async {
    if (state.isPlaying) {
      await _player.pause();
    } else {
      await _player.play();
    }
  }

  Future<void> seek(Duration pos) => _player.seek(pos);
}

final playerStateProvider = NotifierProvider<PlayerNotifier, PlayerState>(
  PlayerNotifier.new,
);
