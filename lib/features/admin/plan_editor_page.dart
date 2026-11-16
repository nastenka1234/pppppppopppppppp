import 'package:flutter/material.dart';
import '../../core/api_client.dart';
import '../../core/jalali.dart';
import '../../core/models.dart';
import 'plan_text_parser.dart';
import '../../theme/glass.dart';
import '../../theme/tokens.dart';
import '../../theme/lottie_views.dart';

class PlanEditor extends StatefulWidget {
  final String studentId;
  const PlanEditor({super.key, required this.studentId});
  @override
  State<PlanEditor> createState() => _PlanEditorState();
}

class _PlanEditorState extends State<PlanEditor> {
  static const _maxParts = 5; // اولویت ۱ تا ۵؛ ترتیب فهرست = اولویت
  late final List<String> days = [for (var i = 0; i < 7; i++) addDays(todayIso(), i)];
  final Map<String, List<PlanItem>> mine = {};
  final Map<String, PlanDay> server = {};
  final Set<String> dirty = {};
  bool loading = true, saving = false;
  String? error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await Api.i.get('/admin/plan/${widget.studentId}', q: {'from': days.first});
      for (final x in (r['plans'] as List? ?? [])) {
        final p = PlanDay.fromJson(x);
        server[p.day] = p;
      }
      for (final d in days) {
        final p = server[d];
        final src = p == null ? <PlanItem>[] : (p.base.isNotEmpty ? p.base : p.items);
        mine[d] = [for (final i in src) PlanItem.fromJson(i.toJson())];
      }
    } on ApiError catch (e) {
      error = e.fa;
    }
    if (mounted) setState(() => loading = false);
  }

  Future<void> _save() async {
    if (dirty.isEmpty) return;
    setState(() => saving = true);
    try {
      await Api.i.put('/admin/plan/${widget.studentId}', body: {
        'days': [
          for (final d in days)
            if (dirty.contains(d)) {'day': d, 'items': [for (final i in mine[d]!) i.toJson()]},
        ],
      });
      dirty.clear();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('برنامه ذخیره شد')));
    } on ApiError catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.fa)));
    }
    if (mounted) setState(() => saving = false);
  }

  Future<void> _edit(String day, int? index) async {
    final it = index == null ? PlanItem(minutes: 60) : PlanItem.fromJson(mine[day]![index].toJson());
    final part = TextEditingController(text: it.part);
    final subject = TextEditingController(text: it.subject);
    final minutes = TextEditingController(text: it.minutes == 0 ? '' : '${it.minutes}');
    final tests = TextEditingController(text: it.testsTarget == 0 ? '' : '${it.testsTarget}');
    final note = TextEditingController(text: it.note);
    final action = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (_) => Padding(
        padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: part, decoration: const InputDecoration(labelText: 'نام پارت (اجباری)')),
            const SizedBox(height: 10),
            TextField(controller: subject, decoration: const InputDecoration(labelText: 'درس')),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                  child: TextField(
                      controller: minutes,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'دقیقه (۰–۳۶۰)'))),
              const SizedBox(width: 10),
              Expanded(
                  child: TextField(
                      controller: tests,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'هدف تست'))),
            ]),
            const SizedBox(height: 10),
            TextField(controller: note, decoration: const InputDecoration(labelText: 'یادداشت')),
            const SizedBox(height: 14),
            Row(children: [
              if (index != null) ...[
                GhostButton('حذف', icon: Icons.delete_outline_rounded, onPressed: () => Navigator.pop(context, 'del')),
                const SizedBox(width: 10),
              ],
              Expanded(child: PrimaryButton('تأیید', onPressed: () => Navigator.pop(context, 'ok'))),
            ]),
          ]),
        ),
      ),
    );
    if (action == null) return;
    setState(() {
      final list = mine[day]!;
      if (action == 'del' && index != null) {
        list.removeAt(index);
      } else if (action == 'ok' && part.text.trim().isNotEmpty) {
        final n = PlanItem(
          part: part.text.trim(),
          subject: subject.text.trim(),
          minutes: (int.tryParse(minutes.text.trim().replaceAll(RegExp(r'[^0-9]'), '')) ?? 0).clamp(0, 360),
          testsTarget: (int.tryParse(tests.text.trim().replaceAll(RegExp(r'[^0-9]'), '')) ?? 0).clamp(0, 500),
          note: note.text.trim(),
        );
        if (index == null) {
          if (list.length >= _maxParts) return;
          list.add(n);
        } else {
          list[index] = n;
        }
      }
      dirty.add(day);
    });
  }

  Future<void> _bulkEntry() async {
    final result = await showModalBottomSheet<Map<String, List<PlanItem>>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: T.bg,
      builder: (_) => FractionallySizedBox(
        heightFactor: .94,
        child: _BulkPlanSheet(days: days),
      ),
    );
    if (!mounted || result == null || result.isEmpty) return;
    setState(() {
      for (final entry in result.entries) {
        mine[entry.key] = [for (final item in entry.value) PlanItem.fromJson(item.toJson())];
        dirty.add(entry.key);
      }
    });
    final count = result.values.fold<int>(0, (sum, items) => sum + items.length);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${fa(result.length)} روز و ${fa(count)} پارت وارد شد؛ برای ثبت نهایی ذخیره را بزن.')),
      );
    }
  }

  void _copyPrev(String day) {
    final i = days.indexOf(day);
    if (i <= 0) return;
    setState(() {
      mine[day] = [for (final x in mine[days[i - 1]]!) PlanItem.fromJson(x.toJson())];
      dirty.add(day);
    });
  }

  String _line(PlanItem i) =>
      '${i.part}${i.subject.isEmpty ? '' : ' — ${i.subject}'}، ${fmtMin(i.minutes)}${i.testsTarget > 0 ? '، ${fa(i.testsTarget)} تست' : ''}';

  Future<void> _copyTo(String from) async {
    final others = [for (final x in days) if (x != from) x];
    final targets = await showModalBottomSheet<Set<String>>(
      context: context,
      builder: (_) => _CopyToSheet(days: others),
    );
    if (targets == null || targets.isEmpty) return;
    setState(() {
      for (final t in targets) {
        mine[t] = [for (final x in mine[from]!) PlanItem.fromJson(x.toJson())];
        dirty.add(t);
      }
    });
  }

  Widget _actionChip(String label, IconData icon, VoidCallback on) => InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: on,
        child: Pill(label, icon: icon, color: T.tx),
      );

  Widget _partRow(String d, int i, Key key) {
    final it = mine[d]![i];
    final optional = i == 4;
    return InkWell(
      key: key,
      onTap: () => _edit(d, i),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          ReorderableDragStartListener(
            index: i,
            child: const Padding(
              padding: EdgeInsets.fromLTRB(0, 2, 8, 0),
              child: Icon(Icons.drag_indicator_rounded, size: 20, color: T.tx2),
            ),
          ),
          Container(
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: optional ? Colors.transparent : T.acc,
              border: Border.all(color: T.acc),
            ),
            child: Text(fa(i + 1),
                style: TextStyle(
                    fontSize: 12,
                    height: 1.2,
                    fontWeight: FontWeight.w700,
                    color: optional ? T.acc : T.onAcc)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(it.part, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
              const SizedBox(height: 4),
              Wrap(spacing: 6, runSpacing: 6, children: [
                if (it.subject.isNotEmpty) Pill(it.subject),
                Pill(fmtMin(it.minutes)),
                if (it.testsTarget > 0) Pill('${fa(it.testsTarget)} تست'),
                if (optional) const Pill('اختیاری', color: T.acc),
              ]),
            ]),
          ),
          const Icon(Icons.edit_rounded, size: 15, color: T.tx2),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const AppLoader();
    if (error != null) return Center(child: Text(error!));
    return Column(children: [
      Expanded(
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 16), children: [
          Glass(
            borderColor: T.acc.withOpacity(.55),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('ورود سریع برنامه', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
              const SizedBox(height: 4),
              const Text('کل هفته را با دستورهای متنی وارد کن؛ لازم نیست پارت‌ها را یکی‌یکی بسازی.',
                  style: TextStyle(color: T.tx2, fontSize: 12)),
              const SizedBox(height: 10),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: _actionChip('نوشتن متن هفته', Icons.text_snippet_outlined, () { _bulkEntry(); }),
              ),
            ]),
          ),
          const SizedBox(height: 12),
          for (final d in days)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Glass(
                borderColor: dirty.contains(d) ? T.acc : null,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(jalaliFull(d), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                  const SizedBox(height: 8),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    if (d != days.first) _actionChip('کپی از روز قبل', Icons.copy_rounded, () => _copyPrev(d)),
                    if (mine[d]!.isNotEmpty)
                      _actionChip('کپی به روزهای دیگر', Icons.content_copy_rounded, () => _copyTo(d)),
                  ]),
                  if (mine[d]!.isEmpty)
                    const Padding(
                        padding: EdgeInsets.only(top: 10),
                        child: Text('خالی', style: TextStyle(color: T.tx2)))
                  else
                    ReorderableListView(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      buildDefaultDragHandles: false,
                      proxyDecorator: (child, _, __) =>
                          Material(color: T.surfaceHi, borderRadius: BorderRadius.circular(12), child: child),
                      onReorder: (o, n) => setState(() {
                        if (n > o) n -= 1;
                        final x = mine[d]!.removeAt(o);
                        mine[d]!.insert(n, x);
                        dirty.add(d);
                      }),
                      children: [
                        for (var i = 0; i < mine[d]!.length; i++) _partRow(d, i, ObjectKey(mine[d]![i])),
                      ],
                    ),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: TextButton.icon(
                        onPressed: mine[d]!.length >= _maxParts ? null : () => _edit(d, null),
                        icon: const Icon(Icons.add_rounded),
                        label: Text(mine[d]!.length >= _maxParts ? 'حداکثر ${fa(_maxParts)} پارت' : 'افزودن پارت')),
                  ),
                  if (server[d]?.source == 'ai')
                    Theme(
                      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                      child: ExpansionTile(
                        tilePadding: EdgeInsets.zero,
                        title: const Text('نسخه‌ی AI در برابر برنامه‌ی من',
                            style: TextStyle(color: T.hi, fontSize: 13)),
                        children: [
                          Align(
                              alignment: AlignmentDirectional.centerStart,
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                const Text('برنامه‌ی من:', style: TextStyle(fontWeight: FontWeight.w700)),
                                for (final i in server[d]!.base)
                                  Text(_line(i), style: const TextStyle(color: T.tx2, fontSize: 12)),
                                const SizedBox(height: 8),
                                const Text('ویرایش AI:', style: TextStyle(fontWeight: FontWeight.w700)),
                                for (final i in server[d]!.items)
                                  Text(_line(i), style: const TextStyle(color: T.hi, fontSize: 12)),
                                if (server[d]!.note.isNotEmpty)
                                  Padding(
                                      padding: const EdgeInsets.only(top: 6),
                                      child: Text(server[d]!.note,
                                          style: const TextStyle(color: T.tx2, fontSize: 12))),
                              ])),
                        ],
                      ),
                    ),
                ]),
              ),
            ),
        ]),
      ),
      Container(
        decoration: const BoxDecoration(color: T.bg, border: Border(top: BorderSide(color: T.line))),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: SafeArea(
          top: false,
          child: SizedBox(
            width: double.infinity,
            child: PrimaryButton(dirty.isEmpty ? 'تغییری نیست' : 'ذخیره‌ی ${fa(dirty.length)} تغییر',
                busy: saving, onPressed: dirty.isEmpty ? null : _save),
          ),
        ),
      ),
    ]);
  }
}

