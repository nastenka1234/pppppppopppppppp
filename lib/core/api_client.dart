import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'config.dart';

class ApiError implements Exception {
  final String code;
  final int status;
  ApiError(this.code, this.status);
  bool get isNetwork => status == 0;

  /// خطاهایی که تقصیر داده نیستند و بعداً درست می‌شوند (اینترنت، سرور، توکن منقضی…).
  /// داده‌ی این درخواست‌ها هیچ‌وقت دور ریخته نمی‌شود.
  bool get isRetryable =>
      status == 0 || status >= 500 || status == 429 || status == 408 || status == 401 || status == 403;

  String get fa {
    switch (code) {
      case 'wrong_password':
        return 'رمز اشتباه است';
      case 'account_disabled':
        return 'این حساب غیرفعال شده است';
      case 'too_many_attempts':
        return 'تلاش زیاد؛ ۱۰ دقیقه‌ی دیگر دوباره امتحان کن';
      case 'password_in_use':
        return 'این رمز قبلاً استفاده شده';
      case 'network':
        return 'ارتباط با سرور برقرار نشد، دوباره تلاش کن';
      case 'bad_password':
        return 'رمز باید حداقل ۶ و حداکثر ۶۴ نویسه باشد';
      case 'insecure_url':
        return 'آدرس سرور باید با https:// شروع شود';
      case 'file_too_large':
        return 'حجم فایل زیاد است (حداکثر ۲۵ مگابایت)؛ فایل را فشرده‌تر کن';
      case 'http_404':
      case 'messages_not_configured':
        return 'پیام‌رسان سمت سرور هنوز فعال نشده؛ Worker باید به‌روزرسانی شود';
      case 'upload_response_invalid':
        return 'سرور پاسخ معتبر برای فایل برنگرداند';
      case 'file_missing':
        return 'فایل انتخاب‌شده دیگر در دسترس نیست';
      case 'media_not_configured':
        return 'فضای رسانه روی سرور هنوز تنظیم نشده';
      case 'order_locked':
        return 'اول اولویت قبلی را تموم کن';
      default:
        return 'مشکلی پیش آمد، دوباره تلاش کن';
    }
  }

  @override
  String toString() => code;
}

class Api {
  Api._();
  static final Api i = Api._();

  final _sec = const FlutterSecureStorage();
  late Dio dio;
  String? token;

  /// شناسه‌ی دانش‌آموزِ واردشده (برای جدا نگه داشتن داده‌ی محلی هر حساب). ادمین: null.
  String? sid;

  /// وقتی true شد یعنی آخرین داده‌ی نمایش‌داده‌شده از حافظه‌ی گوشی آمده نه از سرور.
  final ValueNotifier<bool> offlineData = ValueNotifier(false);
  String baseUrl = Config.defaultBaseUrl;
  void Function()? onUnauthorized;
  void Function()? onDisabled;

  String get _root => baseUrl.replaceAll(RegExp(r'/+$'), '');

  Future<void> init() async {
    final p = await SharedPreferences.getInstance();
    baseUrl = p.getString('baseUrl') ?? Config.defaultBaseUrl;
    token = await _sec.read(key: 'token');
    sid = await _sec.read(key: 'sid');
    _build();
  }

