import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'providers/app_state.dart';
import 'router/app_router.dart';
import 'theme/app_colors.dart';
import 'services/audio_cache.dart';
import 'services/auth_store.dart';
import 'services/device_fingerprint.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await JustAudioBackground.init(
    androidNotificationChannelId: 'com.furkid.music.channel.audio',
    androidNotificationChannelName: 'FurKid Music',
    androidNotificationOngoing: true,
  );

  // await AudioCache.clear();

  await AudioCache.size();
  AudioCache.trim().catchError((_) {});

  final prefs = await SharedPreferences.getInstance();

  // 把 prefs 挂给 AuthStore
  AuthStore.attach(prefs);

  // ★ 初始化设备指纹（持久化 guid / qimei）
  await DeviceFingerprint.init();

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
