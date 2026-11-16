import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lottie/lottie.dart';
import '../../core/prefs.dart';
import '../../theme/glass.dart';
import '../../theme/lottie_views.dart';
import '../../theme/tokens.dart';

/// صفحه‌ی سیاه با متن و موشن‌گرافیک؛ فقط اولین باز شدن اپ، قبل از وارد کردن رمز.
class IntroPage extends StatefulWidget {
  const IntroPage({super.key});
  @override
  State<IntroPage> createState() => _IntroPageState();
}

class _IntroPageState extends State<IntroPage> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this);
  bool _done = false, _left = false;

  @override
  void initState() {
    super.initState();
    _c.addStatusListener((s) {
      if (s == AnimationStatus.completed && mounted) {
        setState(() => _done = true);
        Future<void>.delayed(const Duration(milliseconds: 900), _go);
      }
    });
  }

  Future<void> _go() async {
    if (_left || !mounted) return;
    _left = true;
    Prefs.introSeen = true;
    await Prefs.save();
    if (mounted) context.go('/login');
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(children: [
          Center(
            child: Lottie.asset(
              LottieAssets.intro,
              controller: _c,
              fit: BoxFit.contain,
              width: double.infinity,
              onLoaded: (comp) {
                _c.duration = comp.duration;
                if (MediaQuery.disableAnimationsOf(context)) {
                  _c.value = 1;
                } else {
                  _c.forward();
                }
              },
              // متن لوتی با فونت Cal Sans ساخته شده؛ این فونت در اپ نیست، پس Vazirmatn (لاتین) جایگزین می‌شود.
              delegates: LottieDelegates(
                textStyle: (font) => const TextStyle(fontFamily: T.font, fontWeight: FontWeight.w800),
              ),
              errorBuilder: (_, __, ___) {
                WidgetsBinding.instance.addPostFrameCallback((_) => _go());
                return const SizedBox.shrink();
              },
            ),
          ),
          Positioned(
            left: 24,
            right: 24,
            bottom: 24,
            child: AnimatedOpacity(
              opacity: _done ? 1 : .0,
              duration: const Duration(milliseconds: 400),
              child: PrimaryButton('شروع', onPressed: _go),
            ),
          ),
          Positioned(
            top: 8,
            left: 8,
            child: TextButton(
              onPressed: _go,
              child: const Text('رد کردن', style: TextStyle(color: Colors.white54)),
            ),
          ),
        ]),
      ),
    );
  }
}
