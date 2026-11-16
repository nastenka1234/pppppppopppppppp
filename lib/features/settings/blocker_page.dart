import 'package:flutter/material.dart';
import '../../core/blocker.dart';
import '../../theme/tokens.dart';

class BlockerPage extends StatefulWidget {
  const BlockerPage({super.key});
  @override
  State<BlockerPage> createState() => _BlockerPageState();
}

class _BlockerPageState extends State<BlockerPage> with WidgetsBindingObserver {
  List<AppInfo> all = [];
  Set<String> sel = {};
  bool on = false, always = false, access = false, loading = true;
  String q = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed) _checkAccess();
  }

  Future<void> _checkAccess() async {
    final a = await Blocker.enabled();
    if (mounted) setState(() => access = a);
  }

  Future<void> _init() async {
    final s = await Blocker.load();
    final a = await Blocker.apps();
    final acc = await Blocker.enabled();
    if (!mounted) return;
    setState(() {
      sel = s.apps;
      on = s.on;
      always = s.always;
      all = a;
      access = acc;
      loading = false;
    });
  }

  void _save() => Blocker.save(sel, on, always);

  @override
  Widget build(BuildContext context) {
    final list = [
      for (final a in all)
        if (q.isEmpty || a.label.toLowerCase().contains(q.toLowerCase())) a
    ]..sort((a, b) => (sel.contains(b.pkg) ? 1 : 0) - (sel.contains(a.pkg) ? 1 : 0));
    return Scaffold(
      appBar: AppBar(title: const Text('مسدودکننده‌ی برنامه')),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : Column(children: [
              if (!access)
                Container(
                  margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                      color: T.bad.withOpacity(.15), borderRadius: BorderRadius.circular(T.rCard)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text(
                        'برای کار کردن باید «امید» را در تنظیمات دسترسی‌پذیری روشن کنی. این سرویس فقط اسم برنامه‌ی بازشده را می‌بیند و هیچ داده‌ای نمی‌فرستد.',
                        style: TextStyle(fontSize: 13)),
                    const SizedBox(height: 8),
                    FilledButton(onPressed: Blocker.openSettings, child: const Text('باز کردن تنظیمات')),
                  ]),
                ),
              SwitchListTile(
                title: const Text('فعال'),
                value: on,
                onChanged: (v) {
                  setState(() => on = v);
                  _save();
                },
              ),
              SwitchListTile(
                title: const Text('همیشه (نه فقط هنگام تمرکز)'),
                subtitle: const Text('خاموش = فقط وقتی اتاق تمرکز در حال اجراست',
                    style: TextStyle(fontSize: 12, color: T.tx2)),
                value: always,
                onChanged: (v) {
                  setState(() => always = v);
                  _save();
                },
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                child: TextField(
                  decoration: InputDecoration(
                      hintText: 'جستجوی برنامه…  (${sel.length} انتخاب‌شده)',
                      prefixIcon: const Icon(Icons.search_rounded)),
                  onChanged: (v) => setState(() => q = v),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: list.length,
                  itemBuilder: (_, i) {
                    final a = list[i];
                    return CheckboxListTile(
                      dense: true,
                      title: Text(a.label),
                      value: sel.contains(a.pkg),
                      onChanged: (v) {
                        setState(() => v == true ? sel.add(a.pkg) : sel.remove(a.pkg));
                        _save();
                      },
                    );
                  },
                ),
              ),
            ]),
    );
  }
}
