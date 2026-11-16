import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/api_client.dart';
import '../../core/jalali.dart';
import '../../core/models.dart';
import '../../theme/glass.dart';
import '../../theme/tokens.dart';
import '../../theme/lottie_views.dart';

final weekPlanProvider = FutureProvider.autoDispose<List<PlanDay>>((ref) async {
  final today = todayIso();
  Map<String, dynamic> r;
  try {
    r = await Api.i.getC('/plan', q: {'day': today, 'days': 7});
  } on ApiError catch (e) {
    if (!e.isNetwork) rethrow;
    // آفلاین و بدون کش هفتگیِ همین روز: از کش روزهای تکی بساز.
    final days = <PlanDay>[];
    for (var i = 0; i < 7; i++) {
      final day = addDays(today, i);
      final c = await Api.i.cacheRead('/plan', {'day': day});
      days.add(c is Map ? PlanDay.fromJson(c) : PlanDay(day, [], 'none', ''));
    }
    if (days.every((d) => d.items.isEmpty && d.source == 'none')) rethrow;
    Api.i.offlineData.value = true;
    return days;
  }
  final list = r['plans'] as List?;
  if (list == null) return [PlanDay.fromJson(r)];
  return [for (final x in list) PlanDay.fromJson(x)];
});

class PlanWeekPage extends ConsumerStatefulWidget {
  const PlanWeekPage({super.key});
  @override
  ConsumerState<PlanWeekPage> createState() => _PlanWeekPageState();
}

