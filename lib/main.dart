import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'providers/app_state.dart';
import 'router/app_router.dart';
import 'theme/app_colors.dart';
import 'services/audio_cache.dart';
import 'services/image_cache.dart';
import 'services/auth_store.dart';
import 'services/device_fingerprint.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await JustAudioBackground.init(
    androidNotificationChannelId: 'com.furkid.music.channel.audio',
    androidNotificationChannelName: 'FurKid Music',
    androidNotificationOngoing: true,
  );

  // ★ 建立缓存索引
  await AudioCache.init();
  await ImageCacheManager.init();

  AudioCache.trim().catchError((_) {});
  ImageCacheManager.trim().catchError((_) {});

  final prefs = await SharedPreferences.getInstance();
  AuthStore.attach(prefs);
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