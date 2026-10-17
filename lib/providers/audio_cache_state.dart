import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/audio_cache.dart';

/// 订阅某首歌的缓存进度（0.0~1.0），已缓存立即返回 1.0
final audioCacheProgressProvider =
    StreamProvider.autoDispose.family<double, String>(
  (ref, songId) => AudioCache.watchProgress(songId),
);