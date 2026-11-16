import 'dart:async';
import 'package:flutter/foundation.dart';
import 'api_client.dart';
import 'offline_queue.dart';
import 'sync_service.dart';

/// heartbeat هر ~۶۰ ثانیه وقتی اپ باز است.
class Live {
  static final ValueNotifier<String> state = ValueNotifier('idle'); // focus|break|idle
  static String? part;
  static Timer? _t;
  static void Function()? onInactive;

  static void start() {
    stop();
    beat();
    _t = Timer.periodic(const Duration(seconds: 60), (_) => beat());
  }

  static void stop() {
    _t?.cancel();
    _t = null;
    state.value = 'idle';
  }

  static Future<void> beat() async {
    try {
      final r = await Api.i.post('/live', body: {'state': state.value, 'part': part});
      if (r['active'] == false) onInactive?.call();
      // سرور جواب داد؛ صف را خالی کن. اگر خالی شد، همگام‌سازی موفق است.
      if (await OfflineQueue.i.flush()) {
        SyncService.markOk();
        SyncService.maybePrefetch(); // هر چند ساعت کش برنامه/آمار تازه شود
      }
    } catch (_) {}
  }
}
