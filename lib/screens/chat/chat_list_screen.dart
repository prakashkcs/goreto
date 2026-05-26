import 'dart:async';
import 'package:flutter/material.dart';
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
  List<Conversation> _conversations = [];
  List<Conversation> _filteredConversations = [];
  String _searchQuery = '';
  bool _isLoading = true;
  bool _showSearch = false;
  final TextEditingController _searchCtrl = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  Timer? _pollTimer;
  StreamSubscription<dynamic>? _newMsgSub;

  @override
  void initState() {
    super.initState();
    _loadConversations();
    _startPolling();
    // Real-time: reload list instantly when a new message arrives via socket
    _newMsgSub = _socket.onNewMessage.listen((_) {
      if (mounted) _loadConversations(isPolling: true);
    });
  }

  void _startPolling() {
    _pollTimer?.cancel();
    // Back off to 10 s when socket is connected; socket covers the real-time gap.
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
    _searchCtrl.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  Future<void> _loadConversations({bool isPolling = false}) async {
    try {
      final conversations = await _chatService.getConversations();
      if (mounted) {
        setState(() {
          _conversations = conversations;
          _filteredConversations = _searchQuery.isEmpty
              ? conversations
              : conversations
                    .where(
                      (c) => c.otherUserName.toLowerCase().contains(
                        _searchQuery.toLowerCase(),
                      ),
                    )
                    .toList();
          if (!isPolling) _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        if (!isPolling) setState(() => _isLoading = false);
        // Only show toast if not polling, so we don't spam errors on bad connection
        if (!isPolling) {
          NeonToast.error(context, 'Error loading conversations: $e');
        }
      }
    }
  }

  void _hapticFeedback() {
    HapticFeedback.mediumImpact();
  }

  void _openConversation(Conversation conversation) {
    _hapticFeedback();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          userId: conversation.otherUserId,
          userName: conversation.otherUserName,
          userAvatar: conversation.otherUserAvatar,
        ),
      ),
    ).then((_) => _loadConversations());
  }

  void _showDeleteDialog(Conversation conv) {
    _hapticFeedback();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(20))),
        title: const Text(
          'Delete Conversation',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: Text(
          'Delete all messages with ${conv.otherUserName}? This cannot be undone.',
          style: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'Cancel',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
            ),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final success = await _chatService.deleteConversation(
                conv.otherUserId,
              );
              if (mounted) {
                if (success) {
                  setState(() {
                    _conversations.removeWhere((c) => c.id == conv.id);
                  });
                  NeonToast.success(context, 'Conversation deleted');
                } else {
                  NeonToast.error(context, 'Failed to delete conversation');
                }
              }
            },
            child: const Text(
              'Delete',
              style: TextStyle(
                color: Color(0xFFFF4444),
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);

    if (diff.inDays == 0) {
      return DateFormat.jm().format(time);
    } else if (diff.inDays == 1) {
      return 'Yesterday';
    } else if (diff.inDays < 7) {
      return DateFormat.E().format(time);
    } else {
      return DateFormat.Md().format(time);
    }
  }

  String _getLastMessagePreview(Conversation conv) {
    final msg = conv.lastMessage;
    if (msg == null) return 'No messages';

    switch (msg.type) {
      case MessageType.text:
        return msg.content ?? '';
      case MessageType.image:
        return '📷 Photo';
      case MessageType.video:
        return '🎥 Video';
      case MessageType.voice:
        final duration = msg.voiceDuration;
        if (duration != null) {
          return '🎤 ${duration.inSeconds}s voice message';
        }
        return '🎤 Voice message';
      case MessageType.call:
        return '📞 ${msg.content ?? "Call"}';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: Padding(
        padding: EdgeInsets.zero,
        child: DefaultTabController(
          length: 2,
          child: Column(
            children: [
              _buildHeader(),
              const TabBar(
                indicatorColor: Color(0xFFD946EF),
                labelColor: Colors.white,
                unselectedLabelColor: Colors.white54,
                tabs: [
                  Tab(text: 'Direct'),
                  Tab(text: 'Groups'),
                ],
              ),
              Expanded(
                child: TabBarView(
                  children: [
                    // Tab 1: Direct Messages
                    _isLoading
                        ? const Center(
                            child: CircularProgressIndicator(
                              color: GalacticTheme.laserPink,
                            ),
                          )
                        : _conversations.isEmpty
                        ? _buildEmptyState()
                        : _buildConversationList(),

                    // Tab 2: Group Chats
                    const GroupChatListTab(),
                  ],
                ),
              ),
            ],
          ),
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
                setState(() {
                  _showSearch = false;
                  _searchQuery = '';
                  _searchCtrl.clear();
                  _filteredConversations = _conversations;
                });
                _searchFocus.unfocus();
              },
            ),
            Expanded(
              child: Container(
                height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1A1A),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(
                    color: const Color(0xFFD946EF).withValues(alpha: 0.4),
                    width: 1.5,
                  ),
                ),
                child: TextField(
                  controller: _searchCtrl,
                  focusNode: _searchFocus,
                  style: const TextStyle(color: Colors.white, fontSize: 15),
                  decoration: const InputDecoration(
                    hintText: 'Search messages...',
                    hintStyle: TextStyle(color: Colors.white38),
                    prefixIcon: Icon(Icons.search_rounded,
                        color: Colors.white38, size: 20),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(vertical: 12),
                  ),
                  onChanged: (v) {
                    setState(() {
                      _searchQuery = v;
                      _filteredConversations = v.isEmpty
                          ? _conversations
                          : _conversations
                              .where((c) => c.otherUserName
                                  .toLowerCase()
                                  .contains(v.toLowerCase()))
                              .toList();
                    });
                  },
                ),
              ),
            ),
            if (_searchCtrl.text.isNotEmpty) ...[
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () {
                  setState(() {
                    _searchQuery = '';
                    _searchCtrl.clear();
                    _filteredConversations = _conversations;
                  });
                },
                child: const Icon(Icons.close_rounded,
                    color: Colors.white54, size: 22),
              ),
            ],
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text(
            'Messages',
            style: TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.bold,
            ),
          ),
          GestureDetector(
            onTap: () {
              HapticFeedback.mediumImpact();
              setState(() => _showSearch = true);
              Future.delayed(const Duration(milliseconds: 80),
                  _searchFocus.requestFocus);
            },
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A1A),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: const Color(0xFFD946EF).withValues(alpha: 0.45),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFD946EF).withValues(alpha: 0.15),
                    blurRadius: 10,
                  ),
                ],
              ),
              child: const Icon(Icons.search_rounded,
                  color: Colors.white, size: 22),
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
              border: Border.all(
                color: const Color(0xFFD946EF).withValues(alpha: 0.3),
                width: 2,
              ),
            ),
            child: const Icon(
              Icons.chat_bubble_outline,
              color: Color(0xFFD946EF),
              size: 48,
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'No messages yet',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Start a conversation with someone',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.6),
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConversationList() {
    return RefreshIndicator(
      color: GalacticTheme.laserPink,
      backgroundColor: const Color(0xFF1A1A1A),
      onRefresh: _loadConversations,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _filteredConversations.length,
        itemBuilder: (context, index) {
          return _buildConversationItem(_filteredConversations[index]);
        },
      ),
    );
  }

  Widget _buildConversationItem(Conversation conv) {
    final isMyMessage =
        conv.lastMessage?.senderId == _chatService.currentUserId;

    return GestureDetector(
      onTap: () => _openConversation(conv),
      onLongPress: () => _showDeleteDialog(conv),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF121212),
          borderRadius: const BorderRadius.all(Radius.circular(20)),
          border: Border.all(
            color: conv.unreadCount > 0
                ? const Color(0xFFD946EF).withValues(alpha: 0.5)
                : Colors.white.withValues(alpha: 0.08),
            width: 1,
          ),
          boxShadow: conv.unreadCount > 0
              ? [
                  BoxShadow(
                    color: const Color(0xFFD946EF).withValues(alpha: 0.1),
                    blurRadius: 12,
                  ),
                ]
              : null,
        ),
        child: Row(
          children: [
            // Avatar
            GestureDetector(
              onTap: () {
                HapticFeedback.lightImpact();
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ProfileScreen(userId: conv.otherUserId),
                  ),
                );
              },
              child: Stack(
                children: [
                  Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: const Color(0xFFD946EF).withValues(alpha: 0.5),
                      width: 2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFD946EF).withValues(alpha: 0.2),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                  child: ClipOval(
                    child: conv.otherUserAvatar != null
                        ? CachedNetworkImage(
                            imageUrl: conv.otherUserAvatar!,
                            width: 56,
                            height: 56,
                            fit: BoxFit.cover,
                            placeholder: (_, __) => Container(
                              color: const Color(0xFF2A2A2A),
                              child: const Icon(
                                Icons.person,
                                color: Colors.white38,
                              ),
                            ),
                            errorWidget: (_, __, ___) => Container(
                              color: const Color(0xFF2A2A2A),
                              child: const Icon(
                                Icons.person,
                                color: Colors.white38,
                              ),
                            ),
                          )
                        : Container(
                            width: 56,
                            height: 56,
                            color: const Color(0xFF2A2A2A),
                            child: const Icon(
                              Icons.person,
                              color: Colors.white38,
                            ),
                          ),
                  ),
                ),
                // Online indicator
                const Positioned(
                  bottom: 2,
                  right: 2,
                  child: SizedBox(
                    width: 14,
                    height: 14,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Color(0xFF22C55E),
                        shape: BoxShape.circle,
                        border: Border.fromBorderSide(BorderSide(
                          color: Color(0xFF121212),
                          width: 2,
                        )),
                      ),
                    ),
                  ),
                ),
              ],
              ),
            ),
            const SizedBox(width: 14),
            // Content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          conv.otherUserName,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _formatTime(conv.updatedAt),
                        style: TextStyle(
                          color: conv.unreadCount > 0
                              ? const Color(0xFFD946EF)
                              : Colors.white.withValues(alpha: 0.5),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      if (isMyMessage) ...[
                        Builder(builder: (_) {
                          final status = conv.lastMessage?.status;
                          final isRead = status == MessageStatus.read;
                          final isDelivered = status == MessageStatus.delivered;
                          return Icon(
                            (isRead || isDelivered) ? Icons.done_all : Icons.done,
                            color: isRead
                                ? const Color(0xFF29B6F6)   // bright blue = seen
                                : isDelivered
                                    ? Colors.white54         // gray double = delivered
                                    : Colors.white30,        // dim single = sent/offline
                            size: 16,
                          );
                        }),
                        const SizedBox(width: 4),
                      ],
                      Expanded(
                        child: Text(
                          _getLastMessagePreview(conv),
                          style: TextStyle(
                            color: conv.unreadCount > 0
                                ? Colors.white
                                : Colors.white.withValues(alpha: 0.6),
                            fontSize: 13,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            // Unread badge
            if (conv.unreadCount > 0) ...[
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFD946EF), Color(0xFFFF007F)],
                  ),
                  borderRadius: const BorderRadius.all(Radius.circular(12)),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFD946EF).withValues(alpha: 0.4),
                      blurRadius: 8,
                    ),
                  ],
                ),
                child: Text(
                  '${conv.unreadCount}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
