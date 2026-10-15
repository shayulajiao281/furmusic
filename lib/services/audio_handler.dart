import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';

class MusicHandler extends BaseAudioHandler with SeekHandler {
  final AudioPlayer _player = AudioPlayer();

  MusicHandler() {
    _player.playbackEventStream.listen(_broadcastState);
    _player.processingStateStream.listen((state) {
      if (state == ProcessingState.completed) skipToNext();
    });
  }

  AudioPlayer get player => _player;

  void _broadcastState(PlaybackEvent event) {
    playbackState.add(
      playbackState.value.copyWith(
        controls: [
          MediaControl.skipToPrevious,
          if (_player.playing) MediaControl.pause else MediaControl.play,
          MediaControl.skipToNext,
        ],
        processingState: {
          ProcessingState.idle: AudioProcessingState.idle,
          ProcessingState.loading: AudioProcessingState.loading,
          ProcessingState.buffering: AudioProcessingState.buffering,
          ProcessingState.ready: AudioProcessingState.ready,
          ProcessingState.completed: AudioProcessingState.completed,
        }[_player.processingState]!,
        playing: _player.playing,
        updatePosition: _player.position,
        bufferedPosition: _player.bufferedPosition,
      ),
    );
  }

  Future<void> loadQueue(List<MediaItem> items, int startIndex) async {
    queue.add(items);
    await _player.setAudioSources(
      items
          .map(
            (item) => AudioSource.uri(
              Uri.parse(item.extras?['audioPath'] as String? ?? item.id),
              tag: item,
            ),
          )
          .toList(),
      initialIndex: startIndex,
    );
    mediaItem.add(items[startIndex]);
  }

  @override
  Future<void> play() => _player.play();
  @override
  Future<void> pause() => _player.pause();
  @override
  Future<void> seek(Duration position) => _player.seek(position);
  @override
  Future<void> skipToNext() async {
    if (_player.hasNext) {
      await _player.seekToNext();
      final idx = _player.currentIndex ?? 0;
      if (idx < queue.value.length) mediaItem.add(queue.value[idx]);
    }
  }

  @override
  Future<void> skipToPrevious() async {
    if (_player.hasPrevious) {
      await _player.seekToPrevious();
      final idx = _player.currentIndex ?? 0;
      if (idx < queue.value.length) mediaItem.add(queue.value[idx]);
    }
  }
}

late MusicHandler musicHandler;
