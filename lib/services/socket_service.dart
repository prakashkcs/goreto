import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:socket_io_client/socket_io_client.dart' as sio;
import 'package:love_vibe_pro/models/message.dart';
import 'package:love_vibe_pro/utils/date_util.dart';
import 'package:love_vibe_pro/services/sound_service.dart';

/// Real-time chat via Socket.IO.
/// The server runs at wss://goreto.org/socket.io/ (proxied by nginx to port 3001).
class SocketService {
  static final SocketService instance = SocketService._();
  SocketService._();

  static const String _serverUrl = 'https://goreto.org';

  sio.Socket? _socket;
  bool _isConnected = false;
  String _currentUserId = '';

  // ── Event streams ──────────────────────────────────────────────────────────
  final _newMessageCtrl =
      StreamController<Message>.broadcast();
  final _readReceiptCtrl =
      StreamController<Map<String, dynamic>>.broadcast();
  final _deliveredCtrl =
      StreamController<Map<String, dynamic>>.broadcast();
  final _typingCtrl =
      StreamController<Map<String, dynamic>>.broadcast();
  final _onlineStatusCtrl =
      StreamController<Map<String, dynamic>>.broadcast();
  final _connectionCtrl = StreamController<bool>.broadcast();
  final _messageActionCtrl =
      StreamController<Map<String, dynamic>>.broadcast();
  final _liveMessageCtrl =
      StreamController<Map<String, dynamic>>.broadcast();
  final _liveViewersCtrl =
      StreamController<List<Map<String, dynamic>>>.broadcast();

  Stream<Message> get onNewMessage => _newMessageCtrl.stream;
  Stream<Map<String, dynamic>> get onReadReceipt => _readReceiptCtrl.stream;
  Stream<Map<String, dynamic>> get onDelivered => _deliveredCtrl.stream;
  Stream<Map<String, dynamic>> get onTyping => _typingCtrl.stream;
  Stream<Map<String, dynamic>> get onOnlineStatus => _onlineStatusCtrl.stream;
  Stream<bool> get onConnectionChange => _connectionCtrl.stream;

  /// Real-time message actions (reaction / pin / unsend / edit) from the peer.
  Stream<Map<String, dynamic>> get onMessageAction =>
      _messageActionCtrl.stream;

  /// Live-room chat messages: {sender_id, sender_name, text}. Used as the
  /// messaging transport for live streams when the active video provider
  /// (e.g. Agora) has no signaling of its own -- see ZegoProvider for the
  /// equivalent Zego-native path.
  Stream<Map<String, dynamic>> get onLiveMessage => _liveMessageCtrl.stream;

  /// Current viewer list for a live room: each entry is {id, name}.
  /// Re-emitted on every join/leave.
  Stream<List<Map<String, dynamic>>> get onLiveViewers =>
      _liveViewersCtrl.stream;

  bool get isConnected => _isConnected;
  String get currentUserId => _currentUserId;

  // ── Connect ───────────────────────────────────────────────────────────────
  Future<void> connect() async {
    if (_socket != null && _isConnected) return;
    _socket?.dispose();

    final prefs = await SharedPreferences.getInstance();
    final token =
        prefs.getString('app_token') ?? prefs.getString('auth_token') ?? '';
    _currentUserId = prefs.getString('user_id') ?? '';

    if (token.isEmpty) return;

    _socket = sio.io(
      _serverUrl,
      sio.OptionBuilder()
          .setTransports(['websocket'])
          .setPath('/socket.io/')
          .setAuth({'token': token})
          .enableAutoConnect()
          .enableReconnection()
          .setReconnectionDelay(1000)
          .setReconnectionDelayMax(5000)
          .setReconnectionAttempts(double.infinity)
          .build(),
    );

    _socket!.onConnect((_) {
      _isConnected = true;
      _connectionCtrl.add(true);
      debugPrint('[Socket] Connected');
    });

    _socket!.onDisconnect((_) {
      _isConnected = false;
      _connectionCtrl.add(false);
      debugPrint('[Socket] Disconnected');
    });

    _socket!.onConnectError((err) {
      _isConnected = false;
      debugPrint('[Socket] Connect error: $err');
    });

    _socket!.on('new_message', (data) {
      try {
        final map = _toMap(data);
        final msg = _parseMessage(map);
        _newMessageCtrl.add(msg);
        // Play the in-app notification tone for messages received from others
        // (the server only emits new_message to the recipient, but guard anyway).
        if (_currentUserId.isEmpty || msg.senderId != _currentUserId) {
          SoundService().playMessageNotification();
        }
      } catch (e) {
        debugPrint('[Socket] new_message parse error: $e');
      }
    });

    _socket!.on('messages_read', (data) {
      _readReceiptCtrl.add(_toMap(data));
    });

    _socket!.on('message_delivered', (data) {
      _deliveredCtrl.add(_toMap(data));
    });

    _socket!.on('user_typing', (data) {
      _typingCtrl.add(_toMap(data));
    });

    _socket!.on('message_action', (data) {
      _messageActionCtrl.add(_toMap(data));
    });

    _socket!.on('online_status', (data) {
      _onlineStatusCtrl.add(_toMap(data));
    });

    _socket!.on('live_message', (data) {
      _liveMessageCtrl.add(_toMap(data));
    });

    _socket!.on('live_viewers', (data) {
      try {
        final list = (data as List)
            .map((e) => _toMap(e))
            .toList(growable: false);
        _liveViewersCtrl.add(list);
      } catch (e) {
        debugPrint('[Socket] live_viewers parse error: $e');
      }
    });

    _socket!.connect();
  }

