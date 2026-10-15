import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import '../theme/app_colors.dart';
import '../widgets/mini_player.dart';

class MainShell extends StatelessWidget {
  final StatefulNavigationShell navigationShell;

  const MainShell({super.key, required this.navigationShell});

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom;

    return CupertinoPageScaffold(
      child: Column(
        children: [
          Expanded(child: navigationShell),
          const MiniPlayer(),
          Container(
            height: 60 + bottom,
            padding: EdgeInsets.only(bottom: bottom),
            decoration: const BoxDecoration(
              color: Color(0xF0FFFFFF),
              border: Border(
                top: BorderSide(color: Color(0x12141928), width: 1),
              ),
            ),
            child: Row(
              children: [
                _tab(
                  context,
                  0,
                  CupertinoIcons.music_note,
                  CupertinoIcons.music_note,
                  '音乐',
                ),
                _tab(
                  context,
                  1,
                  CupertinoIcons.compass,
                  CupertinoIcons.compass_fill,
                  '发现',
                ),
                _tab(
                  context,
                  2,
                  CupertinoIcons.person,
                  CupertinoIcons.person_fill,
                  '我的',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _tab(
    BuildContext context,
    int index,
    IconData icon,
    IconData activeIcon,
    String label,
  ) {
    final active = navigationShell.currentIndex == index;
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          HapticFeedback.selectionClick();
          navigationShell.goBranch(
            index,
            initialLocation: index == navigationShell.currentIndex,
          );
        },
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              active ? activeIcon : icon,
              size: 22,
              color: active ? AppColors.primary : AppColors.muted,
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: active ? FontWeight.w700 : FontWeight.w400,
                color: active ? AppColors.primary : AppColors.muted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
