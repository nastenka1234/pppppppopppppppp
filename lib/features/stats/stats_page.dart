import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/api_client.dart';
import '../../core/jalali.dart';
import '../../core/models.dart';
import '../../theme/glass.dart';
import '../../theme/tokens.dart';
import '../../theme/lottie_views.dart';
import '../../theme/striped_bar.dart';
import 'dart:math' as math;
import '../messenger/floating_messenger.dart';
import '../report/weekly_report_pdf.dart';

final statsProvider =
    FutureProvider.autoDispose.family<Stats, (int, String?)>((ref, key) async {
  final r = await Api.i.getC('/stats', q: sq(key.$2, {'range': key.$1}));
  return Stats.fromJson(r);
});

/// برنامه‌ی ۶۰ روز آینده (اگر سرور پشتیبانی نکند خالی برمی‌گردد و بخش مربوطه پنهان می‌شود).
final futurePlanProvider = FutureProvider.autoDispose<List<PlanDay>>((ref) async {
  try {
    final r = await Api.i.getC('/plan', q: {'day': todayIso(), 'days': 60});
    final l = r['plans'] as List?;
    return l == null ? [] : [for (final x in l) PlanDay.fromJson(x)];
  } catch (_) {
    return [];
  }
});

class StatsPage extends StatelessWidget {
  const StatsPage({super.key});
  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: const [PageTitle('آمار'), StatsView()],
      );
}

/// برای دانش‌آموز (studentId == null) و ادمین (با ?student=).
class StatsView extends ConsumerStatefulWidget {
  final String? studentId;
  const StatsView({super.key, this.studentId});
  @override
  ConsumerState<StatsView> createState() => _StatsViewState();
}

class _StatsViewState extends ConsumerState<StatsView> {
  int range = 7;
  bool _sendingWeekly = false;
  static const _ranges = [(3, '۳ روز'), (7, 'هفته'), (30, 'ماه'), (90, '۳ ماه')];

  Future<void> _sendWeeklyReport() async {
    if (_sendingWeekly) return;
    setState(() => _sendingWeekly = true);
    try {
      await WeeklyReportSender.send();
      if (!mounted) return;
      MessengerLauncher.show(refresh: true);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('گزارش هفتگی به پیام‌رسان ارسال شد')));
    } on ApiError catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.fa)));
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('ساخت یا ارسال گزارش ناموفق بود')));
    } finally {
      if (mounted) setState(() => _sendingWeekly = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final st = ref.watch(statsProvider((range, widget.studentId)));
    return Column(children: [
      Wrap(spacing: 8, children: [
        for (final r in _ranges)
          ChoiceChip(
            label: Text(r.$2),
            selected: range == r.$1,
            onSelected: (_) => setState(() => range = r.$1),
            selectedColor: T.acc,
            backgroundColor: T.glass,
            side: const BorderSide(color: T.line),
            labelStyle: TextStyle(
                fontFamily: 'Vazirmatn',
                fontWeight: FontWeight.w700,
                color: range == r.$1 ? T.bg : T.tx),
            showCheckmark: false,
          ),
      ]),
      if (widget.studentId == null) ...[
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _sendingWeekly ? null : _sendWeeklyReport,
            icon: _sendingWeekly
                ? const SizedBox(width: 17, height: 17, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.picture_as_pdf_rounded),
            label: Text(_sendingWeekly ? 'در حال ساخت و ارسال PDF...' : 'ارسال گزارش هفتگی به مشاور'),
            style: OutlinedButton.styleFrom(
              foregroundColor: T.acc,
              side: BorderSide(color: T.acc.withOpacity(.55)),
              padding: const EdgeInsets.symmetric(vertical: 13),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
            ),
          ),
        ),
      ],
      const SizedBox(height: 12),
      st.when(
        loading: () => const AppLoader(),
        error: (e, _) => ErrorState(e is ApiError ? e.fa : 'خطا در دریافت آمار',
            onRetry: () => ref.invalidate(statsProvider((range, widget.studentId)))),
        data: (s) => Column(children: [
          Row(children: [
            Expanded(child: _Total('جمع مطالعه', fmtMin(s.totalMin))),
            const SizedBox(width: 10),
            Expanded(child: _Total('جمع تست', fa(s.totalTests))),
          ]),
          const SizedBox(height: 12),
          _Highlights(s),
          const SizedBox(height: 12),
          _Journey(studiedMin: s.totalMin),
          const SizedBox(height: 12),
          _ChartCard(
            title: 'ساعت مطالعه',
            days: s.days,
            bars: (d) => [(d.studyMin / 60, T.acc)],
            unit: 'ساعت',
          ),
          const SizedBox(height: 12),
          _ChartCard(
            title: 'تعداد تست',
            days: s.days,
            bars: (d) => [(d.tests.toDouble(), T.acc), (d.correct.toDouble(), T.hi)],
            unit: 'تست',
          ),
          const SizedBox(height: 12),
          _AccuracyCard(s.days),
          const SizedBox(height: 12),
          _PartBars(s.parts),
          const SizedBox(height: 12),
          Glass(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('جمع هر پارت', style: TextStyle(fontWeight: FontWeight.w900)),
              const SizedBox(height: 8),
              if (s.parts.isEmpty) const Text('داده‌ای نیست', style: TextStyle(color: T.tx2)),
              for (final p in s.parts)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(children: [
                    Expanded(flex: 3, child: Text(p.part)),
                    Expanded(
                        flex: 2,
                        child: Text('${fa(p.tests)} تست',
                            style: const TextStyle(color: T.tx2, fontSize: 13))),
                    Expanded(
                        flex: 2,
                        child: Text('${fa(p.percent.round())}٪ درست',
                            style: const TextStyle(color: T.hi, fontSize: 13))),
                    Expanded(
                        flex: 3,
                        child: Text(fmtMin(p.minutes),
                            style: const TextStyle(color: T.tx2, fontSize: 13))),
                  ]),
                ),
            ]),
          ),
        ]),
      ),
    ]);
  }
}

