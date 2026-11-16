import 'package:flutter/services.dart';

class AppInfo {
  final String pkg, label;
  const AppInfo(this.pkg, this.label);
}

/// پل به سرویس دسترسی‌پذیری اندروید (فقط اندروید).
class Blocker {
  static const _c = MethodChannel('omid/blocker');

  static Future<T?> _call<T>(String m, [dynamic a]) async {
    try {
      return await _c.invokeMethod<T>(m, a);
    } catch (_) {
      return null;
    }
  }

  /// تا [sec] ثانیه‌ی دیگر «حالت تمرکز» فعال است؛ 0 = غیرفعال. (خودش منقضی می‌شود)
  static Future<void> focus(int sec) => _call('focus', sec);
  static Future<bool> enabled() async => await _call<bool>('enabled') ?? false;
  static Future<void> openSettings() => _call('openSettings');

  static Future<List<AppInfo>> apps() async {
    final r = await _call<List<dynamic>>('apps') ?? [];
    return [for (final x in r) AppInfo(x['pkg'] as String, x['label'] as String)];
  }

  static Future<({Set<String> apps, bool on, bool always})> load() async {
    final r = await _call<Map<dynamic, dynamic>>('get') ?? {};
    return (
      apps: {for (final x in (r['apps'] as List? ?? [])) x as String},
      on: r['on'] == true,
      always: r['always'] == true,
    );
  }

  static Future<void> save(Set<String> apps, bool on, bool always) =>
      _call('save', {'apps': apps.toList(), 'on': on, 'always': always});
}
