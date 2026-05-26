import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/app_notification.dart';
import '../../utils/date_util.dart';
import '../../services/notification_service.dart';
import '../profile_screen.dart';
import '../profile/post_detail_screen.dart';
import '../gifts/gifts_notification_screen.dart';
import '../settings/kyc_screen.dart';
import '../settings/wallet_screen.dart';
import '../match/proposals_screen.dart';
import '../match/nearby_screen.dart';
import '../match/nearby_user_preview_screen.dart';
import '../live/live_room_screen.dart';
import '../../models/match_user.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final NotificationService _svc = NotificationService();
  List<AppNotification> _notifications = [];
  bool _isLoading = true;

  // ---- Section labels ----
  static const _kContentTypes = {
    'like',
    'comment',
    'comment_reply',
    'repost',
    'mention'
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool forceRefresh = false}) async {
    // Show cached data immediately so the screen never shows a blank spinner
    final cached = _svc.getCached();
    if (cached.isNotEmpty && !forceRefresh) {
      setState(() {
        _notifications = cached;
        _isLoading = false;
      });
      // Refresh in background; update UI if fresh data differs
      _svc.getNotifications().then((fresh) {
        if (mounted && fresh.isNotEmpty) {
          setState(() => _notifications = fresh);
          _svc.markAsRead();
        }
      });
      return;
    }

    setState(() => _isLoading = cached.isEmpty);
    final list = await _svc.getNotifications();
    if (!mounted) return;
    setState(() {
      _notifications = list;
      _isLoading = false;
    });
    _svc.markAsRead();
  }

  // ---- Navigation ----
  void _onTap(AppNotification n) {
    switch (n.type) {
      // Content: open the post
      case 'like':
      case 'comment':
      case 'comment_reply':
      case 'repost':
      case 'mention':
        if (n.referenceId != null && n.referenceId! > 0) {
          Navigator.push(
              context,
              _route(
                PostDetailScreen(postId: n.referenceId.toString()),
              ));
        }
        break;

      // Social: open sender profile
      case 'follow':
        if (n.senderId != null && n.senderId! > 0) {
          Navigator.push(
              context,
              _route(
                ProfileScreen(userId: n.senderId.toString()),
              ));
        }
        break;

      case 'nearby':
        if (n.senderId != null && n.senderId! > 0) {
          // Build a minimal MatchUser from notification data and open preview
          final nearbyUser = MatchUser(
            id: n.senderId.toString(),
            name: n.senderName ?? 'Nearby User',
            age: 0,
            rating: 5.0,
            city: '',
            country: '',
            lat: 0.0,
            lng: 0.0,
            photoUrl: n.senderAvatar ?? '',
            interests: const [],
            isOnline: true,
          );
          Navigator.push(
            context,
            _route(NearbyUserPreviewScreen(user: nearbyUser)),
          );
        } else {
          Navigator.push(context, _route(const NearbyScreen()));
        }
        break;

      case 'gift':
        // Only open the gifts page if this notification is newer than the last
        // time the user viewed the gifts page. This prevents re-opening a page
        // the user has already seen.
        _openGiftPageIfNew(n);
        break;

      case 'proposal':
      case 'proposal_accepted':
        Navigator.push(context, _route(const ProposalsScreen()));
        break;

      case 'live_start':
        if (n.referenceId != null && n.referenceId! > 0) {
          Navigator.push(
              context,
              _route(
                LiveRoomScreen(
                  userId: n.referenceId.toString(),
                  userName: n.senderName,
                  userAvatar: n.senderAvatar,
                ),
              ));
        }
        break;

      case 'kyc_accept':
      case 'kyc_reject':
        Navigator.push(context, _route(const KycScreen()));
        break;

      case 'wallet_accept':
      case 'wallet_reject':
      case 'deposit_accept':
      case 'deposit_reject':
      case 'income_accept':
      case 'income_reject':
        Navigator.push(context, _route(const WalletScreen()));
        break;

      default:
        break;
    }
  }

  /// Opens GiftsNotificationScreen only if this specific gift notification
  /// has not been viewed before. Tracks by notification ID so each gift
  /// notification can only auto-open the page once.
  Future<void> _openGiftPageIfNew(AppNotification n) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Track viewed notification IDs as a set stored in prefs
      final viewedKey = 'gift_notif_viewed_ids';
      final viewedIds = prefs.getStringList(viewedKey) ?? [];

      final notifIdStr = n.id.toString();
      if (viewedIds.contains(notifIdStr)) {
        // Already opened this specific notification — don't re-open
        return;
      }

      // Also check the last-viewed timestamp as a fallback:
      // compare both sides in UTC to avoid timezone mismatch
      final lastViewedStr = prefs.getString('gift_notification_last_viewed');
      if (lastViewedStr != null) {
        final lastViewed = DateTime.tryParse(lastViewedStr)?.toUtc();
        if (lastViewed != null) {
          // n.createdAt is local time (from DateUtil.parseServerTime → toLocal())
          // convert to UTC for a fair comparison
          final notifUtc = n.createdAt.toUtc();
          if (!notifUtc.isAfter(lastViewed)) return;
        }
      }
    } catch (_) {}
    if (!mounted) return;

    // Mark this notification ID as viewed before navigating
    try {
      final prefs = await SharedPreferences.getInstance();
      final viewedKey = 'gift_notif_viewed_ids';
      final viewedIds = List<String>.from(prefs.getStringList(viewedKey) ?? []);
      viewedIds.add(n.id.toString());
      // Keep list bounded to last 200 IDs to avoid unbounded growth
      if (viewedIds.length > 200) {
        viewedIds.removeRange(0, viewedIds.length - 200);
      }
      await prefs.setStringList(viewedKey, viewedIds);
    } catch (_) {}

    Navigator.push(context, _route(const GiftsNotificationScreen()));
  }

  Route _route(Widget page) => MaterialPageRoute(builder: (_) => page);

  // ---- Type metadata ----
  ({IconData icon, Color color}) _typeMeta(String type) => switch (type) {
        'like' => (
            icon: Icons.favorite_rounded,
            color: const Color(0xFFFF4569)
          ),
        'comment' => (
            icon: Icons.chat_bubble_rounded,
            color: const Color(0xFFFF9500)
          ),
        'comment_reply' => (
            icon: Icons.reply_rounded,
            color: const Color(0xFFFF9500)
          ),
        'repost' => (
            icon: Icons.repeat_rounded,
            color: const Color(0xFF30D158)
          ),
        'mention' => (
            icon: Icons.alternate_email_rounded,
            color: const Color(0xFF0A84FF)
          ),
        'follow' => (
            icon: Icons.person_add_rounded,
            color: const Color(0xFFBF5AF2)
          ),
        'gift' => (
            icon: Icons.card_giftcard_rounded,
            color: const Color(0xFFFF375F)
          ),
        'proposal' || 'proposal_accepted' => (
            icon: Icons.favorite_rounded,
            color: const Color(0xFFFF2D55)
          ),
        'nearby' => (
            icon: Icons.location_on_rounded,
            color: const Color(0xFF30D158)
          ),
        'kyc_accept' ||
        'wallet_accept' ||
        'deposit_accept' ||
        'income_accept' =>
          (icon: Icons.check_circle_rounded, color: const Color(0xFF30D158)),
        'kyc_reject' ||
        'wallet_reject' ||
        'deposit_reject' ||
        'income_reject' =>
          (icon: Icons.cancel_rounded, color: const Color(0xFFFF453A)),
        'live_start' => (
            icon: Icons.wifi_tethering_rounded,
            color: const Color(0xFFFF3B30)
          ),
        'system' || 'admin' => (
            icon: Icons.campaign_rounded,
            color: const Color(0xFF64D2FF)
          ),
        _ => (
            icon: Icons.notifications_rounded,
            color: const Color(0xFF8E8E93)
          ),
      };

  // ---- Group by time ----
  Map<String, List<AppNotification>> _grouped() {
    final now = DateTime.now();
    final today = <AppNotification>[];
    final thisWeek = <AppNotification>[];
    final earlier = <AppNotification>[];
    for (final n in _notifications) {
      final diff = now.difference(n.createdAt);
      if (diff.inDays < 1) {
        today.add(n);
      } else if (diff.inDays < 7) {
        thisWeek.add(n);
      } else {
        earlier.add(n);
      }
    }
    return {
      if (today.isNotEmpty) 'Today': today,
      if (thisWeek.isNotEmpty) 'This Week': thisWeek,
      if (earlier.isNotEmpty) 'Earlier': earlier,
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0F),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A0A0F),
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        centerTitle: true,
        title: const Text(
          'Activity',
          style: TextStyle(
            color: Colors.white,
            fontSize: 17,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.3,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: Colors.white, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.done_all_rounded,
                color: Color(0xFF8E8E93), size: 22),
            tooltip: 'Mark all read',
            onPressed: () async {
              await _svc.markAsRead();
              if (mounted) {
                setState(() {
                  _notifications = _notifications
                      .map((n) => AppNotification(
                            id: n.id,
                            userId: n.userId,
                            senderId: n.senderId,
                            senderName: n.senderName,
                            senderAvatar: n.senderAvatar,
                            type: n.type,
                            title: n.title,
                            message: n.message,
                            referenceId: n.referenceId,
                            referenceImage: n.referenceImage,
                            isRead: true,
                            createdAt: n.createdAt,
                          ))
                      .toList();
                });
              }
            },
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(
            height: 1,
            decoration: const BoxDecoration(
              gradient: LinearGradient(colors: [
                Colors.transparent,
                Color(0x33FFFFFF),
                Colors.transparent,
              ]),
            ),
          ),
        ),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(
                color: Color(0xFFD946EF),
                strokeWidth: 2,
              ),
            )
          : _notifications.isEmpty
              ? _buildEmpty()
              : RefreshIndicator(
                  color: const Color(0xFFD946EF),
                  backgroundColor: const Color(0xFF1C1C1E),
                  displacement: 20,
                  onRefresh: () => _load(forceRefresh: true),
                  child: _buildList(),
                ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(
              color: const Color(0xFF1C1C1E),
              borderRadius: BorderRadius.circular(28),
            ),
            child: const Icon(
              Icons.notifications_off_rounded,
              size: 40,
              color: Color(0xFF3A3A3C),
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'No activity yet',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'When someone likes, comments\nor follows you, you\'ll see it here.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Color(0xFF8E8E93),
              fontSize: 14,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildList() {
    final groups = _grouped();
    final sections = groups.entries.toList();
    return CustomScrollView(
      physics:
          const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
      slivers: [
        for (final entry in sections) ...[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
              child: Text(
                entry.key,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.2,
                ),
              ),
            ),
          ),
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, i) => _buildCard(entry.value[i]),
              childCount: entry.value.length,
            ),
          ),
        ],
        const SliverToBoxAdapter(child: SizedBox(height: 32)),
      ],
    );
  }

  Widget _buildCard(AppNotification n) {
    final meta = _typeMeta(n.type);
    final isContent = _kContentTypes.contains(n.type);
    final hasThumb =
        isContent && n.referenceImage != null && n.referenceImage!.isNotEmpty;

    return GestureDetector(
      onTap: () => _onTap(n),
      behavior: HitTestBehavior.opaque,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: n.isRead ? Colors.transparent : const Color(0xFF1C1C1E),
          borderRadius: BorderRadius.circular(16),
          border: n.isRead
              ? null
              : Border.all(
                  color: meta.color.withValues(alpha: 0.2),
                  width: 1,
                ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // ---- Sender avatar + type icon badge ----
            SizedBox(
              width: 52,
              height: 52,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  // Avatar
                  ClipRRect(
                    borderRadius: BorderRadius.circular(26),
                    child: n.senderAvatar != null && n.senderAvatar!.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: n.senderAvatar!,
                            width: 48,
                            height: 48,
                            fit: BoxFit.cover,
                            errorWidget: (_, __, ___) => _avatarFallback(meta),
                          )
                        : _avatarFallback(meta),
                  ),
                  // Type badge
                  Positioned(
                    right: -2,
                    bottom: -2,
                    child: Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        color: meta.color,
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: const Color(0xFF0A0A0F), width: 2),
                      ),
                      child: Icon(meta.icon, size: 11, color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(width: 12),

            // ---- Text content ----
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  RichText(
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    text: TextSpan(
                      style: const TextStyle(
                        fontSize: 14,
                        height: 1.4,
                        color: Colors.white,
                      ),
                      children: [
                        if (n.senderName != null &&
                            n.senderName!.isNotEmpty) ...[
                          TextSpan(
                            text: n.senderName,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const TextSpan(text: ' '),
                        ],
                        TextSpan(
                          text: _actionText(n),
                          style: const TextStyle(
                            fontWeight: FontWeight.w400,
                            color: Color(0xCCFFFFFF),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    DateUtil.formatTimeAgo(n.createdAt),
                    style: TextStyle(
                      fontSize: 12,
                      color: meta.color.withValues(alpha: 0.8),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(width: 10),

            // ---- Right side: post thumbnail OR unread dot ----
            if (hasThumb)
              _buildThumb(n.referenceImage!)
            else if (!n.isRead)
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: meta.color,
                  shape: BoxShape.circle,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _avatarFallback(({IconData icon, Color color}) meta) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: meta.color.withValues(alpha: 0.15),
        shape: BoxShape.circle,
      ),
      child: Icon(meta.icon, color: meta.color, size: 22),
    );
  }

  Widget _buildThumb(String url) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: CachedNetworkImage(
        imageUrl: url,
        width: 48,
        height: 48,
        fit: BoxFit.cover,
        errorWidget: (_, __, ___) => Container(
          width: 48,
          height: 48,
          color: const Color(0xFF2C2C2E),
          child: const Icon(Icons.image_rounded,
              color: Color(0xFF8E8E93), size: 20),
        ),
      ),
    );
  }

  /// Returns the human-readable action verb/phrase (without the sender name prefix).
  String _actionText(AppNotification n) {
    switch (n.type) {
      case 'like':
        return 'liked your post.';
      case 'comment':
        return 'commented on your post.';
      case 'comment_reply':
        return 'replied to your comment.';
      case 'repost':
        return 'reshared your post.';
      case 'mention':
        return 'mentioned you in a comment.';
      case 'follow':
        return 'started following you.';
      case 'gift':
        return 'sent you a gift.';
      case 'proposal':
        return 'sent you a proposal.';
      case 'proposal_accepted':
        return 'accepted your proposal.';
      case 'nearby':
        return 'is near you.';
      case 'live_start':
        return 'is live now! Tap to join.';
      case 'kyc_accept':
        return 'Your KYC has been approved.';
      case 'kyc_reject':
        return 'Your KYC was not approved.';
      case 'wallet_accept':
        return 'Your wallet request was approved.';
      case 'wallet_reject':
        return 'Your wallet request was rejected.';
      case 'deposit_accept':
        return 'Your deposit has been approved.';
      case 'deposit_reject':
        return 'Your deposit was not approved.';
      case 'income_accept':
        return 'Your income proof was approved.';
      case 'income_reject':
        return 'Your income proof was rejected.';
      default:
        return n.message.isNotEmpty ? n.message : n.title;
    }
  }
}
