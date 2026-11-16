import 'package:shamsi_date/shamsi_date.dart';

const _digits = '۰۱۲۳۴۵۶۷۸۹';
String fa(Object? v) =>
    '$v'.replaceAllMapped(RegExp(r'\d'), (m) => _digits[int.parse(m[0]!)]);

/// وقت تهران (بدون DST).
DateTime tehranNow() => DateTime.now().toUtc().add(const Duration(hours: 3, minutes: 30));

String isoDay(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
String todayIso() => isoDay(tehranNow());

/// قفل نمایش برنامه‌ی دانش‌آموز: فقط برنامه‌ی تاریخ جاری تهران، از ساعت ۰۱:۰۰ همان روز باز است.
/// این قاعده در کلاینت است و برای قفل امنیتیِ قابل اتکا باید در Worker هم بررسی شود.
bool isPlanDayUnlocked(String day, [DateTime? at]) {
  final now = at ?? tehranNow();
  return day == isoDay(now) && now.hour >= 1;
}
DateTime parseIso(String iso) {
  final p = iso.split('-').map(int.parse).toList();
  return DateTime.utc(p[0], p[1], p[2]);
}

String addDays(String iso, int n) => isoDay(parseIso(iso).add(Duration(days: n)));

String jalaliShort(String iso) {
  final j = Jalali.fromDateTime(parseIso(iso));
  return '${fa(j.day)} ${j.formatter.mN}';
}

String jalaliFull(String iso) {
  final j = Jalali.fromDateTime(parseIso(iso));
  return '${j.formatter.wN} ${fa(j.day)} ${j.formatter.mN}';
}

String fmtMin(num m) {
  final t = m.round();
  if (t < 60) return '${fa(t)} دقیقه';
  final h = t ~/ 60, r = t % 60;
  return r == 0 ? '${fa(h)} ساعت' : '${fa(h)} ساعت و ${fa(r)} دقیقه';
}

String clock(int sec) {
  final m = (sec ~/ 60).toString().padLeft(2, '0');
  final s = (sec % 60).toString().padLeft(2, '0');
  return fa('$m:$s');
}

/// epoch (ثانیه/میلی‌ثانیه) یا رشته‌ی ISO.
DateTime? parseTs(dynamic v) {
  if (v == null) return null;
  if (v is num) {
    final n = v.toInt();
    return DateTime.fromMillisecondsSinceEpoch(n > 100000000000 ? n : n * 1000, isUtc: true);
  }
  final s = '$v'.trim();
  if (s.isEmpty) return null;
  final asNum = num.tryParse(s);
  if (asNum != null) return parseTs(asNum);
  var d = DateTime.tryParse(s);
  if (d != null && !d.isUtc && !s.contains('Z') && !s.contains('+')) d = DateTime.utc(d.year, d.month, d.day, d.hour, d.minute, d.second);
  return d?.toUtc();
}

String ago(DateTime? t, [DateTime? now]) {
  if (t == null) return '—';
  final s = (now ?? DateTime.now().toUtc()).difference(t).inSeconds;
  if (s < 60) return 'همین الان';
  if (s < 3600) return '${fa(s ~/ 60)} دقیقه پیش';
  if (s < 86400) return '${fa(s ~/ 3600)} ساعت پیش';
  return '${fa(s ~/ 86400)} روز پیش';
}
