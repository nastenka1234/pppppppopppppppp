import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'tokens.dart';

/// کارت تخت (نام قدیمی Glass برای سازگاری حفظ شده است): بدون blur و سایه.
class Glass extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final VoidCallback? onTap;
  final Color? borderColor;
  final Color? color;

  /// کارت فعال/برجسته (سطح بالا).
  final bool highlight;
  const Glass({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.radius = T.rCard,
    this.onTap,
    this.borderColor,
    this.color,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    final r = BorderRadius.circular(radius);
    return ClipRRect(
      borderRadius: r,
      child: Material(
        color: color ?? (highlight ? T.surfaceHi : T.sec),
        child: InkWell(
          onTap: onTap,
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              borderRadius: r,
              border: Border.all(color: borderColor ?? T.line),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// با فشردن، کمی کوچک می‌شود (scale 0.97).
class Press extends StatefulWidget {
  final Widget child;
  final bool enabled;
  const Press({super.key, required this.child, this.enabled = true});
  @override
  State<Press> createState() => _PressState();
}

class _PressState extends State<Press> {
  bool _down = false;
  void _set(bool v) {
    if (_down != v && mounted) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) => Listener(
        onPointerDown: widget.enabled ? (_) => _set(true) : null,
        onPointerUp: (_) => _set(false),
        onPointerCancel: (_) => _set(false),
        child: AnimatedScale(
          scale: _down ? 0.97 : 1,
          duration: const Duration(milliseconds: 90),
          curve: Curves.easeOut,
          child: widget.child,
        ),
      );
}

VoidCallback? _tap(VoidCallback? f) => f == null
    ? null
    : () {
        HapticFeedback.lightImpact();
        f();
      };

/// تنها دکمه‌ی پررنگِ هر صفحه.
class PrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool busy;
  const PrimaryButton(this.label, {super.key, this.onPressed, this.icon, this.busy = false});

  @override
  Widget build(BuildContext context) {
    final on = !busy && onPressed != null;
    return Press(
      enabled: on,
      child: SizedBox(
        height: 52,
        child: FilledButton(
          onPressed: busy ? null : _tap(onPressed),
          style: FilledButton.styleFrom(
            backgroundColor: T.acc,
            foregroundColor: T.onAcc,
            disabledBackgroundColor: T.brown,
            disabledForegroundColor: T.tx2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(T.rButton)),
            textStyle: const TextStyle(fontFamily: T.font, fontWeight: FontWeight.w700, fontSize: 15),
          ),
          child: busy
              ? const SizedBox(
                  width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: T.onAcc))
              : Row(mainAxisSize: MainAxisSize.min, children: [
                  if (icon != null) ...[Icon(icon, size: 20), const SizedBox(width: 8)],
                  Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
                ]),
        ),
      ),
    );
  }
}

/// دکمه‌ی ثانویه (outlined).
class GhostButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  const GhostButton(this.label, {super.key, this.onPressed, this.icon});

  @override
  Widget build(BuildContext context) {
    return Press(
      enabled: onPressed != null,
      child: SizedBox(
        height: 46,
        child: OutlinedButton(
          onPressed: _tap(onPressed),
          style: OutlinedButton.styleFrom(
            foregroundColor: T.tx,
            disabledForegroundColor: T.tx2.withOpacity(.5),
            side: const BorderSide(color: T.line2),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(T.rButton)),
            textStyle: const TextStyle(fontFamily: T.font, fontWeight: FontWeight.w700, fontSize: 14),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (icon != null) ...[Icon(icon, size: 18), const SizedBox(width: 6)],
            Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
          ]),
        ),
      ),
    );
  }
}

/// دکمه‌ی عمل خطرناک (مثل خروج): کم‌رنگ و با رنگ هشدار، نه شبیه دکمه‌ی اصلی.
class DangerButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  const DangerButton(this.label, {super.key, this.onPressed, this.icon});

  @override
  Widget build(BuildContext context) {
    return Press(
      enabled: onPressed != null,
      child: SizedBox(
        height: 48,
        child: OutlinedButton(
          onPressed: _tap(onPressed),
          style: OutlinedButton.styleFrom(
            foregroundColor: T.bad,
            side: BorderSide(color: T.bad.withOpacity(.6)),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(T.rButton)),
            textStyle: const TextStyle(fontFamily: T.font, fontWeight: FontWeight.w700, fontSize: 14),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (icon != null) ...[Icon(icon, size: 18), const SizedBox(width: 6)],
            Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
          ]),
        ),
      ),
    );
  }
}

/// چیپ کوچک (ارتفاع ۲۶، شعاع کامل). برای درس، وضعیت، «۱۰ تست» و ... — جای جداکننده‌ی «·».
class Pill extends StatelessWidget {
  final String label;
  final IconData? icon;
  final Color? color; // رنگ متن و حاشیه
  final bool filled;
  const Pill(this.label, {super.key, this.icon, this.color, this.filled = false});

  @override
  Widget build(BuildContext context) {
    final c = color ?? T.tx2;
    return Container(
      height: 26,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: filled ? c : Colors.transparent,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: filled ? c : T.line2),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[Icon(icon, size: 13, color: filled ? T.onAcc : c), const SizedBox(width: 4)],
        Text(label,
            style: TextStyle(
                fontSize: 11,
                height: 1.2,
                fontWeight: FontWeight.w500,
                color: filled ? T.onAcc : c)),
      ]),
    );
  }
}

class PageTitle extends StatelessWidget {
  final String text;
  final String? sub;
  const PageTitle(this.text, {super.key, this.sub});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 8, 4, 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(text, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
          if (sub != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(sub!, style: const TextStyle(color: T.tx2, fontSize: 13)),
            ),
        ]),
      );
}