  void disconnect() {
    _socket?.disconnect();
    _socket?.dispose();
    _socket = null;
    _isConnected = false;
  }

  // ── Send text message via socket ──────────────────────────────────────────
  /// Returns the server-confirmed message on success, null on failure.
  Future<Message?> sendMessage({
    required String receiverId,
    required String content,
    String type = 'text',
    required String tempId,
  }) async {
    if (_socket == null || !_isConnected) return null;

    final completer = Completer<Message?>();
    final timer = Timer(const Duration(seconds: 5), () {
      if (!completer.isCompleted) completer.complete(null);
    });

    _socket!.emitWithAck('send_message', {
      'receiver_id': receiverId,
      'content': content,
      'type': type,
      'temp_id': tempId,
    }, ack: (response) {
      timer.cancel();
      if (completer.isCompleted) return;
      try {
        final map = _toMap(response);
        if (map['success'] == true && map['message'] != null) {
          completer.complete(_parseMessage(_toMap(map['message'])));
        } else {
          completer.complete(null);
        }
      } catch (_) {
        completer.complete(null);
      }
    });

    return completer.future;
  }

  // ── Mark messages read ────────────────────────────────────────────────────
  void markRead(String senderId) {
    if (_socket == null || !_isConnected) return;
    _socket!.emit('mark_read', {'sender_id': senderId});
  }

  // ── Typing indicator ──────────────────────────────────────────────────────
  void sendTyping(String receiverId, {required bool isTyping}) {
    if (_socket == null || !_isConnected) return;
    _socket!.emit('typing', {'receiver_id': receiverId, 'is_typing': isTyping});
  }

  /// Relay a message action (reaction / pin / unsend / edit) to the peer in
  /// real time so their chat updates instantly (FB-Messenger style).
  void sendMessageAction(Map<String, dynamic> payload) {
    if (_socket == null || !_isConnected) return;
    _socket!.emit('message_action', payload);
  }

  // ── Live room (chat + viewers relay for non-Zego video providers) ────────
  void joinLiveRoom(String roomId, String displayName) {
    if (_socket == null || !_isConnected) return;
    _socket!.emit('live_join', {'room_id': roomId, 'name': displayName});
  }

  void leaveLiveRoom(String roomId) {
    if (_socket == null || !_isConnected) return;
    _socket!.emit('live_leave', {'room_id': roomId});
  }

  void sendLiveMessage(String roomId, String text) {
    if (_socket == null || !_isConnected) return;
    _socket!.emit('live_message', {'room_id': roomId, 'text': text});
  }

  // ── Online status subscription ────────────────────────────────────────────
  void subscribeStatus(String userId) {
    if (_socket == null || !_isConnected) return;
    _socket!.emit('subscribe_status', {'user_id': userId});
  }

  void unsubscribeStatus(String userId) {
    if (_socket == null || !_isConnected) return;
    _socket!.emit('unsubscribe_status', {'user_id': userId});
  }

  Future<Map<String, bool>> getOnlineStatuses(List<String> userIds) async {
    if (_socket == null || !_isConnected || userIds.isEmpty) return {};
    final completer = Completer<Map<String, bool>>();
    final timer = Timer(const Duration(seconds: 3), () {
      if (!completer.isCompleted) completer.complete({});
    });
    _socket!.emitWithAck('get_online_status', {'user_ids': userIds},
        ack: (response) {
      timer.cancel();
      if (completer.isCompleted) return;
      final result = <String, bool>{};
      try {
        final map = _toMap(response);
        map.forEach((k, v) => result[k.toString()] = v == true);
      } catch (_) {}
      completer.complete(result);
    });
    return completer.future;
  }

  // ── Helpers ───────────────────────────────────────────────────────────────
  Map<String, dynamic> _toMap(dynamic data) {
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    if (data is String) return jsonDecode(data) as Map<String, dynamic>;
    return {};
  }

  Message _parseMessage(Map<String, dynamic> m) {
    final statusStr = (m['status'] ?? 'sent').toString();
    final status = MessageStatus.values.firstWhere(
      (e) => e.name == statusStr,
      orElse: () => MessageStatus.sent,
    );
    final typeStr = (m['type'] ?? 'text').toString();
    final type = MessageType.values.firstWhere(
      (e) => e.name == typeStr,
      orElse: () => MessageType.text,
    );
    return Message(
      id: m['id']?.toString() ?? '',
      senderId: m['sender_id']?.toString() ?? '',
      receiverId: m['receiver_id']?.toString() ?? '',
      type: type,
      content: m['content']?.toString(),
      mediaUrl: m['media_url']?.toString(),
      status: status,
      createdAt: m['created_at'] != null
          ? DateUtil.parseServerTime(m['created_at'].toString())
          : DateTime.now(),
      readAt: m['read_at'] != null
          ? DateUtil.parseServerTime(m['read_at'].toString())
          : null,
    );
  }
}
