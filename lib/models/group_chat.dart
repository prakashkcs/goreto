import 'package:love_vibe_pro/utils/date_util.dart';
import 'package:love_vibe_pro/config/app_env.dart';

/// PHP/MySQL hands booleans back as 1/0, "1"/"0", true/false or "true".
bool _asBool(dynamic v) {
  if (v == null) return false;
  if (v is bool) return v;
  if (v is num) return v != 0;
  final s = v.toString().trim().toLowerCase();
  return s == '1' || s == 'true' || s == 'yes' || s == 'on';
}

int _asInt(dynamic v, [int fallback = 0]) =>
    int.tryParse(v?.toString() ?? '') ?? fallback;

/// Resolves a user avatar stored either as an absolute URL or relative to the
/// site root (https://goreto.org/ekloadmin/).
String? resolveUserAvatar(String? raw) {
  if (raw == null || raw.trim().isEmpty) return null;
  final v = raw.trim();
  if (v.startsWith('http')) return v;
  var base = AppEnv.liveBaseUrl.replaceAll('/api/v1/', '/');
  if (!base.endsWith('/')) base = '$base/';
  var path = v.startsWith('/') ? v.substring(1) : v;
  final host = Uri.parse(base).host;
  if (path.startsWith(host)) return 'https://$path';
  return '$base$path';
}

/// Resolves files stored under api/v1/uploads (group avatars, chat media).
String resolveGroupFile(String raw) {
  if (raw.startsWith('http')) return raw;
  var base = AppEnv.liveBaseUrl;
  if (!base.endsWith('/')) base = '$base/';
  final path = raw.startsWith('/') ? raw.substring(1) : raw;
  return '$base$path';
}

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
  final bool joinApproval;
  final bool membersCanInvite;
  final GroupPermissions permissions;
  final int messageDelay;
  final int viewsCount;
  final DateTime? lastActive;
  final int unreadCount;
  final int pendingRequests;
  final bool requestPending;

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
    this.joinApproval = false,
    this.membersCanInvite = true,
    this.permissions = const GroupPermissions(),
    this.messageDelay = 0,
    this.viewsCount = 0,
    this.lastActive,
    this.unreadCount = 0,
    this.pendingRequests = 0,
    this.requestPending = false,
  });

  bool get isAdmin => myRole == 'admin';

  String? get avatarUrl {
    if (avatar == null || avatar!.isEmpty) return null;
    return resolveGroupFile(avatar!);
  }

  String get initial =>
      name.trim().isNotEmpty ? name.trim()[0].toUpperCase() : 'G';

  ChatGroup copyWith({
    String? name,
    String? username,
    String? avatar,
    String? bio,
    int? memberCount,
    int? joinFee,
    bool? isMember,
    String? myRole,
    bool? isPrivate,
    bool? joinApproval,
    bool? membersCanInvite,
    GroupPermissions? permissions,
    int? messageDelay,
    int? pendingRequests,
    bool? requestPending,
  }) {
    return ChatGroup(
      id: id,
      name: name ?? this.name,
      username: username ?? this.username,
      avatar: avatar ?? this.avatar,
      bio: bio ?? this.bio,
      joinFee: joinFee ?? this.joinFee,
      monthlyFee: monthlyFee,
      createdBy: createdBy,
      memberCount: memberCount ?? this.memberCount,
      isMember: isMember ?? this.isMember,
      myRole: myRole ?? this.myRole,
      lastMessage: lastMessage,
      lastMessageType: lastMessageType,
      lastMessageSender: lastMessageSender,
      lastMessageSenderId: lastMessageSenderId,
      lastMessageTime: lastMessageTime,
      isPrivate: isPrivate ?? this.isPrivate,
      joinApproval: joinApproval ?? this.joinApproval,
      membersCanInvite: membersCanInvite ?? this.membersCanInvite,
      permissions: permissions ?? this.permissions,
      messageDelay: messageDelay ?? this.messageDelay,
      viewsCount: viewsCount,
      lastActive: lastActive,
      unreadCount: unreadCount,
      pendingRequests: pendingRequests ?? this.pendingRequests,
      requestPending: requestPending ?? this.requestPending,
    );
  }

  factory ChatGroup.fromJson(Map<String, dynamic> json) {
    final perms = json['permissions'];
    return ChatGroup(
      id: _asInt(json['id']),
      name: (json['name'] ?? 'Group').toString(),
      username: json['username']?.toString(),
      avatar: json['avatar']?.toString(),
      bio: json['bio']?.toString(),
      joinFee: _asInt(json['join_fee']),
      monthlyFee: _asInt(json['monthly_fee']),
      createdBy: _asInt(json['created_by']),
      memberCount: _asInt(json['member_count']),
      isMember: _asBool(json['is_member']),
      myRole: json['my_role']?.toString(),
      lastMessage: json['last_message']?.toString(),
      lastMessageType: json['last_message_type']?.toString(),
      lastMessageSender: json['last_message_sender']?.toString(),
      lastMessageSenderId:
          int.tryParse(json['last_message_sender_id']?.toString() ?? ''),
      lastMessageTime: json['last_message_time'] != null
          ? DateUtil.parseServerTime(json['last_message_time'])
          : null,
      isPrivate: _asBool(json['is_private']),
      joinApproval: _asBool(json['join_approval']),
      membersCanInvite: json.containsKey('members_can_invite')
          ? _asBool(json['members_can_invite'])
          : true,
      permissions: perms is Map
          ? GroupPermissions.fromJson(Map<String, dynamic>.from(perms))
          : const GroupPermissions(),
      messageDelay: _asInt(json['message_delay']),
      viewsCount: _asInt(json['views_count']),
      lastActive: json['last_active'] != null
          ? DateUtil.parseServerTime(json['last_active'])
          : null,
      unreadCount: _asInt(json['unread_count']),
      pendingRequests: _asInt(json['pending_requests']),
      requestPending: _asBool(json['request_pending']),
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
    bool read(String k) => !json.containsKey(k) || _asBool(json[k]);
    return GroupPermissions(
      canSendText: read('can_send_text'),
      canSendMedia: read('can_send_media'),
      canSendVoice: read('can_send_voice'),
      canSendStickers: read('can_send_stickers'),
    );
  }

  GroupPermissions copyWith({
    bool? canSendText,
    bool? canSendMedia,
    bool? canSendVoice,
    bool? canSendStickers,
  }) =>
      GroupPermissions(
        canSendText: canSendText ?? this.canSendText,
        canSendMedia: canSendMedia ?? this.canSendMedia,
        canSendVoice: canSendVoice ?? this.canSendVoice,
        canSendStickers: canSendStickers ?? this.canSendStickers,
      );

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

  bool get isAdmin => role == 'admin';

  String? get avatarUrl => resolveUserAvatar(avatar);

  factory ChatGroupMember.fromJson(Map<String, dynamic> json) {
    return ChatGroupMember(
      id: _asInt(json['id']),
      name: (json['name'] ?? '').toString(),
      username: (json['username'] ?? '').toString(),
      avatar: json['avatar']?.toString(),
      role: (json['role'] ?? 'member').toString(),
      joinedAt: DateUtil.parseServerTime(json['joined_at']),
    );
  }
}

