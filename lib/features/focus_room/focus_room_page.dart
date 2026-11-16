import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:video_player/video_player.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../../core/api_client.dart';
import '../../core/blocker.dart';
import '../../core/jalali.dart';
import '../../core/live.dart';
import '../../core/models.dart';
import '../../core/offline_queue.dart';
import '../../core/prefs.dart';
import '../../core/progress_store.dart';
import '../../theme/glass.dart';
import '../../theme/tokens.dart';
import '../music/player_service.dart';

class FocusRoomPage extends StatefulWidget {
  final String part, subject;
  const FocusRoomPage({super.key, required this.part, required this.subject});
  @override
  State<FocusRoomPage> createState() => _FocusRoomPageState();
}

class _FocusRoomPageState extends State<FocusRoomPage> {
  final day = todayIso();
  String mode = 'pomodoro'; // free | pomodoro
  bool running = false, onBreak = false, videoReady = false;
  late int focusLen = Prefs.focusMin; // دقیقه؛ قابل‌تنظیم برای همین جلسه
  late int phaseLeft = Prefs.focusMin * 60;
  int sessionSeconds = 0, unsynced = 0;
  DateTime? startedAt;
  Timer? timer;
  VideoPlayerController? vc;
  String? videoId;

  @override
  void initState() {
    super.initState();
    Live.part = widget.part.isEmpty ? null : widget.part;
    _loadVideo();
  }

  Future<void> _loadVideo() async {
    try {
      final r = await Api.i.getC('/focus/videos');
      final list = [for (final x in (r['videos'] as List? ?? [])) FocusVideo.fromJson(x)];
      if (list.isEmpty) return;
      final v = list[DateTime.now().day % list.length];
      final c = VideoPlayerController.networkUrl(
        Uri.parse(Api.i.abs(v.url)),
        httpHeaders: Api.i.authHeaders,
        videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
      );
      await c.initialize();
      await c.setLooping(true);
      await c.setVolume(0);
      await c.play();
      if (!mounted) {
        c.dispose();
        return;
      }
      setState(() {
        vc = c;
        videoId = v.id;
        videoReady = true;
      });
    } catch (_) {}
  }

  void _setLen(int m) {
    setState(() {
      focusLen = m;
      phaseLeft = m * 60;
    });
    Prefs.focusMin = m;
    Prefs.save();
  }