class _Total extends StatelessWidget {
  final String label, value;
  const _Total(this.label, this.value);
  @override
  Widget build(BuildContext context) => Glass(
        radius: 24,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(color: T.tx2, fontSize: 12)),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
        ]),
      );
}

class _ChartCard extends StatelessWidget {
  final String title, unit;
  final List<DayStat> days;
  final List<(double, Color)> Function(DayStat) bars;
  const _ChartCard({required this.title, required this.days, required this.bars, required this.unit});

  @override
  Widget build(BuildContext context) {
    final n = days.length;
    final rodW = n <= 7 ? 14.0 : (n <= 30 ? 5.0 : 2.0);
    final step = n <= 7 ? 1 : (n <= 30 ? 5 : 15);
    double maxY = 1;
    for (final d in days) {
      for (final b in bars(d)) {
        if (b.$1 > maxY) maxY = b.$1;
      }
    }
    return Glass(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
        const SizedBox(height: 14),
        SizedBox(
          height: 170,
          child: days.isEmpty
              ? const Center(child: Text('داده‌ای نیست', style: TextStyle(color: T.tx2)))
              : BarChart(BarChartData(
                  maxY: maxY * 1.15,
                  gridData: FlGridData(
                      drawVerticalLine: false,
                      getDrawingHorizontalLine: (_) => const FlLine(color: T.line, strokeWidth: .5)),
                  borderData: FlBorderData(show: false),
                  titlesData: FlTitlesData(
                    topTitles: const AxisTitles(),
                    rightTitles: const AxisTitles(),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 30,
                        getTitlesWidget: (v, m) => Text(
                            fa(v == v.roundToDouble() ? v.round() : v.toStringAsFixed(1)),
                            style: const TextStyle(color: T.tx2, fontSize: 10)),
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 22,
                        getTitlesWidget: (v, _) {
                          final i = v.toInt();
                          if (i < 0 || i >= n || (n - 1 - i) % step != 0) return const SizedBox.shrink();
                          final j = jalaliShort(days[i].day).split(' ').first;
                          return Text(j, style: const TextStyle(color: T.tx2, fontSize: 10));
                        },
                      ),
                    ),
                  ),
                  barGroups: [
                    for (var i = 0; i < n; i++)
                      BarChartGroupData(x: i, barsSpace: 2, barRods: [
                        for (final b in bars(days[i]))
                          BarChartRodData(
                              toY: b.$1,
                              color: b.$2,
                              width: rodW,
                              borderRadius: BorderRadius.circular(rodW > 6 ? 6 : 1)),
                      ]),
                  ],
                )),
        ),
      ]),
    );
  }
}