class GroupMessage {
  final int id;
  final int senderId;
  final String senderName;
  final String? senderUsername;
  final String? senderAvatar;
  final String message;
  final String type;
  final Duration? voiceDuration;
  final DateTime createdAt;
  final bool isEdited;
  final bool isDeleted;

  GroupMessage({
    required this.id,
    required this.senderId,
    required this.senderName,
    this.senderUsername,
    this.senderAvatar,
    required this.message,
    required this.type,
    this.voiceDuration,
    required this.createdAt,
    this.isEdited = false,
    this.isDeleted = false,
  });

  String? get senderAvatarUrl => resolveUserAvatar(senderAvatar);

  bool get isSystem => type == 'system';

  GroupMessage copyWith({String? message, bool? isEdited, bool? isDeleted}) {
    return GroupMessage(
      id: id,
      senderId: senderId,
      senderName: senderName,
      senderUsername: senderUsername,
      senderAvatar: senderAvatar,
      message: message ?? this.message,
      type: type,
      voiceDuration: voiceDuration,
      createdAt: createdAt,
      isEdited: isEdited ?? this.isEdited,
      isDeleted: isDeleted ?? this.isDeleted,
    );
  }

  factory GroupMessage.fromJson(Map<String, dynamic> json) {
    return GroupMessage(
      id: _asInt(json['id']),
      senderId: _asInt(json['sender_id']),
      senderName: (json['sender_name'] ?? 'System').toString(),
      senderUsername: json['sender_username']?.toString(),
      senderAvatar: json['sender_avatar']?.toString(),
      message: (json['message'] ?? '').toString(),
      type: (json['type'] ?? 'text').toString(),
      voiceDuration: json['voice_duration'] != null
          ? Duration(seconds: _asInt(json['voice_duration']))
          : null,
      createdAt: DateUtil.parseServerTime(json['created_at']),
      isEdited: _asBool(json['is_edited']),
      isDeleted: _asBool(json['is_deleted']),
    );
  }
}