class _BulkPlanSheet extends StatefulWidget {
  final List<String> days;
  const _BulkPlanSheet({required this.days});

  @override
  State<_BulkPlanSheet> createState() => _BulkPlanSheetState();
}

class _BulkPlanSheetState extends State<_BulkPlanSheet> {
  final controller = TextEditingController();
  ParsedPlanText? parsed;

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  void _analyze() {
    FocusScope.of(context).unfocus();
    setState(() => parsed = PlanTextParser.parse(controller.text, widget.days));
  }

  @override
  Widget build(BuildContext context) {
    final result = parsed;
    return Padding(
      padding: EdgeInsets.fromLTRB(18, 14, 18, 16 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Expanded(
            child: Text('ورود یک‌جای برنامه‌ی هفته', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          ),
          IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded)),
        ]),
        const Text('هر دستور را در یک خط بنویس. روز را با نام روز یا تاریخ شمسی وارد کن و برای هر پارت دستورهایش را زیر آن بیاور.',
            style: TextStyle(color: T.tx2, fontSize: 12)),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: T.sec, borderRadius: BorderRadius.circular(14), border: Border.all(color: T.line)),
          child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('/روز شنبه', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
            Text('/پارت زیست فصل ۱', style: TextStyle(fontSize: 12)),
            Text('/درس زیست', style: TextStyle(fontSize: 12)),
            Text('/دقیقه ۹۰', style: TextStyle(fontSize: 12)),
            Text('/هدف_تست ۴۰', style: TextStyle(fontSize: 12)),
            Text('/توضیح تحلیل گفتار متن', style: TextStyle(fontSize: 12)),
            SizedBox(height: 4),
            Text('برای پارت بعدی دوباره /پارت و برای روز بعد /روز را بنویس.',
                style: TextStyle(color: T.tx2, fontSize: 11)),
          ]),
        ),
        const SizedBox(height: 10),
        Expanded(
          child: ListView(children: [
            TextField(
              controller: controller,
              minLines: 8,
              maxLines: 14,
              keyboardType: TextInputType.multiline,
              textDirection: TextDirection.rtl,
              decoration: const InputDecoration(
                alignLabelWithHint: true,
                labelText: 'متن کامل برنامه‌ی هفته',
                hintText: '/روز شنبه\n/پارت ...\n/درس ...\n/دقیقه ...\n/تست ...\n/توضیح ...',
                border: OutlineInputBorder(),
              ),
              onChanged: (_) {
                if (parsed != null) setState(() => parsed = null);
              },
            ),
            if (result != null) ...[
              const SizedBox(height: 12),
              if (result.errors.isNotEmpty)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: T.bad.withOpacity(.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: T.bad.withOpacity(.45)),
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('نیاز به اصلاح', style: TextStyle(color: T.bad, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 6),
                    for (final error in result.errors)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text('• $error', style: const TextStyle(color: T.bad, fontSize: 12)),
                      ),
                  ]),
                )
              else ...[
                Text('پیش‌نمایش: ${fa(result.days.length)} روز، ${fa(result.partCount)} پارت',
                    style: const TextStyle(color: T.hi, fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                for (final entry in result.days.entries)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Glass(
                      padding: const EdgeInsets.all(12),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(jalaliFull(entry.key), style: const TextStyle(fontWeight: FontWeight.w700)),
                        if (entry.value.isEmpty)
                          const Text('این روز خالی می‌شود.', style: TextStyle(color: T.tx2, fontSize: 12)),
                        for (var i = 0; i < entry.value.length; i++)
                          Padding(
                            padding: const EdgeInsets.only(top: 5),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(
                                '${fa(i + 1)}. ${entry.value[i].part}'
                                '${entry.value[i].subject.isEmpty ? '' : ' · ${entry.value[i].subject}'}'
                                ' · ${fmtMin(entry.value[i].minutes)}'
                                '${entry.value[i].testsTarget > 0 ? ' · ${fa(entry.value[i].testsTarget)} تست' : ''}',
                                style: const TextStyle(fontSize: 12, color: T.tx2),
                              ),
                              if (entry.value[i].note.isNotEmpty)
                                Text(entry.value[i].note,
                                    style: const TextStyle(fontSize: 11, color: T.tx2)),
                            ]),
                          ),
                      ]),
                    ),
                  ),
                const Text('فقط روزهای بالا جایگزین می‌شوند؛ روزهای دیگر تغییری نمی‌کنند.',
                    style: TextStyle(color: T.tx2, fontSize: 11)),
              ],
            ],
          ]),
        ),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: GhostButton('تحلیل متن', icon: Icons.fact_check_outlined, onPressed: _analyze)),
          const SizedBox(width: 10),
          Expanded(
            child: PrimaryButton(
              'اعمال به برنامه',
              icon: Icons.playlist_add_check_rounded,
              onPressed: result?.isValid == true ? () => Navigator.pop(context, result!.days) : null,
            ),
          ),
        ]),
      ]),
    );
  }
}