class _PlanWeekPageState extends ConsumerState<PlanWeekPage> with WidgetsBindingObserver {
  DateTime _now = tehranNow();
  late String _activeDay = todayIso();
  Timer? _clock;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // برای باز شدن خودکار در ۰۱:۰۰ و تغییر روز در نیمه‌شب، بدون نیاز به بستن اپ.
    _clock = Timer.periodic(const Duration(seconds: 15), (_) => _syncClock());
  }

  void _syncClock() {
    if (!mounted) return;
    final next = tehranNow();
    final nextDay = isoDay(next);
    final dayChanged = nextDay != _activeDay;
    final timeChanged = next.hour != _now.hour || next.minute != _now.minute;
    if (!dayChanged && !timeChanged) return;

    setState(() {
      _now = next;
      if (dayChanged) _activeDay = nextDay;
    });
    // در شروع روز جدید، برنامه‌ی هفت‌روزه باید با تاریخ جدید از سرور/کش خوانده شود.
    if (dayChanged) ref.invalidate(weekPlanProvider);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _syncClock();
  }

  @override
  void dispose() {
    _clock?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _showLockedMessage(String day) {
    final today = isoDay(_now);
    final message = day == today && _now.hour < 1
        ? 'برنامه‌ی امروز ساعت ۰۱:۰۰ بامداد باز می‌شود.'
        : 'برنامه‌ی هر روز فقط از ساعت ۰۱:۰۰ همان روز قابل مشاهده است.';
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Widget _strip(List<PlanDay> list) => SizedBox(
        height: 74,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: list.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (_, i) {
            final day = list[i].day;
            final j = Jalali.fromDateTime(parseIso(day));
            final isOpen = isPlanDayUnlocked(day, _now);
            final w = j.formatter.wN.split(' ').first;
            return GestureDetector(
              onTap: isOpen ? null : () => _showLockedMessage(day),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOutCubic,
                width: 58,
                decoration: BoxDecoration(
                  color: isOpen ? T.acc : T.sec,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: isOpen ? T.acc : T.line),
                ),
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Text(w,
                      style: TextStyle(
                          fontSize: 11,
                          color: isOpen ? T.bg : T.tx2.withOpacity(.55),
                          fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text(fa(j.day),
                      style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          color: isOpen ? T.bg : T.tx2.withOpacity(.55))),
                  const SizedBox(height: 3),
                  if (isOpen)
                    Container(
                      width: 5,
                      height: 5,
                      decoration: const BoxDecoration(shape: BoxShape.circle, color: T.bg),
                    )
                  else
                    Icon(Icons.lock_rounded, size: 12, color: T.tx2.withOpacity(.5)),
                ]),
              ),
            );
          },
        ),
      );

  Widget _lockedCard() => Glass(
        key: ValueKey('locked-$_activeDay'),
        child: SizedBox(
          width: double.infinity,
          child: Column(children: [
            const Icon(Icons.lock_outline_rounded, size: 34, color: T.acc),
            const SizedBox(height: 10),
            const Text('برنامه‌ی امروز هنوز قفل است',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
            const SizedBox(height: 5),
            Text(
              'برنامه‌ی امروز ساعت ۰۱:۰۰ بامداد باز می‌شود.',
              textAlign: TextAlign.center,
              style: TextStyle(color: T.tx2, fontSize: 13),
            ),
          ]),
        ),
      );

  Widget _day(PlanDay p) => Glass(
        key: ValueKey(p.day),
        borderColor: p.source == 'ai' ? T.acc : null,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
                child: Text(jalaliFull(p.day),
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900))),
            if (p.source == 'ai')
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: T.acc, borderRadius: BorderRadius.circular(20)),
                child: const Text('ویرایش‌شده توسط هوش مصنوعی',
                    style: TextStyle(color: T.bg, fontSize: 11, fontWeight: FontWeight.w700)),
              ),
          ]),
          if (p.note.isNotEmpty)
            Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(p.note, style: const TextStyle(color: T.hi, fontSize: 13))),
          const SizedBox(height: 8),
          if (p.items.isEmpty)
            const Text('برنامه‌ای ثبت نشده', style: TextStyle(color: T.tx2))
          else
            for (var i = 0; i < p.items.length; i++)
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: 1),
                duration: Duration(milliseconds: 320 + i * 90),
                curve: Curves.easeOutCubic,
                builder: (_, v, c) => Opacity(
                    opacity: v,
                    child: Transform.translate(offset: Offset(0, 14 * (1 - v)), child: c)),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(children: [
                    Text(fa(i + 1), style: const TextStyle(color: T.acc, fontWeight: FontWeight.w800)),
                    const SizedBox(width: 10),
                    Expanded(
                        child: Text(
                            '${p.items[i].part}${p.items[i].subject.isEmpty ? '' : ' — ${p.items[i].subject}'}')),
                    Text(
                        '${fmtMin(p.items[i].minutes)}${p.items[i].testsTarget > 0 ? ' · ${fa(p.items[i].testsTarget)} تست' : ''}',
                        style: const TextStyle(color: T.tx2, fontSize: 12)),
                  ]),
                ),
              ),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final plans = ref.watch(weekPlanProvider);
    final today = isoDay(_now);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Padding(
          padding: EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: PageTitle('برنامه', sub: 'فقط برنامه‌ی امروز')),
      plans.when(
        loading: () => const Expanded(child: AppLoader()),
        error: (e, _) => Expanded(
            child: ErrorState(e is ApiError ? e.fa : 'خطا در دریافت برنامه',
                onRetry: () => ref.invalidate(weekPlanProvider))),
        data: (list) {
          final todayPlan = list.firstWhere((p) => p.day == today,
              orElse: () => PlanDay(today, [], 'none', ''));
          final isOpen = isPlanDayUnlocked(today, _now);
          return Expanded(
            child: Column(children: [
              _strip(list),
              const SizedBox(height: 12),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: () async => ref.refresh(weekPlanProvider.future),
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    children: [
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 350),
                        switchInCurve: Curves.easeOutCubic,
                        transitionBuilder: (c, a) => FadeTransition(
                          opacity: a,
                          child: SlideTransition(
                              position: Tween(begin: const Offset(0, .08), end: Offset.zero).animate(a),
                              child: c),
                        ),
                        child: isOpen ? _day(todayPlan) : _lockedCard(),
                      ),
                    ],
                  ),
                ),
              ),
            ]),
          );
        },
      ),
    ]);
  }
}
