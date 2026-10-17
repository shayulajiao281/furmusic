import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/song.dart';
import 'app_state.dart';
import 'music_sources.dart';
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
  final bool expanded;
  final String? lastError;
  final int errorId;

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
    this.expanded = false,
    this.lastError,
    this.errorId = 0,
  });

  PlayerState copyWith({
    Song? current,
    bool clearCurrent = false,
    bool? isPlaying,
    bool? isLoading,
    Duration? position,
    Duration? duration,
    List<MapEntry<double, String>>? lyric,
    int? lyricIndex,
    PlayMode? mode,
    List<Song>? queue,
    bool? expanded,
    String? lastError,
    int? errorId,
  }) => PlayerState(
    current: clearCurrent ? null : (current ?? this.current),
    isPlaying: isPlaying ?? this.isPlaying,
    isLoading: isLoading ?? this.isLoading,
    position: position ?? this.position,
    duration: duration ?? this.duration,
    lyric: lyric ?? this.lyric,
    lyricIndex: lyricIndex ?? this.lyricIndex,
    mode: mode ?? this.mode,
    queue: queue ?? this.queue,
    expanded: expanded ?? this.expanded,
    lastError: lastError ?? this.lastError,
    errorId: errorId ?? this.errorId,
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
  bool _hasSource = false;
  bool _switching = false;
  DateTime? _switchLockTime;

  bool _completing = false;
  static const _lockTimeout = 20;

  @override
  PlayerState build() {
    _prefs = ref.read(sharedPrefsProvider);

    _player.setLoopMode(LoopMode.off);
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
      _loadLyricAsync(song);
      _persist();
    });

    _player.playingStream.listen((p) {
      state = state.copyWith(
        isPlaying: p,
        isLoading: p ? false : state.isLoading,
      );
      if (!p) _persist();
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

    _player.processingStateStream.listen((s) {
      if (s == ProcessingState.completed) {
        _onSongCompleted();
      }
    });

    return _restore();
  }

  // ═══════════════════════════════════════════
  // 播完当前歌：由这里接管
  // ═══════════════════════════════════════════
  Future<void> _onSongCompleted() async {
    if (_completing) return;
    _completing = true;
    try {
      print('🔚 [player] 当前歌播完，模式=${state.mode.name}');

      if (state.mode == PlayMode.repeatOne) {
        // 单曲循环：重播当前
        try {
          await _player.seek(Duration.zero);
          unawaited(_player.play());
          print('🔂 [player] 单曲循环：重播当前');
          return;
        } catch (e) {
          print('❌ [player] 重播失败，尝试切下一首: $e');
          // 失败则降级去切下一首
        }
      }

      // 列表循环 / 随机 / 单曲失败：自动切下一首
      await _autoPlayNext();
    } finally {
      _completing = false;
    }
  }

  /// ★ 自动切下一首：遇到播不了的自动跳过
  Future<void> _autoPlayNext() async {
    if (_queue.isEmpty) return;
    var cur = state.current;
    if (cur == null) return;

    int attempts = 0;
    final maxAttempts = _queue.length;

    while (attempts < maxAttempts) {
      attempts++;
      
      // 关键：将 cur 提取为 final，避免闭包类型提升失效
      final currentSong = cur!; 
      
      final idx = _queue.indexWhere((s) => s.globalId == currentSong.globalId);
      if (idx < 0) return;

      int nextIdx;
      if (state.mode == PlayMode.shuffle && _queue.length > 1) {
        final rand = DateTime.now().millisecondsSinceEpoch % _queue.length;
        nextIdx = rand == idx ? (idx + 1) % _queue.length : rand;
      } else {
        nextIdx = idx + 1;
        if (nextIdx >= _queue.length) nextIdx = 0;
      }

      final nextSong = _queue[nextIdx];
      print('⏭ [player] 自动切到队列第 $nextIdx 首: ${nextSong.title}');

      // 传 fromAutoPlay: true，告诉 playSong 失败时不要弹 Toast
      final ok = await playSong(nextSong, queue: _queue, fromAutoPlay: true);
      if (ok) {
        return; // 播放成功，结束循环
      }

      // 如果在此期间用户手动切了歌，打断当前自动循环
      if (state.current?.globalId != currentSong.globalId) {
        print('⚠️ [player] 自动切歌被用户打断');
        return;
      }

      // 播放失败，继续尝试下一首
      print('⚠️ [player] 自动切歌失败，跳过到下一首');
      cur = nextSong;
    }

    print('❌ [player] 队列里所有歌都播不了，暂停');
    _forceStop();
    state = state.copyWith(isLoading: false, isPlaying: false);
  }

  // ═══ 锁 ═══
  bool get _isSwitching {
    if (!_switching) return false;
    if (_switchLockTime != null) {
      final elapsed = DateTime.now().difference(_switchLockTime!);
      if (elapsed.inSeconds > _lockTimeout) {
        print('🔓 [player] 锁超时 ${elapsed.inSeconds}s，自动释放');
        _switching = false;
        _switchLockTime = null;
        return false;
      }
    }
    return true;
  }

  void _lock() {
    _switching = true;
    _switchLockTime = DateTime.now();
  }

  void _unlock() {
    _switching = false;
    _switchLockTime = null;
  }

  void _reportError(String msg) {
    print('🚨 [player] $msg');
    state = state.copyWith(
      lastError: msg,
      errorId: state.errorId + 1,
      isLoading: false,
    );
  }

  void expand() {
    if (!state.expanded) state = state.copyWith(expanded: true);
  }

  void collapse() {
    if (state.expanded) state = state.copyWith(expanded: false);
  }

  // ═══ 持久化 ═══
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
        expanded: false,
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
      case PlayMode.shuffle:
        _player.setLoopMode(LoopMode.off);
        _player.setShuffleModeEnabled(false);
        break;
      case PlayMode.repeatOne:
        _player.setLoopMode(LoopMode.one);
        _player.setShuffleModeEnabled(false);
        break;
    }
  }

  Future<void> _forceStop() async {
    try {
      await _player.stop().timeout(const Duration(seconds: 2));
      print('⏹ [player] 已停止');
    } catch (e) {
      print('⚠️ [player] stop 异常，强制 pause+stop: $e');
      try {
        await _player.pause().timeout(const Duration(seconds: 1));
      } catch (_) {}
      try {
        await _player.stop().timeout(const Duration(seconds: 1));
      } catch (_) {}
    }
    _hasSource = false;
  }

  Future<void> _resetPlayer() async {
    await _forceStop();
    _targetSongId = null;
  }

  String _failReason(Song song) {
    if (song.isVip) {
      return '《${song.title}》需要 VIP 会员，无法播放';
    }
    return '《${song.title}》暂时无法播放（可能是版权限制）';
  }

  // ═══════════════════════════════════════════
  // 播放（返回是否成功）
  // ═══════════════════════════════════════════
  Future<bool> playSong(
    Song song, {
    List<Song>? queue,
    bool fromAutoPlay = false,
  }) async {
    if (_isSwitching) {
      print('⚠️ [player] 正在切歌，忽略本次点击');
      return false;
    }
    _lock();
    print('🔒 [player] 加锁，播放 ${song.title}${fromAutoPlay ? " (自动)" : ""}');

    try {
      HapticFeedback.mediumImpact();

      final rawList = queue ?? [song];
      final seen = <String>{};
      final list = <Song>[];
      for (final s in rawList) {
        if (seen.add(s.globalId)) list.add(s);
      }
      if (!list.any((s) => s.globalId == song.globalId)) {
        list.add(song);
      }

      await _forceStop();

      state = state.copyWith(
        current: song,
        expanded: true,
        isLoading: true,
        isPlaying: false,
        position: Duration.zero,
        duration: song.duration,
        lyric: const [],
        lyricIndex: -1,
        queue: List.unmodifiable(list),
      );

      _queue = list;

      print('🔍 [player] 解析 ${song.title} (${song.source})');
      final current = await _resolveOne(song).timeout(
        const Duration(seconds: 20),
        onTimeout: () {
          print('❌ [player] _resolveOne 超时');
          return null;
        },
      );

      if (current == null || current.audioPath.isEmpty) {
        print('❌ [player] 解析失败');
        await _resetPlayer();
        state = state.copyWith(isLoading: false);
        if (!fromAutoPlay) _reportError(_failReason(song));
        return false;
      }

      _targetSongId = song.id;

      try {
        print('🎵 [player] setAudioSource: ${current.audioPath}');
        await _player
            .setAudioSource(_toSource(current))
            .timeout(const Duration(seconds: 20));
        _hasSource = true;
      } catch (e) {
        print('❌ [player] setAudioSource 失败: $e');

        // 坏缓存自动清理重试
        if (!current.audioPath.startsWith('http')) {
          print('🔧 [player] 可能是坏缓存，删除后重试');
          try {
            final f = File(current.audioPath);
            if (f.existsSync()) f.deleteSync();
          } catch (_) {}
          final retry = await _resolveOne(song).timeout(
            const Duration(seconds: 20),
            onTimeout: () => null,
          );
          if (retry != null && retry.audioPath.isNotEmpty) {
            try {
              await _player
                  .setAudioSource(_toSource(retry))
                  .timeout(const Duration(seconds: 20));
              _hasSource = true;
              unawaited(_player.play());
              state = state.copyWith(isLoading: false, isPlaying: true);
              _persist();
              _loadLyricAsync(song);
              return true;
            } catch (e2) {
              print('❌ [player] 重试也失败: $e2');
            }
          }
        }

        await _resetPlayer();
        state = state.copyWith(isLoading: false, isPlaying: false);
        if (!fromAutoPlay) _reportError(_failReason(song));
        return false;
      }

      unawaited(_player.play());

      state = state.copyWith(isLoading: false, isPlaying: true);
      HapticFeedback.lightImpact();
      _persist();

      _loadLyricAsync(song);

      print('✅ [player] 播放已启动');
      return true;
    } catch (e) {
      print('❌ [player] playSong 异常: $e');
      await _resetPlayer();
      state = state.copyWith(isLoading: false, isPlaying: false);
      if (!fromAutoPlay) _reportError('播放失败: $e');
      return false;
    } finally {
      _unlock();
      print('🔓 [player] 解锁');
    }
  }

  Future<void> _resumeFromRestore() async {
    final song = state.current;
    if (song == null) return;
    if (_isSwitching) return;
    _lock();

    try {
      final resumeAt = state.position;
      _targetSongId = song.id;
      state = state.copyWith(isLoading: true);

      final current = await _resolveOne(song).timeout(
        const Duration(seconds: 20),
        onTimeout: () => null,
      );

      if (current == null || current.audioPath.isEmpty) {
        await _resetPlayer();
        state = state.copyWith(isLoading: false);
        _reportError('《${song.title}》无法恢复播放');
        return;
      }

      _queue = state.queue.isNotEmpty ? state.queue : [song];

      try {
        await _player
            .setAudioSource(_toSource(current))
            .timeout(const Duration(seconds: 20));
        _hasSource = true;
        if (resumeAt > Duration.zero) {
          await _player.seek(resumeAt).timeout(const Duration(seconds: 5));
        }
        unawaited(_player.play());
        state = state.copyWith(
          isLoading: false,
          isPlaying: true,
          queue: List.unmodifiable(_queue),
        );
      } catch (e) {
        print('❌ [player] resume 失败: $e');
        await _resetPlayer();
        state = state.copyWith(isLoading: false, isPlaying: false);
        _reportError(_failReason(song));
      }
    } finally {
      _unlock();
    }
  }

  AudioSource _toSource(Song s) {
    final path = s.audioPath;
    final isHttp = path.startsWith('http://') || path.startsWith('https://');
    final isLocal = !isHttp;

    final source = ref.read(sourceByIdProvider)(s.source);
    final headers = isLocal ? null : source.audioHeaders;

    return AudioSource.uri(
      isLocal ? Uri.file(path) : Uri.parse(path),
      tag: MediaItem(
        id: s.globalId,
        title: s.title,
        artist: s.artist,
        album: s.album,
        duration: s.duration,
        artUri: s.coverPath.isNotEmpty ? Uri.tryParse(s.coverPath) : null,
        extras: {
          'audioPath': s.audioPath,
          'source': s.source,
          'duration': s.duration.inMilliseconds,
        },
      ),
      headers: headers,
    );
  }

  Future<Song?> _resolveOne(Song song) async {
    if (song.source == 'local') return song;

    final cached = await AudioCache.get(song.globalId);
    if (cached != null) {
      print('📂 [player] 缓存命中: ${song.title}');
      return song.copyWith(audioPath: cached);
    }

    String? url = song.audioPath;
    if (url.isEmpty || !url.startsWith('http')) {
      final source = ref.read(sourceByIdProvider)(song.source);
      url = await source.getSongUrl(song.id).timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          print('❌ [player] getSongUrl 超时: ${song.title}');
          return null;
        },
      );
    }

    if (url == null || url.isEmpty) {
      print('❌ [player] URL 为空: ${song.title}');
      return null;
    }

    final source = ref.read(sourceByIdProvider)(song.source);
    AudioCache.download(
      song.globalId,
      url,
      headers: source.audioHeaders,
    ).then((_) => AudioCache.trim()).catchError((_) {});

    return song.copyWith(audioPath: url);
  }

  void _loadLyricAsync(Song song) {
    final source = ref.read(sourceByIdProvider)(song.source);
    source
        .getLyric(song.id)
        .then((lyric) {
          if (state.current?.globalId == song.globalId && lyric.isNotEmpty) {
            state = state.copyWith(lyric: lyric);
          }
        })
        .catchError((_) {});
  }

  Future<void> _playIndex(int idx) async {
    if (idx < 0 || idx >= _queue.length) return;
    final song = _queue[idx];
    print('🎯 [player] 切到队列第 $idx 首: ${song.title}');
    await playSong(song, queue: _queue);
  }

  Future<void> playFromQueue(int idx) async {
    await _playIndex(idx);
  }

  void removeFromQueue(Song song) {
    final oldIdx = _queue.indexWhere((s) => s.globalId == song.globalId);
    if (oldIdx < 0) {
      print('⚠️ [player] 队列里找不到这首歌');
      return;
    }

    final isCurrent = state.current?.globalId == song.globalId;
    final newQueue = [..._queue]..removeAt(oldIdx);
    _queue = newQueue;

    if (!isCurrent) {
      state = state.copyWith(queue: List.unmodifiable(newQueue));
      _persist();
      print('🗑 [player] 已移除: ${song.title}，剩余 ${newQueue.length} 首');
      return;
    }

    if (newQueue.isEmpty) {
      print('🗑 [player] 删除当前歌，队列空了，暂停');
      _forceStop();
      state = state.copyWith(
        clearCurrent: true,
        queue: const [],
        isPlaying: false,
        isLoading: false,
        position: Duration.zero,
        duration: Duration.zero,
        lyric: const [],
        lyricIndex: -1,
      );
      _prefs.remove(_kPlayerStateKey);
      return;
    }

    final nextIdx = oldIdx < newQueue.length ? oldIdx : newQueue.length - 1;
    final nextSong = newQueue[nextIdx];

    state = state.copyWith(queue: List.unmodifiable(newQueue));
    print('🗑 [player] 删除当前歌，自动切到队列第 $nextIdx 首: ${nextSong.title}');

    playSong(nextSong, queue: newQueue);
  }

  Future<void> setPlayMode(PlayMode mode) async {
    state = state.copyWith(mode: mode);
    _applyModeToPlayer(mode);
    _persist();
    print('🔀 [player] 播放模式切换为: ${mode.name}');
  }

  Future<void> nextPlayMode() async {
    final order = [PlayMode.repeatAll, PlayMode.repeatOne, PlayMode.shuffle];
    final idx = order.indexOf(state.mode);
    await setPlayMode(order[(idx + 1) % order.length]);
  }

  Future<void> next() async {
    final cur = state.current;
    if (cur == null) return;
    if (_queue.isEmpty) return;

    final idx = _queue.indexWhere((s) => s.globalId == cur.globalId);
    if (idx < 0) return;

    if (state.mode == PlayMode.shuffle && _queue.length > 1) {
      final rand = DateTime.now().millisecondsSinceEpoch % _queue.length;
      if (rand != idx) {
        await _playIndex(rand);
        return;
      }
    }

    if (idx + 1 < _queue.length) {
      await _playIndex(idx + 1);
    } else {
      if (state.mode == PlayMode.repeatAll) {
        await _playIndex(0);
      }
    }
  }

  Future<void> previous() async {
    final cur = state.current;
    if (cur == null) return;
    if (_queue.isEmpty) return;

    final idx = _queue.indexWhere((s) => s.globalId == cur.globalId);
    if (idx < 0) return;

    if (idx - 1 >= 0) {
      await _playIndex(idx - 1);
    } else {
      if (state.mode == PlayMode.repeatAll) {
        await _playIndex(_queue.length - 1);
      }
    }
  }

  Future<void> togglePlay() async {
    if (state.isPlaying) {
      try {
        await _player.pause().timeout(const Duration(seconds: 3));
      } catch (e) {
        print('⚠️ [player] pause 异常: $e');
      }
      state = state.copyWith(isPlaying: false);
      return;
    }
    if (!_hasSource && state.current != null) {
      await _resumeFromRestore();
      return;
    }
    try {
      unawaited(_player.play());
      state = state.copyWith(isPlaying: true);
    } catch (e) {
      print('❌ [player] togglePlay 失败: $e');
      await _resetPlayer();
      state = state.copyWith(isPlaying: false, isLoading: false);
      final s = state.current;
      if (s != null) _reportError(_failReason(s));
    }
  }

  Future<void> seek(Duration pos) async {
    try {
      await _player.seek(pos);
      _persist();
    } catch (_) {}
  }
}

final playerStateProvider = NotifierProvider<PlayerNotifier, PlayerState>(
  PlayerNotifier.new,
);