class _CopyToSheet extends StatefulWidget {
  final List<String> days;
  const _CopyToSheet({required this.days});
  @override
  State<_CopyToSheet> createState() => _CopyToSheetState();
}

class _CopyToSheetState extends State<_CopyToSheet> {
  final Set<String> sel = {};

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('کپی به کدام روزها؟', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        const Text('برنامه‌ی روزهای انتخاب‌شده جایگزین می‌شود.',
            style: TextStyle(color: T.tx2, fontSize: 12)),
        const SizedBox(height: 14),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final d in widget.days)
            FilterChip(
              label: Text(jalaliShort(d)),
              selected: sel.contains(d),
              showCheckmark: false,
              selectedColor: T.acc,
              backgroundColor: T.sec,
              side: BorderSide(color: sel.contains(d) ? T.acc : T.line2),
              labelStyle: TextStyle(color: sel.contains(d) ? T.onAcc : T.tx, fontWeight: FontWeight.w500),
              shape: const StadiumBorder(),
              onSelected: (v) => setState(() => v ? sel.add(d) : sel.remove(d)),
            ),
        ]),
        const SizedBox(height: 18),
        SizedBox(
          width: double.infinity,
          child: PrimaryButton(sel.isEmpty ? 'یک روز انتخاب کن' : 'کپی به ${fa(sel.length)} روز',
              onPressed: sel.isEmpty ? null : () => Navigator.pop(context, sel)),
        ),
      ]),
    );
  }
}
