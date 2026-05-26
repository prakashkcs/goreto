import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:love_vibe_pro/config/app_env.dart';
import 'package:love_vibe_pro/services/api_service.dart';
import 'package:love_vibe_pro/services/sound_service.dart';
import 'package:love_vibe_pro/widgets/gifter_badge.dart';
import 'package:love_vibe_pro/screens/gifts/gifts_sheet.dart';
import 'package:love_vibe_pro/services/profile_service.dart';
import 'package:love_vibe_pro/services/video_call/video_call_manager.dart';
import 'package:love_vibe_pro/services/video_call/providers/zego_provider.dart';
import 'package:love_vibe_pro/services/user_prefs_cache.dart';
import 'package:zego_uikit_prebuilt_live_streaming/zego_uikit_prebuilt_live_streaming.dart';

String _giftEmojiFor(String name) {
  final n = name.toLowerCase();
  if (n.contains('rose') || n.contains('flower') || n.contains('bouquet')) return '🌹';
  if (n.contains('kiss') || n.contains('lip')) return '💋';
  if (n.contains('diamond')) return '💎';
  if (n.contains('ring')) return '💍';
  if (n.contains('crown')) return '👑';
  if (n.contains('castle')) return '🏰';
  if (n.contains('angel')) return '👼';
  if (n.contains('cupid') || n.contains('arrow')) return '💘';
  if (n.contains('heart') || n.contains('love') || n.contains('sweet')) return '💖';
  if (n.contains('teddy') || n.contains('bear')) return '🧸';
  if (n.contains('chocolate') || n.contains('choco')) return '🍫';
  if (n.contains('letter')) return '💌';
  if (n.contains('rocket') || n.contains('space')) return '🚀';
  if (n.contains('fire')) return '🔥';
  if (n.contains('star')) return '⭐';
  if (n.contains('unicorn')) return '🦄';
  if (n.contains('dragon')) return '🐉';
  if (n.contains('money') || n.contains('bag')) return '💰';
  if (n.contains('yacht') || n.contains('boat')) return '⛵';
  if (n.contains('jet') || n.contains('plane')) return '✈️';
  if (n.contains('car')) return '🏎️';
  if (n.contains('galaxy')) return '🌌';
  if (n.contains('gold')) return '🥇';
  if (n.contains('poop')) return '💩';
  return '🎁';
}

class _ChatMsg {
  final String sender;
  final String senderUserId;
  final String text;
  final Color color;
  _ChatMsg({
    required this.sender,
    this.senderUserId = '',
    required this.text,
    required this.color,
  });
}

class _GiftAnim {
  final String name;
  final String senderName;
  final String senderId;
  final String senderAvatar;
  final int coins;
  final String gifUrl;
  final String emoji;
  _GiftAnim({
    required this.name,
    required this.senderName,
    this.senderId = '',
    this.senderAvatar = '',
    required this.coins,
    this.gifUrl = '',
    String? emoji,
  }) : emoji = emoji ?? _giftEmojiFor(name);
}

class _TopGifter {
  final String userId;
  String name;
  String avatar;
  int totalCoins;
  _TopGifter({required this.userId, required this.name,
      required this.avatar, required this.totalCoins});
}

class LiveRoomScreen extends StatefulWidget {
  final String userId;
  final String? userName;
  final String? userAvatar;
  final int? viewerCount;

  const LiveRoomScreen({
    super.key,
    required this.userId,
    this.userName,
    this.userAvatar,
    this.viewerCount,
  });

  @override
  State<LiveRoomScreen> createState() => _LiveRoomScreenState();
}

