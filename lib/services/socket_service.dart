import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:socket_io_client/socket_io_client.dart' as sio;
import 'package:love_vibe_pro/models/message.dart';
import 'package:love_vibe_pro/utils/date_util.dart';

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

  Stream<Message> get onNewMessage => _newMessageCtrl.stream;
  Stream<Map<String, dynamic>> get onReadReceipt => _readReceiptCtrl.stream;
  Stream<Map<String, dynamic>> get onDelivered => _deliveredCtrl.stream;
  Stream<Map<String, dynamic>> get onTyping => _typingCtrl.stream;
  Stream<Map<String, dynamic>> get onOnlineStatus => _onlineStatusCtrl.stream;
  Stream<bool> get onConnectionChange => _connectionCtrl.stream;

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

    _socket!.on('online_status', (data) {
      _onlineStatusCtrl.add(_toMap(data));
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
