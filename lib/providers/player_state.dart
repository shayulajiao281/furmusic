import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/song.dart';
import 'app_state.dart';
import '../services/music_api.dart';
import '../services/audio_cache.dart';

const _kPlayerStateKey = 'furkid_player_state_v1';

enum PlayMode { repeatAll, repeatOne, shuffle }

class PlayerState {
  final Song? current;
  final bool isPlaying;
  final bool isLoading;
  final Duration position;
  final Duration duration;
  final List<MapEntry<double, String>> lyric;
  final int lyricIndex;
  final PlayMode mode;
  final List<Song> queue;

  PlayerState({
    this.current,
    this.isPlaying = false,
    this.isLoading = false,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.lyric = const [],
    this.lyricIndex = -1,
    this.mode = PlayMode.repeatAll,
    this.queue = const [],
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
    List<Song>? queue,
  }) => PlayerState(
    current: current ?? this.current,
    isPlaying: isPlaying ?? this.isPlaying,
    isLoading: isLoading ?? this.isLoading,
    position: position ?? this.position,
    duration: duration ?? this.duration,
    lyric: lyric ?? this.lyric,
    lyricIndex: lyricIndex ?? this.lyricIndex,
    mode: mode ?? this.mode,
    queue: queue ?? this.queue,
  );

  double get progress {
    if (duration.inMilliseconds == 0) return 0;
    return position.inMilliseconds / duration.inMilliseconds;
  }
}

class PlayerNotifier extends Notifier<PlayerState> {
  final AudioPlayer _player = AudioPlayer();
  Duration _lastKnownDuration = Duration.zero;
  List<Song> _queue = [];
  String? _targetSongId;
  late final SharedPreferences _prefs;

  /// ★ 是否已经给 _player 设置过 audio source
  bool _hasSource = false;

  @override
  PlayerState build() {
    _prefs = ref.read(sharedPrefsProvider);

    _player.setLoopMode(LoopMode.all);
    _player.setShuffleModeEnabled(false);

    _player.currentIndexStream.listen((idx) {
      if (idx == null || idx < 0 || idx >= _queue.length) return;
      final song = _queue[idx];
      if (_targetSongId != null && song.id != _targetSongId) return;
      if (song.id == _targetSongId) _targetSongId = null;

      _lastKnownDuration = song.duration;
      state = state.copyWith(
        current: song,
        position: Duration.zero,
        duration: song.duration,
        lyric: const [],
        lyricIndex: -1,
      );
      _loadLyricAsync(song.id);
      _persist();
    });

    _player.playingStream.listen((p) {
      state = state.copyWith(isPlaying: p);
      if (!p) _persist(); // 暂停时把进度落盘
    });

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

    _player.durationStream.listen((d) {
      if (d != null && d > Duration.zero) {
        _lastKnownDuration = d;
        state = state.copyWith(duration: d);
      }
    });

    return _restore();
  }

  // ═══════════════════════════════════════════
  // 持久化
  // ═══════════════════════════════════════════
  PlayerState _restore() {
    try {
      final raw = _prefs.getString(_kPlayerStateKey);
      if (raw == null || raw.isEmpty) return PlayerState();

      final j = jsonDecode(raw) as Map<String, dynamic>;
      final songRaw = j['current'];
      if (songRaw == null) return PlayerState();

      final song = Song.fromJson(Map<String, dynamic>.from(songRaw as Map));
      final posMs = j['position'] as int? ?? 0;
      final modeStr = j['mode'] as String? ?? 'repeatAll';
      final queueRaw = j['queue'] as List? ?? [];
      final queue = queueRaw
          .whereType<Map>()
          .map((e) => Song.fromJson(Map<String, dynamic>.from(e)))
          .toList();

      final mode = PlayMode.values.firstWhere(
        (m) => m.name == modeStr,
        orElse: () => PlayMode.repeatAll,
      );

      _queue = queue.isNotEmpty ? queue : [song];
      _lastKnownDuration = song.duration;
      _applyModeToPlayer(mode);

      return PlayerState(
        current: song,
        isPlaying: false,
        isLoading: false,
        position: Duration(milliseconds: posMs),
        duration: song.duration > Duration.zero
            ? song.duration
            : Duration(milliseconds: posMs),
        mode: mode,
        queue: _queue,
      );
    } catch (_) {
      return PlayerState();
    }
  }

