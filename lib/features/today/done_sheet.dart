import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/jalali.dart';
import '../../core/priority.dart';
import '../../core/progress_store.dart';
import '../../theme/glass.dart';
import '../../theme/tokens.dart';

/// bottom sheet «تموم شد»: تعداد تست (الزامی، صفر هم مجاز)، درست‌ها (اختیاری)،
/// ثبت و بازشدن اولویت بعدی، یا «نصفه موند». برمی‌گرداند true اگر چیزی ذخیره شد.
Future<bool?> showDoneSheet(BuildContext context, String day, PartState st, {required int? nextPriority}) =>
    showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _DoneSheet(day, st, nextPriority),
    );

class _DoneSheet extends StatefulWidget {
  final String day;
  final PartState st;
  final int? nextPriority;
  const _DoneSheet(this.day, this.st, this.nextPriority);
  @override
  State<_DoneSheet> createState() => _DoneSheetState();
}

class _DoneSheetState extends State<_DoneSheet> {
  late int tests = widget.st.pp?.tests ?? 0;
  late int? correct = (widget.st.pp?.correctKnown ?? false) ? widget.st.pp!.correct : null;
  bool saving = false;

  int get target => widget.st.item.testsTarget;
  bool get editing => widget.st.isDone;

  Widget _stepper(String label, String valueText, VoidCallback? minus, VoidCallback plus, {String? hint}) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
              if (hint != null) Text(hint, style: const TextStyle(color: T.tx2, fontSize: 12)),
            ]),
          ),
          IconButton(onPressed: minus, icon: const Icon(Icons.remove_circle_outline_rounded)),
          SizedBox(
            width: 44,
            child: Center(
                child: Text(valueText, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800))),
          ),
          IconButton(onPressed: plus, icon: const Icon(Icons.add_circle_outline_rounded)),
        ]),
      );

  Future<void> _save({required bool carried}) async {
    if (saving) return;
    setState(() => saving = true);
    HapticFeedback.mediumImpact();
    await ProgressStore.update(widget.day, widget.st.item.part, (p) {
      p.tests = tests;
      if (correct != null) {
        p.correct = correct!;
        p.correctKnown = true;
      } else if (p.correct > tests) {
        p.correct = tests;
      }
      if (carried) {
        p.done = false;
        p.carried = true;
      } else {
        p.done = true;
        p.carried = false;
        if (p.doneAt.isEmpty) p.doneAt = DateTime.now().toUtc().toIso8601String();
      }
    }, priority: widget.st.priority);
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final st = widget.st;
    final low = target > 0 && tests < target;
    final primary = editing
        ? 'ذخیره'
        : (widget.nextPriority != null ? 'ثبت و باز شدن اولویت ${fa(widget.nextPriority)}' : 'ثبت و تموم شد');
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 4, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('اولویت ${fa(st.priority)}', style: const TextStyle(color: T.tx2, fontSize: 12)),
          Text(st.item.part, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 14),
          _stepper(
            'چند تست زدی؟',
            fa(tests),
            tests > 0
                ? () => setState(() {
                      tests--;
                      if (correct != null && correct! > tests) correct = tests;
                    })
                : null,
            () => setState(() => tests++),
            hint: target > 0 ? 'هدف: ${fa(target)} تست' : null,
          ),
          _stepper(
            'چند تاش درست بود؟',
            correct == null ? '—' : fa(correct),
            (correct ?? 0) > 0 ? () => setState(() => correct = correct! - 1) : null,
            () => setState(() => correct = ((correct ?? 0) + 1).clamp(0, tests).toInt()),
            hint: 'اختیاری',
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            alignment: Alignment.topCenter,
            child: low
                ? Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Icon(Icons.info_outline_rounded, size: 16, color: T.tx2),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'با ${fa(tests)} تست ثبت می‌شه و مشاور هم می‌بینه که از هدف کمتر بوده.',
                          style: const TextStyle(color: T.tx2, fontSize: 12),
                        ),
                      ),
                    ]),
                  )
                : const SizedBox(width: double.infinity),
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: PrimaryButton(primary, busy: saving, onPressed: () => _save(carried: false)),
          ),
          if (!editing) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: GhostButton('نصفه موند، فردا ادامه بده',
                  onPressed: saving ? null : () => _save(carried: true)),
            ),
          ],
        ]),
      ),
    );
  }
}