/// An edit or unsend of a message the client already has.
class GroupMessageChange {
  final int id;
  final String message;
  final bool isEdited;
  final bool isDeleted;

  const GroupMessageChange({
    required this.id,
    required this.message,
    required this.isEdited,
    required this.isDeleted,
  });

  factory GroupMessageChange.fromJson(Map<String, dynamic> json) =>
      GroupMessageChange(
        id: _asInt(json['id']),
        message: (json['message'] ?? '').toString(),
        isEdited: _asBool(json['is_edited']),
        isDeleted: _asBool(json['is_deleted']),
      );
}

class GroupSyncResult {
  final List<GroupMessage> messages;
  final List<GroupMessageChange> changes;
  final String? serverTime;
  final bool notMember;

  const GroupSyncResult({
    this.messages = const [],
    this.changes = const [],
    this.serverTime,
    this.notMember = false,
  });
}

/// A pending invitation the current user received.
class GroupInvite {
  final int inviteId;
  final ChatGroup group;
  final int inviterId;
  final String inviterName;
  final String? inviterAvatar;
  final DateTime invitedAt;

  GroupInvite({
    required this.inviteId,
    required this.group,
    required this.inviterId,
    required this.inviterName,
    this.inviterAvatar,
    required this.invitedAt,
  });

  factory GroupInvite.fromJson(Map<String, dynamic> json) => GroupInvite(
        inviteId: _asInt(json['invite_id']),
        group: ChatGroup.fromJson(json),
        inviterId: _asInt(json['inviter_id']),
        inviterName: (json['inviter_name'] ?? 'Someone').toString(),
        inviterAvatar: json['inviter_avatar']?.toString(),
        invitedAt: DateUtil.parseServerTime(json['invited_at']),
      );
}

/// A join request (admin view) or an outgoing invite (admin view).
class GroupPendingUser {
  final int id; // request id or invite id
  final int userId;
  final String name;
  final String username;
  final String? avatar;
  final String? invitedByName;
  final DateTime createdAt;

  GroupPendingUser({
    required this.id,
    required this.userId,
    required this.name,
    required this.username,
    this.avatar,
    this.invitedByName,
    required this.createdAt,
  });

  factory GroupPendingUser.fromJson(Map<String, dynamic> json) =>
      GroupPendingUser(
        id: _asInt(json['id']),
        userId: _asInt(json['user_id']),
        name: (json['name'] ?? '').toString(),
        username: (json['username'] ?? '').toString(),
        avatar: resolveUserAvatar(json['avatar']?.toString()),
        invitedByName: json['invited_by_name']?.toString(),
        createdAt: DateUtil.parseServerTime(json['created_at']),
      );
}

/// A person shown in the "Add members" sheet.
class GroupInvitee {
  final int id;
  final String name;
  final String username;
  final String? avatar;
  final bool isFriend;
  final bool iFollow;

  /// none | member | invited | requested | banned
  final String status;

  GroupInvitee({
    required this.id,
    required this.name,
    required this.username,
    this.avatar,
    this.isFriend = false,
    this.iFollow = false,
    this.status = 'none',
  });

  factory GroupInvitee.fromJson(Map<String, dynamic> json) => GroupInvitee(
        id: _asInt(json['id']),
        name: (json['name'] ?? '').toString(),
        username: (json['username'] ?? '').toString(),
        avatar: resolveUserAvatar(json['avatar']?.toString()),
        isFriend: _asBool(json['is_friend']),
        iFollow: _asBool(json['i_follow']),
        status: (json['status'] ?? 'none').toString(),
      );
}

class UsernameCheck {
  final String username;
  final bool valid;
  final bool available;
  final String? message;
  final String? suggestion;

  const UsernameCheck({
    required this.username,
    required this.valid,
    required this.available,
    this.message,
    this.suggestion,
  });
}
