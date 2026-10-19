import 'dart:async';
import 'package:audio_session/audio_session.dart';
import 'package:just_audio/just_audio.dart';

class AudioEngine {
  final AudioPlayer _player = AudioPlayer();

  bool _hasSource = false;
  bool _isReady = false;

  AudioPlayer get player => _player;
  bool get hasSource => _hasSource;
  bool get isPlaying => _player.playing;
  bool get isReady => _isReady;

  /// 只配置音频会话，不激活
  Future<void> init() async {
    try {
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration.music());
    } catch (e) {
      print('⚠️ [engine] init 异常: $e');
    }
  }

  Future<void> setPlaylist({
    required List<AudioSource> sources,
    required int initialIndex,
    Duration initialPosition = Duration.zero,
  }) async {
    if (sources.isEmpty) return;
    _isReady = false;
    try {
      await _player
          .setAudioSources(
            sources,
            initialIndex: initialIndex.clamp(0, sources.length - 1),
            initialPosition: initialPosition,
          )
          .timeout(const Duration(seconds: 15));
      _hasSource = true;
      _isReady = true;
      print('✅ [engine] setPlaylist 成功 (${sources.length} 首)');
    } catch (e) {
      print('❌ [engine] setPlaylist 失败: $e');
      _hasSource = false;
      _isReady = false;
      rethrow;
    }
  }

  Future<void> seekToIndex(int index) async {
    if (!_hasSource) {
      print('⚠️ [engine] seekToIndex 忽略：无 source');
      return;
    }
    if (index < 0 || index >= _player.effectiveIndices.length) return;
    try {
      await _player
          .seek(Duration.zero, index: index)
          .timeout(const Duration(seconds: 8));
    } catch (e) {
      print('⚠️ [engine] seekToIndex 失败: $e');
    }
  }

  Future<void> removeAt(int index) async {
    if (!_hasSource) return;
    if (index < 0 || index >= _player.effectiveIndices.length) return;
    try {
      await _player.removeAudioSourceAt(index);
    } catch (e) {
      print('❌ [engine] removeAudioSourceAt 失败: $e');
    }
  }

  Future<void> reset() async {
    try {
      await _player.stop().timeout(const Duration(seconds: 3));
    } catch (_) {}
    _hasSource = false;
    _isReady = false;
    print('🔄 [engine] reset 完成');
  }

  Future<bool> insertAndPlay({
    required AudioSource source,
    required int index,
  }) async {
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
  }

  /// 先启动播放，再异步激活会话（不阻塞）
  Future<void> play() async {
    if (!_isReady) {
      print('⚠️ [engine] play 忽略：未就绪');
      return;
    }
    unawaited(_player.play());
    try {
      final session = await AudioSession.instance;
      await session.setActive(true).timeout(const Duration(seconds: 2));
    } catch (e) {
      print('⚠️ [engine] setActive 异常: $e');
    }
  }

  Future<void> pause() async {
    try {
      await _player.pause().timeout(const Duration(seconds: 3));
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

  Future<void> next() async {
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
  }

  Future<void> previous() async {
    if (!_hasSource) return;
    try {
      if (_player.hasPrevious) {
        await _player.seekToPrevious();
        return;
      }
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
  }

  Future<void> dispose() async {
    try {
      await _player.dispose();
    } catch (_) {}
  }
}
