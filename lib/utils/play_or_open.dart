import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../models/song.dart';
import '../providers/app_state.dart';
import '../providers/player_state.dart';

/// 统一的"点击歌曲"行为：
/// - 点的是当前正在播放的歌 → 打开播放页
/// - appendToQueue=true（发现页）→ 插到队列最前面
/// - 其他 → 整体替换队列
void playOrOpen(
  BuildContext context,
  WidgetRef ref,
  Song song, {
  List<Song>? queue,
  bool appendToQueue = false,
}) {
  final player = ref.read(playerStateProvider);

  // 当前播放这首 → 打开播放页
  if (player.current?.globalId == song.globalId) {
    print('🎵 [playOrOpen] 点击当前歌，进播放页');
    context.push('/player');
    return;
  }

  final playerNotifier = ref.read(playerStateProvider.notifier);
  final appNotifier = ref.read(appStateProvider.notifier);

  if (appendToQueue) {
    // 发现页：插到当前队列最前面
    final currentQueue = player.queue;
    final newQueue = [...currentQueue];

    // 如果已经在队列里，先移除再插到最前
    newQueue.removeWhere((s) => s.globalId == song.globalId);

    // 插到最前面
    newQueue.insert(0, song);

    print('➕ [playOrOpen] 插到队列最前，当前 ${newQueue.length} 首');
    playerNotifier.playSong(song, queue: newQueue);
  } else {
    // 其他页面：整体替换
    playerNotifier.playSong(song, queue: queue ?? [song]);
  }
  appNotifier.addRecent(song);
}