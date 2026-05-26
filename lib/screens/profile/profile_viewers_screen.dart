import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:love_vibe_pro/services/api_service.dart';
import 'package:love_vibe_pro/screens/profile_screen.dart';

class ProfileViewersScreen extends StatefulWidget {
  const ProfileViewersScreen({super.key});

  @override
  State<ProfileViewersScreen> createState() => _ProfileViewersScreenState();
}

class _ProfileViewersScreenState extends State<ProfileViewersScreen> {
  final ApiService _api = ApiService();
  final List<Map<String, dynamic>> _viewers = [];
  final ScrollController _scroll = ScrollController();
  bool _loading = true;
  bool _loadingMore = false;
  int _page = 1;
  bool _hasMore = true;

  @override
  void initState() {
    super.initState();
    _fetchPage(1);
    _scroll.addListener(() {
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 200 &&
          !_loadingMore && _hasMore) {
        _loadMore();
      }
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _fetchPage(int page) async {
    if (page == 1) setState(() => _loading = true);
    try {
      final result = await _api.getProfileViewers(page: page);
      final list = (result['viewers'] as List?)
              ?.map((e) => Map<String, dynamic>.from(e as Map))
              .toList() ??
          [];
      if (mounted) {
        setState(() {
          if (page == 1) _viewers.clear();
          _viewers.addAll(list);
          _page = page;
          _hasMore = list.length >= 30;
        });
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadMore() async {
    setState(() => _loadingMore = true);
    await _fetchPage(_page + 1);
    if (mounted) setState(() => _loadingMore = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A0A0A),
        leading: const BackButton(color: Colors.white),
        title: const Text(
          'Who Viewed My Profile',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFFD946EF)))
          : _viewers.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.visibility_off,
                            color: Colors.white24, size: 56),
                        const SizedBox(height: 16),
                        const Text('No profile views yet',
                            style: TextStyle(
                                color: Colors.white54, fontSize: 16)),
                        const SizedBox(height: 8),
                        const Text(
                          'When someone visits your profile,\nthey\'ll appear here.',
                          style:
                              TextStyle(color: Colors.white38, fontSize: 13),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                )
              : ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.all(16),
                  itemCount: _viewers.length + (_loadingMore ? 1 : 0),
                  itemBuilder: (context, i) {
                    if (i == _viewers.length) {
                      return const Center(
                        child: Padding(
                          padding: EdgeInsets.all(16),
                          child: CircularProgressIndicator(
                              color: Color(0xFFD946EF), strokeWidth: 2),
                        ),
                      );
                    }
                    return _ViewerTile(viewer: _viewers[i]);
                  },
                ),
    );
  }
}

class _ViewerTile extends StatelessWidget {
  final Map<String, dynamic> viewer;
  const _ViewerTile({required this.viewer});

  String _timeAgo(String? raw) {
    if (raw == null || raw.isEmpty) return '';
    try {
      final dt = DateTime.parse(raw).toLocal();
      final diff = DateTime.now().difference(dt);
      if (diff.inMinutes < 1) return 'just now';
      if (diff.inHours < 1) return '${diff.inMinutes}m ago';
      if (diff.inDays < 1) return '${diff.inHours}h ago';
      if (diff.inDays < 7) return '${diff.inDays}d ago';
      return '${(diff.inDays / 7).floor()}w ago';
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = viewer['name']?.toString() ?? 'User';
    final username = viewer['username']?.toString() ?? '';
    final avatar = viewer['avatar']?.toString();
    final timeAgo = _timeAgo(viewer['viewed_at']?.toString());

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) =>
              ProfileScreen(userId: viewer['user_id']?.toString()),
        ),
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFD946EF).withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: const Color(0xFFD946EF).withValues(alpha: 0.15)),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 24,
              backgroundColor: const Color(0xFF2A2A2A),
              backgroundImage:
                  (avatar != null && avatar.isNotEmpty)
                      ? CachedNetworkImageProvider(avatar)
                      : null,
              child: (avatar == null || avatar.isEmpty)
                  ? const Icon(Icons.person,
                      color: Colors.white38, size: 24)
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name,
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 14)),
                  if (username.isNotEmpty)
                    Text('@$username',
                        style: const TextStyle(
                            color: Colors.white54, fontSize: 12)),
                ],
              ),
            ),
            if (timeAgo.isNotEmpty)
              Text(timeAgo,
                  style: const TextStyle(
                      color: Colors.white38, fontSize: 11)),
          ],
        ),
      ),
    );
  }
}
