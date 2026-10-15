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

  /// 覆盖本地歌单（保留已有收藏标记）
  void setSongs(List<Song> newSongs) {
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

  /// ★ 核心：切换收藏（接收完整 Song）
  void toggleFavorite(Song song) {
    final idx = state.songs.indexWhere((s) => s.id == song.id);

    List<Song> newSongs;
    if (idx >= 0) {
      // 已存在 → 切换
      newSongs = state.songs.map((s) {
        if (s.id == song.id) return s.copyWith(isFavorite: !s.isFavorite);
        return s;
      }).toList();
    } else {
      // 不存在 → 加进列表 + 标为收藏
      newSongs = [...state.songs, song.copyWith(isFavorite: true)];
    }

    state = AppState(songs: newSongs, recentPlayedIds: state.recentPlayedIds);
    _persist();
  }

  /// 判断是否已收藏
  bool isFavorite(String songId) {
    final list = state.songs.where((s) => s.id == songId).toList();
    return list.isNotEmpty && list.first.isFavorite;
  }

  void addRecent(String songId) {
    final list = [songId, ...state.recentPlayedIds.where((id) => id != songId)];
    state = AppState(
      songs: state.songs,
      recentPlayedIds: list.take(20).toList(),
    );
    _persist();
  }

  List<Song> get recentSongs {
    final map = {for (final s in state.songs) s.id: s};
    return state.recentPlayedIds
        .map((id) => map[id])
        .whereType<Song>()
        .toList();
  }

  /// ★ 收藏列表
  List<Song> get favoriteSongs =>
      state.songs.where((s) => s.isFavorite).toList();
}

final appStateProvider = NotifierProvider<AppStateNotifier, AppState>(
  AppStateNotifier.new,
);

final allSongsProvider = Provider((ref) => ref.watch(appStateProvider).songs);
