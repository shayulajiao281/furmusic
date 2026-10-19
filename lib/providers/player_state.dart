import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/widgets.dart';
import '../models/song.dart';
import 'app_state.dart';
import 'music_sources.dart';
import '../services/audio_cache.dart';
import '../services/image_cache.dart';
import '../services/lyric_cache.dart';
import '../core/player/audio_engine.dart';

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

class PlayerNotifier extends Notifier<PlayerState> with WidgetsBindingObserver {
  late final AudioEngine _engine;
  late final SharedPreferences _prefs;

  List<Song> _queue = [];
  Duration _lastKnownDuration = Duration.zero;

  final Map<String, String> _resolvedUrls = {};
  final Set<String> _cacheTriggeredSongs = {};

  /// 歌词请求版本号，防止旧请求覆盖新歌词
  int _lyricRequestId = 0;

  /// 连续错误计数（带时间窗口）
  int _consecutiveErrors = 0;
  DateTime? _lastErrorTime;

  /// ★ 切换锁：切歌期间屏蔽所有 stream，防止旧歌状态覆盖 UI
  bool _switching = false;

  @override
  PlayerState build() {
    _engine = AudioEngine();
    _prefs = ref.read(sharedPrefsProvider);

    _engine.init();

    WidgetsBinding.instance.addObserver(this);

    ref.onDispose(() {
      WidgetsBinding.instance.removeObserver(this);
      _resolvedUrls.clear();
      _cacheTriggeredSongs.clear();
      _engine.dispose();
    });

    _bindEngineEvents();
    _bindPlayerStreams();

    return _restore();
  }

  void _bindEngineEvents() {
    _engine.player.playerStateStream.listen(
      (ps) {
        if (_switching) return; // ★
        state = state.copyWith(
          isPlaying: ps.playing,
          isLoading:
              ps.processingState == ProcessingState.loading ||
              ps.processingState == ProcessingState.buffering,
        );
        if (!ps.playing) _persist();
      },
      onError: (Object e, StackTrace st) {
        print('⚠️ [player] playerStateStream error: $e');
      },
    );
  }

  void _bindPlayerStreams() {
    _engine.player.currentIndexStream.listen((idx) {
      if (_switching) return; // ★
      if (idx == null || idx < 0 || idx >= _queue.length) return;
      final song = _queue[idx];
      if (state.current?.globalId == song.globalId) return;

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
      print('🎵 [player] 原生队列切换到第 $idx 首: ${song.title}');
    });

    _engine.player.positionStream.listen((pos) {
      if (_switching) return; // ★
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

      if (pos > Duration.zero) {
        final song = state.current;
        if (song != null) _triggerCacheIfNeeded(song);
      }
    });

    _engine.player.durationStream.listen((d) {
      if (_switching) return; // ★
      if (d != null && d > Duration.zero) {
        _lastKnownDuration = d;
        state = state.copyWith(duration: d);
      }
    });

    _engine.player.playbackEventStream.listen(
      (event) {},
      onError: (Object e, StackTrace st) {
        print('❌ [player] 播放发生错误: $e');
        _handlePlaybackError();
      },
    );
  }