  Future<void> _customLen() async {
    final c = TextEditingController();
    final v = await showDialog<int>(
      context: context,
      builder: (_) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('مدت تمرکز (دقیقه)'),
          content: TextField(controller: c, keyboardType: TextInputType.number, autofocus: true),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, int.tryParse(c.text.trim())),
                child: const Text('تأیید')),
          ],
        ),
      ),
    );
    if (v != null && v >= 5 && v <= 300) _setLen(v);
  }

  void _toggle() {
    if (running) {
      timer?.cancel();
      setState(() => running = false);
      Live.state.value = 'idle';
      WakelockPlus.disable();
      Blocker.focus(0);
    } else {
      startedAt ??= DateTime.now().toUtc();
      timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
      setState(() => running = true);
      Live.state.value = onBreak ? 'break' : 'focus';
      WakelockPlus.enable();
      Blocker.focus(onBreak ? 0 : 150);
    }
    Live.beat();
  }

  void _tick() {
    setState(() {
      if (onBreak) {
        phaseLeft--;
      } else {
        sessionSeconds++;
        unsynced++;
        if (mode == 'pomodoro') phaseLeft--;
      }
    });
    if (!onBreak && sessionSeconds % 60 == 0) Blocker.focus(150);
    if (unsynced >= 60) _flush();
    if (mode == 'pomodoro' && phaseLeft <= 0) _switchPhase();
  }

  void _switchPhase() {
    HapticFeedback.heavyImpact();
    setState(() {
      onBreak = !onBreak;
      phaseLeft = (onBreak ? Prefs.breakMin : focusLen) * 60;
    });
    Live.state.value = onBreak ? 'break' : 'focus';
    Blocker.focus(onBreak ? 0 : 150);
    Live.beat();
    if (onBreak && Prefs.autoMusic && PlayerService.i.loaded) PlayerService.i.next();
  }

  Future<void> _flush() async {
    final add = unsynced;
    unsynced = 0;
    if (add == 0 || widget.part.isEmpty) return;
    await ProgressStore.update(day, widget.part, (p) => p.studySeconds += add);
  }

  Future<void> _finish() async {
    timer?.cancel();
    running = false;
    Blocker.focus(0);
    await _flush();
    if (sessionSeconds >= 30) {
      final tag = PlayerService.i.player.sequenceState?.currentSource?.tag;
      try {
        await OfflineQueue.i.send('/focus/session', {
          'seconds': sessionSeconds,
          'started_at': startedAt?.toIso8601String(),
          'ended_at': DateTime.now().toUtc().toIso8601String(),
          'mode': mode,
          'music_id': tag is MediaItem ? tag.id : null,
          'video_id': videoId,
        });
      } catch (_) {}
    }
    Live.state.value = 'idle';
    Live.part = null;
    Live.beat();
    if (mounted) context.pop();
  }

  Future<void> _confirmExit() async {
    if (sessionSeconds == 0) {
      if (mounted) context.pop();
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('پایان جلسه؟'),
          content: Text('${fmtMin(sessionSeconds / 60)} مطالعه ثبت می‌شود.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('ادامه')),
            TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('پایان')),
          ],
        ),
      ),
    );
    if (ok == true) await _finish();
  }

  Future<void> _startMusic() async {
    try {
      final r = await Api.i.getC('/music');
      final list = [for (final x in (r['tracks'] as List? ?? [])) Track.fromJson(x)];
      if (list.isNotEmpty) await PlayerService.i.play(list, 0);
      if (mounted) setState(() {});
    } catch (_) {}
  }

  @override
  void dispose() {
    timer?.cancel();
    vc?.dispose();
    Blocker.focus(0);
    WakelockPlus.disable();
    Live.state.value = 'idle';
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final shown = mode == 'pomodoro' ? phaseLeft : sessionSeconds;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmExit();
      },
      child: Scaffold(
        body: Stack(fit: StackFit.expand, children: [
          if (vc != null)
            AnimatedOpacity(
              opacity: videoReady ? .55 : 0,
              duration: const Duration(milliseconds: 900),
              child: FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                    width: vc!.value.size.width, height: vc!.value.size.height, child: VideoPlayer(vc!)),
              ),
            ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [T.bg.withOpacity(.55), T.bg.withOpacity(.75)],
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(children: [
                Row(children: [
                  IconButton(icon: const Icon(Icons.close_rounded), onPressed: _confirmExit),
                  const Spacer(),
                ]),
                const Spacer(),
                if (widget.part.isNotEmpty)
                  Text(widget.part, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
                if (widget.subject.isNotEmpty)
                  Text(widget.subject, style: const TextStyle(color: T.tx2)),
                const SizedBox(height: 10),
                _Ring(
                  frac: mode == 'pomodoro'
                      ? 1 - (phaseLeft / ((onBreak ? Prefs.breakMin : focusLen) * 60)).clamp(0.0, 1.0)
                      : (sessionSeconds % 3600) / 3600,
                  onBreak: onBreak,
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(clock(shown),
                        style: const TextStyle(
                            fontSize: 58, fontWeight: FontWeight.w300, color: T.hi, letterSpacing: 1)),
                    const SizedBox(height: 4),
                    Text(onBreak ? 'استراحت' : (running ? 'تمرکز' : 'آماده'),
                        style: TextStyle(color: onBreak ? T.ok : T.tx2, fontSize: 14)),
                  ]),
                ),
                const SizedBox(height: 6),
                Text('مطالعه‌ی این جلسه: ${fmtMin(sessionSeconds / 60)}',
                    style: const TextStyle(color: T.tx2, fontSize: 12)),
                const SizedBox(height: 22),
                SegmentedButton<String>(
                  showSelectedIcon: false,
                  style: SegmentedButton.styleFrom(
                    selectedBackgroundColor: T.acc,
                    selectedForegroundColor: T.bg,
                    foregroundColor: T.tx,
                    side: const BorderSide(color: T.line),
                    textStyle: const TextStyle(fontFamily: 'Vazirmatn', fontWeight: FontWeight.w700),
                  ),
                  segments: const [
                    ButtonSegment(value: 'pomodoro', label: Text('پومودورو')),
                    ButtonSegment(value: 'free', label: Text('آزاد')),
                  ],
                  selected: {mode},
                  onSelectionChanged: running || sessionSeconds > 0
                      ? null
                      : (s) => setState(() {
                            mode = s.first;
                            phaseLeft = focusLen * 60;
                          }),
                ),
                if (mode == 'pomodoro' && !running && sessionSeconds == 0) ...[
                  const SizedBox(height: 14),
                  Wrap(spacing: 6, runSpacing: 6, alignment: WrapAlignment.center, children: [
                    for (final m in const [25, 40, 50, 60, 90, 120])
                      ChoiceChip(
                        label: Text(m >= 60 ? (m == 60 ? '۱ ساعت' : m == 90 ? '۱٫۵ ساعت' : '۲ ساعت') : '${fa(m)} دقیقه'),
                        selected: focusLen == m,
                        showCheckmark: false,
                        selectedColor: T.acc,
                        backgroundColor: T.glass,
                        side: const BorderSide(color: T.line),
                        labelStyle: TextStyle(
                            fontFamily: 'Vazirmatn',
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: focusLen == m ? T.bg : T.tx),
                        onSelected: (_) => _setLen(m),
                      ),
                    ActionChip(
                      label: const Text('دلخواه'),
                      backgroundColor: T.glass,
                      side: const BorderSide(color: T.line),
                      labelStyle: const TextStyle(fontFamily: 'Vazirmatn', fontSize: 12, color: T.tx),
                      onPressed: _customLen,
                    ),
                  ]),
                ],
                const SizedBox(height: 22),
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  IconButton.filled(
                    iconSize: 44,
                    style: IconButton.styleFrom(
                        backgroundColor: T.acc, foregroundColor: T.bg, padding: const EdgeInsets.all(20)),
                    icon: Icon(running ? Icons.pause_rounded : Icons.play_arrow_rounded),
                    onPressed: _toggle,
                  ),
                  const SizedBox(width: 18),
                  if (sessionSeconds > 0) GhostButton('پایان', icon: Icons.stop_rounded, onPressed: _confirmExit),
                ]),
                const Spacer(),
                Glass(
                  radius: 24,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  child: PlayerService.i.loaded
                      ? Row(children: [
                          const Icon(Icons.graphic_eq_rounded, color: T.acc),
                          const SizedBox(width: 10),
                          Expanded(
                            child: StreamBuilder<SequenceState?>(
                              stream: PlayerService.i.player.sequenceStateStream,
                              builder: (_, s) {
                                final tag = s.data?.currentSource?.tag;
                                return Text(tag is MediaItem ? tag.title : '',
                                    maxLines: 1, overflow: TextOverflow.ellipsis);
                              },
                            ),
                          ),
                          StreamBuilder<PlayerState>(
                            stream: PlayerService.i.player.playerStateStream,
                            builder: (_, s) => IconButton(
                              icon: Icon((s.data?.playing ?? false)
                                  ? Icons.pause_rounded
                                  : Icons.play_arrow_rounded),
                              onPressed: PlayerService.i.toggle,
                            ),
                          ),
                          IconButton(icon: const Icon(Icons.skip_next_rounded), onPressed: PlayerService.i.next),
                        ])
                      : Row(children: [
                          const Icon(Icons.music_note_rounded, color: T.tx2),
                          const SizedBox(width: 10),
                          const Expanded(child: Text('موزیک پخش نمی‌شود', style: TextStyle(color: T.tx2))),
                          TextButton(onPressed: _startMusic, child: const Text('پخش')),
                        ]),
                ),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}

