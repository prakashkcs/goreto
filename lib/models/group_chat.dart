import 'package:love_vibe_pro/utils/date_util.dart';
import 'package:love_vibe_pro/config/app_env.dart';

class ChatGroup {
  final int id;
  final String name;
  final String? username;
  final String? avatar;
  final String? bio;
  final int memberCount;
  final int joinFee;
  final int monthlyFee;
  final int createdBy;
  final bool isMember;
  final String? myRole;
  final String? lastMessage;
  final String? lastMessageType;
  final String? lastMessageSender;
  final int? lastMessageSenderId;
  final DateTime? lastMessageTime;
  final bool isPrivate;
  final GroupPermissions permissions;
  final int messageDelay;
  final int viewsCount;
  final DateTime? lastActive;
  final int unreadCount;

  ChatGroup({
    required this.id,
    required this.name,
    this.username,
    this.avatar,
    this.bio,
    this.joinFee = 0,
    this.monthlyFee = 0,
    this.createdBy = 0,
    this.memberCount = 0,
    this.isMember = false,
    this.myRole,
    this.lastMessage,
    this.lastMessageType,
    this.lastMessageSender,
    this.lastMessageSenderId,
    this.lastMessageTime,
    this.isPrivate = false,
    this.permissions = const GroupPermissions(),
    this.messageDelay = 0,
    this.viewsCount = 0,
    this.lastActive,
    this.unreadCount = 0,
  });

  String? get avatarUrl {
    if (avatar == null || avatar!.isEmpty) return null;
    if (avatar!.startsWith('http')) return avatar;
    // Files are stored under api/v1/uploads/, so keep the full api/v1 base.
    String base = AppEnv.liveBaseUrl;
    if (!base.endsWith('/')) base = '$base/';
    String path = avatar!.startsWith('/') ? avatar!.substring(1) : avatar!;
    return '$base$path';
  }

  factory ChatGroup.fromJson(Map<String, dynamic> json) {
    return ChatGroup(
      id: int.tryParse(json['id'].toString()) ?? 0,
      name: json['name'] ?? 'Group',
      username: json['username'],
      avatar: json['avatar'],
      bio: json['bio'],
      joinFee: int.tryParse(json['join_fee']?.toString() ?? '0') ?? 0,
      monthlyFee: int.tryParse(json['monthly_fee']?.toString() ?? '0') ?? 0,
      createdBy: int.tryParse(json['created_by']?.toString() ?? '0') ?? 0,
      memberCount: int.tryParse(json['member_count']?.toString() ?? '0') ?? 0,
      isMember: json['is_member'] == 1 || json['is_member'] == true,
      myRole: json['my_role'],
      lastMessage: json['last_message'],
      lastMessageType: json['last_message_type'],
      lastMessageSender: json['last_message_sender'],
      lastMessageSenderId: int.tryParse(json['last_message_sender_id']?.toString() ?? ''),
      lastMessageTime: json['last_message_time'] != null
          ? DateUtil.parseServerTime(json['last_message_time'])
          : null,
      isPrivate: json['is_private'] == 1 || json['is_private'] == true,
      permissions: json['permissions'] != null
          ? GroupPermissions.fromJson(json['permissions'])
          : const GroupPermissions(),
      messageDelay: int.tryParse(json['message_delay']?.toString() ?? '0') ?? 0,
      viewsCount: int.tryParse(json['views_count']?.toString() ?? '0') ?? 0,
      lastActive: json['last_active'] != null
          ? DateUtil.parseServerTime(json['last_active'])
          : null,
      unreadCount: int.tryParse(json['unread_count']?.toString() ?? '0') ?? 0,
    );
  }
}

class GroupPermissions {
  final bool canSendText;
  final bool canSendMedia;
  final bool canSendVoice;
  final bool canSendStickers;

  const GroupPermissions({
    this.canSendText = true,
    this.canSendMedia = true,
    this.canSendVoice = true,
    this.canSendStickers = true,
  });

  factory GroupPermissions.fromJson(Map<String, dynamic> json) {
    return GroupPermissions(
      canSendText: json['can_send_text'] != false,
      canSendMedia: json['can_send_media'] != false,
      canSendVoice: json['can_send_voice'] != false,
      canSendStickers: json['can_send_stickers'] != false,
    );
  }

  Map<String, dynamic> toJson() => {
        'can_send_text': canSendText,
        'can_send_media': canSendMedia,
        'can_send_voice': canSendVoice,
        'can_send_stickers': canSendStickers,
      };
}

class ChatGroupMember {
  final int id; // user_id
  final String name;
  final String username;
  final String? avatar;
  final String role;
  final DateTime joinedAt;

  ChatGroupMember({
    required this.id,
    required this.name,
    required this.username,
    this.avatar,
    required this.role,
    required this.joinedAt,
  });

  String? get avatarUrl {
    if (avatar == null || avatar!.isEmpty) return null;
    if (avatar!.startsWith('http')) return avatar;
    String base = AppEnv.liveBaseUrl.replaceAll('/api/v1/', '');
    if (!base.endsWith('/')) base = '$base/';
    final path = avatar!.startsWith('/') ? avatar!.substring(1) : avatar!;
    return '$base$path';
  }

  factory ChatGroupMember.fromJson(Map<String, dynamic> json) {
    return ChatGroupMember(
      id: int.tryParse(json['id'].toString()) ?? 0,
      name: json['name'] ?? '',
      username: json['username'] ?? '',
      avatar: json['avatar'],
      role: json['role'] ?? 'member',
      joinedAt: DateUtil.parseServerTime(json['joined_at']),
    );
  }
}

class GroupMessage {
  final int id;
  final int senderId;
  final String senderName;
  final String? senderAvatar;
  final String message;
  final String type;
  final Duration? voiceDuration;
  final DateTime createdAt;

  GroupMessage({
    required this.id,
    required this.senderId,
    required this.senderName,
    this.senderAvatar,
    required this.message,
    required this.type,
    this.voiceDuration,
    required this.createdAt,
  });

  String? get senderAvatarUrl {
    if (senderAvatar == null || senderAvatar!.isEmpty) return null;
    if (senderAvatar!.startsWith('http')) return senderAvatar;
    // Strip /api/v1/ to get root: https://goreto.org/ekloadmin/
    String base = AppEnv.liveBaseUrl.replaceAll('/api/v1/', '');
    if (!base.endsWith('/')) base = '$base/';
    // Handle paths like /ekloadmin/uploads/... or uploads/...
    String path = senderAvatar!;
    if (path.startsWith('/')) path = path.substring(1);
    // If path already contains the base domain segment, avoid double-prefix
    final baseHost = Uri.parse(base).host;
    if (path.startsWith(baseHost)) return 'https://$path';
    return '$base$path';
  }

  factory GroupMessage.fromJson(Map<String, dynamic> json) {
    return GroupMessage(
      id: int.tryParse(json['id'].toString()) ?? 0,
      senderId: int.tryParse(json['sender_id'].toString()) ?? 0,
      senderName: json['sender_name'] ?? 'System',
      senderAvatar: json['sender_avatar'],
      message: json['message'] ?? '',
      type: json['type'] ?? 'text',
      voiceDuration: json['voice_duration'] != null
          ? Duration(seconds: int.tryParse(json['voice_duration'].toString()) ?? 0)
          : null,
      createdAt: DateUtil.parseServerTime(json['created_at']),
    );
  }
}
