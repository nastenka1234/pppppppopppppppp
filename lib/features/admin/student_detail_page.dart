import 'package:flutter/material.dart';
import '../../core/api_client.dart';
import '../../core/jalali.dart';
import '../../theme/glass.dart';
import '../../theme/tokens.dart';
import '../stats/stats_page.dart';
import 'admin_home.dart' show showPasswordOnce;
import 'plan_editor_page.dart';
import 'package:lottie/lottie.dart';
import '../../theme/lottie_views.dart';

class StudentDetailPage extends StatefulWidget {
  final String id;
  const StudentDetailPage({super.key, required this.id});
  @override
  State<StudentDetailPage> createState() => _StudentDetailPageState();
}

class _StudentDetailPageState extends State<StudentDetailPage> {
  Map? student;
  List reports = [];
  String? error;
  bool loading = true, replanning = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await Api.i.get('/admin/student/${widget.id}/overview', q: {'range': 14});
      if (!mounted) return;
      setState(() {
        student = r['student'] is Map ? Map.from(r['student']) : {'name': ''};
        reports = r['reports'] as List? ?? [];
        loading = false;
      });
    } on ApiError catch (e) {
      if (mounted) setState(() {
        error = e.fa;
        loading = false;
      });
    }
  }

  void _snack(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _setActive(bool v) async {
    try {
      await Api.i.patch('/admin/students/${widget.id}', body: {'active': v});
      setState(() => student!['active'] = v);
    } on ApiError catch (e) {
      _snack(e.fa);
    }
  }

  Future<void> _changePass() async {
    final c = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('تغییر رمز'),
        content: TextField(controller: c, decoration: const InputDecoration(labelText: 'رمز جدید')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('انصراف')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('ذخیره')),
        ],
      ),
    );
    if (ok != true || c.text.trim().isEmpty) return;
    try {
      await Api.i.patch('/admin/students/${widget.id}', body: {'password': c.text.trim()});
      if (mounted) await showPasswordOnce(context, '${student?['name']}', c.text.trim());
    } on ApiError catch (e) {
      _snack(e.fa);
    }
  }

  Future<void> _replan() async {
    setState(() => replanning = true);
    // انیمیشن «هوش مصنوعی در حال کار» تا پایان بازبینی
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        child: Directionality(
          textDirection: TextDirection.rtl,
          child: Dialog(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                SizedBox(height: 150, child: Lottie.asset(LottieAssets.ai)),
                const SizedBox(height: 8),
                const Text('هوش مصنوعی در حال بازبینی برنامه‌ی فردا…',
                    textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w700)),
              ]),
            ),
          ),
        ),
      ),
    );
    try {
      await Api.i.post('/admin/replan/${widget.id}');
      _snack('بازبینی برنامه‌ی فردا انجام شد');
    } on ApiError catch (e) {
      _snack(e.fa);
    }
    if (mounted) {
      Navigator.of(context, rootNavigator: true).pop(); // بستن دیالوگ انیمیشن
      setState(() => replanning = false);
    }
  }

  Widget _reportCard(Map r) {
    final parts = r['parts'] as List? ?? [];
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Glass(
        radius: 24,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
                child: Text(r['day'] == null ? '' : jalaliFull('${r['day']}'),
                    style: const TextStyle(fontWeight: FontWeight.w900))),
            if (r['mood'] != null) Text('حال: ${fa(r['mood'])} از ۵', style: const TextStyle(color: T.hi)),
          ]),
          for (final p in parts)
            if (p is Map)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                    '${p['part']}: ${fa(p['tests'] ?? 0)} تست، ${fa(p['correct'] ?? 0)} درست${p['done'] == true || p['done'] == 1 ? ' ✓' : ''}',
                    style: const TextStyle(color: T.tx2, fontSize: 13)),
              ),
          if ('${r['hard'] ?? ''}'.isNotEmpty)
            Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('سخت‌ترین: ${r['hard']}', style: const TextStyle(fontSize: 13))),
          if (r['slept'] == 0 || r['slept'] == false)
            const Padding(padding: EdgeInsets.only(top: 4), child: Text('کم‌خوابی', style: TextStyle(color: T.hi, fontSize: 12))),
          if (r['distractions'] == 1 || r['distractions'] == true)
            const Padding(padding: EdgeInsets.only(top: 2), child: Text('حواس‌پرتی زیاد', style: TextStyle(color: T.hi, fontSize: 12))),
          if ('${r['note'] ?? ''}'.isNotEmpty)
            Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('${r['note']}', style: const TextStyle(color: T.tx2, fontSize: 13))),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text('${student?['name'] ?? ''}'),
          bottom: const TabBar(
            indicatorColor: T.acc,
            labelColor: T.hi,
            unselectedLabelColor: T.tx2,
            dividerColor: T.line,
            tabs: [Tab(text: 'آمار'), Tab(text: 'گزارش‌ها'), Tab(text: 'برنامه')],
          ),
        ),
        body: SafeArea(
          child: loading
              ? const AppLoader()
              : error != null
                  ? Center(child: Text(error!))
                  : TabBarView(children: [
                      ListView(padding: const EdgeInsets.all(16), children: [
                        Glass(
                          child: Column(children: [
                            SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              title: const Text('فعال'),
                              value: student?['active'] == true || student?['active'] == 1 || student?['active'] == null,
                              onChanged: _setActive,
                            ),
                            Row(children: [
                              Expanded(child: GhostButton('تغییر رمز', icon: Icons.key_rounded, onPressed: _changePass)),
                              const SizedBox(width: 10),
                              Expanded(
                                  child: GhostButton(replanning ? '…' : 'بازبینی فردا با AI',
                                      icon: Icons.auto_fix_high_rounded,
                                      onPressed: replanning ? null : _replan)),
                            ]),
                          ]),
                        ),
                        const SizedBox(height: 14),
                        StatsView(studentId: widget.id),
                      ]),
                      ListView(padding: const EdgeInsets.all(16), children: [
                        if (reports.isEmpty) const Glass(child: Text('گزارشی ثبت نشده.')),
                        for (final r in reports) if (r is Map) _reportCard(r),
                      ]),
                      PlanEditor(studentId: widget.id),
                    ]),
        ),
      ),
    );
  }
}