class _Highlights extends StatelessWidget {
  final Stats s;
  const _Highlights(this.s);
  @override
  Widget build(BuildContext context) {
    final active = s.days.where((d) => d.studyMin > 0).toList();
    final best = active.isEmpty ? null : active.reduce((a, b) => a.studyMin >= b.studyMin ? a : b);
    final avg = active.isEmpty ? 0 : s.totalMin ~/ active.length;
    final tests = s.days.fold<int>(0, (a, d) => a + d.tests), ok = s.days.fold<int>(0, (a, d) => a + d.correct);
    final acc = tests == 0 ? 0 : (ok * 100 / tests).round();
    Widget c(String l, String v, IconData i) => Expanded(
          child: Glass(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(i, size: 18, color: T.acc),
              const SizedBox(height: 8),
              FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(v, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900))),
              const SizedBox(height: 2),
              Text(l, style: const TextStyle(color: T.tx2, fontSize: 11)),
            ]),
          ),
        );
    return Row(children: [
      c('روز فعال', '${fa(active.length)} از ${fa(s.days.length)}', Icons.local_fire_department_rounded),
      const SizedBox(width: 8),
      c('میانگین روزانه', fmtMin(avg), Icons.timelapse_rounded),
      const SizedBox(width: 8),
      c(best == null ? 'بهترین روز' : 'بهترین: ${jalaliShort(best.day)}', best == null ? '—' : fmtMin(best.studyMin),
          Icons.emoji_events_rounded),
      const SizedBox(width: 8),
      c('درصد درست', '${fa(acc)}٪', Icons.task_alt_rounded),
    ]);
  }
}

class _AccuracyCard extends StatelessWidget {
  final List<DayStat> days;
  const _AccuracyCard(this.days);
  @override
  Widget build(BuildContext context) {
    final pts = <FlSpot>[
      for (var i = 0; i < days.length; i++)
        if (days[i].tests > 0) FlSpot(i.toDouble(), days[i].correct * 100 / days[i].tests)
    ];
    return Glass(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('درصد درست در هر روز', style: TextStyle(fontWeight: FontWeight.w900)),
        const SizedBox(height: 14),
        SizedBox(
          height: 150,
          child: pts.length < 2
              ? const Center(child: Text('بعد از چند روز تست‌زدن نمودار پیشرفتت اینجا می‌آید', style: TextStyle(color: T.tx2, fontSize: 12)))
              : LineChart(LineChartData(
                  minY: 0,
                  maxY: 100,
                  minX: 0,
                  maxX: (days.length - 1).toDouble(),
                  gridData: FlGridData(
                      drawVerticalLine: false,
                      horizontalInterval: 25,
                      getDrawingHorizontalLine: (_) => const FlLine(color: T.line, strokeWidth: .5)),
                  borderData: FlBorderData(show: false),
                  titlesData: FlTitlesData(
                    topTitles: const AxisTitles(),
                    rightTitles: const AxisTitles(),
                    bottomTitles: const AxisTitles(),
                    leftTitles: AxisTitles(
                        sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 30,
                            interval: 25,
                            getTitlesWidget: (v, m) =>
                                Text(fa(v.round()), style: const TextStyle(color: T.tx2, fontSize: 10)))),
                  ),
                  lineBarsData: [
                    LineChartBarData(
                      spots: pts,
                      isCurved: true,
                      color: T.ok,
                      barWidth: 3,
                      dotData: FlDotData(show: pts.length <= 14),
                      belowBarData: BarAreaData(show: true, color: T.ok.withOpacity(.12)),
                    ),
                  ],
                )),
        ),
      ]),
    );
  }
}

class _PartBars extends StatelessWidget {
  final List<PartStat> parts;
  const _PartBars(this.parts);
  @override
  Widget build(BuildContext context) {
    if (parts.isEmpty) return const SizedBox.shrink();
    final list = [...parts]..sort((a, b) => b.minutes.compareTo(a.minutes));
    final top = list.take(8).toList();
    final mx = math.max(1, top.first.minutes);
    return Glass(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('زمان مطالعه‌ی هر پارت', style: TextStyle(fontWeight: FontWeight.w900)),
        const SizedBox(height: 10),
        for (final p in top)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(p.part, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13))),
                Text(fmtMin(p.minutes), style: const TextStyle(color: T.tx2, fontSize: 12)),
              ]),
              const SizedBox(height: 6),
              StripedBar(p.minutes / mx, height: 6),
            ]),
          ),
      ]),
    );
  }
}

