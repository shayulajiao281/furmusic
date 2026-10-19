import 'dart:async';
import 'package:audio_session/audio_session.dart';
import 'package:just_audio/just_audio.dart';

typedef AudioSourceBuilder = AudioSource Function(int index);

class AudioEngine {
  final AudioPlayer _player = AudioPlayer();

  bool _hasSource = false;
  bool _isReady = false;

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

  /// ★ 迁移：使用 player.setAudioSources 替代 ConcatenatingAudioSource
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
            .timeout(const Duration(seconds: 30));
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

  /// 按索引 seek（不变）
  Future<void> seekToIndex(int index) {
    return _enqueue(() async {
      if (!_hasSource) return;
      if (index < 0 || index >= _player.effectiveIndices.length) return;
      try {
        await _player
            .seek(Duration.zero, index: index)
            .timeout(const Duration(seconds: 10));
      } catch (e) {
        print('⚠️ [engine] seekToIndex 失败: $e');
      }
    });
  }

  /// ★ 迁移：使用 player.removeAudioSourceAt 替代 source.removeAt
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

  /// 重置引擎（不变）
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

  /// ★ 迁移：使用 player.insertAudioSource 替代 concat.insert
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
            .timeout(const Duration(seconds: 10));
        unawaited(play());
        return true;
      } catch (e) {
        print('❌ [engine] insertAndPlay 失败: $e');
        return false;
      }
    });
  }

  /// play 前再次激活音频会话（不变）
  Future<void> play() async {
    if (!_isReady) {
      print('⚠️ [engine] play() 被忽略：未就绪');
      return;
    }
    try {
      final session = await AudioSession.instance;
      await session.setActive(true);
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
