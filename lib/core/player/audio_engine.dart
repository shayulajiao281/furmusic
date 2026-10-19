import 'dart:async';
import 'package:audio_session/audio_session.dart';
import 'package:just_audio/just_audio.dart';

typedef AudioSourceBuilder = AudioSource Function(int index);

class AudioEngine {
  final AudioPlayer _player = AudioPlayer();

  bool _hasSource = false;
  bool _isReady = false;

  /// 串行化队列：所有改变 source / 状态的操作依次执行，防止并发冲突
  Future<void> _pending = Future.value();

  Future<T> _enqueue<T>(Future<T> Function() op) {
    final completer = Completer<T>();
    _pending = _pending.then((_) async {
      try {
        final result = await op();
        if (!completer.isCompleted) completer.complete(result);
      } catch (e, st) {
        if (!completer.isCompleted) completer.completeError(e, st);
      }
    });
    return completer.future;
  }

  AudioPlayer get player => _player;
  bool get hasSource => _hasSource;
  bool get isPlaying => _player.playing;
  bool get isReady => _isReady;

  Stream<PlayerState> get playerStateStream => _player.playerStateStream;

  /// 初始化：配置并激活音频会话
  Future<void> init() async {
    try {
      await _player.setLoopMode(LoopMode.off);
      await _player.setShuffleModeEnabled(false);

      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration.music());
      await session.setActive(true);
    } catch (e) {
      print('⚠️ [engine] init 异常: $e');
    }
  }

  /// 设置完整播放列表（不走 stop()，直接 setAudioSources 会中断上一次播放）
  Future<void> setPlaylist({
    required List<AudioSource> sources,
    required int initialIndex,
    Duration initialPosition = Duration.zero,
  }) {
    return _enqueue(() async {
      if (sources.isEmpty) return;

      _isReady = false;

      try {
        await _player
            .setAudioSources(
              sources,
              initialIndex: initialIndex.clamp(0, sources.length - 1),
              initialPosition: initialPosition,
            )
            .timeout(const Duration(seconds: 12));
        _hasSource = true;
        _isReady = true;
      } catch (e) {
        print('❌ [engine] setAudioSources 失败: $e');
        _hasSource = false;
        _isReady = false;
        rethrow;
      }
    });
  }

  /// 按索引 seek
  Future<void> seekToIndex(int index) {
    return _enqueue(() async {
      if (!_hasSource) return;
      if (index < 0 || index >= _player.effectiveIndices.length) return;
      try {
        await _player
            .seek(Duration.zero, index: index)
            .timeout(const Duration(seconds: 8));
      } catch (e) {
        print('⚠️ [engine] seekToIndex 失败: $e');
      }
    });
  }

  /// 从当前队列移除指定索引
  Future<void> removeAt(int index) {
    return _enqueue(() async {
      if (!_hasSource) return;
      if (index < 0 || index >= _player.effectiveIndices.length) return;
      try {
        await _player.removeAudioSourceAt(index);
      } catch (e) {
        print('❌ [engine] removeAudioSourceAt 失败: $e');
      }
    });
  }

  /// 重置引擎，停止播放并清空底层队列
  Future<void> reset() {
    return _enqueue(() async {
      try {
        await _player.stop().timeout(const Duration(seconds: 3));
      } catch (e) {
        print('⚠️ [engine] reset stop 异常（可忽略）: $e');
      }
      _hasSource = false;
      _isReady = false;
    });
  }

  /// 热插播：插入到当前队列并播放
  Future<bool> insertAndPlay({
    required AudioSource source,
    required int index,
  }) {
    return _enqueue(() async {
      if (!_hasSource) return false;
      try {
        await _player.insertAudioSource(index, source);
        await _player
            .seek(Duration.zero, index: index)
            .timeout(const Duration(seconds: 8));
        unawaited(play());
        return true;
      } catch (e) {
        print('❌ [engine] insertAndPlay 失败: $e');
        return false;
      }
    });
  }

  /// ★ 修复点：play() 不 await，不超时
  ///   _player.play() 的 Future 只在暂停/播完时 complete，播放中是长时间 pending
  ///   用 unawaited 避免误报 "TimeoutException"
  Future<void> play() async {
    if (!_isReady) {
      print('⚠️ [engine] play() 被忽略：未就绪');
      return;
    }

    // 会话激活：加 2 秒超时兜底，失败也继续尝试播
    try {
      final session = await AudioSession.instance;
      await session.setActive(true).timeout(const Duration(seconds: 2));
    } catch (e) {
      print('⚠️ [engine] setActive 超时或异常（继续尝试播放）: $e');
    }

    // ★ 不 await、不 timeout，play() 的 Future 本来就长时间 pending
    unawaited(_player.play());
  }

  Future<void> pause() async {
    try {
      await _player.pause();
    } catch (e) {
      print('⚠️ [engine] pause 异常: $e');
    }
  }

  Future<void> seek(Duration pos) async {
    try {
      await _player.seek(pos).timeout(const Duration(seconds: 8));
    } catch (e) {
      print('⚠️ [engine] seek 异常: $e');
    }
  }

  Future<void> next() {
    return _enqueue(() async {
      if (!_hasSource) return;
      try {
        if (_player.hasNext) {
          await _player.seekToNext();
        } else {
          await _player.seek(Duration.zero, index: 0);
        }
      } catch (e) {
        print('⚠️ [engine] next 异常: $e');
      }
    });
  }

  Future<void> previous() {
    return _enqueue(() async {
      if (!_hasSource) return;
      try {
        if (_player.hasPrevious) {
          await _player.seekToPrevious();
          return;
        }
        // shuffle 下 hasPrevious=false 表示打乱顺序里已是第一首，
        // 跳物理末尾会破坏打乱顺序，直接回到开头
        if (_player.shuffleModeEnabled) {
          await _player.seek(Duration.zero, index: 0);
          return;
        }
        final len = _player.effectiveIndices.length;
        if (len > 0) {
          await _player.seek(Duration.zero, index: len - 1);
        } else {
          await _player.seek(Duration.zero, index: 0);
        }
      } catch (e) {
        print('⚠️ [engine] previous 异常: $e');
      }
    });
  }

  Future<void> dispose() async {
    try {
      await _player.dispose();
    } catch (_) {}
  }
}
