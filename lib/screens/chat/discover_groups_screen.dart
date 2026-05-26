import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:love_vibe_pro/models/group_chat.dart';
import 'package:love_vibe_pro/services/group_chat_service.dart';
import 'package:love_vibe_pro/services/profile_service.dart';
import 'package:love_vibe_pro/screens/chat/group_chat_screen.dart';
import 'package:love_vibe_pro/widgets/neon_toast.dart';

// ── Palette ────────────────────────────────────────────────────────────────────
const _kBg   = Color(0xFF07050F);
const _kCard = Color(0xFF110D1C);
const _kPink = Color(0xFFD946EF);
const _kPurple = Color(0xFF9B5DE5);

const _kGradients = [
  [Color(0xFF7C3AED), Color(0xFFD946EF)],
  [Color(0xFF0EA5E9), Color(0xFF6366F1)],
  [Color(0xFFEC4899), Color(0xFFF97316)],
  [Color(0xFF10B981), Color(0xFF0EA5E9)],
  [Color(0xFFF59E0B), Color(0xFFEF4444)],
  [Color(0xFF8B5CF6), Color(0xFF06B6D4)],
];

List<Color> _gradFor(int id) => _kGradients[id.abs() % _kGradients.length];

// ── Filter enum ────────────────────────────────────────────────────────────────
enum _Filter { all, trending, active, free }

const _kFilterLabel = {
  _Filter.all:      'All',
  _Filter.trending: '🔥  Trending',
  _Filter.active:   '⚡  Active',
  _Filter.free:     '🆓  Free',
};

// ── Screen ─────────────────────────────────────────────────────────────────────
class DiscoverGroupsScreen extends StatefulWidget {
  const DiscoverGroupsScreen({super.key});

  @override
  State<DiscoverGroupsScreen> createState() => _DiscoverGroupsScreenState();
}

class _DiscoverGroupsScreenState extends State<DiscoverGroupsScreen> {
  final _service    = GroupChatService();
  final _searchCtrl = TextEditingController();

  List<ChatGroup> _all       = [];
  List<ChatGroup> _displayed = [];
  List<String>    _interests = [];
  bool    _loading = true;
  String  _query   = '';
  _Filter _filter  = _Filter.all;

  @override
  void initState() {
    super.initState();
    _interests = ProfileService
            .instance.currentProfileNotifier.value?.interests
            .map((e) => e.toString().toLowerCase())
            .toList() ??
        [];
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final groups = await _service.listAllGroups();
    if (!mounted) return;
    setState(() {
      _all       = groups.where((g) => !g.isPrivate).toList();
      _displayed = _applyFilter(_sorted(_all, ''));
      _loading   = false;
    });
  }

  double _score(ChatGroup g, String q) {
    double s = 0;
    final name  = g.name.toLowerCase();
    final bio   = (g.bio ?? '').toLowerCase();
    final uname = (g.username ?? '').toLowerCase();
    final ql    = q.trim().toLowerCase();
    if (ql.isNotEmpty) {
      if (name == ql)               { s += 200; }
      else if (name.startsWith(ql)) { s += 150; }
      else if (name.contains(ql))   { s += 100; }
      if (uname.contains(ql))  { s += 80; }
      if (bio.contains(ql))    { s += 60; }
    }
    for (final kw in _interests) {
      if (name.contains(kw) || bio.contains(kw)) s += 40;
    }
    if (g.lastActive != null) {
      final h = DateTime.now().difference(g.lastActive!).inHours;
      if (h < 1)        { s += 80; }
      else if (h < 6)   { s += 60; }
      else if (h < 24)  { s += 50; }
      else if (h < 72)  { s += 25; }
      else if (h < 168) { s += 10; }
    }
    if (g.memberCount > 0) s += math.log(g.memberCount) * 8;
    if (g.viewsCount  > 0) s += math.log(g.viewsCount + 1) * 4;
    return s;
  }

  List<ChatGroup> _sorted(List<ChatGroup> list, String q) {
    final copy = [...list];
    copy.sort((a, b) => _score(b, q).compareTo(_score(a, q)));
    return copy;
  }

  List<ChatGroup> _applyFilter(List<ChatGroup> list) {
    switch (_filter) {
      case _Filter.all:
        return list;
      case _Filter.trending:
        return list.where((g) => g.memberCount >= 10 || g.viewsCount >= 50).toList();
      case _Filter.active:
        return list
            .where((g) =>
                g.lastActive != null &&
                DateTime.now().difference(g.lastActive!).inHours < 24)
            .toList();
      case _Filter.free:
        return list.where((g) => g.joinFee == 0).toList();
    }
  }

  void _onSearch(String v) {
    setState(() {
      _query     = v.trim();
      _displayed = _applyFilter(_sorted(_all, _query));
    });
  }

  void _onFilter(_Filter f) {
    setState(() {
      _filter    = f;
      _displayed = _applyFilter(_sorted(_all, _query));
    });
  }

