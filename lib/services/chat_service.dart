import 'package:love_vibe_pro/models/message.dart';
import 'package:love_vibe_pro/utils/date_util.dart';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

/// ChatService - REST wrapper for live chat functionality powered by /chat.php
class ChatService {
  // Singleton pattern
  ChatService._();
  static final ChatService _instance = ChatService._();
  static ChatService get instance => _instance;

  // Mock data store
  final List<Conversation> _conversations = [];
  final Map<String, List<Message>> _messages = {};

  // Block state caches
  final Map<String, bool> _blockedByMeMap = {};
  final Map<String, bool> _blockedByThemMap = {};
  final Map<String, bool> _isFriendMap = {};
  final Map<String, String> _requestStatusMap = {};

  bool isBlockedByMe(String userId) => _blockedByMeMap[userId] ?? false;
  bool isBlockedByThem(String userId) => _blockedByThemMap[userId] ?? false;
  bool isFriend(String userId) => _isFriendMap[userId] ?? false;
  String requestStatus(String userId) => _requestStatusMap[userId] ?? 'none';

  // Current user ID (loaded from SharedPreferences)
  String _currentUserId = '';
  bool _userIdLoaded = false;

  void setCurrentUserId(String userId) {
    _currentUserId = userId;
    _userIdLoaded = true;
  }

