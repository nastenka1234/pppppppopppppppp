import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'api_client.dart';
import 'live.dart';
import 'offline_queue.dart';
import 'sync_service.dart';

class Session {
  final String role; // admin | student
  final String name;
  final String? studentId;
  const Session(this.role, this.name, this.studentId);
  bool get isAdmin => role == 'admin';
}

class AuthNotifier extends StateNotifier<Session?> {
  AuthNotifier(super.initial);

  static Future<Session?> restore() async {
    final api = Api.i;
    if (api.token == null) return null;
    final role = await api.readSecure('role');
    if (role == null) return null;
    return Session(role, await api.readSecure('name') ?? '', await api.readSecure('sid'));
  }

  Future<void> login(String password) async {
    final r = await Api.i.post('/login', body: {'password': password});
    final role = '${r['role']}';
    final st = r['student'] as Map?;
    await Api.i.setToken('${r['token']}');
    await Api.i.writeSecure('role', role);
    await Api.i.writeSecure('name', st == null ? 'مشاور' : '${st['name']}');
    await Api.i.writeSecure('sid', st == null ? null : '${st['id']}');
    Api.i.sid = st == null ? null : '${st['id']}';
    state = Session(role, st == null ? 'مشاور' : '${st['name']}', st == null ? null : '${st['id']}');
    if (role == 'student') {
      Live.start();
      SyncService.start(); // مهاجرت داده‌ی محلی + ارسال صف + کار ۶ ساعته‌ی پس‌زمینه
    }
  }

  /// خروج فقط نشست را می‌بندد؛ صف ارسال، پیشرفت و کش روی گوشی می‌مانند
  /// و با ورود دوباره‌ی همان حساب ارسال می‌شوند.
  Future<void> logout() async {
    Live.stop();
    await SyncService.stop();
    Api.i.sid = null;
    OfflineQueue.i.refreshCount();
    await Api.i.setToken(null);
    await Api.i.writeSecure('role', null);
    await Api.i.writeSecure('name', null);
    await Api.i.writeSecure('sid', null);
    state = null;
  }
}

final authProvider =
    StateNotifierProvider<AuthNotifier, Session?>((ref) => throw UnimplementedError());

/// پیام یک‌بارمصرف برای صفحه‌ی ورود (مثلاً حساب غیرفعال).
final flashProvider = StateProvider<String?>((ref) => null);
