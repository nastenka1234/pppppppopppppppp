import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'core/auth_store.dart';
import 'core/prefs.dart';
import 'features/admin/admin_home.dart';
import 'features/admin/media_page.dart';
import 'features/admin/student_detail_page.dart';
import 'features/auth/login_page.dart';
import 'features/focus_room/focus_room_page.dart';
import 'features/intro/intro_page.dart';
import 'features/music/music_page.dart';
import 'features/plan/plan_week_page.dart';
import 'features/report/nightly_report_flow.dart';
import 'features/settings/settings_page.dart';
import 'features/settings/blocker_page.dart';
import 'features/shell.dart';
import 'features/stats/stats_page.dart';
import 'features/today/today_page.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final role = ref.watch(authProvider.select((s) => s?.role));
  final rootKey = GlobalKey<NavigatorState>();
  return GoRouter(
    navigatorKey: rootKey,
    initialLocation:
        role == null ? (Prefs.introSeen ? '/login' : '/intro') : (role == 'admin' ? '/admin' : '/today'),
    redirect: (ctx, st) {
      final loc = st.matchedLocation;
      if (role == null) {
        if (loc == '/intro' && !Prefs.introSeen) return null;
        return loc == '/login' ? null : '/login';
      }
      if (loc == '/login' || loc == '/intro') return role == 'admin' ? '/admin' : '/today';
      if (role == 'admin' && !loc.startsWith('/admin')) return '/admin';
      if (role == 'student' && loc.startsWith('/admin')) return '/today';
      return null;
    },
    routes: [
      GoRoute(path: '/intro', builder: (_, __) => const IntroPage()),
      GoRoute(path: '/login', builder: (_, __) => const LoginPage()),
      ShellRoute(
        builder: (_, __, child) => StudentShell(child: child),
        routes: [
          GoRoute(path: '/today', builder: (_, __) => const TodayPage()),
          GoRoute(path: '/stats', builder: (_, __) => const StatsPage()),
          GoRoute(path: '/plan', builder: (_, __) => const PlanWeekPage()),
          GoRoute(path: '/music', builder: (_, __) => const MusicPage()),
          GoRoute(path: '/settings', builder: (_, __) => const SettingsPage()),
        ],
      ),
      GoRoute(path: '/blocker', parentNavigatorKey: rootKey, builder: (_, __) => const BlockerPage()),
      GoRoute(
        path: '/focus',
        parentNavigatorKey: rootKey,
        builder: (_, s) => FocusRoomPage(
          part: s.uri.queryParameters['part'] ?? '',
          subject: s.uri.queryParameters['subject'] ?? '',
        ),
      ),
      GoRoute(
          path: '/report', parentNavigatorKey: rootKey, builder: (_, __) => const NightlyReportFlow()),
      GoRoute(path: '/admin', builder: (_, __) => const AdminHome()),
      GoRoute(
          path: '/admin/student/:id',
          builder: (_, s) => StudentDetailPage(id: s.pathParameters['id']!)),
      GoRoute(path: '/admin/media', builder: (_, __) => const MediaPage()),
    ],
  );
});
