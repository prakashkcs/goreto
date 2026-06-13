import 'dart:async';
import 'package:flutter/material.dart';
import 'package:love_vibe_pro/services/api_service.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:love_vibe_pro/core/theme.dart';
import 'package:love_vibe_pro/models/message.dart';
import 'package:love_vibe_pro/services/chat_service.dart';
import 'package:love_vibe_pro/screens/chat/chat_screen.dart';
import 'package:love_vibe_pro/screens/profile_screen.dart';
import 'package:love_vibe_pro/widgets/neon_toast.dart';
import 'package:love_vibe_pro/screens/chat/group_chat_list_tab.dart';
import 'package:love_vibe_pro/services/socket_service.dart';

class ChatListScreen extends StatefulWidget {
  const ChatListScreen({super.key});

  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> {
  final ChatService _chatService = ChatService.instance;
  final SocketService _socket = SocketService.instance;

  List<Conversation> _direct = [];       // friends + accepted + pending_sent
  List<Conversation> _requests = [];     // pending_received
  String _searchQuery = '';
  bool _isLoading = true;
  bool _showSearch = false;
  final TextEditingController _searchCtrl = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  Timer? _pollTimer;
  StreamSubscription<dynamic>? _newMsgSub;
  StreamSubscription<dynamic>? _statusSub;
  final Map<String, bool> _onlineMap = {};
  final Map<String, DateTime?> _lastSeenMap = {};
  final List<String> _subscribedIds = [];

  @override
  void initState() {
    super.initState();
    final cached = _chatService.cachedConversations;
    if (cached.isNotEmpty) {
      _direct   = cached.where((c) => !c.showInRequests).toList();
      _requests = cached.where((c) =>  c.showInRequests).toList();
      _isLoading = false;
    }
    _loadConversations();
    _startPolling();
    _newMsgSub = _socket.onNewMessage.listen((_) {
      if (mounted) _loadConversations(isPolling: true);
    });
    _statusSub = _socket.onOnlineStatus.listen((data) {
      final uid = data['user_id']?.toString();
      if (uid == null || !mounted) return;
      final online = data['is_online'] == true;
      final rawLastSeen = data['last_seen']?.toString();
      setState(() {
        _onlineMap[uid] = online;
        if (!online && rawLastSeen != null) {
          _lastSeenMap[uid] = DateTime.tryParse(rawLastSeen);
        }
      });
    });
  }

  void _startPolling() {
    _pollTimer?.cancel();
    final interval = _socket.isConnected
        ? const Duration(seconds: 10)
        : const Duration(seconds: 4);
    _pollTimer = Timer.periodic(interval, (_) {
      if (mounted) _loadConversations(isPolling: true);
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _newMsgSub?.cancel();
    _statusSub?.cancel();
    for (final id in _subscribedIds) {
      _socket.unsubscribeStatus(id);
    }
    _searchCtrl.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  Future<void> _loadConversations({bool isPolling = false}) async {
    try {
      final all = await _chatService.getConversations();
      if (mounted) {
        setState(() {
          final filtered = _searchQuery.isEmpty
              ? all
              : all.where((c) => c.otherUserName.toLowerCase().contains(_searchQuery.toLowerCase())).toList();

          _requests = filtered.where((c) => c.showInRequests).toList();
          _direct   = filtered.where((c) => !c.showInRequests).toList();
          if (!isPolling) _isLoading = false;
        });
        _subscribeToStatuses();
      }
    } catch (e) {
      if (mounted && !isPolling) {
        setState(() => _isLoading = false);
        NeonToast.error(context, 'Error loading conversations: $e');
      }
    }
  }

  void _subscribeToStatuses() {
    final allIds = [..._direct, ..._requests].map((c) => c.otherUserId).toList();
    final newIds = allIds.where((id) => !_subscribedIds.contains(id)).toList();
    for (final id in newIds) {
      _socket.subscribeStatus(id);
      _subscribedIds.add(id);
    }
    if (allIds.isNotEmpty) {
      _socket.getOnlineStatuses(allIds).then((statuses) {
        if (!mounted) return;
        setState(() => statuses.forEach((uid, online) => _onlineMap[uid] = online));
      });
    }
  }

  String _formatLastSeen(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return DateFormat.Md().format(time);
  }

  void _openConversation(Conversation conv) {
    HapticFeedback.mediumImpact();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          userId: conv.otherUserId,
          userName: conv.otherUserName,
          userAvatar: conv.otherUserAvatar,
        ),
      ),
    ).then((_) => _loadConversations());
  }

  void _showDeleteDialog(Conversation conv) {
    HapticFeedback.mediumImpact();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(20))),
        title: const Text('Delete Conversation', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Text(
          'Delete all messages with ${conv.otherUserName}? This cannot be undone.',
          style: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: TextStyle(color: Colors.white.withValues(alpha: 0.6))),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final ok = await _chatService.deleteConversation(conv.otherUserId);
              if (mounted) {
                if (ok) {
                  setState(() {
                    _direct.removeWhere((c) => c.id == conv.id);
                    _requests.removeWhere((c) => c.id == conv.id);
                  });
                  NeonToast.success(context, 'Conversation deleted');
                } else {
                  NeonToast.error(context, 'Failed to delete conversation');
                }
              }
            },
            child: const Text('Delete', style: TextStyle(color: Color(0xFFFF4444), fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  // Fix: compare calendar dates not duration
  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final today  = DateTime(now.year,  now.month,  now.day);
    final msgDay = DateTime(time.year, time.month, time.day);
    final dayDiff = today.difference(msgDay).inDays;

    if (dayDiff == 0) return DateFormat.jm().format(time);
    if (dayDiff == 1) return 'Yesterday';
    if (dayDiff < 7)  return DateFormat.E().format(time);
    return DateFormat.Md().format(time);
  }

  String _getLastMessagePreview(Conversation conv) {
    final msg = conv.lastMessage;
    if (msg == null) return 'No messages';
    switch (msg.type) {
      case MessageType.text:  return msg.content ?? '';
      case MessageType.image: return '📷 Photo';
      case MessageType.video: return '🎥 Video';
      case MessageType.voice:
        final d = msg.voiceDuration;
        return d != null ? '🎤 ${d.inSeconds}s voice message' : '🎤 Voice message';
      case MessageType.call:  return '📞 ${msg.content ?? "Call"}';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: DefaultTabController(
        length: 2,
        child: Column(
          children: [
            _buildHeader(),
            const _ChatStreakCard(),
            const TabBar(
              indicatorColor: Color(0xFFD946EF),
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white54,
              tabs: [Tab(text: 'Direct'), Tab(text: 'Groups')],
            ),
            Expanded(
              child: TabBarView(
                children: [
                  _isLoading
                      ? const Center(child: CircularProgressIndicator(color: GalacticTheme.laserPink))
                      : (_direct.isEmpty && _requests.isEmpty)
                          ? _buildEmptyState()
                          : _buildDirectTab(),
                  const GroupChatListTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDirectTab() {
    return RefreshIndicator(
      color: GalacticTheme.laserPink,
      backgroundColor: const Color(0xFF1A1A1A),
      onRefresh: _loadConversations,
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          _buildRequestsFolderRow(),
          ..._direct.map((c) => _buildConversationItem(c)),
        ],
      ),
    );
  }

  Widget _buildRequestsFolderRow() {
    final previews = _requests.take(3).toList();
    final hasRequests = _requests.isNotEmpty;
    final previewWidth = previews.length > 1 ? 38.0 + (previews.length - 1) * 20.0 : 38.0;
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => _MessageRequestsScreen(
            requests: _requests,
            onRefresh: _loadConversations,
          ),
        ),
      ).then((_) => _loadConversations()),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12, top: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF121212),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: hasRequests
                ? const Color(0xFFFF9F0A).withValues(alpha: 0.5)
                : Colors.white.withValues(alpha: 0.08),
          ),
          boxShadow: hasRequests
              ? [BoxShadow(color: const Color(0xFFFF9F0A).withValues(alpha: 0.08), blurRadius: 12)]
              : null,
        ),
        child: Row(
          children: [
            if (hasRequests)
              SizedBox(
                width: previewWidth,
                height: 38,
                child: Stack(
                  children: [
                    for (int i = 0; i < previews.length; i++)
                      Positioned(
                        left: i * 20.0,
                        child: Container(
                          width: 38, height: 38,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: const Color(0xFF121212), width: 2),
                          ),
                          child: ClipOval(
                            child: previews[i].otherUserAvatar != null && previews[i].otherUserAvatar!.isNotEmpty
                                ? CachedNetworkImage(imageUrl: previews[i].otherUserAvatar!, fit: BoxFit.cover)
                                : _avatarPlaceholder(),
                          ),
                        ),
                      ),
                  ],
                ),
              )
            else
              Container(
                width: 38, height: 38,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.06),
                ),
                child: const Icon(Icons.mark_email_unread_rounded, color: Colors.white38, size: 18),
              ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Message Requests',
                      style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 3),
                  Text(
                    _requests.isEmpty
                        ? 'No requests'
                        : _requests.length == 1
                            ? '${_requests[0].otherUserName} sent you a request'
                            : '${_requests.length} people sent you requests',
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.55), fontSize: 12),
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (hasRequests) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [Color(0xFFFF9F0A), Color(0xFFFF6B00)]),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text('${_requests.length}',
                    style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 4),
            ],
            Icon(Icons.chevron_right_rounded,
                color: hasRequests ? const Color(0xFFFF9F0A) : Colors.white24, size: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    if (_showSearch) {
      return Container(
        padding: const EdgeInsets.fromLTRB(8, 12, 16, 16),
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
              onPressed: () {
                setState(() { _showSearch = false; _searchQuery = ''; _searchCtrl.clear(); });
                _loadConversations();
                _searchFocus.unfocus();
              },
            ),
            Expanded(
              child: Container(
                height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1A1A),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: const Color(0xFFD946EF).withValues(alpha: 0.4), width: 1.5),
                ),
                child: TextField(
                  controller: _searchCtrl,
                  focusNode: _searchFocus,
                  style: const TextStyle(color: Colors.white, fontSize: 15),
                  decoration: const InputDecoration(
                    hintText: 'Search messages...',
                    hintStyle: TextStyle(color: Colors.white38),
                    prefixIcon: Icon(Icons.search_rounded, color: Colors.white38, size: 20),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(vertical: 12),
                  ),
                  onChanged: (v) {
                    setState(() => _searchQuery = v);
                    _loadConversations(isPolling: true);
                  },
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              const Text('Messages', style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold)),
              if (_requests.isNotEmpty) ...[
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF9F0A),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${_requests.length} request${_requests.length == 1 ? '' : 's'}',
                    style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ],
          ),
          GestureDetector(
            onTap: () {
              HapticFeedback.mediumImpact();
              setState(() => _showSearch = true);
              Future.delayed(const Duration(milliseconds: 80), _searchFocus.requestFocus);
            },
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A1A),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFD946EF).withValues(alpha: 0.45), width: 1.5),
                boxShadow: [BoxShadow(color: const Color(0xFFD946EF).withValues(alpha: 0.15), blurRadius: 10)],
              ),
              child: const Icon(Icons.search_rounded, color: Colors.white, size: 22),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: const Color(0xFFD946EF).withValues(alpha: 0.1),
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFFD946EF).withValues(alpha: 0.3), width: 2),
            ),
            child: const Icon(Icons.chat_bubble_outline, color: Color(0xFFD946EF), size: 48),
          ),
          const SizedBox(height: 24),
          const Text('No messages yet', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text('Start a conversation with someone', style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 14)),
        ],
      ),
    );
  }

  Widget _buildConversationItem(Conversation conv, {bool isRequest = false}) {
    final isMyMessage = conv.lastMessage?.senderId == _chatService.currentUserId;
    final borderColor = isRequest
        ? const Color(0xFFFF9F0A).withValues(alpha: 0.5)
        : conv.unreadCount > 0
            ? const Color(0xFFD946EF).withValues(alpha: 0.5)
            : Colors.white.withValues(alpha: 0.08);

    return GestureDetector(
      onTap: () => _openConversation(conv),
      onLongPress: () => _showDeleteDialog(conv),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF121212),
          borderRadius: const BorderRadius.all(Radius.circular(20)),
          border: Border.all(color: borderColor, width: 1),
          boxShadow: (conv.unreadCount > 0 || isRequest)
              ? [BoxShadow(
                  color: (isRequest ? const Color(0xFFFF9F0A) : const Color(0xFFD946EF)).withValues(alpha: 0.08),
                  blurRadius: 12)]
              : null,
        ),
        child: Row(
          children: [
            // Avatar with optional friend badge
            GestureDetector(
              onTap: () {
                HapticFeedback.lightImpact();
                Navigator.push(context, MaterialPageRoute(builder: (_) => ProfileScreen(userId: conv.otherUserId)));
              },
              child: Stack(
                children: [
                  Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: conv.isFriend
                            ? const Color(0xFF22C55E).withValues(alpha: 0.7)
                            : isRequest
                                ? const Color(0xFFFF9F0A).withValues(alpha: 0.6)
                                : const Color(0xFFD946EF).withValues(alpha: 0.5),
                        width: 2,
                      ),
                    ),
                    child: ClipOval(
                      child: conv.otherUserAvatar != null && conv.otherUserAvatar!.isNotEmpty
                          ? CachedNetworkImage(
                              imageUrl: conv.otherUserAvatar!,
                              width: 52, height: 52, fit: BoxFit.cover,
                              placeholder: (_, __) => _avatarPlaceholder(),
                              errorWidget: (_, __, ___) => _avatarPlaceholder(),
                            )
                          : _avatarPlaceholder(),
                    ),
                  ),
                  // Friend indicator dot
                  if (conv.isFriend)
                    const Positioned(
                      bottom: 2, right: 2,
                      child: SizedBox(
                        width: 12, height: 12,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Color(0xFF22C55E),
                            shape: BoxShape.circle,
                            border: Border.fromBorderSide(BorderSide(color: Color(0xFF121212), width: 2)),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 12),

            // Content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            Flexible(
                              child: Text(
                                conv.otherUserName,
                                style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600),
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                              ),
                            ),
                            if (conv.isFriend) ...[
                              const SizedBox(width: 5),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF22C55E).withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: const Color(0xFF22C55E).withValues(alpha: 0.4)),
                                ),
                                child: const Text('Friends', style: TextStyle(color: Color(0xFF22C55E), fontSize: 9, fontWeight: FontWeight.w700)),
                              ),
                            ],
                            if (conv.requestStatus == 'pending_sent') ...[
                              const SizedBox(width: 5),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.07),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text('Pending', style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 9, fontWeight: FontWeight.w600)),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _formatTime(conv.updatedAt),
                        style: TextStyle(
                          color: (conv.unreadCount > 0 || isRequest)
                              ? (isRequest ? const Color(0xFFFF9F0A) : const Color(0xFFD946EF))
                              : Colors.white.withValues(alpha: 0.5),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Builder(builder: (context) {
                    final isOnline = _onlineMap[conv.otherUserId] ?? false;
                    final lastSeen = _lastSeenMap[conv.otherUserId];
                    if (!isOnline && lastSeen == null) return const SizedBox(height: 3);
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 3),
                      child: Row(
                        children: [
                          Container(
                            width: 7,
                            height: 7,
                            decoration: BoxDecoration(
                              color: isOnline
                                  ? const Color(0xFF22C55E)
                                  : Colors.white30,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            isOnline
                                ? 'Online'
                                : 'Last seen ${_formatLastSeen(lastSeen!)}',
                            style: TextStyle(
                              color: isOnline
                                  ? const Color(0xFF22C55E)
                                  : Colors.white38,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                  Row(
                    children: [
                      if (isMyMessage) ...[
                        Builder(builder: (_) {
                          final status = conv.lastMessage?.status;
                          final isRead = status == MessageStatus.read;
                          final isDel  = status == MessageStatus.delivered;
                          return Icon(
                            (isRead || isDel) ? Icons.done_all : Icons.done,
                            color: isRead ? const Color(0xFF29B6F6) : isDel ? Colors.white54 : Colors.white30,
                            size: 15,
                          );
                        }),
                        const SizedBox(width: 4),
                      ],
                      Expanded(
                        child: Text(
                          isRequest ? '📩 ${_getLastMessagePreview(conv)}' : _getLastMessagePreview(conv),
                          style: TextStyle(
                            color: conv.unreadCount > 0 ? Colors.white : Colors.white.withValues(alpha: 0.55),
                            fontSize: 12,
                          ),
                          maxLines: 1, overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Unread badge or request badge
            if (conv.unreadCount > 0) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: isRequest
                        ? [const Color(0xFFFF9F0A), const Color(0xFFFF6B00)]
                        : [const Color(0xFFD946EF), const Color(0xFFFF007F)],
                  ),
                  borderRadius: const BorderRadius.all(Radius.circular(12)),
                ),
                child: Text('${conv.unreadCount}', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
              ),
            ] else if (isRequest) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF9F0A).withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFFFF9F0A).withValues(alpha: 0.4)),
                ),
                child: const Icon(Icons.person_add_rounded, color: Color(0xFFFF9F0A), size: 14),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _avatarPlaceholder() => Container(
    width: 52, height: 52, color: const Color(0xFF2A2A2A),
    child: const Icon(Icons.person, color: Colors.white38),
  );
}

class _MessageRequestsScreen extends StatelessWidget {
  final List<Conversation> requests;
  final VoidCallback onRefresh;

  const _MessageRequestsScreen({required this.requests, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A0A0A),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Message Requests',
                style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
            Text('${requests.length} request${requests.length == 1 ? '' : 's'}',
                style: const TextStyle(color: Color(0xFFFF9F0A), fontSize: 12)),
          ],
        ),
      ),
      body: requests.isEmpty
          ? const Center(
              child: Text('No message requests', style: TextStyle(color: Colors.white38, fontSize: 15)),
            )
          : ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              itemCount: requests.length,
              itemBuilder: (context, i) => _RequestItem(
                conv: requests[i],
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ChatScreen(
                        userId: requests[i].otherUserId,
                        userName: requests[i].otherUserName,
                        userAvatar: requests[i].otherUserAvatar,
                      ),
                    ),
                  ).then((_) => onRefresh());
                },
              ),
            ),
    );
  }
}

