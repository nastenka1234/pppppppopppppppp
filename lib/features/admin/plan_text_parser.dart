import 'package:shamsi_date/shamsi_date.dart';

import '../../core/jalali.dart';
import '../../core/models.dart';

class ParsedPlanText {
  final Map<String, List<PlanItem>> days;
  final List<String> errors;

  const ParsedPlanText(this.days, this.errors);

  bool get isValid => errors.isEmpty && days.isNotEmpty;
  int get partCount => days.values.fold<int>(0, (sum, items) => sum + items.length);
}

/// Converts the admin's command-based weekly text into the same PlanItem model
/// used by the regular one-by-one editor.
class PlanTextParser {
  static const maxParts = 5;

  static ParsedPlanText parse(String source, List<String> availableDays) {
    final output = <String, List<PlanItem>>{};
    final errors = <String>[];
    String? activeDay;
    Map<String, dynamic>? current;
    final seen = <String>{};
    String? lastField;
    int partLine = 0;

    void flush() {
      if (current == null) return;
      final name = '${current!['part'] ?? ''}'.trim();
      if (name.isEmpty) {
        errors.add('خط $partLine: نام پارت خالی است.');
      } else if (activeDay != null) {
        final list = output.putIfAbsent(activeDay!, () => <PlanItem>[]);
        if (list.length >= maxParts) {
          errors.add('خط $partLine: برای ${jalaliFull(activeDay!)} بیشتر از ${fa(maxParts)} پارت مجاز نیست.');
        } else {
          list.add(PlanItem(
            part: name,
            subject: '${current!['subject'] ?? ''}'.trim(),
            minutes: current!['minutes'] as int? ?? 0,
            testsTarget: current!['tests'] as int? ?? 0,
            note: '${current!['note'] ?? ''}'.trim(),
          ));
        }
      }
      current = null;
      seen.clear();
      lastField = null;
    }

    final lines = source.replaceAll('\r\n', '\n').replaceAll('\r', '\n').split('\n');
    for (var index = 0; index < lines.length; index++) {
      final lineNumber = index + 1;
      final line = lines[index].trim();
      if (line.isEmpty) continue;

      final command = _readCommand(line);
      if (command == null) {
        if (line.startsWith('/') || line.startsWith('#')) {
          errors.add('خط $lineNumber: دستور شناخته نشد.');
        } else if (current != null && lastField == 'note') {
          final before = '${current!['note'] ?? ''}';
          current!['note'] = before.isEmpty ? line : '$before\n$line';
        } else {
          errors.add('خط $lineNumber: هر خط باید با یک دستور شروع شود.');
        }
        continue;
      }

      final key = command.key;
      final value = command.value.trim();
      if (key == 'day') {
        flush();
        final resolved = _resolveDay(value, availableDays);
        if (resolved == null) {
          errors.add('خط $lineNumber: روز «$value» در این بازه‌ی هفت‌روزه پیدا نشد. از نام روز یا تاریخ شمسی استفاده کن.');
          activeDay = null;
        } else {
          activeDay = resolved;
          output.putIfAbsent(resolved, () => <PlanItem>[]);
        }
        continue;
      }

      if (key == 'part') {
        flush();
        if (activeDay == null) {
          errors.add('خط $lineNumber: قبل از تعریف پارت، باید دستور /روز را بنویسی.');
          continue;
        }
        current = {'part': value, 'minutes': 60, 'tests': 0, 'subject': '', 'note': ''};
        seen.add('part');
        partLine = lineNumber;
        lastField = 'part';
        continue;
      }

      if (current == null) {
        errors.add('خط $lineNumber: این فیلد باید بعد از دستور /پارت بیاید.');
        continue;
      }

      if (seen.contains(key)) {
        errors.add('خط $lineNumber: دستور این فیلد برای همین پارت تکرار شده است.');
        continue;
      }
      seen.add(key);

      switch (key) {
        case 'subject':
          current!['subject'] = value;
          break;
        case 'minutes':
        case 'tests':
          final parsed = int.tryParse(_asciiDigits(value.trim()));
          final max = key == 'minutes' ? 360 : 500;
          if (parsed == null || parsed < 0 || parsed > max) {
            errors.add('خط $lineNumber: مقدار ${key == 'minutes' ? 'دقیقه' : 'تست'} باید بین ۰ تا ${fa(max)} باشد.');
            seen.remove(key);
          } else {
            current![key] = parsed;
          }
          break;
        case 'note':
          current!['note'] = value;
          break;
      }
      lastField = key;
    }

    flush();
    if (output.isEmpty && errors.isEmpty) errors.add('هیچ روزی در متن پیدا نشد.');
    return ParsedPlanText(output, errors);
  }

