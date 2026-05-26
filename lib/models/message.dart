import 'package:uuid/uuid.dart';
import 'package:love_vibe_pro/utils/date_util.dart';

enum MessageType { text, image, video, voice, call }

enum MessageStatus { sending, sent, delivered, read, failed }

class Message {
  final String id;
  final String senderId;
  final String receiverId;
  final String? conversationId;
  final MessageType type;
  final String? content; // Text content or file path
  final String? mediaUrl; // For image/video/voice
  final String? mediaThumbnail;
  final Duration? voiceDuration;
  final MessageStatus status;
  final DateTime createdAt;
  final DateTime? readAt;

  Message({
    String? id,
    required this.senderId,
    required this.receiverId,
    this.conversationId,
    required this.type,
    this.content,
    this.mediaUrl,
    this.mediaThumbnail,
    this.voiceDuration,
    this.status = MessageStatus.sending,
    DateTime? createdAt,
    this.readAt,
  }) : id = id ?? const Uuid().v4(),
       createdAt = createdAt ?? DateTime.now();

  bool get isMe => senderId != receiverId;

  Message copyWith({
    String? id,
    String? senderId,
    String? receiverId,
    String? conversationId,
    MessageType? type,
    String? content,
    String? mediaUrl,
    String? mediaThumbnail,
    Duration? voiceDuration,
    MessageStatus? status,
    DateTime? createdAt,
    DateTime? readAt,
  }) {
    return Message(
      id: id ?? this.id,
      senderId: senderId ?? this.senderId,
      receiverId: receiverId ?? this.receiverId,
      conversationId: conversationId ?? this.conversationId,
      type: type ?? this.type,
      content: content ?? this.content,
      mediaUrl: mediaUrl ?? this.mediaUrl,
      mediaThumbnail: mediaThumbnail ?? this.mediaThumbnail,
      voiceDuration: voiceDuration ?? this.voiceDuration,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      readAt: readAt ?? this.readAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'sender_id': senderId,
      'receiver_id': receiverId,
      'conversation_id': conversationId,
      'type': type.name,
      'content': content,
      'media_url': mediaUrl,
      'media_thumbnail': mediaThumbnail,
      'voice_duration': voiceDuration?.inSeconds,
      'status': status.name,
      'created_at': createdAt.toIso8601String(),
      'read_at': readAt?.toIso8601String(),
    };
  }

  factory Message.fromJson(Map<String, dynamic> json) {
    return Message(
      id: json['id'],
      senderId: json['sender_id'],
      receiverId: json['receiver_id'],
      conversationId: json['conversation_id'],
      type: MessageType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => MessageType.text,
      ),
      content: json['content'],
      mediaUrl: json['media_url'],
      mediaThumbnail: json['media_thumbnail'],
      voiceDuration: json['voice_duration'] != null
          ? Duration(seconds: json['voice_duration'])
          : null,
      status: MessageStatus.values.firstWhere(
        (e) => e.name == json['status'],
        orElse: () => MessageStatus.sent,
      ),
      createdAt: DateUtil.parseServerTime(json['created_at']),
      readAt: json['read_at'] != null
          ? DateUtil.parseServerTime(json['read_at'])
          : null,
    );
  }
}

class Conversation {
  final String id;
  final List<String> participantIds;
  final String otherUserId;
  final String otherUserName;
  final String? otherUserAvatar;
  final Message? lastMessage;
  final int unreadCount;
  final DateTime updatedAt;

  Conversation({
    required this.id,
    required this.participantIds,
    required this.otherUserId,
    required this.otherUserName,
    this.otherUserAvatar,
    this.lastMessage,
    this.unreadCount = 0,
    DateTime? updatedAt,
  }) : updatedAt = updatedAt ?? DateTime.now();

  Conversation copyWith({
    String? id,
    List<String>? participantIds,
    String? otherUserId,
    String? otherUserName,
    String? otherUserAvatar,
    Message? lastMessage,
    int? unreadCount,
    DateTime? updatedAt,
  }) {
    return Conversation(
      id: id ?? this.id,
      participantIds: participantIds ?? this.participantIds,
      otherUserId: otherUserId ?? this.otherUserId,
      otherUserName: otherUserName ?? this.otherUserName,
      otherUserAvatar: otherUserAvatar ?? this.otherUserAvatar,
      lastMessage: lastMessage ?? this.lastMessage,
      unreadCount: unreadCount ?? this.unreadCount,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'participant_ids': participantIds,
      'other_user_id': otherUserId,
      'other_user_name': otherUserName,
      'other_user_avatar': otherUserAvatar,
      'last_message': lastMessage?.toJson(),
      'unread_count': unreadCount,
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  factory Conversation.fromJson(Map<String, dynamic> json) {
    return Conversation(
      id: json['id'],
      participantIds: List<String>.from(json['participant_ids'] ?? []),
      otherUserId: json['other_user_id'],
      otherUserName: json['other_user_name'] ?? 'Unknown',
      otherUserAvatar: json['other_user_avatar'],
      lastMessage: json['last_message'] != null
          ? Message.fromJson(json['last_message'])
          : null,
      unreadCount: json['unread_count'] ?? 0,
      updatedAt: DateUtil.parseServerTime(json['updated_at']),
    );
  }
}