class _LiveRoomScreenState extends State<LiveRoomScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  // ── Video ──────────────────────────────────────────────────────────
  final VideoCallManager _videoManager = VideoCallManager();
  bool _videoInitialized = false;
  bool _videoInitializing = true;
  String _initError = '';
  bool _isHost = false;
  bool _hasStartedLive = false;
  bool _hasEndedLive = false;
  bool _isFollowingHost = false;
  Timer? _heartbeatTimer;
  String _currentUserName = 'User';
  String _currentUserId = '';
  String _currentUserAvatar = '';
  final ApiService _api = ApiService();

  // ── Center gift animation (premium ≥100 coins) ────────────────────
  late final AnimationController _giftCtrl;
  late final Animation<double> _giftFade;
  late final Animation<double> _giftScale;
  _GiftAnim? _currentGift;
  final List<_GiftAnim> _giftQueue = [];
  bool _giftPlaying = false;

  // ── Left-side gift notification (all gifts) ───────────────────────
  late final AnimationController _notifCtrl;
  late final Animation<Offset> _notifSlide;
  late final Animation<double> _notifFade;
  _GiftAnim? _activeNotif;
  final List<_GiftAnim> _notifQueue = [];
  bool _notifPlaying = false;

  // ── Chat ───────────────────────────────────────────────────────────
  final TextEditingController _chatController = TextEditingController();
  final ScrollController _chatScroll = ScrollController();
  final List<_ChatMsg> _chatMessages = [];
  static const _chatColors = [
    Color(0xFFFF6B9D), Color(0xFF7C4DFF), Color(0xFF00B8FF),
    Color(0xFF00E5FF), Color(0xFFFF9500), Color(0xFF69F0AE),
    Color(0xFFFFD740), Color(0xFFFF80AB),
  ];
  int _chatColorIdx = 0;
  final Map<String, Color> _userColors = {};

  // ── Gifts & categories ─────────────────────────────────────────────
  List<Map<String, dynamic>> _loadedGifts = [];
  String _selectedCategory = 'all';

  // ── Coin balance & duration ────────────────────────────────────────
  int _coinBalance = 0;
  Timer? _durationTimer;
  final ValueNotifier<int> _durationNotifier = ValueNotifier(0);

  // ── User profile cache (avatar + rating, keyed by userId) ─────────
  final Map<String, Map<String, dynamic>> _userProfileCache = {};

  // ── Top gifters leaderboard ────────────────────────────────────────
  final Map<String, _TopGifter> _topGifters = {};

  // ── Invite & viewer tracking ───────────────────────────────────────
  final Set<String> _invitedUserIds = {};
  Timer? _viewerPollTimer;
  Set<String> _prevViewerIds = {};

  // ── Zego messages ─────────────────────────────────────────────────
  StreamSubscription<ZegoInRoomMessage>? _messageSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _giftCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 3200));
    _giftFade = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.0), weight: 12),
      TweenSequenceItem(tween: ConstantTween(1.0), weight: 72),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0), weight: 16),
    ]).animate(_giftCtrl);
    _giftScale = TweenSequence<double>([
      TweenSequenceItem(
          tween: Tween(begin: 0.4, end: 1.08)
              .chain(CurveTween(curve: Curves.easeOutBack)),
          weight: 20),
      TweenSequenceItem(tween: Tween(begin: 1.08, end: 1.0), weight: 8),
      TweenSequenceItem(tween: ConstantTween(1.0), weight: 72),
    ]).animate(_giftCtrl);
    _giftCtrl.addStatusListener(
        (s) { if (s == AnimationStatus.completed) _playNextGift(); });

    _notifCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 5500));
    _notifSlide = TweenSequence<Offset>([
      TweenSequenceItem(
          tween: Tween(begin: const Offset(-1.5, 0), end: Offset.zero)
              .chain(CurveTween(curve: Curves.easeOutCubic)),
          weight: 9),
      TweenSequenceItem(tween: ConstantTween(Offset.zero), weight: 82),
      TweenSequenceItem(
          tween: Tween(begin: Offset.zero, end: const Offset(-1.5, 0))
              .chain(CurveTween(curve: Curves.easeInCubic)),
          weight: 9),
    ]).animate(_notifCtrl);
    _notifFade = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.0), weight: 7),
      TweenSequenceItem(tween: ConstantTween(1.0), weight: 85),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0), weight: 8),
    ]).animate(_notifCtrl);
    _notifCtrl.addStatusListener(
        (s) { if (s == AnimationStatus.completed) _playNextNotif(); });

    _initializeCamera();
    _loadGifts();
    _loadCoinBalance();
    _subscribeMessages();

    _durationTimer = Timer.periodic(
        const Duration(seconds: 1), (_) { _durationNotifier.value++; });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _durationTimer?.cancel();
      _durationTimer = null;
    } else if (state == AppLifecycleState.resumed && _durationTimer == null) {
      _durationTimer = Timer.periodic(
          const Duration(seconds: 1), (_) { _durationNotifier.value++; });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _messageSub?.cancel();
    _heartbeatTimer?.cancel();
    _viewerPollTimer?.cancel();
    _durationTimer?.cancel();
    _durationNotifier.dispose();
    _giftCtrl.dispose();
    _notifCtrl.dispose();
    _chatController.dispose();
    _chatScroll.dispose();
    if (_isHost && !_hasEndedLive) { _hasEndedLive = true; _api.endLive(); }
    try { _videoManager.activeProvider?.leaveCall(); } catch (_) {}
    super.dispose();
  }

  // ── Data loading ───────────────────────────────────────────────────
  Future<void> _loadGifts() async {
    try {
      final gifts = await _api.getGifts();
      if (mounted) setState(() => _loadedGifts = gifts);
    } catch (_) {}
  }

  Future<void> _fetchFollowStatus() async {
    try {
      final result = await _api.getFollowStatus(widget.userId);
      if (!mounted) return;
      final following = result?['is_following'] == 1 ||
          result?['is_following'] == true ||
          result?['following'] == 1 ||
          result?['following'] == true;
      setState(() => _isFollowingHost = following);
    } catch (_) {}
  }

  Future<void> _loadCoinBalance() async {
    try {
      final info = await _api.getWalletBalanceRemote();
      if (mounted) setState(() => _coinBalance = info.coins);
    } catch (_) {}
  }

  Future<void> _fetchUserProfile(String userId) async {
    if (_userProfileCache.containsKey(userId)) return;
    _userProfileCache[userId] = const {};
    try {
      final data = await _api.getProfileStats(userId);
      if (!mounted || data == null) return;
      String avatar = (data['profile_pic'] ?? data['avatar'] ?? '').toString();
      if (avatar.isNotEmpty && !avatar.startsWith('http')) {
        final base = AppEnv.liveBaseUrl.replaceAll('/api/v1/', '');
        avatar = '$base/${avatar.startsWith('/') ? avatar.substring(1) : avatar}';
      }
      final rating = double.tryParse(data['rating']?.toString() ?? '0') ?? 0.0;
      final totalCoinsSent = int.tryParse((data['total_coins_sent'] ?? '0').toString()) ?? 0;
      setState(() => _userProfileCache[userId] = {
        'avatar': avatar,
        'rating': rating,
        'total_coins_sent': totalCoinsSent,
      });
    } catch (_) {
      _userProfileCache[userId] = {'avatar': '', 'rating': 0.0};
    }
  }

  void _showViewerList() {
    List<ZegoUIKitUser> viewers = [];
    try { viewers = ZegoUIKit().getAllUsers(); } catch (_) {}
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF111111),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.55,
        minChildSize: 0.3,
        maxChildSize: 0.85,
        builder: (_, scroll) => Column(
          children: [
            Container(
              margin: const EdgeInsets.only(top: 10, bottom: 8),
              width: 40, height: 4,
              decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2)),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(children: [
                const Icon(Icons.remove_red_eye_rounded,
                    color: Colors.white54, size: 16),
                const SizedBox(width: 6),
                Text(
                  '${viewers.length} Viewers',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold),
                ),
              ]),
            ),
            const Divider(color: Colors.white12),
            Expanded(
              child: viewers.isEmpty
                  ? const Center(
                      child: Text('No viewers yet',
                          style: TextStyle(color: Colors.white38)))
                  : ListView.builder(
                      controller: scroll,
                      itemCount: viewers.length,
                      itemBuilder: (_, i) {
                        final v = viewers[i];
                        final vid = v.id.toString();
                        final vname = v.name.isEmpty ? 'User' : v.name;
                        if (!_userProfileCache.containsKey(vid)) {
                          _fetchUserProfile(vid);
                        }
                        final cached = _userProfileCache[vid];
                        final avatarUrl = cached?['avatar'] ?? '';
                        final rating = (cached?['rating'] ?? 0.0) as double;
                        return ListTile(
                          leading: CircleAvatar(
                            radius: 22,
                            backgroundColor: const Color(0xFF2A1040),
                            backgroundImage: avatarUrl.isNotEmpty
                                ? CachedNetworkImageProvider(avatarUrl)
                                : null,
                            child: avatarUrl.isEmpty
                                ? Text(
                                    vname.isNotEmpty
                                        ? vname[0].toUpperCase()
                                        : '?',
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold))
                                : null,
                          ),
                          title: Text(vname,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600)),
                          subtitle: rating > 0
                              ? Row(children: [
                                  const Icon(Icons.star_rounded,
                                      color: Colors.amber, size: 13),
                                  const SizedBox(width: 3),
                                  Text(rating.toStringAsFixed(1),
                                      style: const TextStyle(
                                          color: Colors.amber, fontSize: 12)),
                                ])
                              : null,
                          onTap: () {
                            Navigator.pop(ctx);
                            _showUserProfilePreview(vid, vname, avatarUrl, rating);
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  void _showInviteSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF111111),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => _InviteToLiveSheet(
        api: _api,
        currentUserId: _currentUserId,
        invitedUserIds: _invitedUserIds,
        onInvite: (selectedIds) async {
          final newIds = selectedIds
              .where((id) => !_invitedUserIds.contains(id))
              .toList();
          if (newIds.isEmpty) return;
          final ok = await _api.inviteToLive(newIds);
          if (ok) {
            setState(() => _invitedUserIds.addAll(newIds));
            if (mounted) _showSnack('Invite sent to ${newIds.length} friend${newIds.length == 1 ? '' : 's'}!');
          }
        },
      ),
    );
  }

  void _showUserProfilePreview(
      String userId, String userName, String avatarUrl, double rating) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A2E),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 44,
              backgroundColor: const Color(0xFF2A1040),
              backgroundImage: avatarUrl.isNotEmpty
                  ? CachedNetworkImageProvider(avatarUrl)
                  : null,
              child: avatarUrl.isEmpty
                  ? Text(userName.isNotEmpty ? userName[0].toUpperCase() : '?',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 28,
                          fontWeight: FontWeight.bold))
                  : null,
            ),
            const SizedBox(height: 12),
            Text(userName,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold)),
            if (rating > 0) ...[
              const SizedBox(height: 6),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                const Icon(Icons.star_rounded, color: Colors.amber, size: 16),
                const SizedBox(width: 4),
                Text(rating.toStringAsFixed(1),
                    style: const TextStyle(color: Colors.amber, fontSize: 14)),
              ]),
            ],
            const SizedBox(height: 20),
            Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
              _profileActionBtn('Follow', Icons.person_add_rounded,
                  const Color(0xFFFF2D55), () {
                _api.followUser(userId);
                Navigator.pop(ctx);
              }),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _profileActionBtn(
      String label, IconData icon, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 10),
        decoration: BoxDecoration(
          gradient: LinearGradient(
              colors: [color, color.withValues(alpha: 0.7)]),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: Colors.white, size: 16),
          const SizedBox(width: 6),
          Text(label,
              style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 14)),
        ]),
      ),
    );
  }

  List<Map<String, dynamic>> get _categoryGifts {
    List<Map<String, dynamic>> list;
    if (_selectedCategory == 'all') {
      list = List.from(_loadedGifts);
      list.sort((a, b) {
        final af = (a['is_featured'] == true || a['is_featured'] == 1) ? 1 : 0;
        final bf = (b['is_featured'] == true || b['is_featured'] == 1) ? 1 : 0;
        if (af != bf) return bf.compareTo(af);
        final ac = int.tryParse((a['coin_price'] ?? 0).toString()) ?? 0;
        final bc = int.tryParse((b['coin_price'] ?? 0).toString()) ?? 0;
        return ac.compareTo(bc);
      });
    } else {
      list = _loadedGifts
          .where((g) => (g['category'] ?? '').toString() == _selectedCategory)
          .toList()
        ..sort((a, b) {
          final ac = int.tryParse((a['coin_price'] ?? 0).toString()) ?? 0;
          final bc = int.tryParse((b['coin_price'] ?? 0).toString()) ?? 0;
          return ac.compareTo(bc);
        });
    }
    return list.take(10).toList();
  }

  // ── Messages ───────────────────────────────────────────────────────
  void _subscribeMessages() {
    try {
      _messageSub =
          ZegoUIKit().getInRoomMessageStream().listen(_onMessage);
    } catch (_) {}
  }

  void _onMessage(ZegoInRoomMessage msg) {
    if (msg.message.startsWith('GIFT|')) {
      final parts = msg.message.split('|');
      if (parts.length >= 5) {
        final coins    = int.tryParse(parts[2]) ?? 0;
        final senderId = parts.length > 5 ? parts[5] : '';
        // Skip echoes of our own gifts — handled locally in _onQuickGiftTap
        if (senderId == _currentUserId) return;
        final avatar   = parts.length > 6 ? parts[6] : '';
        final emoji    = parts.length > 7 ? parts[7] : '';
        final g = _GiftAnim(
          name: parts[1], coins: coins, senderName: parts[3],
          gifUrl: parts[4], senderId: senderId, senderAvatar: avatar,
          emoji: emoji.isNotEmpty ? emoji : null,
        );
        _updateTopGifter(senderId, parts[3], avatar, coins);
        SoundService().playGiftSound(coins);
        _enqueueNotif(g);
        if (coins >= 100) _enqueueGift(g);
      }
    } else if (msg.message.isNotEmpty) {
      final sender = msg.user.name.isEmpty ? 'User' : msg.user.name;
      final senderId = msg.user.id;
      // Own messages are added optimistically in _sendChat(); skip here.
      if (senderId == _currentUserId) return;
      if (!_userColors.containsKey(sender)) {
        _userColors[sender] =
            _chatColors[_chatColorIdx % _chatColors.length];
        _chatColorIdx++;
      }
      _fetchUserProfile(senderId);
      if (mounted) {
        setState(() {
          _chatMessages.add(_ChatMsg(
              sender: sender,
              senderUserId: senderId,
              text: msg.message,
              color: _userColors[sender]!));
          if (_chatMessages.length > 15) _chatMessages.removeAt(0);
        });
        _scrollChat();
      }
    }
  }

  void _checkNewViewers() {
    if (!mounted) return;
    try {
      final users = ZegoUIKit().getAllUsers();
      final currentIds = users.map((u) => u.id.toString()).toSet();
      final newIds = currentIds.difference(_prevViewerIds);
      for (final uid in newIds) {
        if (uid == _currentUserId) continue;
        final user = users.firstWhere(
          (u) => u.id.toString() == uid,
          orElse: () => ZegoUIKitUser(id: uid, name: ''),
        );
        final name = user.name.isNotEmpty ? user.name : 'Someone';
        setState(() {
          _chatMessages.add(_ChatMsg(
            sender: '',
            text: '$name joined the live!',
            color: const Color(0xFF69F0AE),
          ));
          if (_chatMessages.length > 15) _chatMessages.removeAt(0);
        });
        _scrollChat();
      }
      _prevViewerIds = currentIds;
    } catch (_) {}
  }

  void _scrollChat() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_chatScroll.hasClients) {
        _chatScroll.animateTo(
          _chatScroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // ── Top gifter tracking ────────────────────────────────────────────
  void _updateTopGifter(String userId, String name, String avatar, int coins) {
    if (userId.isEmpty || coins <= 0) return;
    setState(() {
      if (_topGifters.containsKey(userId)) {
        _topGifters[userId]!.totalCoins += coins;
        if (name.isNotEmpty) _topGifters[userId]!.name = name;
        if (avatar.isNotEmpty) _topGifters[userId]!.avatar = avatar;
      } else {
        _topGifters[userId] = _TopGifter(
          userId: userId, name: name.isNotEmpty ? name : 'User',
          avatar: avatar, totalCoins: coins,
        );
      }
    });
  }

  // ── Gift animation queues ──────────────────────────────────────────
  void _enqueueGift(_GiftAnim g) {
    _giftQueue.add(g);
    if (!_giftPlaying) _playNextGift();
  }

  void _playNextGift() {
    if (_giftQueue.isEmpty) {
      if (mounted) setState(() { _currentGift = null; _giftPlaying = false; });
      return;
    }
    _giftPlaying = true;
    final next = _giftQueue.removeAt(0);
    if (mounted) setState(() => _currentGift = next);
    _giftCtrl.forward(from: 0);
  }

  void _enqueueNotif(_GiftAnim g) {
    _notifQueue.add(g);
    if (!_notifPlaying) _playNextNotif();
  }

  void _playNextNotif() {
    if (_notifQueue.isEmpty) {
      if (mounted) setState(() { _activeNotif = null; _notifPlaying = false; });
      return;
    }
    _notifPlaying = true;
    final next = _notifQueue.removeAt(0);
    if (mounted) setState(() => _activeNotif = next);
    _notifCtrl.forward(from: 0);
  }

  // ── Quick gift tap ─────────────────────────────────────────────────
  Future<void> _onQuickGiftTap(Map<String, dynamic> gift) async {
    final giftId = int.tryParse((gift['id'] ?? 0).toString()) ?? 0;
    if (giftId <= 0) return;
    final name = (gift['name'] ?? 'Gift').toString();
    final coins = int.tryParse((gift['coin_price'] ?? 0).toString()) ?? 0;
    final gifUrl = (gift['gif_url'] ?? gift['thumb_image'] ?? '').toString();
    final emoji = (gift['emoji'] ?? _giftEmojiFor(name)).toString();

    HapticFeedback.mediumImpact();

    final result = await _api.sendGift(
      giftId: giftId.toString(),
      toUserId: widget.userId,
      contextType: 'live',
      contextId: widget.userId,
      message: '',
    );
    if (!mounted) return;

    final msg = (result['message'] ?? '').toString();
    final success = result['status'] == 'success' ||
        result['status'] == 'ok' ||
        result['status'] == true ||
        result['status'] == 1 ||
        result['success'] == true ||
        result['success'] == 1 ||
        msg.toLowerCase().contains('sent') ||
        msg.toLowerCase().contains('success');

    if (success) {
      final newBal = result['new_balance'] ?? result['balance_coins'];
      if (newBal != null) {
        setState(() => _coinBalance = int.tryParse(newBal.toString()) ?? _coinBalance);
      } else if (coins > 0) {
        setState(() => _coinBalance = (_coinBalance - coins).clamp(0, 999999));
      }
      ZegoUIKit().sendInRoomMessage('GIFT|$name|$coins|$_currentUserName|$gifUrl|$_currentUserId|$_currentUserAvatar|$emoji');
      _updateTopGifter(_currentUserId, _currentUserName, _currentUserAvatar, coins);
      SoundService().playGiftSound(coins);
      final g = _GiftAnim(name: name, senderName: _currentUserName, senderId: _currentUserId, senderAvatar: _currentUserAvatar, coins: coins, gifUrl: gifUrl, emoji: emoji);
      _enqueueNotif(g);
      if (coins >= 100) _enqueueGift(g);
    } else {
      final isLow = msg.toLowerCase().contains('not enough') ||
          msg.toLowerCase().contains('insufficient');
      _showSnack(isLow
          ? 'Not enough coins! Add coins to your wallet.'
          : (msg.isNotEmpty ? msg : 'Failed to send gift'));
    }
  }

  void _openFullGiftsSheet() {
    HapticFeedback.lightImpact();
    GiftsSheet.show(
      context: context,
      toUserId: widget.userId,
      contextType: 'live',
      contextId: widget.userId,
      liveMode: true,
      onGiftSent: (name, coins, gifUrl, emoji) {
        if (coins > 0) {
          setState(() => _coinBalance = (_coinBalance - coins).clamp(0, 999999));
        }
        ZegoUIKit().sendInRoomMessage('GIFT|$name|$coins|$_currentUserName|$gifUrl|$_currentUserId|$_currentUserAvatar|$emoji');
        _updateTopGifter(_currentUserId, _currentUserName, _currentUserAvatar, coins);
        final g = _GiftAnim(name: name, senderName: _currentUserName, senderId: _currentUserId, senderAvatar: _currentUserAvatar, coins: coins, gifUrl: gifUrl, emoji: emoji);
        _enqueueNotif(g);
        if (coins >= 100) _enqueueGift(g);
        SoundService().playGiftSound(coins);
        _loadCoinBalance();
      },
    );
  }

  void _sendChat() {
    final text = _chatController.text.trim();
    if (text.isEmpty) return;
    ZegoUIKit().sendInRoomMessage(text);
    if (!_userColors.containsKey(_currentUserName)) {
      _userColors[_currentUserName] = const Color(0xFFFF6B9D);
    }
    setState(() {
      _chatMessages.add(_ChatMsg(
          sender: _currentUserName,
          senderUserId: _currentUserId,
          text: text,
          color: _userColors[_currentUserName]!));
      if (_chatMessages.length > 15) _chatMessages.removeAt(0);
    });
    _chatController.clear();
    _scrollChat();
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: const Color(0xFFFF2D55),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      margin: const EdgeInsets.all(16),
    ));
  }

  // ── Live backend ───────────────────────────────────────────────────
  Future<void> _endLiveOnBackend() async {
    if (!_isHost || _hasEndedLive) return;
    _hasEndedLive = true;
    _heartbeatTimer?.cancel();
    try { await _api.endLive(); } catch (_) {}
  }

  Future<void> _endLive() async {
    await _endLiveOnBackend();
    if (mounted) Navigator.pop(context);
  }

  Future<void> _initializeCamera() async {
    try {
      final currentUserId = UserPrefsCache.instance.userId ?? '';
      _currentUserId = currentUserId;
      _isHost = currentUserId == widget.userId;
      if (!_isHost) _fetchFollowStatus();

      final profile = await ProfileService.instance.getCachedProfile();
      String userName = profile?.name ?? '';
      if (userName.isEmpty) {
        userName = _isHost
            ? (widget.userName ?? 'Host')
            : 'Viewer_${currentUserId.isNotEmpty ? currentUserId : '1'}';
      }
      _currentUserName = userName;
      _currentUserAvatar =
          profile?.profilePicUrl ?? profile?.avatar ?? widget.userAvatar ?? '';
      if (currentUserId.isNotEmpty && _currentUserAvatar.isNotEmpty) {
        _userProfileCache[currentUserId] = {
          'avatar': _currentUserAvatar,
          'rating': (profile?.rating ?? 0.0),
        };
      }

      final success = await _videoManager.initialize(
          currentUserId: currentUserId, currentUserName: userName);
      if (!success) {
        if (mounted) {
          setState(() {
            _videoInitializing = false;
            _initError = 'Could not initialize video provider';
          });
        }
        return;
      }

      try {
        final p = _videoManager.activeProvider;
        if (p is ZegoProvider) {
          if (_currentUserAvatar.isNotEmpty) {
            p.setHostAvatar(_isHost ? _currentUserAvatar : (widget.userAvatar ?? ''));
            p.setViewerAvatar(_currentUserAvatar);
          }
          if (_isHost) p.setOnEndLiveCallback(_endLiveOnBackend);
        }
      } catch (_) {}

      await _videoManager.activeProvider!.joinCall('live_${widget.userId}');
      if (_isHost) {
        _hasStartedLive = true;
        _api.startLive();
        _heartbeatTimer = Timer.periodic(
            const Duration(seconds: 15), (_) => _api.heartbeatLive());
        _viewerPollTimer = Timer.periodic(
            const Duration(seconds: 5), (_) => _checkNewViewers());
      }
      if (mounted) {
        setState(() { _videoInitialized = true; _videoInitializing = false; });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _videoInitializing = false;
          _initError = 'Failed to start: $e';
        });
      }
    }
  }

  // ── Build ──────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          Positioned.fill(child: _buildVideoBackground()),

          // Top gradient (readability)
          Positioned(
            top: 0, left: 0, right: 0, height: 180,
            child: IgnorePointer(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.65),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          ),

          // Bottom gradient (readability)
          Positioned(
            bottom: 0, left: 0, right: 0, height: 320,
            child: IgnorePointer(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.82),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          ),

          // Custom header (both host and viewer)
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 12, right: 12,
            child: _buildStreamerHeader(),
          ),

          // Center animation (premium gifts ≥ 100 coins)
          if (_currentGift != null)
            Positioned(
              top: 0, left: 0, right: 0, bottom: 200,
              child: IgnorePointer(
                child: AnimatedBuilder(
                  animation: _giftCtrl,
                  builder: (_, child) =>
                      Opacity(opacity: _giftFade.value, child: child),
                  child: _buildCenterAnim(_currentGift!),
                ),
              ),
            ),

          // Black bar covering transparent system nav bar (edge-to-edge mode)
          Positioned(
            left: 0, right: 0, bottom: 0,
            height: MediaQuery.of(context).padding.bottom,
            child: const ColoredBox(color: Colors.black),
          ),

          // Overlay: chat messages + gift notifications (+ gift controls for viewer)
          _LiveViewerOverlay(
            isHost: _isHost,
            chatController: _chatController,
            onSendChat: _sendChat,
            onQuickGiftTap: _onQuickGiftTap,
            onOpenFullGiftsSheet: _openFullGiftsSheet,
            quickGifts: _categoryGifts,
            userAvatar: _currentUserAvatar,
            chatMessages: _chatMessages,
            chatScrollController: _chatScroll,
            activeNotif: _activeNotif,
            notifSlide: _notifSlide,
            notifFade: _notifFade,
            coinBalance: _coinBalance,
            selectedCategory: _selectedCategory,
            onCategoryChanged: (cat) => setState(() => _selectedCategory = cat),
            currentUserId: _currentUserId,
            hostUserId: widget.userId,
            onFollowGifter: (id) => _api.followUser(id),
            onGifterTap: (id, name, avatar) {
              final cached = _userProfileCache[id];
              final rating = (cached?['rating'] ?? 0.0) as double;
              _showUserProfilePreview(id, name, avatar, rating);
            },
            userProfileCache: _userProfileCache,
          ),
        ],
      ),
    );
  }

  Widget _buildStreamerHeader() {
    final displayAvatar = _isHost && _currentUserAvatar.isNotEmpty
        ? _currentUserAvatar
        : (widget.userAvatar ?? '');
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHeaderRow(displayAvatar),
        if (_topGifters.isNotEmpty) ...[
          const SizedBox(height: 6),
          _buildTopGifterStrip(),
        ],
      ],
    );
  }

  Widget _buildTopGifterStrip() {
    final sorted = _topGifters.values.toList()
      ..sort((a, b) => b.totalCoins.compareTo(a.totalCoins));
    final top = sorted.take(5).toList();
    const medals = ['🥇', '🥈', '🥉', '4️⃣', '5️⃣'];
    const medalColors = [Color(0xFFFFD700), Color(0xFFCCCCCC), Color(0xFFCD7F32),
                         Color(0xFF9B9B9B), Color(0xFF9B9B9B)];

    return SizedBox(
      height: 32,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: top.length,
        itemBuilder: (_, i) {
          final g = top[i];
          return GestureDetector(
            onTap: () => _showLeaderboard(sorted),
            child: Container(
              margin: const EdgeInsets.only(right: 6),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.65),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                    color: medalColors[i].withValues(alpha: 0.5), width: 1),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(medals[i], style: const TextStyle(fontSize: 11)),
                  const SizedBox(width: 4),
                  if (g.avatar.isNotEmpty && g.avatar.startsWith('http'))
                    ClipOval(
                      child: CachedNetworkImage(
                        imageUrl: g.avatar, width: 18, height: 18,
                        fit: BoxFit.cover,
                        errorWidget: (_, __, ___) => _miniAvatar(g.name, medalColors[i]),
                      ),
                    )
                  else
                    _miniAvatar(g.name, medalColors[i]),
                  const SizedBox(width: 4),
                  Text(
                    g.name.length > 8 ? '${g.name.substring(0, 8)}…' : g.name,
                    style: const TextStyle(color: Colors.white,
                        fontSize: 10, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(width: 3),
                  GifterBadge(
                    level: GifterBadge.levelFromCoins(g.totalCoins),
                    animated: false,
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.monetization_on_rounded,
                      color: Colors.amber, size: 10),
                  const SizedBox(width: 2),
                  Text(_fmtCoins(g.totalCoins),
                      style: TextStyle(color: medalColors[i],
                          fontSize: 10, fontWeight: FontWeight.w800)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _showLeaderboard(List<_TopGifter> sorted) {
    const medals = ['🥇', '🥈', '🥉', '4️⃣', '5️⃣', '6️⃣', '7️⃣', '8️⃣', '9️⃣', '🔟'];
    const medalColors = [
      Color(0xFFFFD700), Color(0xFFCCCCCC), Color(0xFFCD7F32),
      Color(0xFF9B9B9B), Color(0xFF9B9B9B), Color(0xFF9B9B9B),
      Color(0xFF9B9B9B), Color(0xFF9B9B9B), Color(0xFF9B9B9B), Color(0xFF9B9B9B),
    ];
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0D0D1A),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.55,
        minChildSize: 0.35,
        maxChildSize: 0.85,
        builder: (_, scroll) => Column(
          children: [
            Container(
              margin: const EdgeInsets.only(top: 10, bottom: 8),
              width: 40, height: 4,
              decoration: BoxDecoration(
                  color: Colors.white24, borderRadius: BorderRadius.circular(2)),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(children: [
                const Icon(Icons.emoji_events_rounded,
                    color: Color(0xFFFFD700), size: 20),
                const SizedBox(width: 8),
                const Text('Top Gifters',
                    style: TextStyle(color: Colors.white,
                        fontSize: 16, fontWeight: FontWeight.bold)),
                const Spacer(),
                Text('${sorted.length} gifters',
                    style: const TextStyle(color: Colors.white38, fontSize: 12)),
              ]),
            ),
            const Divider(color: Colors.white12),
            Expanded(
              child: sorted.isEmpty
                  ? const Center(
                      child: Text('No gifts yet',
                          style: TextStyle(color: Colors.white38)))
                  : ListView.builder(
                      controller: scroll,
                      itemCount: sorted.length,
                      itemBuilder: (_, i) {
                        final g = sorted[i];
                        final color = i < medalColors.length
                            ? medalColors[i] : const Color(0xFF9B9B9B);
                        return ListTile(
                          leading: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              CircleAvatar(
                                radius: 22,
                                backgroundColor: color.withValues(alpha: 0.2),
                                backgroundImage: g.avatar.isNotEmpty &&
                                        g.avatar.startsWith('http')
                                    ? CachedNetworkImageProvider(g.avatar)
                                    : null,
                                child: g.avatar.isEmpty ||
                                        !g.avatar.startsWith('http')
                                    ? Text(
                                        g.name.isNotEmpty
                                            ? g.name[0].toUpperCase()
                                            : '?',
                                        style: TextStyle(
                                            color: color,
                                            fontWeight: FontWeight.bold))
                                    : null,
                              ),
                              Positioned(
                                bottom: -2, right: -4,
                                child: Text(
                                    i < medals.length ? medals[i] : '${i + 1}',
                                    style: const TextStyle(fontSize: 12)),
                              ),
                            ],
                          ),
                          title: Text(g.name,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700)),
                          subtitle: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              GifterBadge(
                                  level: GifterBadge.levelFromCoins(
                                      g.totalCoins),
                                  animated: false),
                            ],
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.monetization_on_rounded,
                                  color: Colors.amber, size: 14),
                              const SizedBox(width: 4),
                              Text(_fmtCoins(g.totalCoins),
                                  style: TextStyle(
                                      color: color,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 14)),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _miniAvatar(String name, Color color) {
    return Container(
      width: 18, height: 18,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withValues(alpha: 0.25),
      ),
      child: Center(
        child: Text(
          name.isNotEmpty ? name[0].toUpperCase() : '?',
          style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.w800),
        ),
      ),
    );
  }

  Widget _buildHeaderRow(String displayAvatar) {
    return Row(
      children: [
        Container(
          width: 44, height: 44,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
                colors: [Color(0xFFFF2D55), Color(0xFFBF5AF2)]),
            boxShadow: [
              BoxShadow(
                  color: const Color(0xFFFF2D55).withValues(alpha: 0.45),
                  blurRadius: 14)
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(2),
            child: ClipOval(
              child: displayAvatar.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: displayAvatar,
                      fit: BoxFit.cover,
                      errorWidget: (_, __, ___) => _avatarFallback())
                  : _avatarFallback(),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.userName ?? 'Live',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  shadows: [Shadow(blurRadius: 6, color: Colors.black87)],
                ),
                maxLines: 1, overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 3),
              Row(children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                        colors: [Color(0xFFFF2D55), Color(0xFFFF9500)]),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text('LIVE',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.0)),
                ),
                const SizedBox(width: 6),
                GestureDetector(
                  onTap: _showViewerList,
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.remove_red_eye_rounded,
                        color: Colors.white54, size: 11),
                    const SizedBox(width: 3),
                    Text(_fmtViewers(widget.viewerCount ?? 0),
                        style: const TextStyle(
                            color: Colors.white60, fontSize: 10, fontWeight: FontWeight.w600)),
                  ]),
                ),
                const SizedBox(width: 8),
                ValueListenableBuilder<int>(
                  valueListenable: _durationNotifier,
                  builder: (_, secs, __) => Text(
                    _fmtDuration(secs),
                    style: const TextStyle(color: Colors.white38, fontSize: 10),
                  ),
                ),
              ]),
            ],
          ),
        ),
        if (_isHost) ...[
          GestureDetector(
            onTap: _showInviteSheet,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                    colors: [Color(0xFF7C3AED), Color(0xFFBF5AF2)]),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                      color: const Color(0xFF7C3AED).withValues(alpha: 0.45),
                      blurRadius: 10)
                ],
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.person_add_rounded, color: Colors.white, size: 13),
                  SizedBox(width: 5),
                  Text('Invite',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w700)),
                ],
              ),
            ),
          ),
          const SizedBox(width: 6),
          GestureDetector(
            onTap: _endLive,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: const Color(0xFFE53935),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                      color: const Color(0xFFE53935).withValues(alpha: 0.45),
                      blurRadius: 10)
                ],
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.stop_circle_outlined, color: Colors.white, size: 13),
                  SizedBox(width: 5),
                  Text('END LIVE',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5)),
                ],
              ),
            ),
          ),
        ]
        else
          GestureDetector(
            onTap: _isFollowingHost
                ? null
                : () {
                    HapticFeedback.lightImpact();
                    _api.followUser(widget.userId);
                    setState(() => _isFollowingHost = true);
                  },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: _isFollowingHost
                  ? BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                          color: Colors.white.withValues(alpha: 0.4), width: 1),
                    )
                  : BoxDecoration(
                      gradient: const LinearGradient(
                          colors: [Color(0xFFFF2D55), Color(0xFFBF5AF2)]),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                            color: const Color(0xFFFF2D55).withValues(alpha: 0.4),
                            blurRadius: 10)
                      ],
                    ),
              child: Text(
                _isFollowingHost ? 'Following' : 'Follow',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w700),
              ),
            ),
          ),
        if (!_isHost) ...[
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              width: 34, height: 34,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.5),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white24),
              ),
              child: const Icon(Icons.close_rounded,
                  color: Colors.white70, size: 16),
            ),
          ),
        ],
      ],
    );
  }

  Widget _avatarFallback() => Container(
        color: const Color(0xFF2A1040),
        child: const Icon(Icons.person_rounded, color: Colors.white38),
      );

  String _fmtViewers(int n) {
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}k';
    return '$n';
  }

  String _fmtDuration(int s) {
    final m = s ~/ 60;
    final sec = s % 60;
    return '${m.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';
  }

  // Returns 0=regular, 1=premium, 2=vip, 3=legendary
  static int _coinTier(int coins) {
    if (coins >= 50000) return 3;
    if (coins >= 20000) return 2;
    if (coins >= 8000)  return 1;
    if (coins >= 5000)  return 0;
    return 0;
  }

  Widget _buildCenterAnim(_GiftAnim g) {
    final tier = _coinTier(g.coins);
    final overlayAlpha = [0.45, 0.55, 0.65, 0.78][tier];
    final primaries   = [const Color(0xFFBF5AF2), const Color(0xFFBF5AF2),
                         const Color(0xFFFF6B00), const Color(0xFFFFD700)];
    final secondaries = [const Color(0xFF06B6D4), const Color(0xFF0088FF),
                         const Color(0xFFFFD700), const Color(0xFFFF6B00)];
    final primary   = primaries[tier];
    final secondary = secondaries[tier];
    final labels    = ['', '💜  P R E M I U M  💜', '⭐  V I P  ⭐', '👑  L E G E N D A R Y  👑'];
    final nameSizes = [18.0, 18.0, 22.0, 26.0];

    return Container(
      color: Colors.black.withValues(alpha: overlayAlpha),
      child: Center(
        child: Transform.scale(
          scale: _giftScale.value,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (tier >= 1) ...[
                Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [primary, secondary]),
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [BoxShadow(color: primary.withValues(alpha: 0.5), blurRadius: 16)],
                  ),
                  child: Text(labels[tier],
                      style: TextStyle(
                          color: tier >= 2 ? Colors.black : Colors.white,
                          fontSize: tier >= 3 ? 13 : 11,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.5)),
                ),
              ],
              _buildGiftVisual(g, primary, tier),
              SizedBox(height: tier >= 3 ? 24 : 16),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [
                    primary.withValues(alpha: 0.92),
                    secondary.withValues(alpha: 0.80),
                  ]),
                  borderRadius: BorderRadius.circular(32),
                  border: Border.all(
                      color: tier >= 2 ? Colors.white30 : primary.withValues(alpha: 0.4),
                      width: tier >= 2 ? 1.5 : 1),
                  boxShadow: [
                    BoxShadow(
                        color: primary.withValues(alpha: tier >= 2 ? 0.70 : 0.50),
                        blurRadius: tier >= 3 ? 70 : tier >= 2 ? 55 : 35,
                        spreadRadius: tier >= 3 ? 22 : tier >= 2 ? 18 : 7),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(g.senderName,
                        style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: nameSizes[tier])),
                    const SizedBox(height: 3),
                    Text('sent ${g.name} ${g.emoji}',
                        style: const TextStyle(
                            color: Color(0xCCFFFFFF), fontSize: 14,
                            fontWeight: FontWeight.w600)),
                    if (g.coins > 0) ...[
                      const SizedBox(height: 8),
                      Row(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.monetization_on_rounded,
                            color: Colors.amber, size: 14),
                        const SizedBox(width: 4),
                        Text(_fmtCoins(g.coins),
                            style: const TextStyle(
                                color: Colors.amber, fontSize: 12,
                                fontWeight: FontWeight.w800)),
                        Text(' coins',
                            style: TextStyle(color: Colors.amber.withValues(alpha: 0.7), fontSize: 11)),
                      ]),
                    ],
                    if (g.senderId.isNotEmpty &&
                        g.senderId != _currentUserId &&
                        g.senderId != widget.userId) ...[
                      const SizedBox(height: 12),
                      GestureDetector(
                        onTap: () async {
                          HapticFeedback.mediumImpact();
                          await _api.followUser(g.senderId);
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 22, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                                color: Colors.white.withValues(alpha: 0.4)),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.person_add_rounded,
                                  color: Colors.white, size: 14),
                              SizedBox(width: 6),
                              Text('Follow',
                                  style: TextStyle(
                                      color: Colors.white, fontSize: 13,
                                      fontWeight: FontWeight.w700)),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGiftVisual(_GiftAnim g, Color glow, int tier) {
    final circleSize = [104.0, 110.0, 124.0, 142.0][tier];
    final emojiSize  = [70.0,  78.0,  90.0,  108.0][tier];
    final Widget inner = g.gifUrl.isNotEmpty && g.gifUrl.startsWith('http')
        ? CachedNetworkImage(
            imageUrl: g.gifUrl, width: circleSize, height: circleSize,
            fit: BoxFit.contain,
            errorWidget: (_, __, ___) =>
                Text(g.emoji, style: TextStyle(fontSize: emojiSize)))
        : Text(g.emoji, style: TextStyle(fontSize: emojiSize));
    return Container(
      width: circleSize + 32, height: circleSize + 32,
      decoration: BoxDecoration(shape: BoxShape.circle, boxShadow: [
        BoxShadow(
            color: glow.withValues(alpha: [0.55, 0.60, 0.72, 0.82][tier]),
            blurRadius: [42.0, 52.0, 65.0, 80.0][tier],
            spreadRadius: [10.0, 14.0, 22.0, 30.0][tier]),
        BoxShadow(
            color: glow.withValues(alpha: 0.25), blurRadius: 20, spreadRadius: 2),
      ]),
      child: Center(child: inner),
    );
  }

  String _fmtCoins(int n) {
    if (n >= 1000) {
      final k = n / 1000;
      return '${k % 1 == 0 ? k.toInt() : k.toStringAsFixed(1)}K';
    }
    return '$n';
  }

  // ── Video background ───────────────────────────────────────────────
  Widget _buildVideoBackground() {
    if (_videoInitializing) {
      return Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF1A0530), Color(0xFF0D0818), Colors.black],
          ),
        ),
        child: const Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            CircularProgressIndicator(color: Color(0xFFFF2D55), strokeWidth: 2.5),
            SizedBox(height: 16),
            Text('Connecting...',
                style: TextStyle(color: Colors.white54, fontSize: 14)),
          ]),
        ),
      );
    }

    if (_videoInitialized && _videoManager.activeProvider != null) {
      return _videoManager.activeProvider!.buildVideoView(
        isVideoCall: true,
        onLeaveCall: () { if (mounted) Navigator.pop(context); },
        onLiveStarted: () {
          if (_isHost && !_hasStartedLive) {
            setState(() => _hasStartedLive = true);
            _api.startLive();
          }
        },
        onProviderError: _handleProviderError,
      );
    }

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF1A0530), Colors.black]),
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 80, height: 80,
              decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.07),
                  border: Border.all(color: Colors.white12)),
              child: const Icon(Icons.videocam_off_rounded,
                  color: Colors.white38, size: 36),
            ),
            const SizedBox(height: 20),
            Text(
              _initError.isNotEmpty ? _initError : 'Could not start video',
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: Colors.white60, fontSize: 14, height: 1.5),
            ),
            const SizedBox(height: 28),
            GestureDetector(
              onTap: _retryInitialization,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 36, vertical: 14),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                      colors: [Color(0xFFFF2D55), Color(0xFFBF5AF2)]),
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: [
                    BoxShadow(
                        color: const Color(0xFFFF2D55).withValues(alpha: 0.35),
                        blurRadius: 20,
                        offset: const Offset(0, 6))
                  ],
                ),
                child: const Text('Retry',
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 15)),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Future<void> _handleProviderError() async {
    if (!mounted) return;
    setState(() {
      _videoInitialized = false;
      _videoInitializing = true;
      _initError = '';
    });
    final userId = UserPrefsCache.instance.userId ?? widget.userId;
    final switched = await _videoManager.reinitialize(
        currentUserId: userId, currentUserName: _currentUserName);
    if (!mounted) return;
    if (switched) {
      try {
        final p = _videoManager.activeProvider;
        if (p is ZegoProvider) p.setOnEndLiveCallback(_isHost ? _endLiveOnBackend : null);
        await _videoManager.activeProvider!.joinCall('live_$userId');
        if (_isHost && !_hasStartedLive) { _hasStartedLive = true; _api.startLive(); }
        setState(() { _videoInitialized = true; _videoInitializing = false; });
      } catch (e) {
        setState(() {
          _videoInitializing = false;
          _initError = 'Switched provider but failed to join: $e';
        });
      }
    } else {
      setState(() {
        _videoInitializing = false;
        _initError = 'All video providers failed.';
      });
    }
  }

  Future<void> _retryInitialization() async {
    if (!mounted) return;
    setState(() {
      _videoInitialized = false;
      _videoInitializing = true;
      _initError = '';
    });
    await _initializeCamera();
  }
}

