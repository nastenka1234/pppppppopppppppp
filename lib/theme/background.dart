import 'package:flutter/material.dart';
import 'tokens.dart';

/// پس‌زمینه‌ی تخت و ساده (سیستم طراحی نارنجی): بدون لکه، شیشه یا انیمیشن.
class AppBackground extends StatelessWidget {
  const AppBackground({super.key});

  @override
  Widget build(BuildContext context) => const ColoredBox(color: T.bg);
}
