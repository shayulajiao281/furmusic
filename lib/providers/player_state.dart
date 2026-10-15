import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import '../models/song.dart';
import '../services/music_api.dart';

/// 播放模式
enum PlayMode {
  sequential, // 顺序播放
  repeatAll, // 列表循环
  repeatOne, // 单曲循环
  shuffle, // 随机播放
}

class PlayerState {
  final Song? current;
  final bool isPlaying;
  final Duration position;
  final Duration duration;
  final List<MapEntry<double, String>> lyric;
  final int lyricIndex;
  final PlayMode mode;

  PlayerState({
    this.current,
    this.isPlaying = false,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.lyric = const [],
    this.lyricIndex = -1,
    this.mode = PlayMode.sequential,
  });

  PlayerState copyWith({
    Song? current,
    bool? isPlaying,
    Duration? position,
    Duration? duration,
    List<MapEntry<double, String>>? lyric,
    int? lyricIndex,
    PlayMode? mode,
  }) => PlayerState(
    current: current ?? this.current,
    isPlaying: isPlaying ?? this.isPlaying,
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

  /// 内部队列
  List<Song> _queue = [];
  int _currentIdx = 0;

  /// 防止并发切歌
  bool _switching = false;

  @override
  PlayerState build() {
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

    // 时长（只在 > 0 时覆盖）
    _player.durationStream.listen((d) {
      if (d != null && d > Duration.zero) {
        _lastKnownDuration = d;
        state = state.copyWith(duration: d);
      }
    });

    // 播放完成 → 自动切歌
    _player.processingStateStream.listen((ps) {
      if (ps == ProcessingState.completed) {
        if (state.mode == PlayMode.repeatOne) {
          // 单曲循环：重头播
          _player.seek(Duration.zero);
          _player.play();
        } else {
          // 其他模式：自动切下一首
          _autoNext();
        }
      }
    });

    return PlayerState();
  }

  // ═══════════════════════════════════════════
  // 播放入口
  // ═══════════════════════════════════════════
  Future<void> playSong(Song song, {List<Song>? queue}) async {
    _queue = List.from(queue ?? [song]);
    _currentIdx = _queue.indexWhere((s) => s.id == song.id);
    if (_currentIdx < 0) {
      _queue.insert(0, song);
      _currentIdx = 0;
    }

    // 更新当前歌为已解析的版本
    _queue[_currentIdx] = song;

    await _playCurrent();

    // 预解析下一首
    _prefetch(_currentIdx + 1);
  }

  /// 播放队列里的第 _currentIdx 首
  Future<void> _playCurrent() async {
    if (_switching) return;
    _switching = true;

    try {
      final song = _queue[_currentIdx];

      // 未解析 URL → 先解析
      if (song.audioPath.isEmpty) {
        print('🔍 解析: ${song.title}');
        final url = await MusicApi.getSongUrl(song.id);
        if (url == null || url.isEmpty) {
          print('❌ 解析失败: ${song.title}');
          _switching = false;
          return;
        }
        _queue[_currentIdx] = song.copyWith(audioPath: url);
      }

      final playable = _queue[_currentIdx];

      // 重置状态
      _lastKnownDuration = playable.duration;
      state = state.copyWith(
        current: playable,
        position: Duration.zero,
        duration: playable.duration,
        lyric: const [],
        lyricIndex: -1,
      );

      // 只加载当前这一首
      await _player.setAudioSource(
        AudioSource.uri(
          Uri.parse(playable.audioPath),
          tag: MediaItem(
            id: playable.id,
            title: playable.title,
            artist: playable.artist,
            album: playable.album,
            duration: playable.duration,
            artUri: playable.coverPath.isNotEmpty
                ? Uri.tryParse(playable.coverPath)
                : null,
            extras: {
              'audioPath': playable.audioPath,
              'duration': playable.duration.inMilliseconds,
            },
          ),
          headers: MusicApi.audioHeaders,
        ),
      );
      await _player.play();

      // 加载歌词（异步）
      final lyric = await MusicApi.getLyric(playable.id);
      if (lyric.isNotEmpty) {
        state = state.copyWith(lyric: lyric);
      }

      // 预解析下一首
      _prefetch(_currentIdx + 1);
    } finally {
      _switching = false;
    }
  }

  /// 后台预解析某首歌的 URL（不阻塞）
  void _prefetch(int idx) {
    if (idx < 0 || idx >= _queue.length) return;
    if (_queue[idx].audioPath.isNotEmpty) return;

    MusicApi.getSongUrl(_queue[idx].id)
        .then((url) {
          if (url != null && url.isNotEmpty) {
            _queue[idx] = _queue[idx].copyWith(audioPath: url);
            print('📦 预解析完成: ${_queue[idx].title}');
          }
        })
        .catchError((_) {});
  }

  // ═══════════════════════════════════════════
  // 播放模式
  // ═══════════════════════════════════════════
  Future<void> setPlayMode(PlayMode mode) async {
    state = state.copyWith(mode: mode);
    if (mode == PlayMode.repeatOne) {
      await _player.setLoopMode(LoopMode.one);
    } else {
      await _player.setLoopMode(LoopMode.off);
    }
    if (mode == PlayMode.shuffle) {
      await _player.setShuffleModeEnabled(true);
    } else {
      await _player.setShuffleModeEnabled(false);
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
    if (_switching) return;
    if (_queue.isEmpty) return;

    if (state.mode == PlayMode.shuffle) {
      _currentIdx = _randomIndex();
    } else {
      _currentIdx++;
      if (_currentIdx >= _queue.length) {
        if (state.mode == PlayMode.repeatAll) {
          _currentIdx = 0;
        } else {
          return; // 顺序播放到底，停
        }
      }
    }
    await _playCurrent();
  }

  Future<void> previous() async {
    if (_switching) return;
    if (_queue.isEmpty) return;

    if (state.mode == PlayMode.shuffle) {
      _currentIdx = _randomIndex();
    } else {
      _currentIdx--;
      if (_currentIdx < 0) _currentIdx = 0;
    }
    await _playCurrent();
  }

  /// 播放完成时自动切歌
  void _autoNext() {
    if (_queue.isEmpty) return;
    if (state.mode == PlayMode.sequential) {
      if (_currentIdx >= _queue.length - 1) return; // 到底了，停
    }
    next();
  }

  int _randomIndex() {
    if (_queue.length <= 1) return 0;
    int idx;
    do {
      idx = DateTime.now().microsecondsSinceEpoch % _queue.length;
    } while (idx == _currentIdx);
    return idx;
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
