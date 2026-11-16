import 'dart:async';
import 'package:flutter/material.dart';
import '../core/api_client.dart';
import '../core/jalali.dart';
import '../core/offline_queue.dart';
import '../core/sync_service.dart';
import '../theme/glass.dart';
import '../theme/tokens.dart';

/// نوار وضعیت همگام‌سازی (بالای همه‌ی تب‌های دانش‌آموز):
/// ۱) بیش از ۶ ساعت همگام نشده ← هشدار + دکمه
/// ۲) چیزی در صف ارسال است ← اطلاع
/// ۳) داده از حافظه‌ی گوشی نشان داده می‌شود ← اطلاع
class SyncBanner extends StatefulWidget {
  const SyncBanner({super.key});
  @override
  State<SyncBanner> createState() => _SyncBannerState();
}

class _SyncBannerState extends State<SyncBanner> {
  Timer? _t;

  @override
  void initState() {
    super.initState();
    // هر دقیقه دوباره حساب کن (گذشت زمان بدون هیچ رویداد دیگری هم باید هشدار بدهد)
    _t = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  String _ago() {
    final t = SyncService.lastOk.value;
    if (t == null) return 'هنوز';
    final h = DateTime.now().difference(t).inHours;
    return h < 1 ? 'کمی پیش' : '${fa(h)} ساعت پیش';
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        SyncService.lastOk,
        SyncService.running,
        OfflineQueue.i.pending,
        Api.i.offlineData,
      ]),
      builder: (context, _) {
        final n = OfflineQueue.i.pending.value;
        final busy = SyncService.running.value;
        String? text;
        Color color = T.tx2;
        var showBtn = false;
        if (SyncService.stale) {
          text = 'آخرین همگام‌سازی: ${_ago()}. اینترنت را وصل کن تا اطلاعاتت ارسال شود.';
          color = T.warn;
          showBtn = true;
        } else if (n > 0) {
          text = '${fa(n)} مورد روی گوشی ذخیره شده و با اینترنت ارسال می‌شود.';
          showBtn = true;
        } else if (Api.i.offlineData.value) {
          text = 'آفلاین هستی؛ آخرین اطلاعات ذخیره‌شده نمایش داده می‌شود.';
        }
        if (text == null) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Glass(
            radius: 12,
            borderColor: color == T.warn ? T.warn : null,
            padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
            child: Row(children: [
              Icon(color == T.warn ? Icons.cloud_off_rounded : Icons.cloud_queue_rounded, size: 18, color: color),
              const SizedBox(width: 8),
              Expanded(child: Text(text, style: TextStyle(color: color, fontSize: 12.5))),
              if (showBtn)
                TextButton(
                  onPressed: busy ? null : () => SyncService.run(force: true),
                  child: busy
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('همگام‌سازی'),
                ),
            ]),
          ),
        );
      },
    );
  }
}
