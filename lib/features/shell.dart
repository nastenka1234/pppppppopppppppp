import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'dock_nav.dart';
import 'music/mini_player.dart';
import 'sync_banner.dart';

class StudentShell extends StatelessWidget {
  final Widget child;
  const StudentShell({super.key, required this.child});

  static const _paths = ['/today', '/stats', '/plan', '/music', '/settings'];
  static const _items = [
    DockItem('امروز', Icons.today_rounded),
    DockItem('آمار', Icons.bar_chart_rounded),
    DockItem('برنامه', Icons.event_note_rounded),
    DockItem('موزیک', Icons.music_note_rounded),
    DockItem('تنظیمات', Icons.tune_rounded),
  ];

  @override
  Widget build(BuildContext context) {
    final loc = GoRouterState.of(context).matchedLocation;
    final idx = _paths.indexWhere((p) => loc.startsWith(p));
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(children: [const SyncBanner(), Expanded(child: child)]),
      ),
      bottomNavigationBar: Column(mainAxisSize: MainAxisSize.min, children: [
        const MiniPlayer(),
        DockNav(
          items: _items,
          index: idx < 0 ? 0 : idx,
          onSelected: (i) => context.go(_paths[i]),
        ),
      ]),
    );
  }
}
