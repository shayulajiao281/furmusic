import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/song.dart';

const _kStorageKey = 'furkid_music_v2';
const _kHideVipKey = 'furkid_hide_vip';

final sharedPrefsProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError('必须在 main.dart 里 override');
});

class AppState {
  final List<Song> localSongs;
  final List<Song> favoriteSongs;
  final List<Song> recentSongs;

  /// ★ 是否隐藏 VIP 歌曲
  final bool hideVip;

  AppState({
    List<Song>? localSongs,
    List<Song>? favoriteSongs,
    List<Song>? recentSongs,
    this.hideVip = false,
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

  AppState copyWith({
    List<Song>? localSongs,
    List<Song>? favoriteSongs,
    List<Song>? recentSongs,
    bool? hideVip,
  }) => AppState(
    localSongs: localSongs ?? this.localSongs,
    favoriteSongs: favoriteSongs ?? this.favoriteSongs,
    recentSongs: recentSongs ?? this.recentSongs,
    hideVip: hideVip ?? this.hideVip,
  );
}

class AppStateNotifier extends Notifier<AppState> {
  late final SharedPreferences _prefs;

  @override
  AppState build() {
    _prefs = ref.read(sharedPrefsProvider);

    // 读 hideVip 开关（独立 key，不进 json）
    final hideVip = _prefs.getBool(_kHideVipKey) ?? false;

    final raw = _prefs.getString(_kStorageKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        final parsed = AppState.fromJson(jsonDecode(raw));
        return parsed.copyWith(hideVip: hideVip);
      } catch (_) {}
    }
    return AppState(hideVip: hideVip);
  }

  void _persist() => _prefs.setString(_kStorageKey, jsonEncode(state.toJson()));

  /// ★ 切换"隐藏 VIP"
  void setHideVip(bool value) {
    _prefs.setBool(_kHideVipKey, value);
    state = state.copyWith(hideVip: value);
  }

  void setLocalSongs(List<Song> newSongs) {
    state = state.copyWith(localSongs: newSongs);
    _persist();
  }

  void toggleFavorite(Song song) {
    final exists = state.favoriteSongs.any((s) => s.globalId == song.globalId);

    List<Song> newFavs;
    if (exists) {
      newFavs = state.favoriteSongs
          .where((s) => s.globalId != song.globalId)
          .toList();
    } else {
      newFavs = [...state.favoriteSongs, song.copyWith(isFavorite: true)];
    }

    state = state.copyWith(favoriteSongs: newFavs);
    _persist();
  }

  void addRecent(Song song) {
    final list = [
      song,
      ...state.recentSongs.where((s) => s.globalId != song.globalId),
    ];
    state = state.copyWith(recentSongs: list.take(100).toList());
    _persist();
  }

  void clearRecent() {
    state = state.copyWith(recentSongs: []);
    _persist();
  }

  bool isFavorite(String globalId) =>
      state.favoriteSongs.any((s) => s.globalId == globalId);
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

/// ★ 全局读取：是否隐藏 VIP
final hideVipProvider = Provider<bool>(
  (ref) => ref.watch(appStateProvider).hideVip,
);
