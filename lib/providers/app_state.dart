import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/song.dart';

const _kStorageKey = 'furkid_music_v2';

final sharedPrefsProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError('必须在 main.dart 里 override');
});

class AppState {
  final List<Song> localSongs;
  final List<Song> favoriteSongs;
  final List<Song> recentSongs;

  AppState({
    List<Song>? localSongs,
    List<Song>? favoriteSongs,
    List<Song>? recentSongs,
  }) : localSongs = localSongs ?? [],
       favoriteSongs = favoriteSongs ?? [],
       recentSongs = recentSongs ?? [];

  Map<String, dynamic> toJson() => {
    'local': localSongs.map((e) => e.toJson()).toList(),
    'favorites': favoriteSongs.map((e) => e.toJson()).toList(),
    'recent': recentSongs.map((e) => e.toJson()).toList(),
  };

  factory AppState.fromJson(Map<String, dynamic> j) => AppState(
    localSongs: (j['local'] as List? ?? [])
        .map((e) => Song.fromJson(e as Map<String, dynamic>))
        .toList(),
    favoriteSongs: (j['favorites'] as List? ?? [])
        .map((e) => Song.fromJson(e as Map<String, dynamic>))
        .toList(),
    recentSongs: (j['recent'] as List? ?? [])
        .map((e) => Song.fromJson(e as Map<String, dynamic>))
        .toList(),
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

  /// 覆盖本地音乐（不动收藏和最近）
  void setLocalSongs(List<Song> newSongs) {
    state = AppState(
      localSongs: newSongs,
      favoriteSongs: state.favoriteSongs,
      recentSongs: state.recentSongs,
    );
    _persist();
  }

  /// 切换收藏
  void toggleFavorite(Song song) {
    final exists = state.favoriteSongs.any((s) => s.id == song.id);

    List<Song> newFavs;
    if (exists) {
      newFavs = state.favoriteSongs.where((s) => s.id != song.id).toList();
    } else {
      newFavs = [...state.favoriteSongs, song.copyWith(isFavorite: true)];
    }

    state = AppState(
      localSongs: state.localSongs,
      favoriteSongs: newFavs,
      recentSongs: state.recentSongs,
    );
    _persist();
  }

  /// 记录播放
  void addRecent(Song song) {
    final list = [song, ...state.recentSongs.where((s) => s.id != song.id)];
    state = AppState(
      localSongs: state.localSongs,
      favoriteSongs: state.favoriteSongs,
      recentSongs: list.take(30).toList(),
    );
    _persist();
  }

  bool isFavorite(String songId) =>
      state.favoriteSongs.any((s) => s.id == songId);
}

final appStateProvider = NotifierProvider<AppStateNotifier, AppState>(
  AppStateNotifier.new,
);

final localSongsProvider = Provider(
  (ref) => ref.watch(appStateProvider).localSongs,
);
final favoriteSongsProvider = Provider(
  (ref) => ref.watch(appStateProvider).favoriteSongs,
);
final recentSongsProvider = Provider(
  (ref) => ref.watch(appStateProvider).recentSongs,
);
