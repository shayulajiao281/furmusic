import 'dart:async';
import 'package:just_audio/just_audio.dart';

typedef AudioSourceBuilder = AudioSource Function(int index);

class AudioEngine {
  final AudioPlayer _player = AudioPlayer();

  bool _hasSource = false;
  bool _isReady = false;

  /// ★ 串行化队列：所有改变 source / 状态的操作依次执行，防止并发冲突
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

  Future<void> init() async {
    try {
      await _player.setLoopMode(LoopMode.off);
      await _player.setShuffleModeEnabled(false);
    } catch (e) {
      print('⚠️ [engine] init 异常: $e');
    }
  }

  /// 设置完整播放列表
  /// ★ 关键改动：不再调用 stop()，直接 setAudioSource 会自己中断上一次播放
  /// ★ 走队列串行化，避免多个 setPlaylist 并发
  Future<void> setPlaylist({
    required List<AudioSource> sources,
    required int initialIndex,
    Duration initialPosition = Duration.zero,
  }) {
    return _enqueue(() async {
      if (sources.isEmpty) return;

      _isReady = false;

      final concat = ConcatenatingAudioSource(children: sources);

      try {
        await _player
            .setAudioSource(
              concat,
              initialIndex: initialIndex.clamp(0, sources.length - 1),
              initialPosition: initialPosition,
            )
            .timeout(const Duration(seconds: 30));
        _hasSource = true;
        _isReady = true;
      } catch (e) {
        print('❌ [engine] setPlaylist 失败: $e');
        _hasSource = false;
        _isReady = false;
        rethrow;
      }
    });
  }

  Future<void> seekToIndex(int index) {
    return _enqueue(() async {
      if (!_hasSource) return;
      final source = _player.audioSource;
      if (source is! ConcatenatingAudioSource) return;
      if (index < 0 || index >= source.children.length) return;
      try {
        await _player
            .seek(Duration.zero, index: index)
            .timeout(const Duration(seconds: 10));
      } catch (e) {
        print('⚠️ [engine] seekToIndex 失败: $e');
      }
    });
  }

  Future<void> removeAt(int index) {
    return _enqueue(() async {
      if (!_hasSource) return;
      final source = _player.audioSource;
      if (source is! ConcatenatingAudioSource) return;
      if (index < 0 || index >= source.children.length) return;
      try {
        await source.removeAt(index);
      } catch (e) {
        print('❌ [engine] removeAt 失败: $e');
      }
    });
  }

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

  Future<bool> insertAndPlay({
    required AudioSource source,
    required int index,
  }) {
    return _enqueue(() async {
      if (!_hasSource) return false;
      final concat = _player.audioSource;
      if (concat is! ConcatenatingAudioSource) return false;
      try {
        await concat.insert(index, source);
        await _player
            .seek(Duration.zero, index: index)
            .timeout(const Duration(seconds: 10));
        // ★ play() 不阻塞队列，内部有超时兜底
        unawaited(play());
        return true;
      } catch (e) {
        print('❌ [engine] insertAndPlay 失败: $e');
        return false;
      }
    });
  }

  /// ★ play 不走队列：它在 iOS 上可能挂住，一旦进队列会阻塞后续所有操作
  ///   内部超时兜底，即使底层挂住也不会让上层 Future 永久 pending
  Future<void> play() async {
    if (!_isReady) {
      print('⚠️ [engine] play() 被忽略：未就绪');
      return;
    }
    try {
      await _player.play().timeout(const Duration(seconds: 5));
    } catch (e) {
      print('⚠️ [engine] play() 超时或异常: $e');
    }
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
      await _player.seek(pos).timeout(const Duration(seconds: 10));
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
        final source = _player.audioSource;
        if (source is ConcatenatingAudioSource && source.children.isNotEmpty) {
          await _player.seek(Duration.zero, index: source.children.length - 1);
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
