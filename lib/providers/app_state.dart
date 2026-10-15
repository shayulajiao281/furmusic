import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/song.dart';

const _kStorageKey = 'furkid_music_v1';

final sharedPrefsProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError('必须在 main.dart 里 override');
});

class AppState {
  final List<Song> songs;
  final List<String> recentPlayedIds;

  AppState({List<Song>? songs, List<String>? recentPlayedIds})
    : songs = songs ?? [],
      recentPlayedIds = recentPlayedIds ?? [];

  Map<String, dynamic> toJson() => {
    'songs': songs.map((e) => e.toJson()).toList(),
    'recent': recentPlayedIds,
  };

  factory AppState.fromJson(Map<String, dynamic> j) => AppState(
    songs: (j['songs'] as List? ?? [])
        .map((e) => Song.fromJson(e as Map<String, dynamic>))
        .toList(),
    recentPlayedIds: (j['recent'] as List? ?? []).cast<String>().toList(),
  );
}

class AppStateNotifier extends Notifier<AppState> {
  late final SharedPreferences _prefs;

  @override
  AppState build() {
    _prefs = ref.read(sharedPrefsProvider);
    final raw = _prefs.getString(_kStorageKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        return AppState.fromJson(jsonDecode(raw));
      } catch (_) {}
    }
    return AppState();
  }

  void _persist() => _prefs.setString(_kStorageKey, jsonEncode(state.toJson()));

  /// 覆盖歌曲列表（从本地扫描）
  void setSongs(List<Song> newSongs) {
    // 保留原有收藏状态
    final favIds = state.songs
        .where((s) => s.isFavorite)
        .map((s) => s.id)
        .toSet();
    final merged = newSongs.map((s) {
      if (favIds.contains(s.id)) return s.copyWith(isFavorite: true);
      return s;
    }).toList();

    state = AppState(songs: merged, recentPlayedIds: state.recentPlayedIds);
    _persist();
  }

  /// 切换收藏
  void toggleFavorite(String songId) {
    final newSongs = state.songs.map((s) {
      if (s.id == songId) return s.copyWith(isFavorite: !s.isFavorite);
      return s;
    }).toList();
    state = AppState(songs: newSongs, recentPlayedIds: state.recentPlayedIds);
    _persist();
  }

  /// 记录播放
  void addRecent(String songId) {
    final list = [songId, ...state.recentPlayedIds.where((id) => id != songId)];
    state = AppState(
      songs: state.songs,
      recentPlayedIds: list.take(20).toList(),
    );
    _persist();
  }

  /// 最近播放的歌曲
  List<Song> get recentSongs {
    final map = {for (final s in state.songs) s.id: s};
    return state.recentPlayedIds
        .map((id) => map[id])
        .whereType<Song>()
        .toList();
  }

  /// 收藏的歌曲
  List<Song> get favoriteSongs =>
      state.songs.where((s) => s.isFavorite).toList();
}

final appStateProvider = NotifierProvider<AppStateNotifier, AppState>(
  AppStateNotifier.new,
);

final allSongsProvider = Provider((ref) => ref.watch(appStateProvider).songs);
