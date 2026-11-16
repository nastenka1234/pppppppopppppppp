import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'core/api_client.dart';
import 'core/auth_store.dart';
import 'core/live.dart';
import 'core/notifications.dart';
import 'core/offline_queue.dart';
import 'core/local_migrations.dart';
import 'core/prefs.dart';
import 'core/sync_service.dart';
import 'router.dart';
import 'features/messenger/floating_messenger.dart';
import 'theme/background.dart';
import 'theme/tokens.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: Color(0xFF161316),
    systemNavigationBarIconBrightness: Brightness.light,
  ));
  try {
    await JustAudioBackground.init(
      androidNotificationChannelId: 'com.jojo.study.audio',
      androidNotificationChannelName: 'پخش موزیک',
      androidNotificationOngoing: true,
    );
  } catch (_) {}
  await Api.i.init();
  await OfflineQueue.i.load();
  await LocalMigrations.run(); // قبل از هر خواندن داده‌ی محلی؛ آپدیت اپ داده را نمی‌برد
  await SyncService.load();
  await Prefs.load();
  if (Platform.isAndroid) {
    try {
      await Notifs.init();
    } catch (_) {}
  }
  final session = await AuthNotifier.restore();
  if (session != null && !session.isAdmin) {
    Live.start();
    SyncService.start();
  }
  runApp(ProviderScope(
    overrides: [authProvider.overrideWith((ref) => AuthNotifier(session))],
    child: const App(),
  ));
}

class App extends ConsumerStatefulWidget {
  const App({super.key});
  @override
  ConsumerState<App> createState() => _AppState();
}

class _AppState extends ConsumerState<App> with WidgetsBindingObserver {
  void _kick() {
    ref.read(flashProvider.notifier).state = 'این حساب غیرفعال شده است';
    ref.read(authProvider.notifier).logout();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    Api.i.onUnauthorized = () => ref.read(authProvider.notifier).logout();
    Api.i.onDisabled = _kick;
    Live.onInactive = _kick;
    final s = ref.read(authProvider);
    if (s != null && !s.isAdmin) Notifs.scheduleDaily().catchError((_) {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && ref.read(authProvider)?.isAdmin == false) {
      SyncService.run();
      Live.beat();
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<Session?>(authProvider, (prev, next) {
      if (next != null && !next.isAdmin) {
        Notifs.scheduleDaily().catchError((_) {});
      } else {
        Notifs.cancel().catchError((_) {});
      }
    });
    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      title: 'امید',
      theme: T.theme(),
      routerConfig: ref.watch(routerProvider),
      locale: const Locale('fa', 'IR'),
      supportedLocales: const [Locale('fa', 'IR')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (context, child) => Directionality(
        textDirection: TextDirection.rtl,
        child: Stack(fit: StackFit.expand, children: [
          const AppBackground(),
          if (child != null) child,
          const FloatingMessengerLayer(),
        ]),
      ),
    );
  }
}
