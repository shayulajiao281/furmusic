import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/auth_store.dart';

class AuthState {
  final String? bilibili;
  final String? netease;
  final String? qq;

  const AuthState({this.bilibili, this.netease, this.qq});

  String? of(String source) {
    switch (source) {
      case 'bilibili':
        return bilibili;
      case 'netease':
        return netease;
      case 'qq':
        return qq;
    }
    return null;
  }

  bool isLoggedIn(String source) => of(source) != null;
}

class AuthNotifier extends Notifier<AuthState> {
  AuthState _load() => AuthState(
    bilibili: AuthStore.getCookie('bilibili'),
    netease: AuthStore.getCookie('netease'),
    qq: AuthStore.getCookie('qq'),
  );

  @override
  AuthState build() => _load();

  Future<void> save(String source, String cookie) async {
    await AuthStore.saveCookie(source, cookie);
    state = _load();
  }

  Future<void> clear(String source) async {
    await AuthStore.clearCookie(source);
    state = _load();
  }
}

final authProvider = NotifierProvider<AuthNotifier, AuthState>(
  AuthNotifier.new,
);
