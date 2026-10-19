import 'dart:async';
import 'dart:convert';
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
    current: current ?? this.current,
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

  /// ★ 锁的超时（秒）：超过这个时间自动释放，避免死锁
  static const _lockTimeout = 20;

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
      _loadLyricAsync(song);
      _persist();
    });

    _player.playingStream.listen((p) {
      state = state.copyWith(isPlaying: p);
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

    return _restore();
  }

  // ═══ 锁管理：带超时 ═══
  bool get _isSwitching {
    if (!_switching) return false;
    // 检查是否超时
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
    state = state.copyWith(lastError: msg, errorId: state.errorId + 1);
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

  Future<void> _resetPlayer() async {
    try {
      await _player.stop();
    } catch (_) {}
    _hasSource = false;
    _targetSongId = null;
  }

  String _failReason(Song song) {
    if (song.isVip) {
      return '《${song.title}》需要 VIP 会员，无法播放';
    }
    return '《${song.title}》暂时无法播放（可能是版权限制）';
  }

  // ═══ 播放 ═══
  Future<void> playSong(Song song, {List<Song>? queue}) async {
    // ★ 检查锁（自动超时释放）
    if (_isSwitching) {
      print('⚠️ [player] 正在切歌，忽略本次点击');
      return;
    }
    _lock();
    print('🔒 [player] 加锁，播放 ${song.title}');

    try {
      HapticFeedback.mediumImpact();
      final list = queue ?? [song];
      _targetSongId = song.id;

      // 停掉上一首
      try {
        await _player.stop().timeout(const Duration(seconds: 3));
      } catch (e) {
        print('⚠️ [player] stop 超时/异常: $e');
      }
      _hasSource = false;

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

      // ★ 只解析当前这一首，避免整队列卡住
      print('🔍 [player] 解析 ${song.title} (${song.source})');
      final current = await _resolveOne(song).timeout(
        const Duration(seconds: 20),
        onTimeout: () {
          print('❌ [player] _resolveOne 超时');
          return null;
        },
      );

      if (current == null || current.audioPath.isEmpty) {
        print('❌ [player] 当前歌解析失败');
        await _resetPlayer();
        state = state.copyWith(isLoading: false);
        _reportError(_failReason(song));
        return;
      }

      // 队列里其他歌保留原始信息，不预解析
      _queue = list;
      state = state.copyWith(isLoading: false, queue: List.unmodifiable(list));

      try {
        print(
          '🎵 [player] setAudioSource: ${current.audioPath.substring(0, current.audioPath.length.clamp(0, 60))}...',
        );
        await _player
            .setAudioSource(_toSource(current))
            .timeout(const Duration(seconds: 20));

        _hasSource = true;
        await _player.play();
        HapticFeedback.lightImpact();
        _persist();
        print('✅ [player] 播放成功');
      } catch (e) {
        print('❌ [player] setAudioSource/play 失败: $e');
        await _resetPlayer();
        state = state.copyWith(isLoading: false, isPlaying: false);
        _reportError(_failReason(song));
      }
    } catch (e) {
      print('❌ [player] playSong 异常: $e');
      await _resetPlayer();
      state = state.copyWith(isLoading: false, isPlaying: false);
      _reportError('播放失败: $e');
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

      final current = await _resolveOne(
        song,
      ).timeout(const Duration(seconds: 20), onTimeout: () => null);

      if (current == null || current.audioPath.isEmpty) {
        await _resetPlayer();
        state = state.copyWith(isLoading: false);
        _reportError('《${song.title}》无法恢复播放');
        return;
      }

      _queue = state.queue.isNotEmpty ? state.queue : [song];
      state = state.copyWith(
        isLoading: false,
        queue: List.unmodifiable(_queue),
      );

      try {
        await _player
            .setAudioSource(_toSource(current))
            .timeout(const Duration(seconds: 20));
        _hasSource = true;
        if (resumeAt > Duration.zero) {
          await _player.seek(resumeAt).timeout(const Duration(seconds: 5));
        }
        await _player.play();
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
    final isLocal = s.source == 'local' && !s.audioPath.startsWith('http');
    final source = ref.read(sourceByIdProvider)(s.source);
    final headers = isLocal ? null : source.audioHeaders;

    return AudioSource.uri(
      isLocal ? Uri.file(s.audioPath) : Uri.parse(s.audioPath),
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
      url = await source
          .getSongUrl(song.id)
          .timeout(
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

  Future<void> playFromQueue(int idx) async {
    if (idx < 0 || idx >= _queue.length) return;
    try {
      await _player.seek(Duration.zero, index: idx);
      if (!_player.playing) await _player.play();
      HapticFeedback.mediumImpact();
    } catch (e) {
      print('❌ [player] playFromQueue 失败: $e');
      await _resetPlayer();
      state = state.copyWith(isPlaying: false, isLoading: false);
    }
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
    if (!_hasSource && state.current != null) {
      await _resumeFromRestore();
      return;
    }
    try {
      await _player.play();
    } catch (e) {
      print('❌ [player] togglePlay 失败123: $e');
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
