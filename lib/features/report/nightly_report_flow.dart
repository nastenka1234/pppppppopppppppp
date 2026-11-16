import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/api_client.dart';
import '../../core/jalali.dart';
import '../../core/models.dart';
import '../../core/offline_queue.dart';
import '../../core/priority.dart';
import '../../core/progress_store.dart';
import '../../theme/glass.dart';
import '../../theme/tokens.dart';
import '../../theme/lottie_views.dart';

class NightlyReportFlow extends StatefulWidget {
  const NightlyReportFlow({super.key});
  @override
  State<NightlyReportFlow> createState() => _NightlyReportFlowState();
}

class _NightlyReportFlowState extends State<NightlyReportFlow> {
  final day = todayIso();
  final pc = PageController();
  List<PlanItem> items = [];
  final Map<String, PartProgress> prog = {};
  final Set<String> locked = {}; // پارت‌های قفل (قانون اولویت‌ها): در گزارش هم نمی‌شود «تمام شد» زد
  bool loading = true, busy = false;
  String? error;
  int page = 0;
  int mood = 3;
  bool sleptWell = true, distracted = false;
  final hard = TextEditingController();
  final note = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await Api.i.getC('/plan', q: {'day': day});
      final plan = PlanDay.fromJson(r);
      items = plan.items;
      final local = await ProgressStore.load(day);
      for (final it in items) {
        prog[it.part] = local[it.part] ?? PartProgress();
      }
      for (final st in Priority.compute(plan, local).parts) {
        if (st.isLocked) locked.add(st.item.part);
      }
    } on ApiError catch (e) {
      error = e.fa;
    }
    if (mounted) setState(() => loading = false);
  }

  int get total => items.length + 1;

  void _go(int p) {
    setState(() => page = p);
    pc.animateToPage(p, duration: const Duration(milliseconds: 280), curve: Curves.easeOutCubic);
  }

  Future<void> _submit() async {
    setState(() => busy = true);
    final parts = [
      for (final it in items) {'part': it.part, ...prog[it.part]!.toJson()},
    ];
    for (final it in items) {
      final pp = prog[it.part]!;
      await ProgressStore.update(day, it.part, (p) {
        p.tests = pp.tests;
        p.correct = pp.correct;
        p.done = pp.done;
        p.note = pp.note;
        if (pp.correct > 0) p.correctKnown = true;
        if (pp.done) {
          p.carried = false;
          if (p.doneAt.isEmpty) p.doneAt = DateTime.now().toUtc().toIso8601String();
        }
      }, send: false);
    }
    try {
      final sent = await OfflineQueue.i.send(
        '/report',
        {
          'day': day,
          'parts': parts,
          'mood': mood,
          'note': note.text.trim(),
          'hard': hard.text.trim(),
          'slept': sleptWell ? 1 : 0,
          'distractions': distracted ? 1 : 0,
        },
        key: 'report:$day',
      );
      if (!mounted) return;
      if (sent) await showVerifiedTick(context, text: 'گزارش ثبت شد');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(sent ? 'گزارش ثبت شد. برنامه‌ی فردا ساعت ۱ بامداد تنظیم می‌شود.' : 'ارسال نشد؛ گزارش روی گوشی ذخیره شد و بعداً خودکار ارسال می‌شود.')));
      context.go('/today');
    } on ApiError catch (e) {
      if (mounted) {
        setState(() => busy = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.fa)));
      }
    }
  }

  Widget _stepper(String label, int v, ValueChanged<int> on) => Row(children: [
        Expanded(child: Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
        IconButton(onPressed: v > 0 ? () => on(v - 1) : null, icon: const Icon(Icons.remove_circle_outline)),
        SizedBox(width: 50, child: Center(child: Text(fa(v), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900)))),
        IconButton(onPressed: () => on(v + 1), icon: const Icon(Icons.add_circle_outline)),
      ]);

  Widget _partPage(PlanItem it) {
    final p = prog[it.part]!;
    return ListView(padding: const EdgeInsets.all(18), children: [
      PageTitle(it.part, sub: it.subject.isEmpty ? null : it.subject),
      Glass(
        child: Column(children: [
          _stepper('چند تست زدی؟', p.tests, (v) => setState(() {
                p.tests = v;
                if (p.correct > v) p.correct = v;
              })),
          const Divider(),
          _stepper('چندتا درست؟', p.correct, (v) => setState(() => p.correct = v > p.tests ? p.tests : v)),
          const Divider(),
          SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('تمام شد؟'),
              subtitle: locked.contains(it.part)
                  ? const Text('اول اولویت‌های قبلی را تموم کن', style: TextStyle(color: T.tx2, fontSize: 12))
                  : null,
              value: p.done,
              onChanged: locked.contains(it.part) ? null : (v) => setState(() => p.done = v)),
        ]),
      ),
      if (it.testsTarget > 0)
        Padding(
          padding: const EdgeInsets.only(top: 10, right: 6),
          child: Text('هدف امروز: ${fa(it.testsTarget)} تست', style: const TextStyle(color: T.tx2)),
        ),
    ]);
  }

  Widget _finalPage() => ListView(padding: const EdgeInsets.all(18), children: [
        const PageTitle('حال امروز', sub: 'برنامه‌ی فردا با همین تنظیم می‌شود'),
        Glass(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('حالت چطور بود؟', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              for (var i = 1; i <= 5; i++)
                GestureDetector(
                  onTap: () => setState(() => mood = i),
                  child: Container(
                    width: 48,
                    height: 48,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: mood == i ? T.acc : T.glass,
                      border: Border.all(color: T.line),
                    ),
                    child: Text(fa(i),
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w900, color: mood == i ? T.bg : T.tx)),
                  ),
                ),
            ]),
            const SizedBox(height: 6),
            const Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text('خیلی بد', style: TextStyle(color: T.tx2, fontSize: 11)),
              Text('عالی', style: TextStyle(color: T.tx2, fontSize: 11)),
            ]),
            const SizedBox(height: 14),
            TextField(controller: hard, decoration: const InputDecoration(labelText: 'سخت‌ترین بخش امروز')),
            SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('دیشب کافی خوابیدم'),
                value: sleptWell,
                onChanged: (v) => setState(() => sleptWell = v)),
            SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('حواسم زیاد پرت شد'),
                value: distracted,
                onChanged: (v) => setState(() => distracted = v)),
            TextField(
                controller: note,
                maxLines: 3,
                decoration: const InputDecoration(labelText: 'یادداشت (اختیاری)')),
          ]),
        ),
      ]);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('گزارشکار شبانه'),
        leading: IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => context.go('/today')),
      ),
      body: SafeArea(
        child: loading
            ? const AppLoader()
            : error != null
                ? Center(child: Text(error!))
                : items.isEmpty
                    ? Center(
                        child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(mainAxisSize: MainAxisSize.min, children: [
                              const Text('برای امروز پارتی ثبت نشده.'),
                              const SizedBox(height: 12),
                              GhostButton('برگشت', onPressed: () => context.go('/today')),
                            ])))
                    : Column(children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 22),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: LinearProgressIndicator(
                                value: (page + 1) / total, minHeight: 6, backgroundColor: T.glass, color: T.acc),
                          ),
                        ),
                        Expanded(
                          child: PageView(
                            controller: pc,
                            physics: const NeverScrollableScrollPhysics(),
                            children: [for (final it in items) _partPage(it), _finalPage()],
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(18, 0, 18, 16),
                          child: Row(children: [
                            if (page > 0) ...[
                              GhostButton('قبلی', onPressed: () => _go(page - 1)),
                              const SizedBox(width: 12),
                            ],
                            Expanded(
                              child: page == total - 1
                                  ? PrimaryButton('ارسال گزارش', busy: busy, onPressed: _submit)
                                  : PrimaryButton('بعدی', onPressed: () => _go(page + 1)),
                            ),
                          ]),
                        ),
                      ]),
      ),
    );
  }
}
