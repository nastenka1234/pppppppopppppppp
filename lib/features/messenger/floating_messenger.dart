import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';
import 'package:file_picker/file_picker.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import '../../core/api_client.dart';
import '../../core/auth_store.dart';
import '../../core/jalali.dart';
import '../../core/messenger.dart';
import '../../theme/tokens.dart';
import '../report/weekly_report_pdf.dart';

class MessengerLauncher {
  static final ValueNotifier<bool> open = ValueNotifier(false);
  static final ValueNotifier<int> revision = ValueNotifier(0);

  static void show({bool refresh = false}) {
    open.value = true;
    if (refresh) revision.value++;
  }

  static void refresh() => revision.value++;
}

/// شناور داخل محیط اپ؛ روی صفحه‌ی تمرکز هم باقی می‌ماند، اما بیرون از اپ overlay سیستم نیست.
class FloatingMessengerLayer extends ConsumerStatefulWidget {
  const FloatingMessengerLayer({super.key});

  @override
  ConsumerState<FloatingMessengerLayer> createState() => _FloatingMessengerLayerState();
}

class _FloatingMessengerLayerState extends ConsumerState<FloatingMessengerLayer> with SingleTickerProviderStateMixin {
  bool _expanded = false;
  bool _faded = false;
  bool _loading = false;
  bool _sending = false;
  bool _loadedOnce = false;
  String? _error;
  String? _selectedStudentId;
  String _selectedStudentName = '';
  List<MessageThread> _threads = [];
  List<ChatMessage> _messages = [];
  Offset? _position;
  Timer? _poller;
  bool _requesting = false;
  int _requestEpoch = 0;
  final _text = TextEditingController();
  final _scroll = ScrollController();
  late final AnimationController _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 2200))..repeat();

  bool get _isAdmin => ref.read(authProvider)?.isAdmin == true;
  String? get _targetStudent => _isAdmin ? _selectedStudentId : null;

  @override
  void initState() {
    super.initState();
    MessengerLauncher.open.addListener(_onOpenChanged);
    MessengerLauncher.revision.addListener(_onRevisionChanged);
    _poller = Timer.periodic(const Duration(seconds: 8), (_) {
      if (_expanded) _load(silent: true);
    });
    if (MessengerLauncher.open.value) {
      _expanded = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _load());
    }
  }

  @override
  void dispose() {
    MessengerLauncher.open.removeListener(_onOpenChanged);
    MessengerLauncher.revision.removeListener(_onRevisionChanged);
    _poller?.cancel();
    _pulse.dispose();
    _text.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onOpenChanged() {
    if (!mounted) return;
    setState(() => _expanded = MessengerLauncher.open.value);
    if (_expanded) _load();
  }

  void _onRevisionChanged() {
    if (!mounted) return;
    if (_expanded) _load();
  }

  Future<void> _load({bool silent = false}) async {
    if (_requesting) return;
    if (_isAdmin && _selectedStudentId == null) {
      final requestEpoch = _requestEpoch;
      _requesting = true;
      if (!silent && mounted) setState(() { _loading = true; _error = null; });
      try {
        final data = await MessengerApi.threads();
        if (!mounted || requestEpoch != _requestEpoch) return;
        setState(() { _threads = data; _error = null; _loadedOnce = true; });
      } on ApiError catch (e) {
        if (mounted && requestEpoch == _requestEpoch) setState(() => _error = e.fa);
      } catch (_) {
        if (mounted && requestEpoch == _requestEpoch) setState(() => _error = 'دریافت پیام‌ها ممکن نشد');
      } finally {
        _requesting = false;
        if (mounted && requestEpoch == _requestEpoch) {
          setState(() => _loading = false);
        } else if (mounted && _expanded) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && !_requesting && _expanded) _load();
          });
        }
      }
      return;
    }

    final requestEpoch = _requestEpoch;
    _requesting = true;
    if (!silent && mounted) setState(() { _loading = true; _error = null; });
    try {
      final data = await MessengerApi.messages(studentId: _targetStudent);
      if (!mounted || requestEpoch != _requestEpoch) return;
      setState(() { _messages = data; _error = null; _loadedOnce = true; });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients && requestEpoch == _requestEpoch) _scroll.jumpTo(_scroll.position.maxScrollExtent);
      });
    } on ApiError catch (e) {
      if (mounted && requestEpoch == _requestEpoch) setState(() => _error = e.fa);
    } catch (_) {
      if (mounted && requestEpoch == _requestEpoch) setState(() => _error = 'دریافت گفتگو ممکن نشد');
    } finally {
      _requesting = false;
      if (mounted && requestEpoch == _requestEpoch) {
        setState(() => _loading = false);
      } else if (mounted && _expanded) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && !_requesting && _expanded) _load();
        });
      }
    }
  }

  void _selectThread(MessageThread thread) {
    _requestEpoch++;
    setState(() {
      _selectedStudentId = thread.studentId;
      _selectedStudentName = thread.name;
      _messages = [];
      _error = null;
      _loadedOnce = false;
    });
    _load();
  }

  void _backToThreads() {
    _requestEpoch++;
    setState(() {
      _selectedStudentId = null;
      _selectedStudentName = '';
      _messages = [];
      _error = null;
      _loadedOnce = false;
    });
    _load();
  }

  Future<void> _sendText() async {
    final value = _text.text.trim();
    if (value.isEmpty || _sending || (_isAdmin && _selectedStudentId == null)) return;
    _text.clear();
    setState(() => _sending = true);
    try {
      await MessengerApi.sendText(value, studentId: _targetStudent);
      await _load(silent: true);
    } on ApiError catch (e) {
      if (mounted) {
        _text.text = value;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.fa)));
      }
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('ارسال پیام ناموفق بود')));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _pickImage() async {
    if (_sending || (_isAdmin && _selectedStudentId == null)) return;
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png', 'webp'],
    );
    final path = picked?.files.single.path;
    if (path == null) return;
    await _sendAttachment(path, 'image', picked!.files.single.name, _imageMime(path));
  }

  String _imageMime(String path) {
    final ext = path.split('.').last.toLowerCase();
    if (ext == 'png') return 'image/png';
    if (ext == 'webp') return 'image/webp';
    return 'image/jpeg';
  }

  Future<void> _sendAttachment(String path, String type, String name, String mime) async {
    if (_sending || (_isAdmin && _selectedStudentId == null)) return;
    setState(() => _sending = true);
    try {
      await MessengerApi.sendFile(
        path: path,
        type: type,
        name: name,
        mimeType: mime,
        studentId: _targetStudent,
      );
      await _load(silent: true);
    } on ApiError catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.fa)));
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('ارسال فایل ناموفق بود')));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _sendWeeklyReport() async {
    if (_sending) return;
    setState(() => _sending = true);
    try {
      await WeeklyReportSender.send();
      if (!mounted) return;
      MessengerLauncher.refresh();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('گزارش هفتگی به گفتگو ارسال شد')));
    } on ApiError catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.fa)));
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('ساخت یا ارسال PDF ناموفق بود')));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _move(Offset delta, Size screen, {required double width, required double height}) {
    final current = _position ?? Offset(screen.width - 72, screen.height - 160);
    final next = current + delta;
    setState(() {
      _position = Offset(
        next.dx.clamp(8.0, math.max(8.0, screen.width - width - 8)).toDouble(),
        next.dy.clamp(8.0, math.max(8.0, screen.height - height - 8)).toDouble(),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(authProvider);
    ref.listen<Session?>(authProvider, (previous, next) {
      final accountChanged = previous != null &&
          (next == null || previous.role != next.role || previous.studentId != next.studentId);
      if (!accountChanged) return;
      _requestEpoch++;
      MessengerLauncher.open.value = false;
      _text.clear();
      if (mounted) {
        setState(() {
          _expanded = false;
          _selectedStudentId = null;
          _selectedStudentName = '';
          _threads = [];
          _messages = [];
          _loadedOnce = false;
          _loading = false;
          _error = null;
          _position = null;
        });
      }
    });
    if (session == null) return const SizedBox.shrink();
    return LayoutBuilder(builder: (context, constraints) {
      final fullScreen = Size(constraints.maxWidth, constraints.maxHeight);
      final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
      final screen = Size(fullScreen.width, math.max(280.0, fullScreen.height - keyboardInset).toDouble());
      final panelWidth = math.min(390.0, math.max(270.0, screen.width - 20)).toDouble();
      final panelHeight = math.min(620.0, math.max(280.0, screen.height - 24)).toDouble();
      final width = _expanded ? panelWidth : 62.0;
      final height = _expanded ? panelHeight : 62.0;
      final fallback = _expanded
          ? Offset(math.max(8.0, screen.width - panelWidth - 12).toDouble(), math.max(8.0, screen.height - panelHeight - 90).toDouble())
          : Offset(math.max(8.0, screen.width - 76).toDouble(), math.max(8.0, screen.height - 170).toDouble());
      final pos = _position ?? fallback;
      final safeLeft = pos.dx.clamp(8.0, math.max(8.0, screen.width - width - 8)).toDouble();
      final safeTop = pos.dy.clamp(8.0, math.max(8.0, screen.height - height - 8)).toDouble();
      if (_position == null) _position = Offset(safeLeft, safeTop);

      return Stack(clipBehavior: Clip.none, children: [
        Positioned(
        left: safeLeft,
        top: safeTop,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 360),
          reverseDuration: const Duration(milliseconds: 240),
          switchInCurve: Curves.easeOutBack,
          switchOutCurve: Curves.easeInCubic,
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: ScaleTransition(scale: Tween<double>(begin: .82, end: 1).animate(animation), child: child),
          ),
          child: _expanded
              ? _buildPanel(screen, panelWidth, panelHeight, key: const ValueKey('expanded-chat'))
              : _buildBubble(screen, key: const ValueKey('chat-bubble')),
        ),
        ),
      ]);
    });
  }

  Widget _buildBubble(Size screen, {required Key key}) => GestureDetector(
        key: key,
        onPanUpdate: (d) => _move(d.delta, screen, width: 62, height: 62),
        onTap: () {
          MessengerLauncher.open.value = true;
          setState(() => _expanded = true);
          _load();
        },
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 250),
          opacity: _faded ? .38 : 1,
          child: AnimatedBuilder(
            animation: _pulse,
            builder: (_, child) {
              final t = (math.sin(_pulse.value * math.pi * 2) + 1) / 2;
              return Transform.scale(
                scale: 1 + t * .035,
                child: Container(
                  width: 62,
                  height: 62,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFFF965B), T.acc, Color(0xFFB83E17)]),
                    boxShadow: [
                      BoxShadow(color: T.acc.withOpacity(.22 + t * .23), blurRadius: 15 + t * 12, spreadRadius: t * 2, offset: const Offset(0, 7)),
                      const BoxShadow(color: Colors.black45, blurRadius: 12, offset: Offset(0, 5)),
                    ],
                    border: Border.all(color: Colors.white.withOpacity(.24), width: 1.2),
                  ),
                  child: child,
                ),
              );
            },
            child: const Stack(alignment: Alignment.center, children: [
              Icon(Icons.forum_rounded, color: T.onAcc, size: 27),
              Positioned(right: 11, top: 10, child: Icon(Icons.circle, size: 8, color: Colors.white)),
            ]),
          ),
        ),
      );

  Widget _buildPanel(Size screen, double width, double height, {required Key key}) => AnimatedOpacity(
        key: key,
        duration: const Duration(milliseconds: 280),
        opacity: _faded ? .42 : 1,
        child: ClipRRect(
            borderRadius: BorderRadius.circular(26),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
              child: Container(
                width: width,
                height: height,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xF52A2224), Color(0xF5161316)]),
                  borderRadius: BorderRadius.circular(26),
                  border: Border.all(color: Colors.white.withOpacity(.13), width: 1),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(.48), blurRadius: 32, spreadRadius: 1, offset: const Offset(0, 14))],
                ),
                child: Column(children: [
                  _header(screen, width, height),
                  const Divider(height: 1, color: T.line),
                  Expanded(child: _isAdmin && _selectedStudentId == null ? _threadList() : _conversation()),
                  if (!_isAdmin || _selectedStudentId != null) _composer(),
                ]),
              ),
            ),
          ),
      );

  Widget _header(Size screen, double width, double height) => GestureDetector(
        onPanUpdate: (d) => _move(d.delta, screen, width: width, height: height),
        child: Container(
        padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
        decoration: const BoxDecoration(
          gradient: LinearGradient(begin: Alignment.centerRight, end: Alignment.centerLeft, colors: [Color(0xFF352529), Color(0xFF241E20)]),
        ),
        child: Row(children: [
          if (_isAdmin && _selectedStudentId != null)
            _headerButton(Icons.arrow_forward_rounded, 'بازگشت به گفتگوها', _backToThreads),
          Container(
            width: 39,
            height: 39,
            decoration: BoxDecoration(shape: BoxShape.circle, color: T.acc.withOpacity(.17), border: Border.all(color: T.acc.withOpacity(.42))),
            child: const Icon(Icons.forum_rounded, color: T.acc, size: 20),
          ),
          const SizedBox(width: 9),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_isAdmin ? (_selectedStudentId == null ? 'پیام‌های دانش‌آموزان' : _selectedStudentName) : 'گفتگو با مشاور',
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: T.tx, fontSize: 13, fontWeight: FontWeight.w900)),
              const SizedBox(height: 1),
              const Text('پیام‌رسان امید', style: TextStyle(color: T.tx2, fontSize: 10)),
            ])),
          if (!_isAdmin)
            _headerButton(Icons.picture_as_pdf_rounded, 'ارسال گزارش هفتگی', _sendWeeklyReport),
          _headerButton(_faded ? Icons.visibility_rounded : Icons.blur_on_rounded, 'تغییر شفافیت', () => setState(() => _faded = !_faded)),
          _headerButton(Icons.remove_rounded, 'کوچک کردن', () {
            setState(() => _expanded = false);
            MessengerLauncher.open.value = false;
          }),
        ]),
      ));

  Widget _headerButton(IconData icon, String tooltip, VoidCallback onTap) => Tooltip(
        message: tooltip,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(padding: const EdgeInsets.all(7), child: Icon(icon, color: T.tx2, size: 19)),
        ),
      );

  Widget _threadList() {
    if (_loading && !_loadedOnce) return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    if (_error != null && _threads.isEmpty) return _emptyState(_error!, retry: _load);
    if (_threads.isEmpty) return _emptyState('هنوز گفتگویی وجود ندارد');
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: _threads.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final t = _threads[index];
        return Material(
          color: T.surfaceHi.withOpacity(.8),
          borderRadius: BorderRadius.circular(17),
          child: InkWell(
            borderRadius: BorderRadius.circular(17),
            onTap: () => _selectThread(t),
            child: Padding(
              padding: const EdgeInsets.all(11),
              child: Row(children: [
                CircleAvatar(radius: 21, backgroundColor: T.acc.withOpacity(.16), child: const Icon(Icons.person_rounded, color: T.acc)),
                const SizedBox(width: 10),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(t.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
                  const SizedBox(height: 3),
                  Text(t.lastMessage.isEmpty ? 'شروع گفتگو' : t.lastMessage, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: T.tx2, fontSize: 10)),
                ])),
                if (t.unread > 0) Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(color: T.acc, borderRadius: BorderRadius.circular(20)),
                  child: Text(fa(t.unread), style: const TextStyle(color: T.onAcc, fontWeight: FontWeight.w900, fontSize: 10)),
                ),
                const SizedBox(width: 3),
                const Icon(Icons.chevron_left_rounded, color: T.tx2, size: 18),
              ]),
            ),
          ),
        );
      },
    );
  }

  Widget _conversation() {
    if (_loading && !_loadedOnce) return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    if (_error != null && _messages.isEmpty) return _emptyState(_error!, retry: _load);
    if (_messages.isEmpty) {
      return Center(child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 64, height: 64, decoration: BoxDecoration(color: T.acc.withOpacity(.12), shape: BoxShape.circle), child: const Icon(Icons.chat_bubble_outline_rounded, color: T.acc, size: 27)),
          const SizedBox(height: 12),
          const Text('گفتگو از اینجا شروع می‌شود', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
          const SizedBox(height: 5),
          const Text('متن، عکس یا ویس بفرست.', style: TextStyle(color: T.tx2, fontSize: 11)),
        ]),
      ));
    }
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(11, 12, 11, 10),
      itemCount: _messages.length,
      itemBuilder: (_, i) => _MessageBubble(message: _messages[i]),
    );
  }

  Widget _emptyState(String label, {VoidCallback? retry}) => Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.cloud_off_rounded, color: T.tx2, size: 28),
            const SizedBox(height: 8),
            Text(label, textAlign: TextAlign.center, style: const TextStyle(color: T.tx2, fontSize: 11)),
            if (retry != null) TextButton.icon(onPressed: retry, icon: const Icon(Icons.refresh_rounded, size: 16), label: const Text('تلاش دوباره')),
          ]),
        ),
      );

  Widget _composer() => Container(
        padding: const EdgeInsets.fromLTRB(9, 9, 9, 10),
        decoration: const BoxDecoration(color: Color(0xFF201B1D), border: Border(top: BorderSide(color: T.line))),
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          _composerButton(Icons.add_photo_alternate_rounded, 'ارسال عکس', _sending ? null : _pickImage),
          Expanded(
            child: Container(
              constraints: const BoxConstraints(minHeight: 42, maxHeight: 88),
              decoration: BoxDecoration(color: T.bg, borderRadius: BorderRadius.circular(16), border: Border.all(color: T.line2)),
              child: TextField(
                controller: _text,
                minLines: 1,
                maxLines: 3,
                textInputAction: TextInputAction.newline,
                style: const TextStyle(fontSize: 12, color: T.tx),
                decoration: const InputDecoration(
                  hintText: 'پیامت رو بنویس...',
                  hintStyle: TextStyle(fontSize: 11),
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  filled: false,
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          Material(
            color: T.acc,
            borderRadius: BorderRadius.circular(15),
            child: InkWell(
              borderRadius: BorderRadius.circular(15),
              onTap: _sending ? null : _sendText,
              child: SizedBox(width: 42, height: 42, child: Center(
                child: _sending
                    ? const SizedBox(width: 17, height: 17, child: CircularProgressIndicator(strokeWidth: 2, color: T.onAcc))
                    : const Icon(Icons.send_rounded, color: T.onAcc, size: 19),
              )),
            ),
          ),
        ]),
      );

  Widget _composerButton(IconData icon, String tooltip, VoidCallback? action, {Color color = T.tx2}) => Tooltip(
        message: tooltip,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: action,
          child: Padding(padding: const EdgeInsets.all(8), child: Icon(icon, size: 20, color: action == null ? T.line2 : color)),
        ),
      );
}

