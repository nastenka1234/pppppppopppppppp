import 'dart:io';
import 'package:dio/dio.dart';
import 'api_client.dart';

class MessageThread {
  final String studentId;
  final String name;
  final String lastMessage;
  final String updatedAt;
  final int unread;

  const MessageThread({
    required this.studentId,
    required this.name,
    required this.lastMessage,
    required this.updatedAt,
    required this.unread,
  });

  factory MessageThread.fromJson(Map j) => MessageThread(
        studentId: '${j['student_id'] ?? j['student'] ?? j['id'] ?? ''}',
        name: '${j['name'] ?? j['student_name'] ?? 'دانش‌آموز'}',
        lastMessage: '${j['last_message'] ?? j['preview'] ?? ''}',
        updatedAt: '${j['updated_at'] ?? j['last_at'] ?? ''}',
        unread: (j['unread'] as num?)?.toInt() ?? 0,
      );
}

class ChatMessage {
  final String id;
  final String type;
  final String text;
  final String attachmentUrl;
  final String attachmentName;
  final String mimeType;
  final String createdAt;
  final bool mine;

  const ChatMessage({
    required this.id,
    required this.type,
    required this.text,
    required this.attachmentUrl,
    required this.attachmentName,
    required this.mimeType,
    required this.createdAt,
    required this.mine,
  });

  factory ChatMessage.fromJson(Map j) {
    final attachment = j['attachment'] is Map ? j['attachment'] as Map : const {};
    final role = '${j['sender_role'] ?? j['role'] ?? ''}';
    final currentRole = Api.i.sid == null ? 'admin' : 'student';
    return ChatMessage(
      id: '${j['id'] ?? ''}',
      type: '${j['type'] ?? 'text'}',
      text: '${j['text'] ?? j['body'] ?? ''}',
      attachmentUrl: '${j['attachment_url'] ?? j['file_url'] ?? attachment['url'] ?? ''}',
      attachmentName: '${j['attachment_name'] ?? j['file_name'] ?? attachment['name'] ?? ''}',
      mimeType: '${j['mime_type'] ?? attachment['mime_type'] ?? ''}',
      createdAt: '${j['created_at'] ?? j['sent_at'] ?? ''}',
      mine: j['mine'] == true || j['is_mine'] == true || j['from_me'] == true || role == currentRole,
    );
  }
}

/// قرارداد شبکه‌ی پیام‌رسان. مسیرهای این کلاس باید در Worker نیز پیاده‌سازی شوند؛
/// قرارداد کامل و نمونه‌ی پاسخ‌ها در docs/messenger-worker-contract.md آمده است.
class MessengerApi {
  static Future<List<MessageThread>> threads() async {
    final r = await Api.i.get('/messages/threads');
    return [for (final x in (r['threads'] as List? ?? [])) MessageThread.fromJson(x as Map)];
  }

  static Future<List<ChatMessage>> messages({String? studentId}) async {
    final r = await Api.i.get('/messages', q: {
      if (studentId != null && studentId.isNotEmpty) 'student': studentId,
    });
    return [for (final x in (r['messages'] as List? ?? [])) ChatMessage.fromJson(x as Map)];
  }

  static Future<void> sendText(String text, {String? studentId}) async {
    await Api.i.post('/messages', body: {
      'type': 'text',
      'text': text.trim(),
      if (studentId != null && studentId.isNotEmpty) 'student_id': studentId,
    });
  }

  static Future<void> sendFile({
    required String path,
    required String type,
    required String name,
    required String mimeType,
    String? studentId,
  }) async {
    final file = File(path);
    if (!await file.exists()) throw ApiError('file_missing', 400);
    final size = await file.length();
    if (size > 25 * 1024 * 1024) throw ApiError('file_too_large', 413);

    final form = FormData.fromMap({
      'file': await MultipartFile.fromFile(path, filename: name),
      'kind': type,
    });
    final upload = await Api.i.dio.post('/messages/upload', data: form);
    final data = upload.data is Map ? upload.data as Map : const {};
    final nested = data['file'] is Map ? data['file'] as Map : const {};
    final url = '${data['url'] ?? data['file_url'] ?? nested['url'] ?? ''}';
    if (url.isEmpty) throw ApiError('upload_response_invalid', 502);

    await Api.i.post('/messages', body: {
      'type': type,
      'text': '',
      'attachment_url': url,
      'attachment_name': name,
      'mime_type': mimeType,
      'size': size,
      if (studentId != null && studentId.isNotEmpty) 'student_id': studentId,
    });
  }
}
