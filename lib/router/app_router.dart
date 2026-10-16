import 'package:go_router/go_router.dart';
import 'package:flutter/cupertino.dart';
import '../layout/main_shell.dart';
import '../pages/music_page.dart';
import '../pages/discover_page.dart';
import '../pages/play_history_page.dart';
import '../pages/profile_page.dart';
import '../pages/player_page.dart';
import '../pages/local_music_page.dart';
import '../pages/account_page.dart';
import '../pages/login_webview_page.dart';

final appRouter = GoRouter(
  initialLocation: '/music',
  routes: [
    StatefulShellRoute.indexedStack(
      builder: (_, __, shell) => MainShell(navigationShell: shell),
      branches: [
        StatefulShellBranch(
          routes: [
            GoRoute(path: '/music', builder: (_, __) => const MusicPage()),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/discover',
              builder: (_, __) => const DiscoverPage(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(path: '/profile', builder: (_, __) => const ProfilePage()),
          ],
        ),
      ],
    ),
    GoRoute(
      path: '/player',
      pageBuilder: (_, __) =>
          const CupertinoPage(fullscreenDialog: true, child: PlayerPage()),
    ),
    GoRoute(path: '/local-music', builder: (_, __) => const LocalMusicPage()),
    GoRoute(path: '/play-history', builder: (_, __) => const PlayHistoryPage()),
    // ★ 账号管理
    GoRoute(path: '/account', builder: (_, __) => const AccountPage()),
    // ★ WebView 登录页
    GoRoute(
      path: '/login-webview',
      builder: (_, state) {
        final args = state.extra as Map<String, dynamic>;
        return LoginWebviewPage(
          source: args['source'] as String,
          title: args['title'] as String,
          loginUrl: args['loginUrl'] as String,
          cookieUrl: args['cookieUrl'] as String,
          requiredCookieKeys: (args['requiredKeys'] as List).cast<String>(),
        );
      },
    ),
  ],
);