class _MessageBubble extends StatelessWidget {
  final ChatMessage message;
  const _MessageBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    final mine = message.mine;
    final time = parseTs(message.createdAt);
    final stamp = time == null ? '' : fa('${time.toLocal().hour.toString().padLeft(2, '0')}:${time.toLocal().minute.toString().padLeft(2, '0')}');
    return Align(
      alignment: mine ? AlignmentDirectional.centerStart : AlignmentDirectional.centerEnd,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 290),
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(9),
        decoration: BoxDecoration(
          color: mine ? const Color(0xFF493027) : const Color(0xFF292326),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(mine ? 5 : 16),
            bottomRight: Radius.circular(mine ? 16 : 5),
          ),
          border: Border.all(color: Colors.white.withOpacity(.045)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (message.type == 'image' && message.attachmentUrl.isNotEmpty)
            _ImageAttachment(url: message.attachmentUrl, name: message.attachmentName),
          if (message.type == 'audio' && message.attachmentUrl.isNotEmpty)
            _AudioAttachment(url: message.attachmentUrl),
          if ((message.type == 'document' || message.type == 'file') && message.attachmentUrl.isNotEmpty)
            _DocumentAttachment(name: message.attachmentName, url: message.attachmentUrl),
          if (message.text.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(message.text, style: const TextStyle(fontSize: 11, height: 1.6, color: T.tx)),
            ),
          if (stamp.isNotEmpty)
            Align(alignment: AlignmentDirectional.centerStart, child: Text(stamp, style: TextStyle(fontSize: 9, color: T.tx2.withOpacity(.75)))),
        ]),
      ),
    );
  }
}