class _RequestItem extends StatelessWidget {
  final Conversation conv;
  final VoidCallback onTap;

  const _RequestItem({required this.conv, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF121212),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFFF9F0A).withValues(alpha: 0.35)),
        ),
        child: Row(
          children: [
            ClipOval(
              child: conv.otherUserAvatar != null && conv.otherUserAvatar!.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: conv.otherUserAvatar!,
                      width: 52, height: 52, fit: BoxFit.cover,
                    )
                  : Container(
                      width: 52, height: 52, color: const Color(0xFF2A2A2A),
                      child: const Icon(Icons.person, color: Colors.white38),
                    ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(conv.otherUserName,
                      style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 3),
                  Text(
                    conv.lastMessage?.content ?? 'Sent a message request',
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.55), fontSize: 12),
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: Colors.white38, size: 18),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Chat streak card — shows the user's consecutive-day chat streak + a nudge.
// ═══════════════════════════════════════════════════════════════════════════
class _ChatStreakCard extends StatefulWidget {
  const _ChatStreakCard();

  @override
  State<_ChatStreakCard> createState() => _ChatStreakCardState();
}

class _ChatStreakCardState extends State<_ChatStreakCard> {
  Map<String, dynamic>? _chat;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final info = await ApiService().getStreakInfo();
    if (!mounted) return;
    setState(() {
      _chat = info?['chat_streak'] is Map
          ? Map<String, dynamic>.from(info!['chat_streak'])
          : null;
      _loaded = true;
    });
  }

  int _i(dynamic v) => int.tryParse('${v ?? 0}') ?? 0;

  String _fmtLeft(int s) {
    final h = s ~/ 3600, m = (s % 3600) ~/ 60;
    if (h >= 24) {
      final d = h ~/ 24, rh = h % 24;
      return rh > 0 ? '${d}d ${rh}h' : '${d}d';
    }
    if (h > 0) return m > 0 ? '${h}h ${m}m' : '${h}h';
    return '${m}m';
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded || _chat == null) return const SizedBox.shrink();
    final display = _i(_chat!['display_streak']);
    final current = _i(_chat!['current_streak']);
    final threshold = _chat!['start_threshold'] == null
        ? 3
        : _i(_chat!['start_threshold']);
    final secondsLeft = _i(_chat!['seconds_left']);

    final bool started = display > 0;
    final IconData icon =
        started ? Icons.local_fire_department_rounded : Icons.forum_rounded;
    final Color color =
        started ? const Color(0xFFFF6B35) : const Color(0xFF22D3EE);

    String title;
    String subtitle;
    if (started) {
      title = '$display-day chat streak';
      subtitle = secondsLeft > 0
          ? 'Keep it alive — resets in ${_fmtLeft(secondsLeft)}'
          : 'Send a message today to keep it going';
    } else if (current > 0) {
      final left = (threshold - current).clamp(1, threshold);
      title = 'Chat streak building ($current/$threshold)';
      subtitle = 'Chat $left more day${left == 1 ? '' : 's'} in a row to start it';
    } else {
      title = 'Start a chat streak';
      subtitle = 'Chat $threshold days in a row to begin 🔥';
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color.withValues(alpha: 0.18), color.withValues(alpha: 0.05)],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.18),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 14)),
                const SizedBox(height: 2),
                Text(subtitle,
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.6),
                        fontSize: 12)),
              ],
            ),
          ),
          if (started)
            Text('🔥 $display',
                style: TextStyle(
                    color: color, fontWeight: FontWeight.w800, fontSize: 18)),
        ],
      ),
    );
  }
}
