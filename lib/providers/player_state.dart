import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/song.dart';
import 'app_state.dart';
import 'music_sources.dart';
import '../services/audio_cache.dart';
import '../services/lyric_cache.dart';

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
  ConcatenatingAudioSource? _concatSource;
  late final SharedPreferences _prefs;
  bool _hasSource = false;
  bool _switching = false;
  DateTime? _switchLockTime;

  // ★ 缓存 URL 和已触发下载的标记
  final Map<String, String> _resolvedUrls = {};
  final Set<String> _cacheTriggeredSongs = {};

  static const _lockTimeout = 20;

  @override
  PlayerState build() {
    _prefs = ref.read(sharedPrefsProvider);

    _player.setLoopMode(LoopMode.off);
    _player.setShuffleModeEnabled(false);

    _player.currentIndexStream.listen((idx) {
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
      print('🎵 [player] 队列切换到第 $idx 首: ${song.title}');
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

      // ★ 核心机制：只要播放进度大于 0，说明第一帧声音已经出来了，立刻触发后台缓存
      if (pos > Duration.zero) {
        final song = state.current;
        if (song != null) {
          _triggerCacheIfNeeded(song);
        }
      }
    });

    _player.durationStream.listen((d) {
      if (d != null && d > Duration.zero) {
        _lastKnownDuration = d;
        state = state.copyWith(duration: d);
      }
    });

    _player.playbackEventStream.listen((event) {}, onError: (Object e, StackTrace st) {
      print('❌ [player] 播放发生错误: $e');
      if (state.isLoading) {
        _reportError('当前歌曲无法播放，可能音源失效');
      }
    });

    return _restore();
  }

  // ★ 播放启动后触发的缓存
  Future<void> _triggerCacheIfNeeded(Song song) async {
    if (song.source == 'local') return;
    if (_cacheTriggeredSongs.contains(song.globalId)) return;

    final cached = await AudioCache.get(song.globalId);
    if (cached != null) {
      _cacheTriggeredSongs.add(song.globalId);
      return;
    }
    if (AudioCache.isDownloading(song.globalId)) {
      _cacheTriggeredSongs.add(song.globalId);
      return;
    }

    final url = _resolvedUrls[song.globalId];
    if (url == null || !url.startsWith('http')) return;

    _cacheTriggeredSongs.add(song.globalId);
    
    final source = ref.read(sourceByIdProvider)(song.source);
    print('📥 [cache] 播放已启动，立刻触发后台缓存: ${song.title}');
    AudioCache.download(
      song.globalId,
      url,
      headers: source.audioHeaders,
    ).then((_) => AudioCache.trim()).catchError((_) {});
  }

  bool get _isSwitching {
    if (!_switching) return false;
    if (_switchLockTime != null) {
      final elapsed = DateTime.now().difference(_switchLockTime!);
      if (elapsed.inSeconds > _lockTimeout) {
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

  Future<void> _forceStop() async {
    try {
      await _player.stop().timeout(const Duration(seconds: 2));
    } catch (e) {
      try {
        await _player.pause().timeout(const Duration(seconds: 1));
        await _player.stop().timeout(const Duration(seconds: 1));
      } catch (_) {}
    }
    _hasSource = false;
  }

  Future<void> _resetPlayer() async {
    await _forceStop();
    _concatSource = null;
  }

  String _failReason(Song song) {
    if (song.isVip) return '《${song.title}》需要 VIP 会员';
    return '《${song.title}》暂时无法播放';
  }

  Future<Song?> _resolveOne(Song song) async {
    if (song.source == 'local') return song;

    // 1. 查本地缓存
    final cached = await AudioCache.get(song.globalId);
    if (cached != null) {
      return song.copyWith(audioPath: cached);
    }

    // 2. 如果之前已经解析过，直接返回
    if (_resolvedUrls.containsKey(song.globalId)) {
      return song.copyWith(audioPath: _resolvedUrls[song.globalId]);
    }

    // 3. 解析网络 URL
    String? url = song.audioPath;
    if (url.isEmpty || !url.startsWith('http')) {
      final source = ref.read(sourceByIdProvider)(song.source);
      url = await source.getSongUrl(song.id).timeout(
        const Duration(seconds: 15),
        onTimeout: () => null,
      );
    }

    if (url == null || url.isEmpty) return null;

    // 4. 记录 URL，供 positionStream 触发缓存时直接使用
    _resolvedUrls[song.globalId] = url;

    return song.copyWith(audioPath: url);
  }

  AudioSource _buildAudioSource(Song s) {
    return _LazyAudioSource(s, this, ref);
  }

  Future<bool> playSong(
    Song song, {
    List<Song>? queue,
    bool fromAutoPlay = false,
  }) async {
    if (_isSwitching) return false;
    _lock();
    print('🔒 [player] 开始播放 ${song.title}');

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

      await _forceStop();

      final initialIndex = list.indexWhere((s) => s.globalId == song.globalId);
      final sources = list.map((s) => _buildAudioSource(s)).toList();

      final concat = ConcatenatingAudioSource(
        children: sources,
        useLazyPreparation: true, 
      );
      _concatSource = concat;

      try {
        await _player
            .setAudioSource(
              concat,
              initialIndex: initialIndex,
              initialPosition: Duration.zero,
            )
            .timeout(const Duration(seconds: 30));
        _hasSource = true;
      } catch (e) {
        print('❌ [player] setAudioSource 失败: $e');
        await _resetPlayer();
        state = state.copyWith(isLoading: false, isPlaying: false);
        if (!fromAutoPlay) _reportError(_failReason(song));
        return false;
      }

      _applyModeToPlayer(state.mode);

      unawaited(_player.play());
      state = state.copyWith(
        isLoading: false,
        isPlaying: true,
        queue: List.unmodifiable(list),
      );
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
    }
  }

  Future<void> _resumeFromRestore() async {
    final song = state.current;
    if (song == null) return;
    if (_isSwitching) return;
    _lock();

    try {
      final resumeAt = state.position;
      state = state.copyWith(isLoading: true);

      final list = state.queue.isNotEmpty ? state.queue : [song];
      _queue = list;

      final initialIndex = list.indexWhere((s) => s.globalId == song.globalId);
      final sources = list.map((s) => _buildAudioSource(s)).toList();

      final concat = ConcatenatingAudioSource(
        children: sources,
        useLazyPreparation: true,
      );
      _concatSource = concat;

      try {
        await _player
            .setAudioSource(
              concat,
              initialIndex: initialIndex < 0 ? 0 : initialIndex,
              initialPosition: resumeAt,
            )
            .timeout(const Duration(seconds: 30));
        _hasSource = true;
      } catch (e) {
        print('❌ [player] resume setAudioSource 失败: $e');
        await _resetPlayer();
        state = state.copyWith(isLoading: false, isPlaying: false);
        _reportError(_failReason(song));
        return;
      }

      _applyModeToPlayer(state.mode);
      unawaited(_player.play());
      state = state.copyWith(
        isLoading: false,
        isPlaying: true,
        queue: List.unmodifiable(list),
      );
      _loadLyricAsync(song);
    } catch (e) {
      print('❌ [player] resume 异常: $e');
      await _resetPlayer();
      state = state.copyWith(isLoading: false, isPlaying: false);
      _reportError(_failReason(song));
    } finally {
      _unlock();
    }
  }

  void _loadLyricAsync(Song song) async {
    final cached = await LyricCache.load(song.globalId);
    if (cached.isNotEmpty) {
      if (state.current?.globalId == song.globalId) {
        state = state.copyWith(lyric: cached);
      }
    }

    final source = ref.read(sourceByIdProvider)(song.source);
    source
        .getLyric(song.id)
        .then((lyric) {
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
    if (!_hasSource) {
      await playSong(_queue[idx], queue: _queue);
      return;
    }
    try {
      await _player.seek(Duration.zero, index: idx);
      if (!state.isPlaying) unawaited(_player.play());
    } catch (e) {
      print('⚠️ [player] playFromQueue 异常: $e');
    }
  }

  void removeFromQueue(Song song) {
    final oldIdx = _queue.indexWhere((s) => s.globalId == song.globalId);
    if (oldIdx < 0) return;

    final isCurrent = state.current?.globalId == song.globalId;
    final newQueue = [..._queue]..removeAt(oldIdx);
    _queue = newQueue;

    if (newQueue.isEmpty) {
      _forceStop();
      _concatSource = null;
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

    final concat = _concatSource;
    if (concat != null) {
      concat.removeAt(oldIdx).catchError((e) {
        print('⚠️ [player] concat.removeAt 失败: $e');
      });
    }

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
    if (!_hasSource) {
      await _resumeFromRestore();
      if (!_hasSource) return;
    }
    try {
      if (_queue.length == 1) {
        await _player.seek(Duration.zero, index: 0);
      } else if (_player.hasNext) {
        await _player.seekToNext();
      } else {
        await _player.seek(Duration.zero, index: 0);
      }
      if (!state.isPlaying) unawaited(_player.play());
    } catch (e) {
      print('⚠️ [player] next 异常: $e');
    }
  }

  Future<void> previous() async {
    if (_queue.isEmpty) return;
    if (!_hasSource) {
      await _resumeFromRestore();
      if (!_hasSource) return;
    }
    try {
      if (_queue.length == 1) {
        await _player.seek(Duration.zero, index: 0);
      } else if (_player.hasPrevious) {
        await _player.seekToPrevious();
      } else {
        await _player.seek(Duration.zero, index: _queue.length - 1);
      }
      if (!state.isPlaying) unawaited(_player.play());
    } catch (e) {
      print('⚠️ [player] previous 异常: $e');
    }
  }

  Future<void> togglePlay() async {
    if (state.isPlaying) {
      try {
        await _player.pause().timeout(const Duration(seconds: 3));
      } catch (_) {}
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

class _LazyAudioSource extends StreamAudioSource {
  final Song song;
  final PlayerNotifier notifier;
  final Ref ref;

  _LazyAudioSource(this.song, this.notifier, this.ref)
      : super(
          tag: MediaItem(
            id: song.globalId,
            title: song.title,
            artist: song.artist,
            album: song.album,
            duration: song.duration,
            artUri: song.coverPath.isNotEmpty ? Uri.tryParse(song.coverPath) : null,
            extras: {
              'source': song.source,
              'duration': song.duration.inMilliseconds,
            },
          ),
        );

  @override
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    final cachedPath = await AudioCache.get(song.globalId);
    if (cachedPath != null) {
      print('⚡ [LazyAudioSource] 命中本地缓存: ${song.title}');
      return _fileStream(cachedPath, start, end);
    }

    final resolved = await notifier._resolveOne(song);
    if (resolved == null || resolved.audioPath.isEmpty) {
      throw Exception('无法解析音频链接');
    }

    final path = resolved.audioPath;
    final source = ref.read(sourceByIdProvider)(song.source);

    print('🌐 [LazyAudioSource] 走网络流播放: ${song.title}');
    return _networkStream(path, source.audioHeaders, start, end);
  }

  StreamAudioResponse _fileStream(String path, int? start, int? end) {
    final file = File(path);
    final length = file.lengthSync();
    return StreamAudioResponse(
      sourceLength: length,
      contentLength: (end ?? length) - (start ?? 0),
      offset: start ?? 0,
      stream: file.openRead(start ?? 0, end),
      contentType: 'audio/mpeg',
    );
  }

  Future<StreamAudioResponse> _networkStream(
      String url, Map<String, String> headers, int? start, int? end) async {
    final client = http.Client();
    final request = http.Request('GET', Uri.parse(url));
    request.headers.addAll(headers);
    
    // 只有当明确要求拖动进度时，才发送 Range 头
    if (start != null && start > 0) {
      final s = start;
      final e = end != null ? '-$end' : '-';
      request.headers['Range'] = 'bytes=$s$e';
    }

    final response = await client.send(request);
    
    // 如果服务器返回 200，说明不支持 Range 或者直接返回了全量流
    if (response.statusCode == 200) {
      return StreamAudioResponse(
        sourceLength: response.contentLength,
        contentLength: response.contentLength,
        offset: 0, // 返回全量，强制 offset 为 0，避免 iOS 解析错乱
        stream: response.stream,
        contentType: response.headers['content-type'] ?? 'audio/mp4', // B站大多为 m4a
      );
    }
    
    // 处理标准的 206 Partial Content
    int sourceLength = response.contentLength ?? 0;
    final contentRange = response.headers['content-range']; // bytes 0-1234/5678
    if (contentRange != null && contentRange.contains('/')) {
      sourceLength = int.tryParse(contentRange.split('/').last) ?? 0;
    }

    return StreamAudioResponse(
      sourceLength: sourceLength,
      contentLength: response.contentLength,
      offset: start ?? 0,
      stream: response.stream,
      contentType: response.headers['content-type'] ?? 'audio/mp4',
    );
  }
}