  void _build() {
    dio = Dio(BaseOptions(
      baseUrl: '$_root/api',
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 40),
      sendTimeout: const Duration(minutes: 5),
    ));
    dio.interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
      if (token != null) o.headers['Authorization'] = 'Bearer $token';
      h.next(o);
    }));
  }

  Future<void> setBaseUrl(String u) async {
    u = u.trim();
    // امنیت: توکن و داده‌ها فقط روی HTTPS فرستاده می‌شوند.
    if (!u.toLowerCase().startsWith('https://')) throw ApiError('insecure_url', 400);
    baseUrl = u;
    (await SharedPreferences.getInstance()).setString('baseUrl', baseUrl);
    _build();
  }

  Future<void> setToken(String? t) async {
    token = t;
    if (t == null) {
      await _sec.delete(key: 'token');
    } else {
      await _sec.write(key: 'token', value: t);
    }
  }

  /// زمان صدور توکن (ثانیه‌ی epoch) از خود JWT؛ برای تمدید به‌موقع.
  int? get tokenIssuedAt {
    try {
      final b = token!.split('.')[1];
      final m = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(b)))) as Map;
      return (m['iat'] as num?)?.toInt();
    } catch (_) {
      return null;
    }
  }

  Future<String?> readSecure(String k) => _sec.read(key: k);
  Future<void> writeSecure(String k, String? v) =>
      v == null ? _sec.delete(key: k) : _sec.write(key: k, value: v);

  /// آدرس کامل رسانه (نسبی یا مطلق).
  String abs(String url) {
    if (url.startsWith('http')) return url;
    var u = url.startsWith('/') ? url : '/$url';
    if (u.startsWith('/media')) u = '/api$u';
    return '$_root$u';
  }

  Map<String, String> get authHeaders => {if (token != null) 'Authorization': 'Bearer $token'};

  Future<dynamic> _req(String method, String path,
      {Map<String, dynamic>? q, dynamic body}) async {
    try {
      final r = await dio.request(path,
          queryParameters: q, data: body, options: Options(method: method));
      return r.data;
    } on DioException catch (e) {
      final s = e.response?.statusCode ?? 0;
      var code = 'network';
      final d = e.response?.data;
      if (d is Map && d['error'] != null) {
        code = '${d['error']}';
      } else if (s != 0) {
        code = 'http_$s';
      }
      if (s == 401 && code != 'wrong_password') onUnauthorized?.call();
      if (s == 403 && code == 'account_disabled') onDisabled?.call();
      throw ApiError(code, s);
    }
  }


  // ───────────── کش خواندنی (برای کار آفلاین) ─────────────
  String _ck(String path, Map<String, dynamic>? q) {
    final keys = (q?.keys.toList() ?? [])..sort();
    final qs = keys.map((k) => '$k=${q![k]}').join('&');
    return 'rc:${sid ?? 'admin'}:$path?$qs';
  }

  Future<void> cachePut(String path, Map<String, dynamic>? q, dynamic data) async {
    try {
      (await SharedPreferences.getInstance()).setString(_ck(path, q), jsonEncode(data));
    } catch (_) {}
  }

  Future<dynamic> cacheRead(String path, Map<String, dynamic>? q) async {
    try {
      final raw = (await SharedPreferences.getInstance()).getString(_ck(path, q));
      return raw == null ? null : jsonDecode(raw);
    } catch (_) {
      return null;
    }
  }

  /// GET با کش: اگر سرور در دسترس بود جواب تازه را ذخیره می‌کند؛ اگر اینترنت نبود
  /// (یا سرور خطای ۵xx داد) آخرین جواب ذخیره‌شده را برمی‌گرداند.
  Future<Map<String, dynamic>> getC(String p, {Map<String, dynamic>? q}) async {
    try {
      final d = await _req('GET', p, q: q);
      offlineData.value = false;
      await cachePut(p, q, d);
      return Map<String, dynamic>.from(d as Map);
    } on ApiError catch (e) {
      if (e.status == 0 || e.status >= 500) {
        final c = await cacheRead(p, q);
        if (c is Map) {
          offlineData.value = true;
          return Map<String, dynamic>.from(c);
        }
      }
      rethrow;
    }
  }

  Future<dynamic> getAny(String p, {Map<String, dynamic>? q}) => _req('GET', p, q: q);
  Future<Map<String, dynamic>> get(String p, {Map<String, dynamic>? q}) async =>
      Map<String, dynamic>.from(await _req('GET', p, q: q) as Map);
  Future<Map<String, dynamic>> post(String p, {dynamic body, Map<String, dynamic>? q}) async =>
      Map<String, dynamic>.from(await _req('POST', p, body: body, q: q) as Map);
  Future<Map<String, dynamic>> put(String p, {dynamic body}) async =>
      Map<String, dynamic>.from(await _req('PUT', p, body: body) as Map);
  Future<Map<String, dynamic>> patch(String p, {dynamic body}) async =>
      Map<String, dynamic>.from(await _req('PATCH', p, body: body) as Map);
  Future<Map<String, dynamic>> delete(String p) async =>
      Map<String, dynamic>.from(await _req('DELETE', p) as Map);
}

Map<String, dynamic> sq(String? studentId, [Map<String, dynamic>? extra]) =>
    {if (studentId != null) 'student': studentId, ...?extra};
