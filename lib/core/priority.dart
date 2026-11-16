import 'models.dart';

enum PartStatus { done, active, locked }

/// وضعیت یک پارت در قانون اولویت‌ها.
class PartState {
  final int index; // از ۰
  final PlanItem item;
  final PartProgress? pp;
  final PartStatus status;

  /// شماره‌ی اولویتی (از ۱) که این پارت را قفل نگه داشته.
  final int? blockedBy;
  const PartState(this.index, this.item, this.pp, this.status, this.blockedBy);

  int get priority => index + 1;
  bool get optional => index >= Priority.mandatoryMax;
  bool get isDone => status == PartStatus.done;
  bool get isLocked => status == PartStatus.locked;
  bool get isActive => status == PartStatus.active;
  bool get carried => pp?.carried == true && !isDone;
  int get targetMin => item.minutes <= 0 ? 30 : item.minutes;
  int get studiedMin => (pp?.studySeconds ?? 0) ~/ 60;
  int get minNeeded => targetMin < Priority.minStudyMin ? targetMin : Priority.minStudyMin;
  bool get canFinish => studiedMin >= minNeeded;
}

class DayState {
  final List<PartState> parts;
  const DayState(this.parts);

  Iterable<PartState> get mandatory => parts.where((p) => !p.optional);
  int get mandatoryTotal => mandatory.length;
  int get mandatoryDone => mandatory.where((p) => p.isDone).length;
  bool get mandatoryAllDone => mandatoryTotal > 0 && mandatoryDone == mandatoryTotal;

  /// جمع زمان هدف اولویت‌های اصلی و زمانِ مطالعه‌شده‌ی آن‌ها (هر پارت حداکثر تا هدفش).
  int get mandatoryTargetMin => mandatory.fold(0, (a, p) => a + p.item.minutes);
  int get mandatoryStudiedMin => mandatory.fold(0, (a, p) {
        final cap = p.item.minutes <= 0 ? p.studiedMin : p.item.minutes;
        return a + (p.studiedMin > cap ? cap : p.studiedMin);
      });

  /// اولین پارت بازِ تمام‌نشده (پارت جاری).
  PartState? get current {
    for (final p in parts) {
      if (p.isActive) return p;
    }
    return null;
  }
}

class Priority {
  /// اولویت‌های ۱ تا ۴ اصلی‌اند؛ از ۵ به بعد اختیاری است و چیزی را قفل نمی‌کند.
  static const mandatoryMax = 4;

  /// حداقل مطالعه‌ی هر پارت (دقیقه) تا بشود «تموم شد» زد.
  static const minStudyMin = 25;

  /// قانون: اولویت n+1 تا وقتی n «تموم شد» نشده قفل است
  /// (مگر ترتیب اجباری خاموش باشد، یا مشاور آن اولویت را باز/رد کرده باشد).
  static DayState compute(PlanDay plan, Map<String, PartProgress> prog) {
    bool doneAt(int i) => prog[plan.items[i].part]?.done == true;
    final out = <PartState>[];
    for (var i = 0; i < plan.items.length; i++) {
      final pp = prog[plan.items[i].part];
      int? blocker;
      if (plan.forceOrder && !plan.unlocked.contains(i + 1)) {
        for (var j = 0; j < i && j < mandatoryMax; j++) {
          if (!doneAt(j) && !plan.skipped.contains(j + 1)) {
            blocker = j + 1;
            break;
          }
        }
      }
      final st = doneAt(i)
          ? PartStatus.done
          : (blocker != null ? PartStatus.locked : PartStatus.active);
      out.add(PartState(i, plan.items[i], pp, st, blocker));
    }
    return DayState(out);
  }
}