// ── Live viewer overlay ────────────────────────────────────────────────────────
class _LiveViewerOverlay extends StatefulWidget {
  final bool isHost;
  final TextEditingController chatController;
  final VoidCallback onSendChat;
  final Function(Map<String, dynamic>) onQuickGiftTap;
  final VoidCallback onOpenFullGiftsSheet;
  final List<Map<String, dynamic>> quickGifts;
  final String userAvatar;
  final List<_ChatMsg> chatMessages;
  final ScrollController chatScrollController;
  final _GiftAnim? activeNotif;
  final Animation<Offset> notifSlide;
  final Animation<double> notifFade;
  final int coinBalance;
  final String selectedCategory;
  final Function(String) onCategoryChanged;
  final String currentUserId;
  final String hostUserId;
  final Function(String senderId)? onFollowGifter;
  final void Function(String senderId, String senderName, String senderAvatar)? onGifterTap;
  final Map<String, Map<String, dynamic>> userProfileCache;

  static const _categories = [
    {'key': 'all',    'label': 'All',    'emoji': '🎁'},
    {'key': 'love',   'label': 'Love',   'emoji': '💖'},
    {'key': 'vibe',   'label': 'Vibe',   'emoji': '🔥'},
    {'key': 'luxury', 'label': 'Luxury', 'emoji': '💎'},
    {'key': 'cute',   'label': 'Cute',   'emoji': '🐰'},
    {'key': 'funny',  'label': 'Funny',  'emoji': '😂'},
    {'key': 'legend', 'label': 'Legend', 'emoji': '👑'},
  ];

