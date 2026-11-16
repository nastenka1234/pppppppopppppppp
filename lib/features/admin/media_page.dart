import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../../core/api_client.dart';
import '../../core/jalali.dart';
import '../../core/models.dart';
import '../../theme/glass.dart';
import '../../theme/tokens.dart';
import '../../theme/lottie_views.dart';

class MediaPage extends StatefulWidget {
  const MediaPage({super.key});
  @override
  State<MediaPage> createState() => _MediaPageState();
}

class _MediaPageState extends State<MediaPage> {
  List<Track> music = [];
  List<FocusVideo> videos = [];
  String? error;
  bool loading = true;
  double? progress;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final m = await Api.i.get('/music');
      final v = await Api.i.get('/focus/videos');
      music = [for (final x in (m['tracks'] as List? ?? [])) Track.fromJson(x)];
      videos = [for (final x in (v['videos'] as List? ?? [])) FocusVideo.fromJson(x)];
      error = null;
    } on ApiError catch (e) {
      error = e.fa;
    }
    if (mounted) setState(() => loading = false);
  }

  Future<void> _upload(String kind) async {
    final pick = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: kind == 'music' ? ['mp3', 'm4a', 'ogg', 'wav'] : ['mp4', 'webm'],
    );
    final path = pick?.files.single.path;
    if (path == null || !mounted) return;
    final title = TextEditingController(text: pick!.files.single.name.replaceAll(RegExp(r'\.[^.]+$'), ''));
    final tag = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(kind == 'music' ? 'آپلود موزیک' : 'آپلود ویدیو'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: title, decoration: const InputDecoration(labelText: 'عنوان')),
          const SizedBox(height: 10),
          TextField(controller: tag, decoration: const InputDecoration(labelText: 'برچسب (اختیاری)')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('انصراف')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('آپلود')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => progress = 0);
    try {
      final form = FormData.fromMap({
        'kind': kind,
        'title': title.text.trim(),
        'tag': tag.text.trim(),
        'file': await MultipartFile.fromFile(path),
      });
      await Api.i.dio.post('/admin/media',
          data: form, onSendProgress: (a, b) => setState(() => progress = b <= 0 ? null : a / b));
      await _load();
    } on DioException catch (e) {
      final d = e.response?.data;
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(d is Map && d['error'] != null ? '${d['error']}' : 'آپلود ناموفق بود')));
      }
    }
    if (mounted) setState(() => progress = null);
  }

  Future<void> _delete(String id) async {
    try {
      await Api.i.delete('/admin/media/$id');
      await _load();
    } on ApiError catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.fa)));
    }
  }

  Widget _row(String id, String title, String sub, IconData icon) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Glass(
          radius: 22,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          child: Row(children: [
            Icon(icon, color: T.acc),
            const SizedBox(width: 10),
            Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
              if (sub.isNotEmpty) Text(sub, style: const TextStyle(color: T.tx2, fontSize: 12)),
            ])),
            IconButton(icon: const Icon(Icons.delete_outline_rounded), onPressed: () => _delete(id)),
          ]),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('موزیک و ویدیو')),
      body: SafeArea(
        child: loading
            ? const AppLoader()
            : ListView(padding: const EdgeInsets.all(16), children: [
                if (error != null) Glass(child: Text(error!)),
                if (progress != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: LinearProgressIndicator(value: progress, color: T.acc, backgroundColor: T.glass),
                  ),
                Row(children: [
                  Expanded(child: GhostButton('آپلود موزیک', icon: Icons.upload_rounded, onPressed: () => _upload('music'))),
                  const SizedBox(width: 10),
                  Expanded(child: GhostButton('آپلود ویدیو', icon: Icons.upload_rounded, onPressed: () => _upload('video'))),
                ]),
                const PageTitle('موزیک‌ها'),
                for (final t in music) _row(t.id, t.title, '${t.tag} ${clock(t.duration)}', Icons.music_note_rounded),
                const PageTitle('ویدیوهای اتاق تمرکز'),
                for (final v in videos) _row(v.id, v.title, '', Icons.movie_rounded),
              ]),
      ),
    );
  }
}
