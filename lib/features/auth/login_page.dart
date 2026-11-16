import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lottie/lottie.dart';
import '../../core/api_client.dart';
import '../../core/auth_store.dart';
import '../../theme/glass.dart';
import '../../theme/lottie_views.dart';
import '../../theme/tokens.dart';

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});
  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _pw = TextEditingController();
  bool _busy = false;
  String? _err;

  Future<void> _submit() async {
    if (_pw.text.trim().isEmpty) return;
    setState(() {
      _busy = true;
      _err = null;
    });
    try {
      ref.read(flashProvider.notifier).state = null;
      await ref.read(authProvider.notifier).login(_pw.text.trim());
    } on ApiError catch (e) {
      if (mounted) setState(() => _err = e.fa);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final flash = ref.watch(flashProvider);
    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: Colors.black,
      body: Stack(fit: StackFit.expand, children: [
        // پس‌زمینه‌ی رنگیِ متحرک، مات (blur) و کم‌نور تا متن خوانا بماند.
        RepaintBoundary(
          child: ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: 46, sigmaY: 46, tileMode: TileMode.decal),
            child: Lottie.asset(
              LottieAssets.gradientBg,
              fit: BoxFit.cover,
              animate: !MediaQuery.disableAnimationsOf(context),
              errorBuilder: (_, __, ___) => const SizedBox.shrink(),
            ),
          ),
        ),
        ColoredBox(color: Colors.black.withOpacity(.38)),
        SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(22),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Image.asset('assets/icon/logo.png', width: 84, height: 84),
                  const SizedBox(height: 14),
                  const Text('امید', style: TextStyle(fontSize: 34, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 6),
                  const Text('رمزت را وارد کن', style: TextStyle(color: T.tx2)),
                  const SizedBox(height: 24),
                  Glass(
                    color: T.bg.withOpacity(.72),
                    child: Column(children: [
                      TextField(
                        controller: _pw,
                        obscureText: true,
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => _submit(),
                        decoration: const InputDecoration(hintText: 'رمز'),
                      ),
                      if (_err != null || flash != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Text(_err ?? flash!,
                              style: const TextStyle(color: T.hi, fontWeight: FontWeight.w700)),
                        ),
                      const SizedBox(height: 16),
                      SizedBox(
                          width: double.infinity,
                          child: PrimaryButton('ورود', onPressed: _submit, busy: _busy)),
                    ]),
                  ),
                ]),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}