  _LiveViewerOverlay({
    required this.isHost,
    required this.chatController,
    required this.onSendChat,
    required this.onQuickGiftTap,
    required this.onOpenFullGiftsSheet,
    required this.quickGifts,
    required this.userAvatar,
    required this.chatMessages,
    required this.chatScrollController,
    required this.activeNotif,
    required this.notifSlide,
    required this.notifFade,
    required this.coinBalance,
    required this.selectedCategory,
    required this.onCategoryChanged,
    required this.currentUserId,
    required this.hostUserId,
    this.onFollowGifter,
    this.onGifterTap,
    required this.userProfileCache,
  });

  @override
  State<_LiveViewerOverlay> createState() => _LiveViewerOverlayState();
}

class _LiveViewerOverlayState extends State<_LiveViewerOverlay>
    with WidgetsBindingObserver {
  double _keyboardHeight = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    if (!mounted) return;
    final view = WidgetsBinding.instance.platformDispatcher.views.first;
    final h = view.viewInsets.bottom / view.devicePixelRatio;
    if ((h - _keyboardHeight).abs() > 1) setState(() => _keyboardHeight = h);
  }

  @override
  Widget build(BuildContext context) {
    // viewPadding.bottom is always the nav bar height regardless of keyboard/ancestor widgets
    final bottomPad = MediaQuery.of(context).viewPadding.bottom;
    final targetBottom =
        _keyboardHeight > 0 ? _keyboardHeight + 6 : bottomPad + 10;

    return Stack(
      children: [
        // Gift notification (slides in from left)
        if (widget.activeNotif != null)
          Positioned(
            left: 12,
            bottom: targetBottom + 235,
            child: SlideTransition(
              position: widget.notifSlide,
              child: FadeTransition(
                opacity: widget.notifFade,
                child: _buildNotifBubble(widget.activeNotif!),
              ),
            ),
          ),

        // Main bottom controls
        AnimatedPositioned(
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
          bottom: targetBottom,
          left: 0,
          right: 0,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildChatMessages(),
              if (!widget.isHost) ...[
                const SizedBox(height: 6),
                _buildCategoryTabs(),
                const SizedBox(height: 5),
                _buildGiftBar(),
                const SizedBox(height: 8),
                _buildChatInput(),
              ] else ...[
                const SizedBox(height: 8),
                _buildHostControls(),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildNotifBubble(_GiftAnim g) {
    final isLegend  = g.coins >= 50000;
    final isVip     = g.coins >= 20000 && !isLegend;
    final isPremium = g.coins >= 8000  && !isVip && !isLegend;
    final accentColor = isLegend
        ? const Color(0xFFFFD700)
        : isVip
            ? const Color(0xFFFF6B00)
            : isPremium
                ? const Color(0xFFBF5AF2)
                : const Color(0xFFFF6B9D);

    final showFollow = g.senderId.isNotEmpty &&
        g.senderId != widget.currentUserId &&
        g.senderId != widget.hostUserId;

    return GestureDetector(
      onTap: g.senderId.isNotEmpty
          ? () {
              HapticFeedback.lightImpact();
              widget.onGifterTap?.call(g.senderId, g.senderName, g.senderAvatar);
            }
          : null,
      child: Container(
      constraints: const BoxConstraints(maxWidth: 260),
      padding: const EdgeInsets.fromLTRB(10, 8, 12, 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: accentColor.withValues(alpha: 0.5), width: 1.2),
        boxShadow: [
          BoxShadow(
              color: accentColor.withValues(alpha: isVip ? 0.4 : 0.25),
              blurRadius: 14,
              spreadRadius: 1)
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Sender avatar
          Container(
            width: 32, height: 32,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: accentColor, width: 1.5),
              gradient: const LinearGradient(
                  colors: [Color(0xFF2A1040), Color(0xFF1A0530)]),
            ),
            child: ClipOval(
              child: g.senderAvatar.isNotEmpty && g.senderAvatar.startsWith('http')
                  ? CachedNetworkImage(
                      imageUrl: g.senderAvatar,
                      fit: BoxFit.cover,
                      errorWidget: (_, __, ___) => Center(
                        child: Text(
                          g.senderName.isNotEmpty
                              ? g.senderName[0].toUpperCase()
                              : '?',
                          style: TextStyle(
                              color: accentColor,
                              fontSize: 13,
                              fontWeight: FontWeight.w800),
                        ),
                      ),
                    )
                  : Center(
                      child: Text(
                        g.senderName.isNotEmpty
                            ? g.senderName[0].toUpperCase()
                            : '?',
                        style: TextStyle(
                            color: accentColor,
                            fontSize: 13,
                            fontWeight: FontWeight.w800),
                      ),
                    ),
            ),
          ),
          const SizedBox(width: 8),

          // Gift info
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        g.senderName,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w800),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 4),
                    GifterBadge(
                      level: GifterBadge.levelFromCoins(g.coins),
                      animated: false,
                    ),
                  ],
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      g.emoji,
                      style: const TextStyle(fontSize: 13),
                    ),
                    const SizedBox(width: 3),
                    Flexible(
                      child: Text(
                        'sent ${g.name}',
                        style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.65),
                            fontSize: 10),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(Icons.monetization_on_rounded,
                        color: Colors.amber, size: 10),
                    Text(' ${g.coins}',
                        style: const TextStyle(
                            color: Colors.amber,
                            fontSize: 10,
                            fontWeight: FontWeight.w800)),
                  ],
                ),
              ],
            ),
          ),

          // Follow button
          if (showFollow) ...[
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () {
                HapticFeedback.lightImpact();
                widget.onFollowGifter?.call(g.senderId);
              },
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                      colors: [accentColor, accentColor.withValues(alpha: 0.7)]),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  '+ Follow',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w800),
                ),
              ),
            ),
          ],
        ],
      ),
      ),
    );
  }

  Widget _buildChatMessages() {
    if (widget.chatMessages.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 130,
      child: ListView.builder(
        controller: widget.chatScrollController,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: widget.chatMessages.length,
        itemBuilder: (_, i) {
          final m = widget.chatMessages[i];
          final cached = widget.userProfileCache[m.senderUserId];
          final avatarUrl = (cached?['avatar'] ?? '').toString();
          final rating = (cached?['rating'] ?? 0.0) as double;
          final gifterLevel = GifterBadge.levelFromCoins(
              int.tryParse((cached?['total_coins_sent'] ?? '0').toString()) ?? 0);
          return Padding(
            padding: const EdgeInsets.only(bottom: 5),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Sender avatar
                Container(
                  width: 26, height: 26,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: m.color.withValues(alpha: 0.25),
                    border: Border.all(color: m.color.withValues(alpha: 0.6), width: 1),
                  ),
                  child: ClipOval(
                    child: avatarUrl.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: avatarUrl,
                            fit: BoxFit.cover,
                            errorWidget: (_, __, ___) => Center(
                              child: Text(
                                m.sender.isNotEmpty ? m.sender[0].toUpperCase() : '?',
                                style: TextStyle(
                                    color: m.color, fontSize: 11, fontWeight: FontWeight.w800),
                              ),
                            ),
                          )
                        : Center(
                            child: Text(
                              m.sender.isNotEmpty ? m.sender[0].toUpperCase() : '?',
                              style: TextStyle(
                                  color: m.color, fontSize: 11, fontWeight: FontWeight.w800),
                            ),
                          ),
                  ),
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              m.sender,
                              style: TextStyle(
                                  color: m.color,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700),
                            ),
                            if (rating > 0) ...[
                              const SizedBox(width: 4),
                              const Icon(Icons.star_rounded,
                                  color: Colors.amber, size: 10),
                              Text(
                                rating.toStringAsFixed(1),
                                style: const TextStyle(
                                    color: Colors.amber,
                                    fontSize: 9,
                                    fontWeight: FontWeight.w700),
                              ),
                            ],
                            if (gifterLevel > 0) ...[
                              const SizedBox(width: 4),
                              GifterBadge(level: gifterLevel),
                            ],
                          ],
                        ),
                        Text(
                          m.text,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w400),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  String _fmtCoins(int n) {
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}k';
    return '$n';
  }

  Widget _buildCategoryTabs() {
    return SizedBox(
      height: 30,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: _LiveViewerOverlay._categories.length,
        itemBuilder: (_, i) {
          final cat = _LiveViewerOverlay._categories[i];
          final isActive = widget.selectedCategory == cat['key'];
          return GestureDetector(
            onTap: () => widget.onCategoryChanged(cat['key']!),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.only(right: 6),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                gradient: isActive
                    ? const LinearGradient(
                        colors: [Color(0xFFFF2D55), Color(0xFFBF5AF2)])
                    : null,
                color: isActive ? null : Colors.black.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isActive
                      ? Colors.transparent
                      : Colors.white.withValues(alpha: 0.2),
                  width: 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(cat['emoji']!,
                      style: const TextStyle(fontSize: 11)),
                  const SizedBox(width: 4),
                  Text(cat['label']!,
                      style: TextStyle(
                          color: isActive ? Colors.white : Colors.white60,
                          fontSize: 11,
                          fontWeight: isActive
                              ? FontWeight.w700
                              : FontWeight.w500)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildGiftBar() {
    return SizedBox(
      height: 76,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: widget.quickGifts.length + 1,
        itemBuilder: (ctx, index) {
          if (index == 0) {
            return GestureDetector(
              onTap: widget.onOpenFullGiftsSheet,
              child: Container(
                width: 62,
                margin: const EdgeInsets.only(right: 8),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFFFF2D55), Color(0xFFBF5AF2)],
                  ),
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                        color: const Color(0xFFFF2D55).withValues(alpha: 0.45),
                        blurRadius: 14,
                        offset: const Offset(0, 4))
                  ],
                ),
                child: const Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.card_giftcard_rounded,
                        color: Colors.white, size: 24),
                    SizedBox(height: 3),
                    Text('Gifts',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
            );
          }

          final gift = widget.quickGifts[index - 1];
          final name = (gift['name'] ?? 'Gift').toString();
          final coins =
              int.tryParse((gift['coin_price'] ?? 0).toString()) ?? 0;
          final gifUrl =
              (gift['gif_url'] ?? gift['thumb_image'] ?? '').toString();
          final emoji =
              (gift['emoji'] ?? _giftEmojiFor(name)).toString();
          final isVip = coins >= 500;
          final isPremium = coins >= 100 && !isVip;

          final glowColor = isVip
              ? const Color(0xFFFFD700)
              : isPremium
                  ? const Color(0xFFBF5AF2)
                  : null;
          final borderColor = isVip
              ? const Color(0xFFFFD700)
              : isPremium
                  ? const Color(0xFFBF5AF2)
                  : Colors.white.withValues(alpha: 0.15);

          return GestureDetector(
            onTap: () => widget.onQuickGiftTap(gift),
            child: Container(
              width: 64,
              margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.60),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: borderColor, width: 1.2),
                boxShadow: glowColor != null
                    ? [
                        BoxShadow(
                            color: glowColor.withValues(alpha: 0.35),
                            blurRadius: 12,
                            spreadRadius: 1)
                      ]
                    : null,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (isVip)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 1),
                      child: Text('👑',
                          style: TextStyle(fontSize: 8)),
                    ),
                  SizedBox(
                    width: 34, height: 34,
                    child: gifUrl.isNotEmpty && gifUrl.startsWith('http')
                        ? CachedNetworkImage(
                            imageUrl: gifUrl,
                            fit: BoxFit.contain,
                            errorWidget: (_, __, ___) => Text(emoji,
                                style: const TextStyle(fontSize: 22),
                                textAlign: TextAlign.center))
                        : Text(emoji,
                            style: const TextStyle(fontSize: 22),
                            textAlign: TextAlign.center),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '$coins',
                    style: TextStyle(
                      color: isVip
                          ? const Color(0xFFFFD700)
                          : isPremium
                              ? const Color(0xFFBF5AF2)
                              : const Color(0xFFFF9F0A),
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildChatInput() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          // Viewer avatar
          if (widget.userAvatar.isNotEmpty)
            Container(
              width: 36, height: 36,
              margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                    color: const Color(0xFFFF2D55).withValues(alpha: 0.6),
                    width: 1.5),
              ),
              child: ClipOval(
                child: CachedNetworkImage(
                  imageUrl: widget.userAvatar,
                  fit: BoxFit.cover,
                  errorWidget: (_, __, ___) => Container(
                    color: const Color(0xFF2A1040),
                    child: const Icon(Icons.person_rounded,
                        color: Colors.white38, size: 18),
                  ),
                ),
              ),
            ),

          // Text field + coin badge
          Expanded(
            child: Container(
              height: 44,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.65),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                    color: Colors.white.withValues(alpha: 0.18), width: 1),
              ),
              child: Row(
                children: [
                  const SizedBox(width: 14),
                  Expanded(
                    child: TextField(
                      controller: widget.chatController,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => widget.onSendChat(),
                      decoration: InputDecoration(
                        border: InputBorder.none,
                        hintText: 'Say something...',
                        hintStyle: TextStyle(
                            color: Colors.white.withValues(alpha: 0.35),
                            fontSize: 13),
                        isDense: true,
                        contentPadding:
                            const EdgeInsets.symmetric(vertical: 13),
                      ),
                    ),
                  ),
                  // Inline coin badge
                  if (!widget.isHost)
                    Container(
                      margin: const EdgeInsets.only(right: 10),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.amber.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: Colors.amber.withValues(alpha: 0.4),
                            width: 1),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.monetization_on_rounded,
                              color: Colors.amber, size: 11),
                          const SizedBox(width: 3),
                          Text(
                            _fmtCoins(widget.coinBalance),
                            style: const TextStyle(
                                color: Colors.amber,
                                fontSize: 10,
                                fontWeight: FontWeight.w800),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),

          const SizedBox(width: 8),

          GestureDetector(
            onTap: widget.onSendChat,
            child: Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFFFF2D55), Color(0xFFBF5AF2)],
                ),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                      color: const Color(0xFFFF2D55).withValues(alpha: 0.45),
                      blurRadius: 14,
                      offset: const Offset(0, 4))
                ],
              ),
              child: const Icon(Icons.send_rounded,
                  color: Colors.white, size: 18),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHostControls() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHostControlBar(),
        const SizedBox(height: 8),
        _buildChatInput(),
      ],
    );
  }

  Widget _buildHostControlBar() {
    final userId = ZegoUIKit().getLocalUser().id;
    if (userId.isEmpty) return const SizedBox(height: 48);
    return Padding(
      padding: const EdgeInsets.only(left: 12, right: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          ValueListenableBuilder<bool>(
            valueListenable: ZegoUIKit().getMicrophoneStateNotifier(userId),
            builder: (_, micOn, __) => _hostControlBtn(
              icon: micOn ? Icons.mic_rounded : Icons.mic_off_rounded,
              label: 'Mic',
              active: micOn,
              onTap: () => ZegoUIKit().turnMicrophoneOn(!micOn),
            ),
          ),
          const SizedBox(width: 14),
          ValueListenableBuilder<bool>(
            valueListenable: ZegoUIKit().getCameraStateNotifier(userId),
            builder: (_, camOn, __) => _hostControlBtn(
              icon: camOn ? Icons.videocam_rounded : Icons.videocam_off_rounded,
              label: 'Camera',
              active: camOn,
              onTap: () => ZegoUIKit().turnCameraOn(!camOn),
            ),
          ),
          const SizedBox(width: 14),
          ValueListenableBuilder<bool>(
            valueListenable: ZegoUIKit().getUseFrontFacingCameraStateNotifier(userId),
            builder: (_, isFront, __) => _hostControlBtn(
              icon: Icons.flip_camera_ios_rounded,
              label: 'Flip',
              active: true,
              onTap: () => ZegoUIKit().useFrontFacingCamera(!isFront),
            ),
          ),
        ],
      ),
    );
  }

  Widget _hostControlBtn({
    required IconData icon,
    required String label,
    required bool active,
    required VoidCallback onTap,
  }) {
    final color = active ? Colors.white : const Color(0xFFFF3B30);
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 48, height: 48,
            decoration: BoxDecoration(
              color: active
                  ? Colors.white.withValues(alpha: 0.12)
                  : const Color(0xFFFF3B30).withValues(alpha: 0.18),
              shape: BoxShape.circle,
              border: Border.all(
                color: active
                    ? Colors.white.withValues(alpha: 0.25)
                    : const Color(0xFFFF3B30).withValues(alpha: 0.45),
                width: 1.2,
              ),
              boxShadow: [
                BoxShadow(
                  color: active
                      ? Colors.white.withValues(alpha: 0.08)
                      : const Color(0xFFFF3B30).withValues(alpha: 0.25),
                  blurRadius: 10,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              color: color.withValues(alpha: 0.85),
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Invite Friends to Live sheet ──────────────────────────────────────────────
class _InviteToLiveSheet extends StatefulWidget {
  final ApiService api;
  final String currentUserId;
  final Set<String> invitedUserIds;
  final Future<void> Function(List<String> selectedIds) onInvite;

  const _InviteToLiveSheet({
    required this.api,
    required this.currentUserId,
    required this.invitedUserIds,
    required this.onInvite,
  });

  @override
  State<_InviteToLiveSheet> createState() => _InviteToLiveSheetState();
}

class _InviteToLiveSheetState extends State<_InviteToLiveSheet> {
  List<Map<String, dynamic>> _friends = [];
  List<Map<String, dynamic>> _filtered = [];
  final Set<String> _selected = {};
  bool _loading = true;
  bool _sending = false;
  final TextEditingController _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadFriends();
    _search.addListener(_onSearch);
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _loadFriends() async {
    final result = await widget.api.getFollowList(
      userId: widget.currentUserId,
      type: 'following',
      limit: 100,
    );
    if (!mounted) return;
    final users = (result?['users'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    setState(() {
      _friends = users;
      _filtered = users;
      _loading = false;
    });
  }

  void _onSearch() {
    final q = _search.text.toLowerCase();
    setState(() {
      _filtered = q.isEmpty
          ? _friends
          : _friends.where((u) {
              final name = (u['name'] ?? u['username'] ?? '').toString().toLowerCase();
              return name.contains(q);
            }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      builder: (_, scroll) => Column(
        children: [
          Container(
            margin: const EdgeInsets.only(top: 10, bottom: 8),
            width: 40, height: 4,
            decoration: BoxDecoration(
                color: Colors.white24, borderRadius: BorderRadius.circular(2)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(children: [
              const Icon(Icons.person_add_rounded, color: Color(0xFFBF5AF2), size: 18),
              const SizedBox(width: 8),
              const Expanded(
                child: Text('Invite Friends',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold)),
              ),
              if (_selected.isNotEmpty)
                TextButton(
                  onPressed: _sending ? null : _sendInvites,
                  child: _sending
                      ? const SizedBox(
                          width: 16, height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFBF5AF2)))
                      : Text('Send (${_selected.length})',
                          style: const TextStyle(
                              color: Color(0xFFBF5AF2), fontWeight: FontWeight.bold)),
                ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: TextField(
              controller: _search,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Search friends...',
                hintStyle: const TextStyle(color: Colors.white38),
                prefixIcon: const Icon(Icons.search, color: Colors.white38, size: 18),
                filled: true,
                fillColor: const Color(0xFF1E1E2E),
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none),
              ),
            ),
          ),
          const Divider(color: Colors.white12),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: Color(0xFFBF5AF2)))
                : _filtered.isEmpty
                    ? const Center(
                        child: Text('No friends found',
                            style: TextStyle(color: Colors.white38)))
                    : ListView.builder(
                        controller: scroll,
                        itemCount: _filtered.length,
                        itemBuilder: (_, i) {
                          final u = _filtered[i];
                          final uid = (u['id'] ?? u['user_id'] ?? '').toString();
                          final name = (u['name'] ?? u['username'] ?? 'User').toString();
                          final avatar = (u['profile_pic'] ?? u['avatar'] ?? '').toString();
                          final alreadyInvited = widget.invitedUserIds.contains(uid);
                          final isSelected = _selected.contains(uid);
                          return ListTile(
                            leading: CircleAvatar(
                              radius: 22,
                              backgroundColor: const Color(0xFF2A1040),
                              backgroundImage: avatar.isNotEmpty
                                  ? CachedNetworkImageProvider(avatar)
                                  : null,
                              child: avatar.isEmpty
                                  ? Text(name.isNotEmpty ? name[0].toUpperCase() : '?',
                                      style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold))
                                  : null,
                            ),
                            title: Text(name,
                                style: const TextStyle(
                                    color: Colors.white, fontWeight: FontWeight.w600)),
                            subtitle: alreadyInvited
                                ? const Text('Invited',
                                    style: TextStyle(color: Color(0xFF69F0AE), fontSize: 12))
                                : null,
                            trailing: alreadyInvited
                                ? const Icon(Icons.check_circle_rounded,
                                    color: Color(0xFF69F0AE), size: 20)
                                : Checkbox(
                                    value: isSelected,
                                    activeColor: const Color(0xFFBF5AF2),
                                    onChanged: (_) => setState(() {
                                      if (isSelected) {
                                        _selected.remove(uid);
                                      } else {
                                        _selected.add(uid);
                                      }
                                    }),
                                  ),
                            onTap: alreadyInvited
                                ? null
                                : () => setState(() {
                                    if (isSelected) {
                                      _selected.remove(uid);
                                    } else {
                                      _selected.add(uid);
                                    }
                                  }),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Future<void> _sendInvites() async {
    if (_selected.isEmpty) return;
    setState(() => _sending = true);
    await widget.onInvite(_selected.toList());
    if (mounted) Navigator.pop(context);
  }
}
