import 'package:flutter/material.dart';
import 'tokens.dart';

/// نوار پیشرفت سبز با هاشور مورب متحرک. [optional]: مسیر خط‌چین (اختیاری).
class StripedBar extends StatefulWidget {
  final double frac, height;
  final bool optional;
  const StripedBar(this.frac, {super.key, this.height = 8, this.optional = false});
  @override
  State<StripedBar> createState() => _StripedBarState();
}

class _StripedBarState extends State<StripedBar> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat();
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rtl = Directionality.of(context) == TextDirection.rtl;
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: widget.frac.clamp(0.0, 1.0)),
      duration: const Duration(milliseconds: 700),
      curve: Curves.easeOutCubic,
      builder: (_, v, __) => AnimatedBuilder(
        animation: _c,
        builder: (_, __) => CustomPaint(
          size: Size.fromHeight(widget.height),
          painter: _P(v, _c.value, widget.optional, rtl),
        ),
      ),
    );
  }
}

class _P extends CustomPainter {
  final double frac, phase;
  final bool optional, rtl;
  _P(this.frac, this.phase, this.optional, this.rtl);

  @override
  void paint(Canvas canvas, Size size) {
    final rr = RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(size.height / 2));
    if (optional) {
      final line = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = const Color(0x99BABABA);
      for (final m in (Path()..addRRect(rr.deflate(.6))).computeMetrics()) {
        for (var d = 0.0; d < m.length; d += 6) {
          canvas.drawPath(m.extractPath(d, d + 3), line);
        }
      }
    } else {
      canvas.drawRRect(rr, Paint()..color = T.brown);
    }
    if (frac <= 0) return;
    canvas.save();
    canvas.clipRRect(rr);
    final w = size.width * frac;
    final r = rtl ? Rect.fromLTWH(size.width - w, 0, w, size.height) : Rect.fromLTWH(0, 0, w, size.height);
    canvas.drawRect(r, Paint()..color = T.ok);
    canvas.save();
    canvas.clipRect(r);
    final sp = Paint()
      ..color = Colors.white.withOpacity(.22)
      ..strokeWidth = size.height * .45;
    final gap = size.height * 1.6;
    final shift = phase * gap * (rtl ? -1 : 1);
    for (var x = -size.height * 2 + shift; x < size.width + size.height * 2; x += gap) {
      canvas.drawLine(Offset(x, size.height + 2), Offset(x + size.height + 4, -2), sp);
    }
    canvas.restore();
    canvas.restore();
  }

  @override
  bool shouldRepaint(_P o) => true;
}
