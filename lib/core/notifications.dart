import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

class Notifs {
  static final _p = FlutterLocalNotificationsPlugin();

  static bool _ready = false;

  /// [askPermission] در پس‌زمینه (WorkManager) false است.
  static Future<void> init({bool askPermission = true}) async {
    if (_ready) return;
    _ready = true;
    tzdata.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Asia/Tehran'));
    await _p.initialize(const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher')));
    if (askPermission) {
      await _p
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
    }
  }

  static Future<void> scheduleDaily() async {
    // فقط یادآوری‌های روزانه؛ یادآوری همگام‌سازی (شناسه‌ی ۳) دست نمی‌خورد.
    await _p.cancel(1);
    await _p.cancel(2);
    await _at(1, 7, 0, 'برنامه‌ی امروزت آماده است', 'اپ را باز کن و پارت اول را شروع کن.');
    await _at(2, 21, 30, 'وقت گزارشکار شبانه', 'تست‌ها و حال امروزت را ثبت کن تا برنامه‌ی فردا تنظیم شود.');
  }

  static Future<void> cancel() => _p.cancelAll();

  /// یادآوری «همگام‌سازی لازم است»: بعد از هر همگام‌سازی موفق دوباره ۶ ساعت جلو می‌رود؛
  /// پس فقط وقتی نمایش داده می‌شود که ۶ ساعت بدون همگام‌سازی گذشته باشد.
  static Future<void> scheduleSyncReminder(Duration after) async {
    final when = tz.TZDateTime.now(tz.local).add(after);
    await _p.zonedSchedule(
      3,
      'اطلاعاتت هنوز ارسال نشده',
      'بیش از ۶ ساعت است اینترنت وصل نشده. اپ را با اینترنت باز کن تا پیشرفتت ذخیره شود.',
      when,
      const NotificationDetails(
        android: AndroidNotificationDetails('sync', 'همگام‌سازی',
            importance: Importance.defaultImportance, priority: Priority.defaultPriority),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
    );
  }

  static Future<void> cancelSyncReminder() => _p.cancel(3);

  static Future<void> _at(int id, int h, int m, String title, String body) async {
    final now = tz.TZDateTime.now(tz.local);
    var when = tz.TZDateTime(tz.local, now.year, now.month, now.day, h, m);
    if (when.isBefore(now)) when = when.add(const Duration(days: 1));
    await _p.zonedSchedule(
      id,
      title,
      body,
      when,
      const NotificationDetails(
        android: AndroidNotificationDetails('daily', 'یادآوری‌ها',
            importance: Importance.high, priority: Priority.high),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }
}