/// «لیوان مسیر»: مطالعه‌ی انجام‌شده نسبت به کل مطالعه‌ی انجام‌شده + برنامه‌ی ۶۰ روز آینده.
class _Journey extends ConsumerWidget {
  final int studiedMin;
  const _Journey({required this.studiedMin});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plans = ref.watch(futurePlanProvider).valueOrNull ?? const <PlanDay>[];
    final planned = plans.fold<int>(0, (a, p) => a + p.items.fold<int>(0, (b, i) => b + i.minutes));
    final parts = plans.fold<int>(0, (a, p) => a + p.items.length);
    if (planned == 0) return const SizedBox.shrink();
    final frac = studiedMin / (studiedMin + planned);
    final bySubject = <String, int>{};
    for (final p in plans) {
      for (final i in p.items) {
        final k = i.subject.isEmpty ? i.part : i.subject;
        bySubject[k] = (bySubject[k] ?? 0) + i.minutes;
      }
    }
    final subs = bySubject.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return Glass(
      child: Row(children: [
        _Cup(frac),
        const SizedBox(width: 16),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('مسیر تا اینجا', style: TextStyle(fontWeight: FontWeight.w900)),
            const SizedBox(height: 6),
            Text('${fa((frac * 100).round())}٪ راه رو رفتی',
                style: const TextStyle(color: T.ok, fontWeight: FontWeight.w800, fontSize: 16)),
            const SizedBox(height: 6),
            Text(
                '${fmtMin(studiedMin)} مطالعه کردی و طبق برنامه‌ی ۲ ماه آینده ${fmtMin(planned)} در ${fa(parts)} پارت مونده.',
                style: const TextStyle(color: T.tx2, fontSize: 12, height: 1.6)),
            const SizedBox(height: 8),
            Text('بیشترین سهم: ${subs.take(3).map((e) => e.key).join('، ')}',
                style: const TextStyle(color: T.tx2, fontSize: 12)),
          ]),
        ),
      ]),
    );
  }
}

class _Cup extends StatefulWidget {
  final double frac;
  const _Cup(this.frac);
  @override
  State<_Cup> createState() => _CupState();
}

class _CupState extends State<_Cup> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 3))..repeat();
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween<double>(end: widget.frac.clamp(0.0, 1.0)),
        duration: const Duration(milliseconds: 1200),
        curve: Curves.easeOutCubic,
        builder: (_, v, __) => AnimatedBuilder(
          animation: _c,
          builder: (_, __) => CustomPaint(size: const Size(84, 112), painter: _CupPainter(v, _c.value)),
        ),
      );
}

class _CupPainter extends CustomPainter {
  final double v, t;
  _CupPainter(this.v, this.t);
  @override
  void paint(Canvas canvas, Size s) {
    final w = s.width, h = s.height, inset = 10.0;
    final cup = Path()
      ..moveTo(0, 0)
      ..lineTo(w, 0)
      ..lineTo(w - inset, h - 6)
      ..quadraticBezierTo(w - inset, h, w - inset - 8, h)
      ..lineTo(inset + 8, h)
      ..quadraticBezierTo(inset, h, inset, h - 6)
      ..close();
    canvas.save();
    canvas.clipPath(cup);
    final y = h - (h - 6) * v;
    final wave = Path()..moveTo(0, h);
    for (var x = 0.0; x <= w; x += 2) {
      wave.lineTo(x, y + math.sin((x / w * 2 * math.pi) + t * 2 * math.pi) * 3);
    }
    wave
      ..lineTo(w, h)
      ..close();
    canvas.drawPath(wave, Paint()..color = T.ok.withOpacity(.85));
    canvas.restore();
    canvas.drawPath(cup, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = Colors.white.withOpacity(.55));
  }

  @override
  bool shouldRepaint(_CupPainter o) => true;
}
