import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:love_vibe_pro/services/api_service.dart';
import 'package:love_vibe_pro/screens/profile_screen.dart';
import 'package:love_vibe_pro/widgets/gift_overlay_widget.dart';
import 'package:love_vibe_pro/widgets/coin_icon.dart';

/// Gifts Notification list page.
/// Shows all gifts received, grouped by date, sorted newest first.
/// Filter toggle: "Recent" (default) or "Expensive" (coin_price desc).
/// Once the user views this page, the gift notification badge is cleared
/// and the page won't re-open automatically on next app launch.
class GiftsNotificationScreen extends StatefulWidget {
  const GiftsNotificationScreen({super.key});

  @override
  State<GiftsNotificationScreen> createState() =>
      _GiftsNotificationScreenState();
}

class _GiftsNotificationScreenState extends State<GiftsNotificationScreen> {
  final ApiService _api = ApiService();
  List<GiftTx> _all = [];
  bool _loading = true;
  bool _sortByExpensive = false;

  @override
  void initState() {
    super.initState();
    _fetch();
    _markViewed();
  }

  /// Persist that the user has viewed the gift notification page.
  /// Callers (e.g. home screen) should check this flag before auto-navigating.
  /// The flag is keyed to the current UTC date so new gifts on a new day
  /// will still surface, but the same session won't re-open the page.
  Future<void> _markViewed() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // Mark as viewed so home screen won't auto-navigate again this session
      await prefs.setBool('gift_notification_viewed', true);
      // Store the exact UTC timestamp — used to detect gifts that arrive AFTER
      // this view (those should still show the badge / auto-navigate once).
      await prefs.setString(
        'gift_notification_last_viewed',
        DateTime.now().toUtc().toIso8601String(),
      );
    } catch (_) {}
  }

  /// Static helper: returns true only if there are unviewed gifts
  /// (i.e. gifts received after the last time the user viewed this page).
  /// Call this from the home screen instead of a simple bool flag.
  static Future<bool> hasUnviewedGifts(ApiService api) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastViewedStr = prefs.getString('gift_notification_last_viewed');

      // Never viewed → show
      if (lastViewedStr == null) return true;

      final lastViewed = DateTime.tryParse(lastViewedStr)?.toUtc();
      if (lastViewed == null) return true;

      // Fetch gift list and check if any arrived after last view
      final raw = await api.fetchGiftNotifications();
      for (final g in raw) {
        final createdStr = (g['created_at'] ?? g['sent_at'] ?? '').toString();
        if (createdStr.isEmpty) continue;
        final created = DateTime.tryParse(
          createdStr.contains('T') ? createdStr : '${createdStr}Z',
        )?.toUtc();
        if (created != null && created.isAfter(lastViewed)) return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<void> _fetch() async {
    setState(() => _loading = true);
    try {
      final raw = await _api.fetchGiftNotifications();
      final list = raw.map((e) => GiftTx.fromJson(e)).toList();
      if (mounted) {
        setState(() {
          _all = list;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<GiftTx> get _sorted {
    final list = List<GiftTx>.from(_all);
    if (_sortByExpensive) {
      list.sort((a, b) {
        final p = b.coinPrice.compareTo(a.coinPrice);
        if (p != 0) return p;
        return b.createdAt.compareTo(a.createdAt);
      });
    } else {
      list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    }
    return list;
  }

  /// Group gifts by date label.
  Map<String, List<GiftTx>> _grouped(List<GiftTx> items) {
    final map = <String, List<GiftTx>>{};
    for (final g in items) {
      final label = _dateLabel(g.createdAt);
      map.putIfAbsent(label, () => []).add(g);
    }
    return map;
  }

  String _dateLabel(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final d = DateTime(dt.year, dt.month, dt.day);
    if (d == today) return 'Today';
    if (d == today.subtract(const Duration(days: 1))) return 'Yesterday';
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${dt.month}/${dt.day}/${dt.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A0A0A),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.white, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Gift Notifications',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        centerTitle: true,
        actions: [
          // Filter toggle
          GestureDetector(
            onTap: () => setState(() => _sortByExpensive = !_sortByExpensive),
            child: Container(
              margin: const EdgeInsets.only(right: 12),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: _sortByExpensive
                    ? const Color(0xFFD946EF).withValues(alpha: 0.2)
                    : Colors.white10,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: _sortByExpensive
                      ? const Color(0xFFD946EF)
                      : Colors.white24,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CoinIcon(
                    size: 14,
                    color: _sortByExpensive ? Colors.amber : Colors.white70,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _sortByExpensive ? 'Expensive' : 'Recent',
                    style: TextStyle(
                      color: _sortByExpensive ? Colors.amber : Colors.white70,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: _loading
            ? const Center(
                child: CircularProgressIndicator(color: Color(0xFFD946EF)),
              )
            : _all.isEmpty
                ? _buildEmpty()
                : _buildList(),
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.card_giftcard,
            color: Colors.white.withValues(alpha: 0.15),
            size: 64,
          ),
          const SizedBox(height: 12),
          const Text(
            'No gift notifications yet',
            style: TextStyle(color: Colors.white38, fontSize: 15),
          ),
        ],
      ),
    );
  }

  Widget _buildList() {
    final sorted = _sorted;
    final grouped = _grouped(sorted);
    final sections = grouped.entries.toList();

    return RefreshIndicator(
      color: const Color(0xFFD946EF),
      onRefresh: _fetch,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: sections.fold<int>(
          0,
          (sum, s) => sum + 1 + s.value.length, // 1 header + items
        ),
        itemBuilder: (context, index) {
          int running = 0;
          for (final section in sections) {
            if (index == running) {
              // Section header
              return _buildSectionHeader(section.key);
            }
            running++;
            if (index < running + section.value.length) {
              final gift = section.value[index - running];
              return _buildGiftTile(gift);
            }
            running += section.value.length;
          }
          return const SizedBox.shrink();
        },
      ),
    );
  }

  Widget _buildSectionHeader(String label) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white54,
          fontSize: 13,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildGiftTile(GiftTx gift) {
    return GestureDetector(
      onTap: () {
        if (gift.senderId.isNotEmpty) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ProfileScreen(userId: gift.senderId),
            ),
          );
        }
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF141414),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white10),
        ),
        child: Row(
          children: [
            // Sender avatar
            _buildAvatar(gift.senderAvatar, gift.senderName),
            const SizedBox(width: 12),
            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    gift.senderName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Text(
                        gift.giftName,
                        style: const TextStyle(
                          color: Color(0xFFD946EF),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 6),
                      const CoinIcon(size: 12, color: Colors.amber),
                      const SizedBox(width: 2),
                      Text(
                        '${gift.coinPrice}',
                        style: const TextStyle(
                          color: Colors.amber,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _timeAgo(gift.createdAt),
                    style: const TextStyle(
                      color: Colors.white38,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
            // Gift gif thumbnail
            _buildGiftThumb(gift.gifUrl, emoji: gift.emoji),
          ],
        ),
      ),
    );
  }

  Widget _buildAvatar(String url, String name) {
    if (url.isNotEmpty && url.startsWith('http')) {
      return CachedNetworkImage(
        imageUrl: url,
        imageBuilder: (_, provider) => CircleAvatar(
          radius: 22,
          backgroundImage: provider,
          backgroundColor: const Color(0xFF1A1A1A),
        ),
        errorWidget: (_, __, ___) => _initialsAvatar(name),
        placeholder: (_, __) => _initialsAvatar(name),
      );
    }
    return _initialsAvatar(name);
  }

  Widget _initialsAvatar(String name) {
    return CircleAvatar(
      radius: 22,
      backgroundColor: const Color(0xFFD946EF).withValues(alpha: 0.3),
      child: Text(
        name.isNotEmpty ? name[0].toUpperCase() : '?',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 16,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildGiftThumb(String url, {String emoji = '🎁'}) {
    if (url.isNotEmpty && url.startsWith('http')) {
      return SizedBox(
        width: 44,
        height: 44,
        child: CachedNetworkImage(
          imageUrl: url,
          fit: BoxFit.contain,
          errorWidget: (_, __, ___) => Center(
            child: Text(emoji, style: const TextStyle(fontSize: 28)),
          ),
        ),
      );
    }
    return Text(emoji, style: const TextStyle(fontSize: 28));
  }
}
