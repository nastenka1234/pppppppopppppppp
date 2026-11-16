import 'package:shared_preferences/shared_preferences.dart';
import 'api_client.dart';

/// مهاجرت داده‌ی محلی بین نسخه‌های اپ.
///
/// قانون آپدیت بدون از دست رفتن داده: هر وقت شکل ذخیره‌ی محلی عوض شد، یک مرحله‌ی تازه
/// اینجا اضافه کن (و [current] را بالا ببر). هیچ‌وقت کلیدهای قدیمی را بی‌صدا حذف نکن.
class LocalMigrations {
  static const current = 2;

  static Future<void> run() async {
    final p = await SharedPreferences.getInstance();
    final v = p.getInt('schema_v') ?? 1;
    final sid = Api.i.sid;
    if (v >= current) return;
    if (sid == null) return; // تا وقتی حساب دانش‌آموز مشخص نیست صبر می‌کنیم

    if (v < 2) {
      // نسخه‌ی ۱: پیشرفت و «روز تمام‌شده» بدون شناسه‌ی حساب ذخیره می‌شد (prog:روز، daydone:روز).
      // از این نسخه به بعد برای هر حساب جدا ذخیره می‌شود.
      final re = RegExp(r'^(prog|daydone):(\d{4}-\d{2}-\d{2})$');
      for (final k in p.getKeys().toList()) {
        final m = re.firstMatch(k);
        if (m == null) continue;
        final nk = '${m[1]}:$sid:${m[2]}';
        if (!p.containsKey(nk)) {
          final val = p.get(k);
          if (val is String) await p.setString(nk, val);
          if (val is bool) await p.setBool(nk, val);
        }
        await p.remove(k);
      }
    }
    await p.setInt('schema_v', current);
  }
}
