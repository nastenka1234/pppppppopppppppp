import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/api_client.dart';
import '../../core/auth_store.dart';
import '../../core/jalali.dart';
import '../../theme/glass.dart';
import '../../theme/tokens.dart';
import '../../theme/lottie_views.dart';

class AdminHome extends ConsumerWidget {
  const AdminHome({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('پنل مشاور'),
          actions: [
            IconButton(icon: const Icon(Icons.library_music_rounded), onPressed: () => context.push('/admin/media')),
            IconButton(icon: const Icon(Icons.logout_rounded), onPressed: () => ref.read(authProvider.notifier).logout()),
          ],
          bottom: const TabBar(
            indicatorColor: T.acc,
            labelColor: T.hi,
            unselectedLabelColor: T.tx2,
            dividerColor: T.line,
            tabs: [Tab(text: 'زنده'), Tab(text: 'دانش‌آموزان')],
          ),
        ),
        body: const SafeArea(child: TabBarView(children: [LivePage(), StudentsPage()])),
      ),
    );
  }
}

class LivePage extends StatefulWidget {
  const LivePage({super.key});
  @override
  State<LivePage> createState() => _LivePageState();
}

class _LivePageState extends State<LivePage> {
  List<Map> students = [];
  DateTime? now;
  String? error;
  bool loading = true;
  Timer? t;

  @override
  void initState() {
    super.initState();
    _load();
    t = Timer.periodic(const Duration(seconds: 15), (_) => _load());
  }

  @override
  void dispose() {
    t?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final r = await Api.i.get('/admin/live');
      if (!mounted) return;
      setState(() {
        students = [for (final x in (r['students'] as List? ?? [])) Map.from(x)];
        now = parseTs(r['now']);
        error = null;
        loading = false;
      });
    } on ApiError catch (e) {
      if (mounted) setState(() {
        error = e.fa;
        loading = false;
      });
    }
  }

  String _status(Map s) {
    final online = s['online'] == true || s['online'] == 1;
    if (!online) return 'آفلاین · ${ago(parseTs(s['last_seen']), now)}';
    final st = '${s['live_state'] ?? 'idle'}';
    final part = '${s['live_part'] ?? ''}';
    final since = parseTs(s['live_since']);
    if (st == 'focus') return 'در حال مطالعه${part.isEmpty ? '' : ' · $part'} · از ${ago(since, now)}';
    if (st == 'break') return 'استراحت${part.isEmpty ? '' : ' · $part'}';
    return 'آنلاین';
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const AppLoader();
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(padding: const EdgeInsets.all(16), children: [
        if (error != null) Glass(child: Text(error!)),
        if (students.isEmpty && error == null) const Glass(child: Text('هنوز دانش‌آموزی نساخته‌ای.')),
        for (final s in students)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Glass(
              radius: 24,
              onTap: () => context.push('/admin/student/${s['id']}'),
              child: Row(children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: (s['online'] == true || s['online'] == 1) ? T.acc : T.tx2.withOpacity(.4),
                    boxShadow: (s['online'] == true || s['online'] == 1)
                        ? [BoxShadow(color: T.acc.withOpacity(.7), blurRadius: 10)]
                        : null,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${s['name']}${s['active'] == false || s['active'] == 0 ? ' (خاموش)' : ''}',
                        style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                    Text(_status(s), style: const TextStyle(color: T.tx2, fontSize: 12)),
                  ]),
                ),
                const Icon(Icons.chevron_left_rounded, color: T.tx2),
              ]),
            ),
          ),
      ]),
    );
  }
}

class StudentsPage extends StatefulWidget {
  const StudentsPage({super.key});
  @override
  State<StudentsPage> createState() => _StudentsPageState();
}

class _StudentsPageState extends State<StudentsPage> {
  List<Map> list = [];
  String? error;
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await Api.i.getAny('/admin/students');
      final raw = r is List ? r : (r['students'] as List? ?? []);
      if (mounted) setState(() {
        list = [for (final x in raw) Map.from(x)];
        error = null;
        loading = false;
      });
    } on ApiError catch (e) {
      if (mounted) setState(() {
        error = e.fa;
        loading = false;
      });
    }
  }

  Future<void> _add() async {
    final name = TextEditingController(), pw = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('دانش‌آموز جدید'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: name, decoration: const InputDecoration(labelText: 'نام')),
          const SizedBox(height: 10),
          TextField(controller: pw, decoration: const InputDecoration(labelText: 'رمز (اختیاری؛ خالی = تصادفی)')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('انصراف')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('ساخت')),
        ],
      ),
    );
    if (ok != true || name.text.trim().isEmpty) return;
    try {
      final r = await Api.i.post('/admin/students', body: {
        'name': name.text.trim(),
        if (pw.text.trim().isNotEmpty) 'password': pw.text.trim(),
      });
      final pass = r['password'] ?? (r['student'] is Map ? r['student']['password'] : null);
      if (mounted && pass != null) await showPasswordOnce(context, name.text.trim(), '$pass');
      _load();
    } on ApiError catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.fa)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(children: [
      if (loading)
        const AppLoader()
      else
        RefreshIndicator(
          onRefresh: _load,
          child: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 90), children: [
            if (error != null) Glass(child: Text(error!)),
            for (final s in list)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Glass(
                  radius: 24,
                  onTap: () => context.push('/admin/student/${s['id']}'),
                  child: Row(children: [
                    Expanded(child: Text('${s['name']}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16))),
                    Switch(
                      value: s['active'] == true || s['active'] == 1,
                      onChanged: (v) async {
                        try {
                          await Api.i.patch('/admin/students/${s['id']}', body: {'active': v});
                          _load();
                        } on ApiError catch (e) {
                          if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.fa)));
                        }
                      },
                    ),
                  ]),
                ),
              ),
          ]),
        ),
      Positioned(
        left: 18,
        bottom: 18,
        child: FloatingActionButton.extended(
          backgroundColor: T.acc,
          foregroundColor: T.bg,
          onPressed: _add,
          icon: const Icon(Icons.person_add_alt_1_rounded),
          label: const Text('دانش‌آموز جدید', style: TextStyle(fontWeight: FontWeight.w700)),
        ),
      ),
    ]);
  }
}

/// رمز فقط یک‌بار برمی‌گردد؛ با دکمه‌ی کپی نشان بده.
Future<void> showPasswordOnce(BuildContext context, String name, String pass) => showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: Text('رمز $name'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('این رمز فقط همین یک‌بار نمایش داده می‌شود. کپی کن و برای دانش‌آموز بفرست.',
              style: TextStyle(color: T.tx2, fontSize: 13)),
          const SizedBox(height: 14),
          SelectableText(pass,
              textDirection: TextDirection.ltr,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: T.hi)),
        ]),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: pass));
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('کپی شد')));
            },
            child: const Text('کپی'),
          ),
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('بستم')),
        ],
      ),
    );