  void _persist() {
    try {
      final song = state.current;
      if (song == null) {
        _prefs.remove(_kPlayerStateKey);
        return;
      }
      final j = <String, dynamic>{
        'current': song.toJson(),
        'position': state.position.inMilliseconds,
        'mode': state.mode.name,
        'queue': state.queue.map((s) => s.toJson()).toList(),
      };
      _prefs.setString(_kPlayerStateKey, jsonEncode(j));
    } catch (_) {}
  }

  void _applyModeToPlayer(PlayMode mode) {
    switch (mode) {
      case PlayMode.repeatAll:
        _player.setLoopMode(LoopMode.all);
        _player.setShuffleModeEnabled(false);
        break;
      case PlayMode.repeatOne:
        _player.setLoopMode(LoopMode.one);
        _player.setShuffleModeEnabled(false);
        break;
      case PlayMode.shuffle:
        _player.setLoopMode(LoopMode.all);
        _player.setShuffleModeEnabled(true);
        break;
    }
  }

  // ═══════════════════════════════════════════
  // 播放入口
  // ═══════════════════════════════════════════
  Future<void> playSong(Song song, {List<Song>? queue}) async {
    HapticFeedback.mediumImpact();
    final list = queue ?? [song];
    _targetSongId = song.id;

    state = state.copyWith(
      current: song,
      isLoading: true,
      position: Duration.zero,
      duration: song.duration,
      lyric: const [],
      lyricIndex: -1,
    );

    final resolved = await _resolveAll(list);
    if (resolved.isEmpty) {
      _targetSongId = null;
      state = state.copyWith(isLoading: false);
      print('❌ 队列里没有任何歌能播放');
      return;
    }

    final idx = resolved.indexWhere((s) => s.id == song.id);
    if (idx < 0) {
      _targetSongId = null;
      state = state.copyWith(isLoading: false);
      print('❌ 当前歌解析失败');
      return;
    }

    _queue = resolved;
    state = state.copyWith(
      isLoading: false,
      queue: List.unmodifiable(resolved),
    );

    try {
      await _player.setAudioSources(
        resolved.map(_toSource).toList(),
        initialIndex: idx,
      );
      _hasSource = true;

      try {
        await _player.play();
      } catch (e) {
        print('⚠️ play 失败，重试: $e');
        await Future.delayed(const Duration(milliseconds: 200));
        await _player.play();
      }

      HapticFeedback.lightImpact();
      _persist();
    } catch (e) {
      _targetSongId = null;
      print('❌ 播放失败: $e');
    }
  }

  // ═══════════════════════════════════════════
  // 冷启动恢复后，第一次点播放
  // ═══════════════════════════════════════════
  Future<void> _resumeFromRestore() async {
    final song = state.current;
    if (song == null) return;

    final resumeAt = state.position;
    _targetSongId = song.id;
    state = state.copyWith(isLoading: true);

    final list = state.queue.isNotEmpty ? state.queue : [song];
    final resolved = await _resolveAll(list);
    if (resolved.isEmpty) {
      _targetSongId = null;
      state = state.copyWith(isLoading: false);
      return;
    }
    final idx = resolved.indexWhere((s) => s.id == song.id);
    if (idx < 0) {
      _targetSongId = null;
      state = state.copyWith(isLoading: false);
      return;
    }
    _queue = resolved;
    state = state.copyWith(
      isLoading: false,
      queue: List.unmodifiable(resolved),
    );

    try {
      await _player.setAudioSources(
        resolved.map(_toSource).toList(),
        initialIndex: idx,
      );
      _hasSource = true;
      if (resumeAt > Duration.zero) {
        await _player.seek(resumeAt);
      }
      await _player.play();
    } catch (e) {
      _targetSongId = null;
      print('❌ 恢复播放失败: $e');
      state = state.copyWith(isLoading: false);
    }
  }