class _ImageAttachment extends StatelessWidget {
  final String url, name;
  const _ImageAttachment({required this.url, required this.name});
  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: () => showDialog<void>(
          context: context,
          builder: (_) => Dialog(
            backgroundColor: T.bg,
            insetPadding: const EdgeInsets.all(12),
            child: InteractiveViewer(child: Image.network(Api.i.abs(url), headers: Api.i.authHeaders, fit: BoxFit.contain, errorBuilder: (_, __, ___) => const Padding(padding: EdgeInsets.all(25), child: Icon(Icons.broken_image_rounded, size: 44)))),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(11),
            child: Image.network(
              Api.i.abs(url),
              headers: Api.i.authHeaders,
              width: 220,
              height: 150,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(width: 220, height: 80, color: T.bg, child: const Icon(Icons.broken_image_rounded, color: T.tx2)),
            ),
          ),
        ),
      );
}

class _AudioAttachment extends StatefulWidget {
  final String url;
  const _AudioAttachment({required this.url});
  @override
  State<_AudioAttachment> createState() => _AudioAttachmentState();
}

class _AudioAttachmentState extends State<_AudioAttachment> {
  late final AudioPlayer _player = AudioPlayer(useProxyForRequestHeaders: false);
  bool _sourceReady = false;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    if (_player.playing) {
      await _player.pause();
      if (mounted) setState(() {});
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      if (!_sourceReady) {
        await _player.setUrl(Api.i.abs(widget.url), headers: Api.i.authHeaders);
        _sourceReady = true;
      }
      if (mounted) setState(() => _loading = false);
      // پس از پایان، لمس دوباره از ابتدای ویس پخش می‌کند.
      if (_player.processingState == ProcessingState.completed) {
        await _player.seek(Duration.zero);
      }
      // play() تا پایان فایل Future را باز نگه می‌دارد؛ نباید دکمه‌ی توقف قفل شود.
      unawaited(_player.play().catchError((Object _) {
        if (mounted) setState(() => _error = 'پخش نشد');
      }));
    } catch (_) {
      if (mounted) setState(() { _error = 'پخش نشد'; _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) => Container(
        width: 205,
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
        decoration: BoxDecoration(color: T.bg.withOpacity(.55), borderRadius: BorderRadius.circular(12)),
        child: Row(children: [
          InkWell(
            onTap: _loading ? null : _toggle,
            borderRadius: BorderRadius.circular(20),
            child: CircleAvatar(
              radius: 16,
              backgroundColor: T.acc,
              child: _loading
                  ? const SizedBox(width: 13, height: 13, child: CircularProgressIndicator(strokeWidth: 1.7, color: T.onAcc))
                  : StreamBuilder<PlayerState>(
                      stream: _player.playerStateStream,
                      initialData: _player.playerState,
                      builder: (_, snap) => Icon(snap.data?.playing == true ? Icons.pause_rounded : Icons.play_arrow_rounded, color: T.onAcc, size: 20),
                    ),
            ),
          ),
          const SizedBox(width: 9),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('پیام صوتی', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700)),
            if (_error != null) Text(_error!, style: const TextStyle(fontSize: 9, color: T.bad)),
            StreamBuilder<Duration?>(
              stream: _player.durationStream,
              builder: (_, snap) => Text(_duration(snap.data), style: const TextStyle(color: T.tx2, fontSize: 9)),
            ),
          ])),
          const Icon(Icons.graphic_eq_rounded, color: T.acc, size: 20),
        ]),
      );

  String _duration(Duration? d) => d == null ? 'ویس' : '${fa(d.inMinutes.toString().padLeft(2, '0'))}:${fa((d.inSeconds % 60).toString().padLeft(2, '0'))}';
}