  void _handlePlaybackError() {
    final now = DateTime.now();
    if (_lastErrorTime != null &&
        now.difference(_lastErrorTime!) < const Duration(seconds: 3)) {
      _consecutiveErrors++;
    } else {
      _consecutiveErrors = 1;
    }
    _lastErrorTime = now;

    if (_consecutiveErrors >= 3) {
      print('🛑 [player] 连续播放失败 3 次，停止自动切换');
      _consecutiveErrors = 0;
      state = state.copyWith(isPlaying: false, isLoading: false);
      final s = state.current;
      if (s != null) _reportError(_failReason(s));
      return;
    }

    if (state.isPlaying && _queue.length > 1) {
      print('🔄 [player] 播放异常，尝试下一首');
      next();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState lifecycleState) {
    if (lifecycleState == AppLifecycleState.resumed) {
      if (state.isPlaying && !_engine.isPlaying && _engine.hasSource) {
        print('🔄 [player] 从后台恢复，强制重新播放');
        _engine.play();
      }
    }
  }

  Future<void> _triggerCacheIfNeeded(Song song) async {
    if (song.source == 'local') return;
    if (_cacheTriggeredSongs.contains(song.globalId)) return;

    final cached = await AudioCache.get(song.globalId);
    if (cached != null) {
      _cacheTriggeredSongs.add(song.globalId);
      return;
    }
    if (AudioCache.isDownloading(song.globalId)) return;

    String? url = _resolvedUrls[song.globalId];
    if (url == null || !url.startsWith('http')) {
      // 重启后 _resolvedUrls 为空，主动解析一次
      try {
        final source = ref.read(sourceByIdProvider)(song.source);
        url = await source.getSongUrl(song.id);
        if (url == null || !url.startsWith('http')) return;
        _resolvedUrls[song.globalId] = url;
      } catch (_) {
        return;
      }
    }

    _cacheTriggeredSongs.add(song.globalId);

    final source = ref.read(sourceByIdProvider)(song.source);
    AudioCache.download(
      song.globalId,
      url,
      headers: source.audioHeaders,
    ).then((_) => AudioCache.trim()).catchError((e) {
      // ★ 失败移除标记，下次播放还能重试
      _cacheTriggeredSongs.remove(song.globalId);
      print('⚠️ [cache] 下载失败，已移除标记: ${song.title} → $e');
    });
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

  /// 从持久化恢复时，本地缓存路径不可信，一律清空
  Song _sanitizeRestoredSong(Song s) {
    if (s.source == 'local') return s;
    final path = s.audioPath;
    if (path.isEmpty) return s;
    if (path.startsWith('http')) return s;
    print('🧹 [restore] 清除跨进程恢复的本地路径: ${s.title} -> $path');
    return s.copyWith(audioPath: '');
  }

  PlayerState _restore() {
    try {
      final raw = _prefs.getString(_kPlayerStateKey);
      if (raw == null || raw.isEmpty) return PlayerState();

      final j = jsonDecode(raw) as Map<String, dynamic>;
      final songRaw = j['current'];
      if (songRaw == null) return PlayerState();

      final song = _sanitizeRestoredSong(
        Song.fromJson(Map<String, dynamic>.from(songRaw as Map)),
      );
      final posMs = j['position'] as int? ?? 0;
      final modeStr = j['mode'] as String? ?? 'repeatAll';
      final queueRaw = j['queue'] as List? ?? [];

      final queue = queueRaw
          .whereType<Map>()
          .map(
            (e) => _sanitizeRestoredSong(
              Song.fromJson(Map<String, dynamic>.from(e)),
            ),
          )
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
        _engine.player.setLoopMode(LoopMode.all);
        _engine.player.setShuffleModeEnabled(false);
        break;
      case PlayMode.repeatOne:
        _engine.player.setLoopMode(LoopMode.one);
        _engine.player.setShuffleModeEnabled(false);
        break;
      case PlayMode.shuffle:
        _engine.player.setLoopMode(LoopMode.all);
        _engine.player.setShuffleModeEnabled(true);
        break;
    }
  }

  String _failReason(Song song) {
    if (song.isVip) return '《${song.title}》需要 VIP 会员';
    return '《${song.title}》暂时无法播放';
  }

  Future<Song?> _resolveOne(Song song) async {
    if (song.source == 'local') {
      if (!File(song.audioPath).existsSync()) return null;
      return song;
    }

    final cached = await AudioCache.get(song.globalId);
    if (cached != null) {
      try {
        final file = File(cached);
        if (await file.exists() && await file.length() > 1024) {
          return song.copyWith(audioPath: cached);
        } else {
          try {
            await file.delete();
          } catch (_) {}
        }
      } catch (e) {
        print('⚠️ [resolve] 缓存校验异常: $e');
      }
    }

    if (_resolvedUrls.containsKey(song.globalId)) {
      return song.copyWith(audioPath: _resolvedUrls[song.globalId]);
    }

    String? url = song.audioPath;
    if (url.isEmpty || !url.startsWith('http')) {
      final source = ref.read(sourceByIdProvider)(song.source);
      url = await source
          .getSongUrl(song.id)
          .timeout(const Duration(seconds: 6), onTimeout: () => null);
    }

    if (url == null || url.isEmpty) return null;

    _resolvedUrls[song.globalId] = url;
    return song.copyWith(audioPath: url);
  }

  /// ★ 加速版：已解析的歌瞬间返回，只有真正未解析的才走网络
  Future<List<Song>> _resolveAll(List<Song> list) async {
    final resolved = await Future.wait(
      list.map((s) async {
        // 1. 本地歌：文件存在即可
        if (s.source == 'local') {
          if (File(s.audioPath).existsSync()) return s;
          return null;
        }

        // 2. audioPath 已经是 http：之前解析过，直接用
        if (s.audioPath.startsWith('http')) {
          return s;
        }

        // 3. 内存缓存命中
        if (_resolvedUrls.containsKey(s.globalId)) {
          return s.copyWith(audioPath: _resolvedUrls[s.globalId]);
        }

        // 4. 本地缓存命中
        final cached = await AudioCache.get(s.globalId);
        if (cached != null) {
          try {
            final f = File(cached);
            if (await f.exists() && await f.length() > 1024) {
              return s.copyWith(audioPath: cached);
            }
          } catch (_) {}
        }

        // 5. 才走网络
        try {
          return await _resolveOne(s);
        } catch (_) {
          return null;
        }
      }),
    );
    return resolved.whereType<Song>().toList();
  }

  AudioSource _singleSource(Song s) {
    final path = s.audioPath;
    final isLocal = !path.startsWith('http');
    final source = ref.read(sourceByIdProvider)(s.source);
    final headers = isLocal ? null : source.audioHeaders;

    // ★ 只给本地/已缓存的封面，避免断网时 just_audio_background 卡住
    Uri? artUri;
    if (s.coverPath.isNotEmpty) {
      if (!s.coverPath.startsWith('http')) {
        artUri = Uri.tryParse(s.coverPath);
      } else {
        final cachedCover = ImageCacheManager.getCached(s.coverPath);
        if (cachedCover != null) {
          artUri = Uri.file(cachedCover.path);
        }
      }
    }

    return AudioSource.uri(
      isLocal ? Uri.file(path) : Uri.parse(path),
      tag: MediaItem(
        id: s.globalId,
        title: s.title,
        artist: s.artist,
        album: s.album,
        duration: s.duration,
        artUri: artUri,
        extras: {
          'audioPath': s.audioPath,
          'source': s.source,
          'duration': s.duration.inMilliseconds,
        },
      ),
      headers: headers,
    );
  }

  List<Song> _deduplicate(List<Song> list, Song target) {
    final seen = <String>{};
    final result = <Song>[];
    for (final s in list) {
      if (seen.add(s.globalId)) result.add(s);
    }
    if (!result.any((s) => s.globalId == target.globalId)) {
      result.add(target);
    }
    return result;
  }

  bool _isSameQueue(List<Song> list) {
    if (list.length != _queue.length) return false;
    for (var i = 0; i < list.length; i++) {
      if (list[i].globalId != _queue[i].globalId) return false;
    }
    return true;
  }

  Future<bool> _seekAndPlay(int idx, Song song) async {
    _switching = true; // ★
    try {
      HapticFeedback.mediumImpact();
      state = state.copyWith(
        current: song,
        expanded: true,
        isLoading: true,
        isPlaying: false,
        position: Duration.zero,
        duration: song.duration,
        lyric: const [],
        lyricIndex: -1,
      );
      try {
        await _engine.seekToIndex(idx);
        state = state.copyWith(isLoading: false, isPlaying: true);
        _loadLyricAsync(song);
        _persist();
        return true;
      } catch (e) {
        print('❌ [player] seek 失败: $e');
        state = state.copyWith(isLoading: false, isPlaying: false);
        _reportError(_failReason(song));
        return false;
      }
    } finally {
      _switching = false;
      unawaited(_engine.play());
    }
  }

  Future<bool> _hotInsertQueue(Song song) async {
    _switching = true; // ★
    try {
      print('🔥 [player] 走热插拔逻辑，目标: ${song.title}');
      final resolved = await _resolveOne(song);
      if (resolved == null || resolved.audioPath.isEmpty) {
        _reportError(_failReason(song));
        return false;
      }

      HapticFeedback.mediumImpact();
      state = state.copyWith(
        current: resolved,
        expanded: true,
        isLoading: true,
        isPlaying: false,
        position: Duration.zero,
        duration: resolved.duration,
        lyric: const [],
        lyricIndex: -1,
      );

      final backup = List<Song>.from(_queue);
      _queue.removeWhere((s) => s.globalId == resolved.globalId);
      _queue.insert(0, resolved);
      state = state.copyWith(queue: List.unmodifiable(_queue));

      final ok = await _engine.insertAndPlay(
        source: _singleSource(resolved),
        index: 0,
      );

      if (ok) {
        state = state.copyWith(isLoading: false, isPlaying: true);
        _loadLyricAsync(resolved);
        _persist();
        print('✅ [player] 热插播成功');
        return true;
      } else {
        _queue = backup;
        state = state.copyWith(
          isLoading: false,
          isPlaying: false,
          queue: List.unmodifiable(backup),
        );
        print('❌ [player] 热插播失败，已回滚');
        return false;
      }
    } finally {
      _switching = false;
      unawaited(_engine.play());
    }
  }

  Future<bool> playSong(
    Song song, {
    List<Song>? queue,
    bool fromAutoPlay = false,
  }) async {
    final rawList = queue ?? [song];
    final list = _deduplicate(rawList, song);

    // ★ 立即停掉旧歌，避免旧歌 stream 干扰
    if (_engine.hasSource) {
      await _engine.pause();
    }

    // 判断1：同队列，直接 seek 到目标
    if (_engine.hasSource && _isSameQueue(list)) {
      final idx = _queue.indexWhere((s) => s.globalId == song.globalId);
      if (idx >= 0) {
        print('🎯 [player] 点击当前队列内的歌，直接 seek 到第 $idx 首');
        return await _seekAndPlay(idx, song);
      }
    }

    // 判断2：插队
    if (_engine.hasSource &&
        list.isNotEmpty &&
        list.first.globalId == song.globalId) {
      final currentIds = _queue.map((e) => e.globalId).toSet();
      final overlap = list.where((e) => currentIds.contains(e.globalId)).length;
      if (overlap >= _queue.length - 1) {
        print('🔥 [player] 插队播放，走热插入逻辑');
        final ok = await _hotInsertQueue(song);
        if (ok) return true;
        print('⚠️ [player] 热插入失败，回退到全量重建');
      }
    }

    print('🔒 [player] 构建底层队列: ${song.title}');
    return await _buildNewQueue(list, song, fromAutoPlay: fromAutoPlay);
  }

  Future<bool> _buildNewQueue(
    List<Song> list,
    Song target, {
    bool fromAutoPlay = false,
  }) async {
    _switching = true; // ★
    try {
      HapticFeedback.mediumImpact();

      state = state.copyWith(
        current: target,
        expanded: true,
        isLoading: true,
        isPlaying: false,
        position: Duration.zero,
        duration: target.duration,
        lyric: const [],
        lyricIndex: -1,
        queue: List.unmodifiable(list),
      );

      final validSongs = await _resolveAll(list);

      int initialIndex = -1;
      for (var i = 0; i < validSongs.length; i++) {
        if (validSongs[i].globalId == target.globalId) {
          initialIndex = i;
          break;
        }
      }

      if (initialIndex < 0) {
        print('❌ [player] 当前歌曲解析失败');
        state = state.copyWith(isLoading: false, isPlaying: false);
        if (!fromAutoPlay) _reportError(_failReason(target));
        return false;
      }

      _queue = validSongs;
      state = state.copyWith(queue: List.unmodifiable(validSongs));

      final sources = validSongs.map((s) => _singleSource(s)).toList();

      try {
        await _engine.setPlaylist(
          sources: sources,
          initialIndex: initialIndex,
          initialPosition: Duration.zero,
        );
      } catch (e) {
        print('❌ [player] setAudioSource 失败: $e');
        state = state.copyWith(isLoading: false, isPlaying: false);
        if (!fromAutoPlay) _reportError(_failReason(target));
        return false;
      }

      _applyModeToPlayer(state.mode);

      state = state.copyWith(
        isLoading: false,
        isPlaying: true,
        queue: List.unmodifiable(validSongs),
      );
      HapticFeedback.lightImpact();
      _persist();
      _loadLyricAsync(target);

      print('✅ [player] 全新队列播放已启动');
      return true;
    } finally {
      _switching = false;
      unawaited(_engine.play());
    }
  }

  Future<void> _resumeFromRestore() async {
    final song = state.current;
    if (song == null) return;

    _switching = true; // ★
    try {
      print('🔄 [player] 恢复播放，断点: ${state.position}');
      state = state.copyWith(isLoading: true, isPlaying: false);

      final list = state.queue.isNotEmpty ? state.queue : [song];
      final validSongs = await _resolveAll(list);

      int initialIndex = -1;
      for (var i = 0; i < validSongs.length; i++) {
        if (validSongs[i].globalId == song.globalId) {
          initialIndex = i;
          break;
        }
      }

      if (initialIndex < 0) {
        state = state.copyWith(isLoading: false, isPlaying: false);
        _reportError(_failReason(song));
        return;
      }

      _queue = validSongs;
      state = state.copyWith(queue: List.unmodifiable(validSongs));

      // position clamp 到 [0, duration]
      final maxMs = song.duration.inMilliseconds > 0
          ? song.duration.inMilliseconds
          : state.position.inMilliseconds;
      final safePos = Duration(
        milliseconds: state.position.inMilliseconds.clamp(0, maxMs),
      );

      final sources = validSongs.map((s) => _singleSource(s)).toList();

      try {
        await _engine.setPlaylist(
          sources: sources,
          initialIndex: initialIndex,
          initialPosition: safePos,
        );
      } catch (e) {
        print('❌ [player] resume setAudioSource 失败: $e');
        state = state.copyWith(isLoading: false, isPlaying: false);
        _reportError(_failReason(song));
        return;
      }

      _applyModeToPlayer(state.mode);

      state = state.copyWith(
        isLoading: false,
        isPlaying: true,
        queue: List.unmodifiable(validSongs),
      );
      _loadLyricAsync(song);
    } finally {
      _switching = false;
      unawaited(_engine.play());
    }
  }

  void _loadLyricAsync(Song song) async {
    final reqId = ++_lyricRequestId;

    final cached = await LyricCache.load(song.globalId);
    if (reqId != _lyricRequestId) return;
    if (cached.isNotEmpty) {
      if (state.current?.globalId == song.globalId) {
        state = state.copyWith(lyric: cached);
      }
    }

    final source = ref.read(sourceByIdProvider)(song.source);
    source
        .getLyric(song.id)
        .then((lyric) {
          if (reqId != _lyricRequestId) return;
          if (lyric.isEmpty) return;
          if (state.current?.globalId == song.globalId) {
            state = state.copyWith(lyric: lyric);
          }
          LyricCache.save(song.globalId, lyric);
        })
        .catchError((_) {});
  }

  Future<void> playFromQueue(int idx) async {
    if (idx < 0 || idx >= _queue.length) return;
    if (!_engine.hasSource) {
      await playSong(_queue[idx], queue: _queue);
      return;
    }
    try {
      await _engine.seekToIndex(idx);
      if (!state.isPlaying) unawaited(_engine.play());
    } catch (e) {
      print('⚠️ [player] playFromQueue 异常: $e');
    }
  }

  void removeFromQueue(Song song) {
    final oldIdx = _queue.indexWhere((s) => s.globalId == song.globalId);
    if (oldIdx < 0) return;

    final newQueue = [..._queue]..removeAt(oldIdx);
    _queue = newQueue;

    if (newQueue.isEmpty) {
      _engine.reset();
      _resolvedUrls.clear();
      _cacheTriggeredSongs.clear();
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

    _engine.removeAt(oldIdx).catchError((e) {
      print('⚠️ [player] engine.removeAt 失败: $e');
    });

    state = state.copyWith(queue: List.unmodifiable(newQueue));
    _persist();
  }

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
    if (_queue.isEmpty) return;
    if (!_engine.hasSource) {
      await _resumeFromRestore();
      return;
    }
    try {
      await _engine.next();
      if (!state.isPlaying) unawaited(_engine.play());
    } catch (e) {
      print('⚠️ [player] next 异常: $e');
    }
  }

  Future<void> previous() async {
    if (_queue.isEmpty) return;
    if (!_engine.hasSource) {
      await _resumeFromRestore();
      return;
    }
    try {
      await _engine.previous();
      if (!state.isPlaying) unawaited(_engine.play());
    } catch (e) {
      print('⚠️ [player] previous 异常: $e');
    }
  }

  Future<void> togglePlay() async {
    // 切换中，忽略点击
    if (_switching) {
      print('⚠️ [player] togglePlay 忽略：切换中');
      return;
    }
    if (!_engine.isReady) {
      print('⚠️ [player] togglePlay 忽略：引擎未就绪');
      return;
    }
    if (_engine.isPlaying) {
      await _engine.pause();
      state = state.copyWith(isPlaying: false);
      return;
    }
    if (!_engine.hasSource && state.current != null) {
      await _resumeFromRestore();
      return;
    }
    unawaited(_engine.play());
    state = state.copyWith(isPlaying: true);
  }

  Future<void> seek(Duration pos) async {
    await _engine.seek(pos);
    _persist();
  }
}

final playerStateProvider = NotifierProvider<PlayerNotifier, PlayerState>(
  PlayerNotifier.new,
);