  // ═══════════════════════════════════════════
  // AudioSource：支持本地文件 + 网络 URL
  // ═══════════════════════════════════════════
  AudioSource _toSource(Song s) {
    final isLocal = !s.audioPath.startsWith('http');

    return AudioSource.uri(
      isLocal ? Uri.file(s.audioPath) : Uri.parse(s.audioPath),
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
      headers: isLocal ? null : MusicApi.audioHeaders,
    );
  }

  Future<List<Song>> _resolveAll(List<Song> list) async {
    final result = <Song>[];
    const concurrent = 8;

    for (int i = 0; i < list.length; i += concurrent) {
      final end = (i + concurrent < list.length) ? i + concurrent : list.length;
      final batch = <Future<Song?>>[];
      for (int j = i; j < end; j++) {
        batch.add(_resolveOne(list[j]));
      }
      final resolved = await Future.wait(batch);
      result.addAll(resolved.whereType<Song>());
    }

    return result;
  }

  Future<Song?> _resolveOne(Song song) async {
    final cached = await AudioCache.get(song.id);
    if (cached != null) {
      print('📂 缓存命中: ${song.title}');
      return song.copyWith(audioPath: cached);
    }

    String? url = song.audioPath;
    if (url.isEmpty || !url.startsWith('http')) {
      print('🔍 线上解析: ${song.title}');
      url = await MusicApi.getSongUrl(song.id);
    }

    if (url == null || url.isEmpty) {
      print('❌ 解析失败: ${song.title}');
      return null;
    }

    AudioCache.download(
      song.id,
      url,
      headers: MusicApi.audioHeaders,
    ).then((_) => AudioCache.trim()).catchError((_) {});

    return song.copyWith(audioPath: url);
  }

  void _loadLyricAsync(String songId) {
    MusicApi.getLyric(songId)
        .then((lyric) {
          if (state.current?.id == songId && lyric.isNotEmpty) {
            state = state.copyWith(lyric: lyric);
          }
        })
        .catchError((_) {});
  }

  Future<void> playFromQueue(int idx) async {
    if (idx < 0 || idx >= _queue.length) return;
    await _player.seek(Duration.zero, index: idx);
    if (!_player.playing) await _player.play();
    HapticFeedback.mediumImpact();
  }

  // ═══════════════════════════════════════════
  // 播放模式
  // ═══════════════════════════════════════════
  Future<void> setPlayMode(PlayMode mode) async {
    state = state.copyWith(mode: mode);
    _applyModeToPlayer(mode);
    _persist();
  }

  Future<void> nextPlayMode() async {
    final order = [PlayMode.repeatAll, PlayMode.repeatOne, PlayMode.shuffle];
    final idx = order.indexOf(state.mode);
    await setPlayMode(order[(idx + 1) % order.length]);
  }

  Future<void> next() async {
    if (_player.hasNext) {
      HapticFeedback.selectionClick();
      await _player.seekToNext();
    }
  }

  Future<void> previous() async {
    if (_player.hasPrevious) {
      HapticFeedback.selectionClick();
      await _player.seekToPrevious();
    }
  }

  Future<void> togglePlay() async {
    if (state.isPlaying) {
      await _player.pause();
      return;
    }

    // ★ 冷启动恢复：有歌但没加载过 audio source → 先加载再续播
    if (!_hasSource && state.current != null) {
      await _resumeFromRestore();
      return;
    }

    await _player.play();
  }

  Future<void> seek(Duration pos) async {
    await _player.seek(pos);
    _persist();
  }
}

final playerStateProvider = NotifierProvider<PlayerNotifier, PlayerState>(
  PlayerNotifier.new,
);
