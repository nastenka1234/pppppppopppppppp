import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_client.dart';
import 'config.dart';
import 'jalali.dart';
import 'models.dart';
import 'offline_queue.dart';

/// پیشرفت امروز به‌صورت محلی نگه داشته می‌شود و **مقدار کل** هر بار به /progress می‌رود.
class ProgressStore {
  // کلیدها با شناسه‌ی حساب جدا می‌شوند تا دو دانش‌آموز روی یک گوشی داده‌ی هم را نبینند/نفرستند.
  static String _k(String day) => 'prog:${Api.i.sid ?? '_'}:$day';
  static String _dd(String day) => 'daydone:${Api.i.sid ?? '_'}:$day';

  static Future<Map<String, PartProgress>> load(String day) async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_k(day));
    if (raw == null) return {};
    final m = jsonDecode(raw) as Map;
    return {for (final e in m.entries) '${e.key}': PartProgress.fromJson(e.value as Map)};
  }

  /// [priority] (شماره‌ی ۱ تا ۵) فقط وقتی Config.sendPriorityFields روشن است به سرور می‌رود.
  static Future<PartProgress> update(String day, String part, void Function(PartProgress) fn,
      {bool send = true, int? priority}) async {
    final all = await load(day);
    final pp = all[part] ?? PartProgress();
    fn(pp);
    all[part] = pp;
    final p = await SharedPreferences.getInstance();
    await p.setString(_k(day), jsonEncode({for (final e in all.entries) e.key: e.value.toLocal()}));
    if (send) {
      final body = <String, dynamic>{'day': day, 'part': part, ...pp.toJson()};
      if (Config.sendPriorityFields) {
        body['priority'] = priority;
        body['status'] = pp.done ? 'done' : (pp.carried ? 'carried' : 'in_progress');
        body['carried'] = pp.carried;
        body['done_at'] = pp.doneAt;
      }
      try {
        await OfflineQueue.i.send('/progress', body, key: 'progress:$day:$part');
      } catch (_) {}
    }
    return pp;
  }

  // ---- روزهای پیاپی (محلی): روزی که همه‌ی اولویت‌های اصلی‌اش تموم شده ----
  static Future<void> markDayDone(String day) async {
    final p = await SharedPreferences.getInstance();
    if (p.getBool(_dd(day)) != true) await p.setBool(_dd(day), true);
  }

  static Future<int> streak(String today) async {
    final p = await SharedPreferences.getInstance();
    var d = today;
    if (p.getBool(_dd(d)) != true) d = addDays(d, -1);
    var n = 0;
    while (p.getBool(_dd(d)) == true && n < 400) {
      n++;
      d = addDays(d, -1);
    }
    return n;
  }
}
