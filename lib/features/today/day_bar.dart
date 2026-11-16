import 'package:flutter/material.dart';
import '../../core/jalali.dart';
import '../../core/priority.dart';
import '../../theme/glass.dart';
import '../../theme/striped_bar.dart';
import '../../theme/tokens.dart';

/// نمودار افقی پیشرفت روز: هر پارت یک بخش، عرض بخش متناسب با minutes_target،
/// به ترتیب اولویت پر می‌شود (از راست). [thin]: نسخه‌ی نازک برای بالای اتاق تمرکز.
class DayProgressBar extends StatelessWidget {
  final DayState state;
  final bool thin;
  final VoidCallback? onTap;
  const DayProgressBar(this.state, {super.key, this.thin = false, this.onTap});

  @override
  Widget build(BuildContext context) {
    if (state.parts.isEmpty) return const SizedBox.shrink();
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final cur = state.current;
    final segments = Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      for (var i = 0; i < state.parts.length; i++) ...[
        if (i > 0) const SizedBox(width: 4),
        _segment(state.parts[i], cur, rtl),
      ],
    ]);
    if (thin) return segments;

    final done = state.mandatoryDone, total = state.mandatoryTotal;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(T.rCard),
          border: Border.all(color: T.line),
          gradient: const LinearGradient(
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
            colors: [Color(0xFF2E2322), T.sec],
          ),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Expanded(
                child: Text('پیشرفت امروز', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15))),
            Text('${fmtMin(state.mandatoryStudiedMin)} از ${fmtMin(state.mandatoryTargetMin)}',
                style: const TextStyle(color: T.tx2, fontSize: 12)),
          ]),
          const SizedBox(height: 4),
          Text('${fa(done)} از ${fa(total)} اولویت اصلی تموم شد',
              style: const TextStyle(color: T.tx2, fontSize: 12)),
          const SizedBox(height: 14),
          segments,
        ]),
      ),
    );
  }

  Widget _segment(PartState p, PartState? cur, bool rtl) {
    final frac = p.isDone ? 1.0 : (p.studiedMin / p.targetMin).clamp(0.0, 1.0).toDouble();
    final isCur = cur != null && cur.index == p.index;
    final label = p.item.subject.isNotEmpty ? p.item.subject : p.item.part;
    return Expanded(
      flex: p.targetMin,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        StripedBar(frac, height: thin ? 4 : 10, optional: p.optional),
        if (!thin) ...[
          const SizedBox(height: 6),
          Row(mainAxisSize: MainAxisSize.min, children: [
            if (p.isLocked) ...[
              const Icon(Icons.lock_rounded, size: 9, color: T.tx2),
              const SizedBox(width: 2),
            ],
            Flexible(
              child: Text('${fa(p.priority)} $label',
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10,
                    height: 1.2,
                    color: isCur ? T.tx : T.tx2,
                    fontWeight: isCur ? FontWeight.w700 : FontWeight.w400,
                  )),
            ),
          ]),
        ],
      ]),
    );
  }

  /// فهرست کوتاه پارت‌ها (با لمس نمودار).
  static void showParts(BuildContext context, DayState state) {
    showModalBottomSheet<void>(
      context: context,
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('پارت‌های امروز', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          for (final p in state.parts)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(children: [
                Text(fa(p.priority), style: const TextStyle(color: T.tx2)),
                const SizedBox(width: 12),
                Expanded(
                    child: Text(p.item.part,
                        style: TextStyle(color: p.isLocked ? T.tx2 : T.tx, fontWeight: FontWeight.w500))),
                if (p.isDone)
                  const Pill('تموم شد', color: T.ok)
                else if (p.isLocked)
                  const Pill('قفل', icon: Icons.lock_rounded)
                else
                  Pill(p.optional ? 'اختیاری' : 'باز', color: T.acc),
              ]),
            ),
        ]),
      ),
    );
  }
}