  static _Command? _readCommand(String line) {
    final trimmed = line.trim();
    String name;
    String value;

    if (trimmed.startsWith('/') || trimmed.startsWith('#')) {
      final body = trimmed.substring(1).trimLeft();
      final split = body.indexOf(RegExp(r'\s'));
      if (split < 0) return null;
      name = body.substring(0, split);
      value = body.substring(split + 1).trim();
    } else {
      final split = trimmed.indexOf(RegExp(r'[:：=]'));
      if (split < 0) return null;
      name = trimmed.substring(0, split).trim();
      value = trimmed.substring(split + 1).trim();
    }

    final normalized = _normalize(name).replaceAll(' ', '_');
    const aliases = <String, String>{
      'روز': 'day',
      'day': 'day',
      'پارت': 'part',
      'part': 'part',
      'عنوان': 'part',
      'درس': 'subject',
      'subject': 'subject',
      'دقیقه': 'minutes',
      'زمان': 'minutes',
      'مدت': 'minutes',
      'minutes': 'minutes',
      'تست': 'tests',
      'هدف_تست': 'tests',
      'هدفتست': 'tests',
      'تعداد_تست': 'tests',
      'tests': 'tests',
      'توضیح': 'note',
      'یادداشت': 'note',
      'note': 'note',
    };
    final key = aliases[normalized];
    return key == null ? null : _Command(key, value);
  }

  static String? _resolveDay(String raw, List<String> availableDays) {
    final value = _normalize(raw);
    if (value.isEmpty) return null;
    final requestedWeekday = value.replaceAll(' ', '');
    for (final date in availableDays) {
      final fullLabel = _normalize(jalaliFull(date)).replaceAll(' ', '');
      if (fullLabel.startsWith(requestedWeekday)) return date;
    }

    final match = RegExp(r'^(\d{4})[-/](\d{1,2})[-/](\d{1,2})$').firstMatch(_asciiDigits(value));
    if (match == null) return null;
    final year = int.parse(match.group(1)!);
    final month = int.parse(match.group(2)!);
    final day = int.parse(match.group(3)!);
    try {
      final DateTime date;
      if (year < 1700) {
        date = Jalali(year, month, day).toDateTime();
        final check = Jalali.fromDateTime(date);
        if (check.year != year || check.month != month || check.day != day) return null;
      } else {
        date = DateTime.utc(year, month, day);
        if (date.year != year || date.month != month || date.day != day) return null;
      }
      final iso = isoDay(date);
      return availableDays.contains(iso) ? iso : null;
    } catch (_) {
      return null;
    }
  }

  static String _normalize(String value) => value
      .trim()
      .replaceAll('ي', 'ی')
      .replaceAll('ك', 'ک')
      .replaceAll('\u200c', '')
      .replaceAll(RegExp(r'\s+'), ' ');

  static String _asciiDigits(String value) => value
      .replaceAll('۰', '0')
      .replaceAll('۱', '1')
      .replaceAll('۲', '2')
      .replaceAll('۳', '3')
      .replaceAll('۴', '4')
      .replaceAll('۵', '5')
      .replaceAll('۶', '6')
      .replaceAll('۷', '7')
      .replaceAll('۸', '8')
      .replaceAll('۹', '9')
      .replaceAll('٠', '0')
      .replaceAll('١', '1')
      .replaceAll('٢', '2')
      .replaceAll('٣', '3')
      .replaceAll('٤', '4')
      .replaceAll('٥', '5')
      .replaceAll('٦', '6')
      .replaceAll('٧', '7')
      .replaceAll('٨', '8')
      .replaceAll('٩', '9');
}

class _Command {
  final String key;
  final String value;
  const _Command(this.key, this.value);
}
