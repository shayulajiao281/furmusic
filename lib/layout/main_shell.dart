import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/player_state.dart';
import '../theme/app_colors.dart';
import '../widgets/mini_player.dart';

class MainShell extends ConsumerWidget {
  final StatefulNavigationShell navigationShell;

  const MainShell({super.key, required this.navigationShell});

  static const double _miniHeight = 56;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bottom = MediaQuery.of(context).padding.bottom;
    final tabbarHeight = 76.0 + bottom;

    final hasSong = ref.watch(
      playerStateProvider.select((s) => s.current != null),
    );
    final contentBottomPadding = tabbarHeight + (hasSong ? _miniHeight : 0);

    return MediaQuery.removeViewInsets(
      context: context,
      removeBottom: true,
      child: CupertinoPageScaffold(
        child: Stack(
          children: [
            Positioned.fill(
              child: Padding(
                padding: EdgeInsets.only(bottom: contentBottomPadding),
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: () =>
                      ref.read(playerStateProvider.notifier).collapse(),
                  child: navigationShell,
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [const MiniPlayer(), _buildTabbar(ref, bottom)],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTabbar(WidgetRef ref, double bottom) {
    return Container(
      height: 76 + bottom,
      padding: EdgeInsets.only(bottom: bottom),
      decoration: const BoxDecoration(
        color: Color(0x00000000),
        border: Border(top: BorderSide(color: Color(0x0F141928), width: 1)),
      ),
      child: Row(
        children: [
          _tab(
            ref,
            0,
            CupertinoIcons.music_note,
            CupertinoIcons.music_note,
            '音乐',
          ),
          _tab(
            ref,
            1,
            CupertinoIcons.compass,
            CupertinoIcons.compass_fill,
            '发现',
          ),
          _tab(ref, 2, CupertinoIcons.person, CupertinoIcons.person_fill, '我的'),
        ],
      ),
    );
  }

  Widget _tab(
    WidgetRef ref,
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
          ref.read(playerStateProvider.notifier).collapse();
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
