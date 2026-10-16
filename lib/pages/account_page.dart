import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/auth_state.dart';
import '../theme/app_colors.dart';

class _Platform {
  final String id;
  final String name;
  final IconData icon;
  final Color color;
  final String loginUrl;
  final String cookieUrl;
  final List<String> requiredKeys;
  const _Platform({
    required this.id,
    required this.name,
    required this.icon,
    required this.color,
    required this.loginUrl,
    required this.cookieUrl,
    required this.requiredKeys,
  });
}

const _platforms = [
  _Platform(
    id: 'bilibili',
    name: 'B站',
    icon: CupertinoIcons.play_circle_fill,
    color: Color(0xFFFB7299),
    loginUrl: 'https://passport.bilibili.com/login',
    cookieUrl: 'https://www.bilibili.com',
    requiredKeys: ['SESSDATA'],
  ),
  _Platform(
    id: 'netease',
    name: '网易云音乐',
    icon: CupertinoIcons.cloud_fill,
    color: Color(0xFFC20C0C),
    loginUrl: 'https://music.163.com/#/login',
    cookieUrl: 'https://music.163.com',
    requiredKeys: ['MUSIC_U'],
  ),
  _Platform(
    id: 'qq',
    name: 'QQ音乐',
    icon: CupertinoIcons.music_albums_fill,
    color: Color(0xFF31C27C),
    loginUrl: 'https://y.qq.com/',
    cookieUrl: 'https://y.qq.com',
    requiredKeys: ['qm_keyst'],
  ),
  _Platform(
    id: 'kugou',
    name: '酷狗音乐',
    icon: CupertinoIcons.headphones,
    color: Color(0xFF2CA2F9),
    loginUrl: 'https://www.kugou.com/',
    cookieUrl: 'https://www.kugou.com',
    requiredKeys: ['token'],
  ),
];

class AccountPage extends ConsumerWidget {
  const AccountPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);

    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(middle: Text('账号')),
      child: Container(
        color: AppColors.bg,
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(4, 0, 4, 12),
                child: Text(
                  '登录后可以播放 VIP / 高音质歌曲。Cookie 只保存在本机，不会上传到任何服务器。',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: AppColors.muted,
                    height: 1.6,
                  ),
                ),
              ),
              ..._platforms.map(
                (p) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _card(context, ref, p, auth.isLoggedIn(p.id)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _card(
    BuildContext context,
    WidgetRef ref,
    _Platform p,
    bool loggedIn,
  ) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        boxShadow: AppColors.cardShadow,
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: p.color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(p.icon, size: 22, color: p.color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  p.name,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.text,
                  ),
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: loggedIn
                            ? const Color(0xFF28C76F)
                            : AppColors.muted,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      loggedIn ? '已登录' : '未登录',
                      style: TextStyle(
                        fontSize: 12,
                        color: loggedIn
                            ? const Color(0xFF28C76F)
                            : AppColors.muted,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (loggedIn)
            CupertinoButton(
              padding: EdgeInsets.zero,
              minSize: 0,
              onPressed: () async {
                final ok = await showCupertinoDialog<bool>(
                  context: context,
                  builder: (_) => CupertinoAlertDialog(
                    title: Text('退出 ${p.name}？'),
                    actions: [
                      CupertinoDialogAction(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('取消'),
                      ),
                      CupertinoDialogAction(
                        isDestructiveAction: true,
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('退出'),
                      ),
                    ],
                  ),
                );
                if (ok == true) {
                  await ref.read(authProvider.notifier).clear(p.id);
                }
              },
              child: const Text(
                '退出',
                style: TextStyle(fontSize: 13, color: AppColors.red),
              ),
            )
          else
            CupertinoButton(
              padding: EdgeInsets.zero,
              minSize: 0,
              onPressed: () async {
                final r = await context.push<bool>(
                  '/login-webview',
                  extra: {
                    'source': p.id,
                    'title': '登录 ${p.name}',
                    'loginUrl': p.loginUrl,
                    'cookieUrl': p.cookieUrl,
                    'requiredKeys': p.requiredKeys,
                  },
                );
                if (r == true && context.mounted) {
                  showCupertinoDialog(
                    context: context,
                    builder: (_) => CupertinoAlertDialog(
                      title: const Text('登录成功'),
                      content: Text('${p.name} 已登录'),
                      actions: [
                        CupertinoDialogAction(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('好'),
                        ),
                      ],
                    ),
                  );
                }
              },
              child: const Text(
                '登录',
                style: TextStyle(fontSize: 13, color: AppColors.primary),
              ),
            ),
        ],
      ),
    );
  }
}
