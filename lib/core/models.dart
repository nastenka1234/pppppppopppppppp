int _i(dynamic v) => v is num ? v.round() : int.tryParse('${v ?? 0}') ?? 0;
Set<int> _ints(dynamic v) => v is List ? {for (final x in v) _i(x)} : <int>{};

class PlanItem {
  String part, subject, note;
  int minutes, testsTarget;
  PlanItem({this.part = '', this.subject = '', this.minutes = 0, this.testsTarget = 0, this.note = ''});
  factory PlanItem.fromJson(Map j) => PlanItem(
        part: '${j['part'] ?? ''}',
        subject: '${j['subject'] ?? ''}',
        minutes: _i(j['minutes']),
        testsTarget: _i(j['tests_target']),
        note: '${j['note'] ?? ''}',
      );
  Map<String, dynamic> toJson() => {
        'part': part,
        'subject': subject,
        'minutes': minutes,
        'tests_target': testsTarget,
        'note': note,
      };
}

class PlanDay {
  final String day, source, note;
  final List<PlanItem> items, base;

  /// قانون اولویت‌ها: ترتیب اجباری (پیش‌فرض روشن). مشاور می‌تواند خاموش کند،
  /// یک اولویت را باز کند (unlocked) یا رد کند (skipped). شماره‌ها از ۱.
  bool forceOrder = true;
  Set<int> unlocked = <int>{}, skipped = <int>{};

  PlanDay(this.day, this.items, this.source, this.note, [this.base = const []]);
  factory PlanDay.fromJson(Map j) => PlanDay(
        '${j['day'] ?? ''}',
        [for (final x in (j['items'] as List? ?? [])) PlanItem.fromJson(x)],
        '${j['source'] ?? 'none'}',
        '${j['note'] ?? ''}',
        [for (final x in (j['base'] as List? ?? [])) PlanItem.fromJson(x)],
      )
        ..forceOrder = !(j['force_order'] == false || j['force_order'] == 0)
        ..unlocked = _ints(j['unlocked'])
        ..skipped = _ints(j['skipped']);
}

class PartProgress {
  int studySeconds, tests, correct;
  bool done;
  String note;

  /// فقط محلی (به سرور نمی‌رود مگر Config.sendPriorityFields روشن باشد):
  /// «نصفه موند»، اینکه تعداد درست‌ها را دانش‌آموز گفته یا نه، و زمان «تموم شد».
  bool carried, correctKnown;
  String doneAt;

  PartProgress({
    this.studySeconds = 0,
    this.tests = 0,
    this.correct = 0,
    this.done = false,
    this.note = '',
    this.carried = false,
    this.correctKnown = false,
    this.doneAt = '',
  });
  factory PartProgress.fromJson(Map j) => PartProgress(
        studySeconds: _i(j['study_seconds']),
        tests: _i(j['tests']),
        correct: _i(j['correct']),
        done: j['done'] == true || j['done'] == 1,
        note: '${j['note'] ?? ''}',
        carried: j['carried'] == true,
        // پیشرفت‌های قدیمی (بدون این کلید): اگر درست ثبت شده، یعنی گفته شده
        correctKnown: j['correct_known'] == true || (j['correct_known'] == null && _i(j['correct']) > 0),
        doneAt: '${j['done_at'] ?? ''}',
      );

  /// شکل قدیمی و امن برای سرور (/progress و /report).
  Map<String, dynamic> toJson() => {
        'study_seconds': studySeconds,
        'tests': tests,
        'correct': correct,
        'done': done,
        'note': note,
      };

  /// ذخیره‌ی محلی (شامل فیلدهای اضافه).
  Map<String, dynamic> toLocal() => {
        ...toJson(),
        'carried': carried,
        'correct_known': correctKnown,
        'done_at': doneAt,
      };

  double get percent => tests == 0 ? 0 : correct * 100 / tests;
}

class Track {
  final String id, title, tag, url;
  final int duration;
  Track(this.id, this.title, this.tag, this.url, this.duration);
  factory Track.fromJson(Map j) => Track('${j['id']}', '${j['title'] ?? ''}', '${j['tag'] ?? ''}',
      '${j['url'] ?? ''}', _i(j['duration_sec']));
}

class FocusVideo {
  final String id, title, url;
  FocusVideo(this.id, this.title, this.url);
  factory FocusVideo.fromJson(Map j) => FocusVideo('${j['id']}', '${j['title'] ?? ''}', '${j['url'] ?? ''}');
}

class DayStat {
  final String day;
  final int studyMin, partMin, focusMin, tests, correct;
  DayStat(this.day, this.studyMin, this.partMin, this.focusMin, this.tests, this.correct);
  factory DayStat.fromJson(Map j) => DayStat('${j['day']}', _i(j['study_min']), _i(j['part_min']),
      _i(j['focus_room_min']), _i(j['tests']), _i(j['correct']));
}

class PartStat {
  final String part;
  final int tests, correct, minutes;
  PartStat(this.part, this.tests, this.correct, this.minutes);
  factory PartStat.fromJson(Map j) =>
      PartStat('${j['part']}', _i(j['tests']), _i(j['correct']), _i(j['minutes']));
  double get percent => tests == 0 ? 0 : correct * 100 / tests;
}

class Stats {
  final List<DayStat> days;
  final List<PartStat> parts;
  final int totalMin, totalTests;
  Stats(this.days, this.parts, this.totalMin, this.totalTests);
  factory Stats.fromJson(Map j) => Stats(
        [for (final x in (j['days'] as List? ?? [])) DayStat.fromJson(x)],
        [for (final x in (j['parts'] as List? ?? [])) PartStat.fromJson(x)],
        _i((j['totals'] ?? {})['study_min']),
        _i((j['totals'] ?? {})['tests']),
      );
}