  /// Ensure the current user ID is loaded from SharedPreferences
  Future<void> _ensureUserIdLoaded() async {
    if (_userIdLoaded && _currentUserId.isNotEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final storedId = prefs.getString('user_id') ?? '';
    if (storedId.isNotEmpty) {
      _currentUserId = storedId;
      _userIdLoaded = true;
    }
  }

  String get currentUserId => _currentUserId;

  // Dio client initialization
  Future<Dio> _ensureInitializedDio() async {
    final prefs = await SharedPreferences.getInstance();
    var baseUrl = prefs.getString('api_base_url') ??
        'https://goreto.org/ekloadmin/api/v1/';

    if (!baseUrl.endsWith('/')) baseUrl = '$baseUrl/';

    final dio = Dio(
      BaseOptions(
        baseUrl: baseUrl,
        connectTimeout: const Duration(seconds: 8),
        receiveTimeout: const Duration(seconds: 8),
      ),
    );

    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final token =
              prefs.getString('app_token') ?? prefs.getString('auth_token');
          if (token != null) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          options.headers['Accept'] = 'application/json';
          return handler.next(options);
        },
      ),
    );
    return dio;
  }

  /// Get all conversations for current user
  Future<List<Conversation>> getConversations() async {
    await _ensureUserIdLoaded();
    final dio = await _ensureInitializedDio();

    try {
      final response = await dio.get(
        'chat.php',
        queryParameters: {'action': 'get_conversations'},
      );
      dynamic payload = response.data;
      if (payload is String) payload = jsonDecode(payload);

      if (payload is Map<String, dynamic> && payload['status'] == 'success') {
        final List<dynamic> data = payload['conversations'] ?? [];
        _conversations.clear();
        for (var item in data) {
          final conv = _parseConversation(item);
          _conversations.add(conv);
          // Auto mark as delivered if unread
          if (conv.unreadCount > 0) {
            markDelivered(conv.id);
          }
        }
      }
    } catch (e) {}
    return _conversations;
  }

  String _extractOtherUserId(String conversationId) {
    final raw = conversationId.replaceFirst('conv_', '');
    final parts = raw.split('_');
    if (parts.length == 2) {
      return parts[0] == _currentUserId ? parts[1] : parts[0];
    }
    return raw.replaceAll(_currentUserId, '').replaceAll('_', '');
  }

  /// Get messages for a conversation
  Future<List<Message>> getMessages(String conversationId, {String? withUserId}) async {
    await _ensureUserIdLoaded();
    final dio = await _ensureInitializedDio();
    final String otherUserId = withUserId ?? _extractOtherUserId(conversationId);

    try {
      final response = await dio.get(
        'chat.php',
        queryParameters: {
          'action': 'get_messages',
          'with_user_id': otherUserId,
        },
      );
      dynamic payload = response.data;
      if (payload is String) payload = jsonDecode(payload);

      if (payload is Map<String, dynamic> && payload['status'] == 'success') {
        _blockedByMeMap[otherUserId] = payload['is_blocked_by_me'] ?? false;
        _blockedByThemMap[otherUserId] = payload['is_blocked_by_them'] ?? false;
        _isFriendMap[otherUserId] = payload['is_friend'] == true || payload['is_friend'] == 1;
        _requestStatusMap[otherUserId] = payload['request_status']?.toString() ?? 'none';

        final List<dynamic> data = payload['messages'] ?? [];
        final parsed = data.map((e) => _parseMessage(e)).toList();
        _messages[conversationId] = parsed;
      }
    } catch (_) {}

    return _messages[conversationId] ?? [];
  }

  /// Get ONLY new messages for active chat (fast polling)
  Future<List<Message>> getNewMessages(
    String conversationId,
    String lastMessageId, {
    String? withUserId,
  }) async {
    await _ensureUserIdLoaded();
    final dio = await _ensureInitializedDio();
    final String otherUserId = withUserId ?? _extractOtherUserId(conversationId);

    try {
      final response = await dio.get(
        'chat.php',
        queryParameters: {
          'action': 'get_new_messages',
          'with_user_id': otherUserId,
          'last_id': lastMessageId,
        },
      );
      dynamic payload = response.data;
      if (payload is String) payload = jsonDecode(payload);

      if (payload is Map<String, dynamic> && payload['status'] == 'success') {
        final List<dynamic> updates = payload['status_updates'] ?? [];
        if (updates.isNotEmpty && _messages.containsKey(conversationId)) {
          var mList = _messages[conversationId]!;
          for (var item in updates) {
            final id = item['id'].toString();
            final statusStr = item['status'];
            final MessageStatus st = statusStr == 'read'
                ? MessageStatus.read
                : (statusStr == 'delivered'
                    ? MessageStatus.delivered
                    : MessageStatus.sent);

            final index = mList.indexWhere((m) => m.id == id);
            if (index != -1 && mList[index].status != st) {
              mList[index] = mList[index].copyWith(
                status: st,
                readAt: item['read_at'] != null
                    ? DateUtil.parseServerTime(item['read_at'].toString())
                    : null,
              );
            }
          }
        }

        final List<dynamic> data = payload['messages'] ?? [];
        if (data.isNotEmpty) {
          final newParsed = data.map((e) => _parseMessage(e)).toList();

          if (!_messages.containsKey(conversationId)) {
            _messages[conversationId] = [];
          }
          // Deduplicate: skip messages already in cache (e.g. just sent via sendMessage)
          final existingIds =
              _messages[conversationId]!.map((m) => m.id).toSet();
          final deduped =
              newParsed.where((m) => !existingIds.contains(m.id)).toList();
          _messages[conversationId]!.addAll(deduped);
          return deduped;
        }

        if (updates.isNotEmpty) {
          return []; // This signals no *new* messages, but state changed
        }
      }
    } catch (_) {}
    return [];
  }

  /// Send a message (text or call log)
  Future<Message> sendMessage({
    required String receiverId,
    required String content,
    MessageType type = MessageType.text,
  }) async {
    final dio = await _ensureInitializedDio();

    final response = await dio.post(
      'chat.php',
      data: {
        'action': 'send_message',
        'receiver_id': receiverId,
        'type': type.name,
        'content': content,
      },
    );

    dynamic payload = response.data;
    if (payload is String) payload = jsonDecode(payload);

    final Message message = _parseMessage(
      payload['message'] ??
          {
            'sender_id': _currentUserId,
            'receiver_id': receiverId,
            'type': 'text',
            'content': content,
            'status': 'sent',
            'created_at': DateTime.now().toIso8601String(),
          },
    );

    final convId = _getConversationId(receiverId);
    if (!_messages.containsKey(convId)) _messages[convId] = [];
    _messages[convId]!.add(message);
    _updateConversationWithMessage(receiverId, message);

    return message;
  }

  /// Send a media message (image/video)
  Future<Message> sendMediaMessage({
    required String receiverId,
    required MessageType type,
    required String mediaPath,
    String? thumbnail,
  }) async {
    final dio = await _ensureInitializedDio();

    String fileName = mediaPath.split('/').last;
    FormData formData = FormData.fromMap({
      'action': 'send_message',
      'receiver_id': receiverId,
      'type': type == MessageType.image ? 'image' : 'video',
      'file': await MultipartFile.fromFile(mediaPath, filename: fileName),
    });

    final response = await dio.post('chat.php', data: formData);
    dynamic payload = response.data;
    if (payload is String) payload = jsonDecode(payload);

    final Message message = _parseMessage(payload['message']);

    final convId = _getConversationId(receiverId);
    if (!_messages.containsKey(convId)) _messages[convId] = [];
    _messages[convId]!.insert(0, message);
    _updateConversationWithMessage(receiverId, message);

    return message;
  }

  /// Send a voice message
  Future<Message> sendVoiceMessage({
    required String receiverId,
    required String audioPath,
    required Duration duration,
  }) async {
    final dio = await _ensureInitializedDio();

    String fileName = audioPath.split('/').last;
    FormData formData = FormData.fromMap({
      'action': 'send_message',
      'receiver_id': receiverId,
      'type': 'voice',
      'voice_duration': duration.inSeconds,
      'file': await MultipartFile.fromFile(audioPath, filename: fileName),
    });

    final response = await dio.post('chat.php', data: formData);
    dynamic payload = response.data;
    if (payload is String) payload = jsonDecode(payload);

    final Message message = _parseMessage(payload['message']);

    final convId = _getConversationId(receiverId);
    if (!_messages.containsKey(convId)) _messages[convId] = [];
    _messages[convId]!.insert(0, message);
    _updateConversationWithMessage(receiverId, message);

    return message;
  }

  /// Mark messages as delivered
  Future<void> markDelivered(String conversationId) async {
    final dio = await _ensureInitializedDio();
    String otherUserId = conversationId
        .replaceFirst('conv_${_currentUserId}_', '')
        .replaceFirst('conv_', '')
        .replaceAll(_currentUserId, '')
        .replaceAll('_', '');

    try {
      await dio.post(
        'chat.php',
        data: {'action': 'mark_delivered', 'sender_id': otherUserId},
      );
    } catch (_) {}
  }

  /// Mark messages as read
  Future<void> markAsRead(String conversationId) async {
    final dio = await _ensureInitializedDio();
    String otherUserId = conversationId
        .replaceFirst('conv_${_currentUserId}_', '')
        .replaceFirst('conv_', '')
        .replaceAll(_currentUserId, '')
        .replaceAll('_', '');

    try {
      await dio.post(
        'chat.php',
        data: {'action': 'mark_read', 'sender_id': otherUserId},
      );

      final messages = _messages[conversationId] ?? [];
      for (int i = 0; i < messages.length; i++) {
        if (messages[i].receiverId == _currentUserId &&
            messages[i].readAt == null) {
          _messages[conversationId]![i] = messages[i].copyWith(
            status: MessageStatus.read,
            readAt: DateTime.now(),
          );
        }
      }
    } catch (_) {}
  }

  /// Get unread count for a conversation (local memory)
  Future<int> getUnreadCount(String conversationId) async {
    final messages = _messages[conversationId] ?? [];
    return messages
        .where((m) => m.receiverId == _currentUserId && m.readAt == null)
        .length;
  }

  /// Get total global unread count from server
  Future<int> getGlobalUnreadCount() async {
    try {
      final dio = await _ensureInitializedDio();
      final response = await dio.get(
        'chat.php',
        queryParameters: {'action': 'get_unread_count'},
      );
      dynamic payload = response.data;
      if (payload is String) payload = jsonDecode(payload);

      if (payload is Map<String, dynamic> && payload['status'] == 'success') {
        return int.tryParse(payload['unread_count']?.toString() ?? '0') ?? 0;
      }
    } catch (_) {}
    return 0;
  }

  // Helper methods
  String _getConversationId(String otherUserId) {
    final ids = [_currentUserId, otherUserId]..sort();
    return 'conv_${ids[0]}_${ids[1]}';
  }

  Message _parseMessage(Map<String, dynamic> json) {
    MessageType mType = MessageType.text;
    if (json['type'] == 'image') mType = MessageType.image;
    if (json['type'] == 'video') mType = MessageType.video;
    if (json['type'] == 'voice') mType = MessageType.voice;
    if (json['type'] == 'call') mType = MessageType.call;

    MessageStatus mStatus = MessageStatus.sent;
    if (json['status'] == 'delivered') mStatus = MessageStatus.delivered;
    if (json['status'] == 'read') mStatus = MessageStatus.read;

    return Message(
      id: json['id']?.toString() ??
          DateTime.now().millisecondsSinceEpoch.toString(),
      senderId: json['sender_id']?.toString() ?? '',
      receiverId: json['receiver_id']?.toString() ?? '',
      conversationId: json['conversation_id']?.toString(),
      type: mType,
      content: json['content']?.toString(),
      mediaUrl: json['media_url']?.toString(),
      mediaThumbnail: json['media_thumbnail']?.toString(),
      voiceDuration: json['voice_duration'] != null
          ? Duration(
              seconds: int.tryParse(json['voice_duration'].toString()) ?? 0,
            )
          : null,
      status: mStatus,
      createdAt: json['created_at'] != null
          ? DateUtil.parseServerTime(json['created_at'].toString())
          : DateTime.now(),
      readAt: json['read_at'] != null
          ? DateUtil.parseServerTime(json['read_at'].toString())
          : null,
    );
  }

  Conversation _parseConversation(Map<String, dynamic> json) {
    return Conversation(
      id: json['id']?.toString() ??
          _getConversationId(json['other_user_id']?.toString() ?? ''),
      participantIds: [_currentUserId, json['other_user_id']?.toString() ?? ''],
      otherUserId: json['other_user_id']?.toString() ?? '',
      otherUserName: json['other_user_name']?.toString() ?? 'User',
      otherUserAvatar: json['other_user_avatar']?.toString(),
      lastMessage: json['last_message'] != null
          ? _parseMessage(json['last_message'])
          : null,
      unreadCount: int.tryParse(json['unread_count']?.toString() ?? '0') ?? 0,
      updatedAt: json['updated_at'] != null
          ? DateUtil.parseServerTime(json['updated_at'].toString())
          : DateTime.now(),
      isFriend: json['is_friend'] == true || json['is_friend'] == 1,
      requestStatus: json['request_status']?.toString() ?? 'none',
    );
  }

  /// Accept a message request from [requesterId]
  Future<bool> acceptRequest(String requesterId) async {
    final dio = await _ensureInitializedDio();
    try {
      final response = await dio.post('chat.php', data: {
        'action': 'accept_request',
        'requester_id': requesterId,
      });
      dynamic payload = response.data;
      if (payload is String) payload = jsonDecode(payload);
      if (payload['status'] == 'success') {
        _requestStatusMap[requesterId] = 'accepted';
        return true;
      }
    } catch (_) {}
    return false;
  }

  /// Decline a message request from [requesterId] (deletes messages too)
  Future<bool> declineRequest(String requesterId) async {
    final dio = await _ensureInitializedDio();
    try {
      final response = await dio.post('chat.php', data: {
        'action': 'decline_request',
        'requester_id': requesterId,
      });
      dynamic payload = response.data;
      if (payload is String) payload = jsonDecode(payload);
      if (payload['status'] == 'success') {
        _requestStatusMap.remove(requesterId);
        _conversations.removeWhere((c) => c.otherUserId == requesterId);
        final convId = _getConversationId(requesterId);
        _messages.remove(convId);
        return true;
      }
    } catch (_) {}
    return false;
  }

  void _updateConversationWithMessage(String otherUserId, Message message) {
    final convId = _getConversationId(otherUserId);
    final convIndex = _conversations.indexWhere((c) => c.id == convId);

    if (convIndex >= 0) {
      _conversations[convIndex] = _conversations[convIndex].copyWith(
        lastMessage: message,
        updatedAt: message.createdAt,
      );
    } else {
      _conversations.add(
        Conversation(
          id: convId,
          participantIds: [_currentUserId, otherUserId],
          otherUserId: otherUserId,
          otherUserName: 'User $otherUserId',
          otherUserAvatar: 'https://i.pravatar.cc/150?u=$otherUserId',
          lastMessage: message,
          updatedAt: message.createdAt,
        ),
      );
    }
  }

  /// Get cached messages for UI sync
  List<Message> getCachedMessages(String conversationId) {
    return _messages[conversationId] ?? [];
  }

  /// Delete a conversation (removes all messages between two users)
  Future<bool> deleteConversation(String otherUserId) async {
    await _ensureUserIdLoaded();
    final dio = await _ensureInitializedDio();

    try {
      final response = await dio.post(
        'chat.php',
        data: {
          'action': 'delete_conversation',
          'other_user_id': otherUserId,
        },
      );
      dynamic payload = response.data;
      if (payload is String) payload = jsonDecode(payload);

      if (payload is Map<String, dynamic> && payload['status'] == 'success') {
        // Remove from local cache
        _conversations.removeWhere((c) => c.otherUserId == otherUserId);
        final convId = _getConversationId(otherUserId);
        _messages.remove(convId);
        return true;
      }
    } catch (_) {}
    return false;
  }
}