class _DocumentAttachment extends StatefulWidget {
  final String name, url;
  const _DocumentAttachment({required this.name, required this.url});

  @override
  State<_DocumentAttachment> createState() => _DocumentAttachmentState();
}

class _DocumentAttachmentState extends State<_DocumentAttachment> {
  bool _downloading = false;

  Future<void> _open() async {
    if (_downloading) return;
    setState(() => _downloading = true);
    try {
      final response = await Api.i.dio.get<List<int>>(
        Api.i.abs(widget.url),
        options: Options(responseType: ResponseType.bytes),
      );
      final dir = await getTemporaryDirectory();
      final safeName = widget.name.isEmpty ? 'omid-report.pdf' : widget.name.replaceAll(RegExp(r'[^\w\-.ا-ی]'), '_');
      final file = File('${dir.path}/$safeName');
      await file.writeAsBytes(response.data ?? const <int>[], flush: true);
      await OpenFilex.open(file.path);
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('باز کردن فایل ممکن نشد')));
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: _open,
        child: Container(
          width: 220,
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: T.bg.withOpacity(.55), borderRadius: BorderRadius.circular(12)),
          child: Row(children: [
            Container(width: 34, height: 38, decoration: BoxDecoration(color: T.acc.withOpacity(.15), borderRadius: BorderRadius.circular(8)), child: const Icon(Icons.picture_as_pdf_rounded, color: T.acc)),
            const SizedBox(width: 9),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(widget.name.isEmpty ? 'سند پیوست' : widget.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800)),
              const Text('PDF · گزارش هفتگی', style: TextStyle(fontSize: 9, color: T.tx2)),
            ])),
            _downloading
                ? const SizedBox(width: 15, height: 15, child: CircularProgressIndicator(strokeWidth: 1.7))
                : const Icon(Icons.download_rounded, color: T.tx2, size: 17),
          ]),
        ),
      );
}
