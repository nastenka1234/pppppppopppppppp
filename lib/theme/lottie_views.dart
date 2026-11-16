import 'dart:async';
import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import 'glass.dart';
import 'tokens.dart';

/// مسیر انیمیشن‌های لوتی (assets/lottie).
class LottieAssets {
  static const intro = 'assets/lottie/intro.json'; // صفحه‌ی سیاه با متن و موشن گرافیک (اولین ورود)
  static const gradientBg = 'assets/lottie/gradient_bg.json'; // پس‌زمینه‌ی رنگی صفحه‌ی ورود
  static const loading = 'assets/lottie/loading.json'; // لودینگ
  static const error404 = 'assets/lottie/error_404.json'; // خطا / چیزی پیدا نشد
  static const happy = 'assets/lottie/happy.json'; // حالت خالی و جشن
  static const verified = 'assets/lottie/verified.json'; // تیک تأیید
  static const ai = 'assets/lottie/ai_abstract.json'; // هوش مصنوعی در حال کار
}

bool _still(BuildContext c) => MediaQuery.disableAnimationsOf(c);

/// لودینگ صفحه (جای CircularProgressIndicator). انیمیشن `Loading.json`.
class AppLoader extends StatelessWidget {
  final double size;
  final EdgeInsetsGeometry padding;
  const AppLoader({super.key, this.size = 72, this.padding = const EdgeInsets.all(40)});

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: padding,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(size * .28),
            child: SizedBox(
              width: size,
              height: size,
              child: Lottie.asset(
                LottieAssets.loading,
                fit: BoxFit.cover,
                animate: !_still(context),
                errorBuilder: (_, __, ___) => const Center(child: CircularProgressIndicator()),
              ),
            ),
          ),
        ),
      );
}

/// حالت خالی / خطا: انیمیشن + عنوان + توضیح + دکمه‌ی اختیاری.
class StateView extends StatelessWidget {
  final String asset;
  final String title;
  final String? sub;
  final String? actionLabel;
  final VoidCallback? onAction;
  final double size;
  final bool repeat;
  const StateView({
    super.key,
    required this.asset,
    required this.title,
    this.sub,
    this.actionLabel,
    this.onAction,
    this.size = 190,
    this.repeat = true,
  });

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 12),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          SizedBox(
            height: size,
            child: Lottie.asset(
              asset,
              repeat: repeat,
              animate: !_still(context),
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => const Icon(Icons.inbox_rounded, size: 56, color: T.brown),
            ),
          ),
          const SizedBox(height: 8),
          Text(title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          if (sub != null) ...[
            const SizedBox(height: 4),
            Text(sub!, textAlign: TextAlign.center, style: const TextStyle(color: T.tx2, fontSize: 13)),
          ],
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 16),
            GhostButton(actionLabel!, icon: Icons.refresh_rounded, onPressed: onAction),
          ],
        ]),
      );
}

/// خطای دریافت اطلاعات (انیمیشن ۴۰۴ + «تلاش دوباره»).
class ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;
  const ErrorState(this.message, {super.key, this.onRetry});

  @override
  Widget build(BuildContext context) => StateView(
        asset: LottieAssets.error404,
        title: message,
        size: 150,
        actionLabel: onRetry == null ? null : 'تلاش دوباره',
        onAction: onRetry,
      );
}

/// تیک تأیید (آبی) که یک لحظه وسط صفحه می‌آید و خودش می‌رود.
Future<void> showVerifiedTick(BuildContext context, {String? text}) async {
  final nav = Navigator.of(context, rootNavigator: true);
  unawaited(showDialog<void>(
    context: context,
    barrierColor: Colors.black54,
    barrierDismissible: false,
    builder: (_) => PopScope(
      canPop: false,
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: Center(
          child: Material(
            color: Colors.transparent,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              SizedBox(
                width: 190,
                height: 190,
                child: Lottie.asset(LottieAssets.verified,
                    repeat: false, errorBuilder: (_, __, ___) => const Icon(Icons.check_circle_rounded, size: 96)),
              ),
              if (text != null)
                Text(text, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: T.tx)),
            ]),
          ),
        ),
      ),
    ),
  ));
  await Future<void>.delayed(const Duration(milliseconds: 2200));
  if (nav.canPop()) nav.pop();
}
