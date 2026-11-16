import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/api_client.dart';
import '../../core/auth_store.dart';
import '../../core/config.dart';
import '../../core/jalali.dart';
import '../../core/media_cache.dart';
import '../../core/offline_queue.dart';
import '../../core/prefs.dart';
import '../../core/sync_service.dart';
import '../../theme/glass.dart';
import '../../theme/tokens.dart';
import '../music/player_service.dart';

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});
  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  int cacheBytes = 0;

  @override
  void initState() {
    super.initState();
    _size();
  }

  Future<void> _size() async {
    final b = await MediaCache.sizeBytes();
    if (mounted) setState(() => cacheBytes = b);
  }

  Future<void> _logout() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('از حساب خارج می‌شوی؟'),
        content: Text(OfflineQueue.i.pending.value > 0
            ? '${fa(OfflineQueue.i.pending.value)} مورد هنوز ارسال نشده. حذف نمی‌شوند؛ روی گوشی می‌مانند و بعد از ورود دوباره با همین حساب ارسال می‌شوند. برای ورود دوباره به رمزت نیاز داری.'
            : 'برای ورود دوباره به رمزت نیاز داری.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('انصراف')),
          TextButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('خروج', style: TextStyle(color: T.bad))),
        ],
      ),
    );
    if (ok != true) return;
    await PlayerService.i.stop();
    await ref.read(authProvider.notifier).logout();
  }

  Widget _group(String title, List<Widget> children) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
            child: Text(title,
                style: const TextStyle(color: T.tx2, fontSize: 13, fontWeight: FontWeight.w700)),
          ),
          Glass(child: Column(children: children)),
        ],
      );

  Widget _drop(String label, int value, List<int> opts, ValueChanged<int> on) => Row(children: [
        Expanded(child: Text(label)),
        DropdownButton<int>(
          value: value,
          dropdownColor: T.surfaceHi,
          underline: const SizedBox.shrink(),
          items: [for (final o in opts) DropdownMenuItem(value: o, child: Text('${fa(o)} دقیقه'))],
          onChanged: (v) {
            if (v != null) {
              on(v);
              Prefs.save();
              setState(() {});
            }
          },
        ),
      ]);

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(authProvider);
    final mb = fa((cacheBytes / 1048576).toStringAsFixed(1).replaceAll('.', '٫'));
    return ListView(padding: const EdgeInsets.fromLTRB(20, 12, 20, 24), children: [
      const PageTitle('تنظیمات'),
      _group('تمرکز', [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('تعویض خودکار موزیک در استراحت'),
          value: Prefs.autoMusic,
          onChanged: (v) {
            setState(() => Prefs.autoMusic = v);
            Prefs.save();
          },
        ),
        const Divider(),
        _drop('مدت تمرکز (پومودورو)', Prefs.focusMin, [25, 35, 45, 50], (v) => Prefs.focusMin = v),
        _drop('مدت استراحت', Prefs.breakMin, [5, 10, 15], (v) => Prefs.breakMin = v),
      ]),
      _group('تمرکز بیشتر', [
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.block_rounded),
          title: const Text('مسدودکننده‌ی برنامه'),
          subtitle: const Text('بستن اینستاگرام و… هنگام تمرکز', style: TextStyle(fontSize: 12, color: T.tx2)),
          trailing: const Icon(Icons.chevron_left_rounded),
          onTap: () => context.push('/blocker'),
        ),
      ]),
      _group('حافظه', [
        Row(children: [
          Expanded(child: Text('کش موزیک: $mb مگابایت')),
          GhostButton('پاک‌کردن', onPressed: () async {
            await PlayerService.i.stop();
            await MediaCache.clear();
            _size();
          }),
        ]),
        const SizedBox(height: 12),
        ValueListenableBuilder<int>(
          valueListenable: OfflineQueue.i.pending,
          builder: (_, n, __) => Row(children: [
            Expanded(child: Text('منتظر ارسال: ${fa(n)} مورد')),
            GhostButton('ارسال الان', onPressed: n == 0 ? null : () => SyncService.run(force: true)),
          ]),
        ),
        const SizedBox(height: 12),
        ValueListenableBuilder<DateTime?>(
          valueListenable: SyncService.lastOk,
          builder: (_, t, __) => Text(
            t == null
                ? 'آخرین همگام‌سازی: هنوز انجام نشده'
                : 'آخرین همگام‌سازی: ${fa(t.hour.toString().padLeft(2, '0'))}:${fa(t.minute.toString().padLeft(2, '0'))} — ${jalaliShort(isoDay(t))}',
            style: const TextStyle(color: T.tx2, fontSize: 12),
          ),
        ),
      ]),
      _group('حساب', [
        Row(children: [
          const Icon(Icons.person_outline_rounded, color: T.tx2),
          const SizedBox(width: 10),
          Expanded(child: Text(s?.name ?? '')),
        ]),
        const SizedBox(height: 16),
        SizedBox(
            width: double.infinity,
            child: DangerButton('خروج', icon: Icons.logout_rounded, onPressed: _logout)),
      ]),
      const SizedBox(height: 24),
      Center(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Text('نسخه‌ی ${fa(Config.appVersion)}',
                style: const TextStyle(color: T.tx2, fontSize: 11)),
          ),
        ),
      ),
    ]);
  }
}
