import 'package:flutter/material.dart';
import 'tokens.dart';

/// جای‌نگهدار هنگام بارگذاری (به‌جای اسپینر): مستطیل کم‌رنگ که آرام نبض می‌زند.
class Skeleton extends StatefulWidget {
  final double height;
  final double? width;
  final double radius;
  const Skeleton({super.key, this.height = 80, this.width, this.radius = T.rCard});
  @override
  State<Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<Skeleton> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1100));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _c.stop();
      _c.value = .5;
    } else if (!_c.isAnimating) {
      _c.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _c,
        builder: (_, __) => Opacity(
          opacity: .35 + .4 * Curves.easeInOut.transform(_c.value),
          child: Container(
            height: widget.height,
            width: widget.width,
            decoration: BoxDecoration(
              color: T.surfaceHi,
              borderRadius: BorderRadius.circular(widget.radius),
            ),
          ),
        ),
      );
}

/// چند اسکلت زیر هم (فهرست در حال بارگذاری).
class SkeletonList extends StatelessWidget {
  final int count;
  final double height;
  const SkeletonList({super.key, this.count = 3, this.height = 96});
  @override
  Widget build(BuildContext context) => Column(children: [
        for (var i = 0; i < count; i++)
          Padding(padding: const EdgeInsets.only(bottom: 12), child: Skeleton(height: height)),
      ]);
}
