import 'dart:async';
import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';
import 'api_client.dart';
import 'jalali.dart';
import 'local_migrations.dart';
import 'notifications.dart';
import 'offline_queue.dart';

const _taskName = 'omid-sync';
const _taskUnique = 'omid-sync-6h';

/// وارد پس‌زمینه می‌شود (هر ~۶ ساعت وقتی اینترنت هست، حتی اگر اپ بسته باشد).
@pragma('vm:entry-point')
void syncCallbackDispatcher() {
  Workmanager().executeTask((task, input) async {
    try {
      WidgetsFlutterBinding.ensureInitialized();
      await Api.i.init();
      await OfflineQueue.i.load();
      if (Api.i.token == null) return true;
      return await SyncService.run(background: true);
    } catch (_) {
      return false; // WorkManager دوباره تلاش می‌کند (backoff)
    }
  });
}

/// همگام‌سازی: ارسال صف آفلاین + تازه‌کردن کش (برنامه‌ی ۱۴ روز آینده، موزیک، ویدیو، آمار).
///
/// «همگام» یعنی صف این حساب خالی شد و سرور جواب داد. ۶ ساعت بدون همگام‌سازی ← هشدار در اپ
/// + اعلان؛ داده هیچ‌وقت پاک نمی‌شود و استفاده از اپ قفل نمی‌شود.
class SyncService {
  static const maxAge = Duration(hours: 6);
  static final ValueNotifier<DateTime?> lastOk = ValueNotifier(null);
  static final ValueNotifier<bool> running = ValueNotifier(false);
  static StreamSubscription? _conn;
  static DateTime? _lastPrefetch;

  static Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    final ms = p.getInt('sync_last_ok');
    lastOk.value = ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  /// بیش از ۶ ساعت بدون همگام‌سازی (یا هیچ‌وقت و چیزی در صف است).
  static bool get stale {
    final t = lastOk.value;
    if (t == null) return OfflineQueue.i.pending.value > 0;
    return DateTime.now().difference(t) > maxAge;
  }

  static Future<void> markOk() async {
    final now = DateTime.now();
    final prev = lastOk.value;
    lastOk.value = now;
    // هر دقیقه صدا زده می‌شود (heartbeat)؛ ذخیره/زمان‌بندی اعلان فقط هر ۵ دقیقه.
    if (prev != null && now.difference(prev) < const Duration(minutes: 5)) return;
    try {
      (await SharedPreferences.getInstance()).setInt('sync_last_ok', now.millisecondsSinceEpoch);
      await Notifs.init(askPermission: false);
      await Notifs.scheduleSyncReminder(maxAge);
    } catch (_) {}
  }

  /// یک دور کامل. true = همه‌چیز ارسال شد و سرور جواب داد.
  static Future<bool> run({bool background = false, bool force = false}) async {
    if (Api.i.token == null || Api.i.sid == null) return false;
    if (running.value) return false;
    running.value = true;
    try {
      if (!await OfflineQueue.i.flush()) return false;
      final me = await Api.i.get('/me'); // اثبات آنلاین بودن + فعال بودن حساب
      if ((me['student'] as Map?)?['active'] == false) {
        Api.i.onDisabled?.call();
        return false;
      }
      await _renewToken();
      final last = _lastPrefetch;
      if (force || last == null || DateTime.now().difference(last) > const Duration(hours: 2)) {
        await _prefetch();
      }
      await markOk();
      return true;
    } on ApiError {
      return false;
    } catch (_) {
      return false;
    } finally {
      running.value = false;
    }
  }

  /// توکن بعد از ۳۰ روز منقضی می‌شود؛ هفته‌ای یک بار تمدید می‌کنیم تا دانش‌آموز بیرون انداخته نشود.
  static Future<void> _renewToken() async {
    final iat = Api.i.tokenIssuedAt;
    if (iat == null) return;
    final age = DateTime.now().millisecondsSinceEpoch ~/ 1000 - iat;
    if (age < 7 * 86400) return;
    try {
      final r = await Api.i.post('/refresh');
      final t = r['token'];
      if (t is String && t.isNotEmpty) await Api.i.setToken(t);
    } catch (_) {}
  }

  static Future<void> _prefetch() async {
    final today = todayIso();
    try {
      final r = await Api.i.get('/plan', q: {'day': today, 'days': 14});
      final plans = (r['plans'] as List?) ?? const [];
      for (final x in plans) {
        if (x is Map && x['day'] != null) await Api.i.cachePut('/plan', {'day': '${x['day']}'}, x);
      }
      if (plans.length >= 7) {
        await Api.i.cachePut('/plan', {'day': today, 'days': 7}, {'plans': plans.take(7).toList()});
      }
    } catch (_) {}
    for (final job in <Future<dynamic> Function()>[
      () => Api.i.getC('/music'),
      () => Api.i.getC('/focus/videos'),
      () => Api.i.getC('/stats', q: {'range': 7}),
      () => Api.i.getC('/stats', q: {'range': 30}),
    ]) {
      try {
        await job();
      } catch (_) {}
    }
    _lastPrefetch = DateTime.now();
  }

  static Future<void> maybePrefetch() async {
    final last = _lastPrefetch;
    if (last != null && DateTime.now().difference(last) < const Duration(hours: 2)) return;
    _lastPrefetch = DateTime.now();
    await _prefetch();
  }

  /// بعد از ورود دانش‌آموز / شروع اپ.
  static Future<void> start() async {
    await LocalMigrations.run();
    OfflineQueue.i.refreshCount();
    unawaited(run(force: true));
    if (!Platform.isAndroid) return;
    _conn?.cancel();
    _conn = Connectivity().onConnectivityChanged.listen((r) {
      if (r.any((x) => x != ConnectivityResult.none)) unawaited(run());
    });
    try {
      await Workmanager().initialize(syncCallbackDispatcher, isInDebugMode: false);
      await Workmanager().registerPeriodicTask(
        _taskUnique,
        _taskName,
        frequency: maxAge,
        constraints: Constraints(networkType: NetworkType.connected),
        existingWorkPolicy: ExistingWorkPolicy.keep,
        backoffPolicy: BackoffPolicy.exponential,
        backoffPolicyDelay: const Duration(minutes: 15),
      );
    } catch (_) {}
  }

  /// فقط کارهای پس‌زمینه را می‌بندد؛ صف و کش دست‌نخورده می‌مانند.
  static Future<void> stop() async {
    _conn?.cancel();
    _conn = null;
    if (!Platform.isAndroid) return;
    try {
      await Workmanager().cancelByUniqueName(_taskUnique);
      await Notifs.cancelSyncReminder();
    } catch (_) {}
  }
}
