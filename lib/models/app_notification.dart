import 'package:love_vibe_pro/utils/date_util.dart';

class AppNotification {
  final int id;
  final int userId;
  final int? senderId;
  final String? senderName;
  final String? senderAvatar;
  final String type;
  final String title;
  final String message;
  final int? referenceId;
  final String? referenceImage;
  final bool isRead;
  final DateTime createdAt;

  AppNotification({
    required this.id,
    required this.userId,
    this.senderId,
    this.senderName,
    this.senderAvatar,
    required this.type,
    required this.title,
    required this.message,
    this.referenceId,
    this.referenceImage,
    required this.isRead,
    required this.createdAt,
  });

  factory AppNotification.fromJson(Map<String, dynamic> json) {
    String? toStr(dynamic v) {
      if (v == null) return null;
      final s = v.toString().trim();
      return s.isEmpty ? null : s;
    }

    int? toInt(dynamic v) {
      if (v == null) return null;
      if (v is int) return v;
      return int.tryParse(v.toString());
    }

    return AppNotification(
      id: toInt(json['id']) ?? 0,
      userId: toInt(json['user_id']) ?? 0,
      senderId: toInt(json['sender_id']),
      senderName: toStr(json['sender_name'] ?? json['sender_full_name']),
      senderAvatar: toStr(json['sender_avatar']),
      type: json['type']?.toString() ?? 'system',
      title: json['title']?.toString() ?? '',
      message: json['message']?.toString() ?? '',
      referenceId: toInt(json['reference_id']),
      referenceImage: toStr(json['reference_image']),
      isRead: json['is_read'] == 1 ||
          json['is_read'] == true ||
          json['is_read'] == '1',
      createdAt: DateUtil.parseServerTime(json['created_at']?.toString()),
    );
  }
}
