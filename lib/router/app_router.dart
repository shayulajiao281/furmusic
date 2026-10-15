import 'package:go_router/go_router.dart';
import 'package:flutter/cupertino.dart';
import '../layout/main_shell.dart';
import '../pages/music_page.dart';
import '../pages/discover_page.dart';
import '../pages/profile_page.dart';
import '../pages/player_page.dart';

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
    // 全屏播放页（从底部滑出）
    GoRoute(
      path: '/player',
      pageBuilder: (_, __) =>
          const CupertinoPage(fullscreenDialog: true, child: PlayerPage()),
    ),
  ],
);
