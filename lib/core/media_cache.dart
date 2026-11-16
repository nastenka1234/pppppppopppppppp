import 'dart:io';
import 'package:path_provider/path_provider.dart';

class MediaCache {
  static Directory? _dir;
  static Future<Directory> dir() async {
    if (_dir != null) return _dir!;
    final t = await getTemporaryDirectory();
    _dir = await Directory('${t.path}/media').create(recursive: true);
    return _dir!;
  }

  static Future<File> file(String name) async => File('${(await dir()).path}/$name');

  static Future<int> sizeBytes() async {
    var s = 0;
    final d = await dir();
    await for (final e in d.list()) {
      if (e is File) s += await e.length();
    }
    return s;
  }

  static Future<void> clear() async {
    final d = await dir();
    await for (final e in d.list()) {
      try {
        await e.delete(recursive: true);
      } catch (_) {}
    }
  }
}
