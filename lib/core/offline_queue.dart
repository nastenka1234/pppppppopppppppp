import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_client.dart';

/// صف آفلاین برای /progress، /report، /focus/session.
///
/// قواعد ایمنی داده:
/// - هر مورد با شناسه‌ی دانش‌آموز (sid) ذخیره می‌شود؛ با حساب دیگر فرستاده نمی‌شود.
/// - فقط وقتی از صف حذف می‌شود که سرور «ok» داده باشد.
/// - خطای موقت (اینترنت، ۵xx، ۴۲۹، ۴۰۱ توکن منقضی، ۴۰۳) هیچ‌وقت داده را دور نمی‌ریزد.
/// - خطای دائمی (مثلاً ۴۰۰) به «صندوق خطا» می‌رود، نه سطل آشغال.
/// - خروج از حساب و آپدیت اپ صف را پاک نمی‌کند.
class OfflineQueue {
  OfflineQueue._();
  static final OfflineQueue i = OfflineQueue._();

  static const _maxItems = 2000;
  final List<Map<String, dynamic>> _q = [];
  final List<Map<String, dynamic>> _dead = [];
  final ValueNotifier<int> pending = ValueNotifier(0);
  bool _busy = false;

  int get deadCount => _dead.length;

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    _q
      ..clear()
      ..addAll(_decode(p.getString('offline_q')));
    _dead
      ..clear()
      ..addAll(_decode(p.getString('offline_dead')));
    _count();
  }

  static List<Map<String, dynamic>> _decode(String? raw) {
    if (raw == null) return [];
    try {
      return (jsonDecode(raw) as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (_) {
      return [];
    }
  }

  void _count() {
    final sid = Api.i.sid;
    pending.value = _q.where((e) => e['sid'] == null || e['sid'] == sid).length;
  }

  /// بعد از ورود/خروج صدا بزن تا شمارنده‌ی صف برای حساب فعلی درست شود.
  void refreshCount() => _count();

  Future<void> _save() async {
    final p = await SharedPreferences.getInstance();
    await p.setString('offline_q', jsonEncode(_q));
    await p.setString('offline_dead', jsonEncode(_dead));
    _count();
  }

  bool _same(Map<String, dynamic> e, String? key, String? sid) =>
      key != null && e['key'] == key && e['sid'] == sid;

  Future<void> _enqueue(String path, Map<String, dynamic> body, String? key, String? sid) async {
    if (key != null) _q.removeWhere((x) => _same(x, key, sid)); // upsert: فقط آخرین مقدار
    _q.add({'path': path, 'body': body, 'key': key, 'sid': sid, 'at': DateTime.now().toUtc().toIso8601String()});
    if (_q.length > _maxItems) _q.removeRange(0, _q.length - _maxItems);
    await _save();
  }

  Future<void> _bury(String path, Map<String, dynamic> body, String? key, String? sid, String err) async {
    _dead.add({'path': path, 'body': body, 'key': key, 'sid': sid, 'err': err, 'at': DateTime.now().toUtc().toIso8601String()});
    if (_dead.length > 100) _dead.removeAt(0);
    await _save();
  }

  /// می‌فرستد؛ اگر نشد صف می‌کند. true یعنی همین الان به سرور رسید.
  /// [key]: برای upsert (فقط آخرین مقدار هر کلید نگه داشته می‌شود).
  Future<bool> send(String path, Map<String, dynamic> body, {String? key}) async {
    final sid = Api.i.sid;
    try {
      await Api.i.post(path, body: body);
      // مقدار قدیمی‌تر همین کلید که در صف مانده بود دیگر نباید فرستاده شود (روی مقدار جدید می‌نشست).
      if (key != null && _q.any((x) => _same(x, key, sid))) {
        _q.removeWhere((x) => _same(x, key, sid));
        await _save();
      }
      return true;
    } on ApiError catch (e) {
      if (e.isRetryable) {
        await _enqueue(path, body, key, sid);
        return false;
      }
      await _bury(path, body, key, sid, e.code);
      rethrow;
    }
  }

  /// صف حساب فعلی را می‌فرستد. true یعنی چیزی برای این حساب باقی نماند.
  Future<bool> flush() async {
    final sid = Api.i.sid;
    if (sid == null) return false; // ادمین یا وارد‌نشده
    if (_busy) return false;
    _busy = true;
    try {
      // موارد قدیمی (قبل از این نسخه) صاحب نداشتند؛ مال همین گوشی/حساب‌اند.
      var claimed = false;
      for (final e in _q) {
        if (e['sid'] == null) {
          e['sid'] = sid;
          claimed = true;
        }
      }
      if (claimed) await _save();

      while (true) {
        Map<String, dynamic>? e;
        for (final x in _q) {
          if (x['sid'] == sid) {
            e = x;
            break;
          }
        }
        if (e == null) return true;
        try {
          await Api.i.post('${e['path']}', body: Map<String, dynamic>.from(e['body'] as Map));
          _q.remove(e); // با شناسه‌ی شیء؛ اگر وسط کار send() صف را عوض کرده باشد اشتباه حذف نمی‌شود
          await _save();
        } on ApiError catch (x) {
          if (x.isRetryable) return false;
          _q.remove(e);
          _dead.add({...e, 'err': x.code});
          if (_dead.length > 100) _dead.removeAt(0);
          await _save();
        }
      }
    } finally {
      _busy = false;
    }
  }
}