  Future<void> _join(ChatGroup g) async {
    if (g.joinFee > 0) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          backgroundColor: const Color(0xFF1A1425),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Join Group',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          content: Text('Joining costs ${g.joinFee} coins. Proceed?',
              style: const TextStyle(color: Colors.white60)),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: const Text('Cancel', style: TextStyle(color: Colors.white38))),
            TextButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Pay & Join',
                  style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }
    final res = await _service.joinGroup(g.id);
    if (!mounted) return;
    if (res['success'] == true) {
      NeonToast.success(context, 'Joined ${g.name}!');
      setState(() {
        _all       = _all.map((x) => x.id == g.id ? _patch(x) : x).toList();
        _displayed = _displayed.map((x) => x.id == g.id ? _patch(x) : x).toList();
      });
    } else {
      NeonToast.error(context, res['msg'] ?? 'Failed to join');
    }
  }

  ChatGroup _patch(ChatGroup x) => ChatGroup(
        id: x.id, name: x.name, username: x.username, avatar: x.avatar,
        bio: x.bio, joinFee: x.joinFee, monthlyFee: x.monthlyFee,
        createdBy: x.createdBy, memberCount: x.memberCount + 1,
        isMember: true, myRole: 'member', lastMessage: x.lastMessage,
        lastMessageType: x.lastMessageType, lastMessageSender: x.lastMessageSender,
        lastMessageSenderId: x.lastMessageSenderId,
        lastMessageTime: x.lastMessageTime, isPrivate: x.isPrivate,
        permissions: x.permissions, messageDelay: x.messageDelay,
        viewsCount: x.viewsCount, lastActive: x.lastActive,
        unreadCount: x.unreadCount,
      );

  String _fmt(int n) {
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(n >= 10000 ? 0 : 1)}k';
    return '$n';
  }

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;
    return Scaffold(
      backgroundColor: _kBg,
      body: CustomScrollView(
        slivers: [
          // ── App bar ────────────────────────────────────────────────────────
          SliverAppBar(
            backgroundColor: _kBg,
            surfaceTintColor: Colors.transparent,
            pinned: true,
            elevation: 0,
            toolbarHeight: 56,
            expandedHeight: 56 + topPad,
            automaticallyImplyLeading: false,
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xFF1E0A35), _kBg],
                  ),
                ),
              ),
            ),
            title: Row(
              children: [
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.07),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.arrow_back_rounded,
                        color: Colors.white, size: 18),
                  ),
                ),
                const SizedBox(width: 12),
                ShaderMask(
                  shaderCallback: (r) => const LinearGradient(
                    colors: [_kPink, _kPurple],
                  ).createShader(r),
                  child: const Text(
                    'Discover Groups',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 20,
                      letterSpacing: -0.4,
                    ),
                  ),
                ),
                const Spacer(),
                if (!_loading)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: _kPink.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: _kPink.withValues(alpha: 0.25)),
                    ),
                    child: Text(
                      '${_displayed.length}',
                      style: const TextStyle(
                        color: _kPink,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(100),
              child: Container(
                color: _kBg,
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Column(
                  children: [
                    // Search bar
                    Container(
                      height: 44,
                      decoration: BoxDecoration(
                        color: const Color(0xFF16111F),
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.08),
                        ),
                      ),
                      child: TextField(
                        controller: _searchCtrl,
                        onChanged: _onSearch,
                        style: const TextStyle(color: Colors.white, fontSize: 14),
                        cursorColor: _kPink,
                        decoration: const InputDecoration(
                          hintText: 'Search groups…',
                          hintStyle: TextStyle(color: Colors.white24, fontSize: 14),
                          prefixIcon: Icon(Icons.search_rounded,
                              color: Colors.white30, size: 20),
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(vertical: 13),
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    // Filter chips
                    SizedBox(
                      height: 34,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: _Filter.values.map((f) {
                          final selected = _filter == f;
                          return GestureDetector(
                            onTap: () => _onFilter(f),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 180),
                              margin: const EdgeInsets.only(right: 8),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 0),
                              decoration: BoxDecoration(
                                gradient: selected
                                    ? const LinearGradient(
                                        colors: [_kPink, _kPurple])
                                    : null,
                                color: selected
                                    ? null
                                    : Colors.white.withValues(alpha: 0.06),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: selected
                                      ? Colors.transparent
                                      : Colors.white.withValues(alpha: 0.1),
                                ),
                              ),
                              child: Center(
                                child: Text(
                                  _kFilterLabel[f]!,
                                  style: TextStyle(
                                    color: selected
                                        ? Colors.white
                                        : Colors.white54,
                                    fontSize: 12,
                                    fontWeight: selected
                                        ? FontWeight.bold
                                        : FontWeight.w400,
                                  ),
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
                ),
              ),
            ),
          ),

          // ── Body ───────────────────────────────────────────────────────────
          if (_loading)
            const SliverFillRemaining(
              child: Center(
                child: CircularProgressIndicator(
                    color: _kPink, strokeWidth: 2),
              ),
            )
          else if (_displayed.isEmpty)
            SliverFillRemaining(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(26),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(colors: [
                          _kPink.withValues(alpha: 0.08),
                          _kPurple.withValues(alpha: 0.08),
                        ]),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.explore_outlined,
                          color: Colors.white24, size: 46),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      _query.isEmpty
                          ? 'No groups found'
                          : 'No results for "$_query"',
                      style: const TextStyle(
                          color: Colors.white54, fontSize: 15,
                          fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Try a different filter or search term',
                      style: TextStyle(color: Colors.white24, fontSize: 12),
                    ),
                  ],
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 40),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (ctx, i) {
                    final g = _displayed[i];
                    return _GroupCard(
                      group: g,
                      formatCount: _fmt,
                      onTap: () {
                        if (g.isMember) {
                          Navigator.push(ctx,
                              MaterialPageRoute(
                                  builder: (_) => GroupChatScreen(group: g)));
                        } else {
                          _join(g);
                        }
                      },
                      onJoin: () => _join(g),
                    );
                  },
                  childCount: _displayed.length,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Group card ─────────────────────────────────────────────────────────────────
class _GroupCard extends StatelessWidget {
  final ChatGroup group;
  final String Function(int) formatCount;
  final VoidCallback onTap;
  final VoidCallback onJoin;

  const _GroupCard({
    required this.group,
    required this.formatCount,
    required this.onTap,
    required this.onJoin,
  });

  @override
  Widget build(BuildContext context) {
    final g        = group;
    final grad     = _gradFor(g.id);
    final isActive = g.lastActive != null &&
        DateTime.now().difference(g.lastActive!).inHours < 24;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: _kCard,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: g.isMember
                ? _kPink.withValues(alpha: 0.28)
                : Colors.white.withValues(alpha: 0.06),
          ),
          boxShadow: g.isMember
              ? [
                  BoxShadow(
                    color: _kPink.withValues(alpha: 0.08),
                    blurRadius: 12,
                    spreadRadius: 1,
                  )
                ]
              : null,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── Left gradient accent stripe ──────────────────────────
                Container(
                  width: 4,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: grad,
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                  ),
                ),
                const SizedBox(width: 12),

                // ── Avatar ───────────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: Stack(
                    children: [
                      Container(
                        width: 54,
                        height: 54,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            colors: grad,
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: grad.first.withValues(alpha: 0.28),
                              blurRadius: 12,
                              spreadRadius: 1,
                            ),
                          ],
                        ),
                        child: ClipOval(
                          child: g.avatarUrl != null
                              ? CachedNetworkImage(
                                  imageUrl: g.avatarUrl!,
                                  fit: BoxFit.cover,
                                  errorWidget: (_, __, ___) => _initials(g.name),
                                )
                              : _initials(g.name),
                        ),
                      ),
                      if (isActive)
                        Positioned(
                          right: 1,
                          bottom: 1,
                          child: Container(
                            width: 13,
                            height: 13,
                            decoration: BoxDecoration(
                              color: const Color(0xFF22C55E),
                              shape: BoxShape.circle,
                              border: Border.all(color: _kCard, width: 2),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),

                // ── Info ─────────────────────────────────────────────────
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Name row
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                g.name,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15,
                                  letterSpacing: -0.2,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (g.joinFee > 0) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.amber.withValues(alpha: 0.14),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  '${g.joinFee}🪙',
                                  style: const TextStyle(
                                    color: Colors.amber,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 4),
                        // Members + active badge
                        Row(
                          children: [
                            const Icon(Icons.people_alt_rounded,
                                color: Colors.white30, size: 12),
                            const SizedBox(width: 4),
                            Text(
                              '${formatCount(g.memberCount)} members',
                              style: const TextStyle(
                                  color: Colors.white38, fontSize: 11),
                            ),
                            if (isActive) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF22C55E)
                                      .withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Text(
                                  'Active',
                                  style: TextStyle(
                                    color: Color(0xFF22C55E),
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 0.3,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        if (g.bio != null && g.bio!.isNotEmpty) ...[
                          const SizedBox(height: 5),
                          Text(
                            g.bio!,
                            style: const TextStyle(
                                color: Colors.white38, fontSize: 12),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 10),

                // ── Action button ────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.only(right: 14),
                  child: Center(
                    child: g.isMember
                        ? Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: const Color(0xFF22C55E)
                                  .withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: const Color(0xFF22C55E)
                                    .withValues(alpha: 0.3),
                              ),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.check_rounded,
                                    color: Color(0xFF22C55E), size: 12),
                                SizedBox(width: 4),
                                Text(
                                  'Joined',
                                  style: TextStyle(
                                    color: Color(0xFF22C55E),
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : GestureDetector(
                            onTap: onJoin,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 8),
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                    colors: [_kPink, _kPurple]),
                                borderRadius: BorderRadius.circular(12),
                                boxShadow: [
                                  BoxShadow(
                                    color: _kPink.withValues(alpha: 0.35),
                                    blurRadius: 10,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: Text(
                                g.joinFee > 0 ? 'Pay & Join' : 'Join',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _initials(String name) => Center(
        child: Text(
          name.isNotEmpty ? name[0].toUpperCase() : '?',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
      );
}