/// حلقه‌ی مینیمال تایمر.
class _Ring extends StatelessWidget {
  final double frac;
  final bool onBreak;
  final Widget child;
  const _Ring({required this.frac, required this.onBreak, required this.child});
  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween<double>(end: frac),
        duration: const Duration(milliseconds: 1000),
        builder: (_, v, __) => CustomPaint(
          painter: _RingPainter(v, onBreak ? T.ok : T.acc),
          child: SizedBox(width: 270, height: 270, child: Center(child: child)),
        ),
      );
}

class _RingPainter extends CustomPainter {
  final double v;
  final Color color;
  _RingPainter(this.v, this.color);
  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2 - 8;
    final rect = Rect.fromCircle(center: c, radius: r);
    canvas.drawCircle(c, r, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = Colors.white.withOpacity(.10));
    // تیک‌های ظریف ساعت
    final tick = Paint()..color = Colors.white.withOpacity(.18)..strokeWidth = 1.2;
    for (var i = 0; i < 60; i += 5) {
      final a = i / 60 * 2 * 3.14159265 - 3.14159265 / 2;
      canvas.drawLine(c + Offset.fromDirection(a, r - 14), c + Offset.fromDirection(a, r - 8), tick);
    }
    if (v <= 0) return;
    final sweep = v * 2 * 3.14159265;
    canvas.drawArc(rect, -3.14159265 / 2, sweep, false, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round
      ..color = color
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 0.5));
    final end = c + Offset.fromDirection(-3.14159265 / 2 + sweep, r);
    canvas.drawCircle(end, 9, Paint()..color = color.withOpacity(.25));
    canvas.drawCircle(end, 4.5, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(_RingPainter o) => o.v != v || o.color != color;
}
