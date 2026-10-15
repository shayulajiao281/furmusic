import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'providers/app_state.dart';
import 'router/app_router.dart';
import 'theme/app_colors.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ★ 初始化后台播放（必须，否则锁屏/通知无控制）
  await JustAudioBackground.init(
    androidNotificationChannelId: 'com.furkid.music.channel.audio',
    androidNotificationChannelName: 'FurKid Music',
    androidNotificationOngoing: true,
  );

  final prefs = await SharedPreferences.getInstance();

  runApp(
    ProviderScope(
      overrides: [sharedPrefsProvider.overrideWithValue(prefs)],
      child: const MusicApp(),
    ),
  );
}

class MusicApp extends StatelessWidget {
  const MusicApp({super.key});

  @override
  Widget build(BuildContext context) {
    return CupertinoApp.router(
      title: 'FurKid Music',
      debugShowCheckedModeBanner: false,
      routerConfig: appRouter,
      theme: const CupertinoThemeData(
        brightness: Brightness.light,
        primaryColor: AppColors.primary,
      ),
    );
  }
}
