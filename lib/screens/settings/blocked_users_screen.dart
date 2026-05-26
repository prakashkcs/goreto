import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:love_vibe_pro/providers/match_provider.dart';
import 'package:love_vibe_pro/services/api_service.dart';
import 'package:love_vibe_pro/screens/profile_screen.dart';
import 'package:love_vibe_pro/widgets/neon_toast.dart';

class BlockedUsersScreen extends StatefulWidget {
  const BlockedUsersScreen({super.key});

  @override
  State<BlockedUsersScreen> createState() => _BlockedUsersScreenState();
}

class _BlockedUsersScreenState extends State<BlockedUsersScreen> {
  final ApiService _api = ApiService();
  List<dynamic> _blockedUsers = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadBlockedUsers();
  }

  Future<void> _loadBlockedUsers() async {
    setState(() => _isLoading = true);
    final users = await _api.getBlockedUsers();
    if (mounted) {
      setState(() {
        _blockedUsers = users;
        _isLoading = false;
      });
    }
  }

  Future<void> _unblockUser(dynamic userId, int index) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: Color(0xFFEF4444), width: 1.2),
        ),
        title: const Text(
          'Unblock User?',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'This user will be able to see your profile and interact with you again.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Colors.white54),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF22C55E),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text('Unblock'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await _api.unblockUser(blockedId: userId.toString());
      if (mounted) {
        setState(() => _blockedUsers.removeAt(index));
        NeonToast.success(context, 'User unblocked');

        try {
          Provider.of<MatchProvider>(context, listen: false).loadNearbyUsers();
        } catch (_) {}
      }
    } catch (_) {
      if (mounted) {
        NeonToast.error(context, 'Failed to unblock user');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A0A0A),
        leading: const BackButton(color: Colors.white),
        title: const Text(
          'Blocked Users',
          style: TextStyle(color: Colors.white),
        ),
      ),
      body: SafeArea(
        child: _isLoading
            ? const Center(
                child: CircularProgressIndicator(color: Color(0xFFEF4444)),
              )
            : _blockedUsers.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.block,
                          color: Colors.white.withValues(alpha: 0.15),
                          size: 64,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No blocked users',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.4),
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: _loadBlockedUsers,
                    child: ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: _blockedUsers.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final user = _blockedUsers[index];
                        final userId =
                            (user['id'] ?? user['user_id'] ?? '').toString();
                        final name =
                            (user['name'] ?? user['username'] ?? 'User')
                                .toString();
                        final username = (user['username'] ?? '').toString();
                        final avatar = (user['profile_pic'] ??
                                user['avatar'] ??
                                user['avatar_url'] ??
                                user['profile_pic_url'] ??
                                '')
                            .toString();

                        return Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1A1A1A),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                                color: Colors.white.withValues(alpha: 0.06)),
                          ),
                          child: Row(
                            children: [
                              GestureDetector(
                                onTap: () {
                                  if (userId.isNotEmpty) {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) =>
                                            ProfileScreen(userId: userId),
                                      ),
                                    );
                                  }
                                },
                                child: CircleAvatar(
                                  radius: 22,
                                  backgroundColor: const Color(0xFF2A2A2A),
                                  backgroundImage: avatar.isNotEmpty &&
                                          avatar.startsWith('http')
                                      ? NetworkImage(avatar)
                                      : null,
                                  child: avatar.isEmpty ||
                                          !avatar.startsWith('http')
                                      ? const Icon(
                                          Icons.person,
                                          color: Colors.white38,
                                        )
                                      : null,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      name,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    if (username.isNotEmpty)
                                      Text(
                                        '@$username',
                                        style: const TextStyle(
                                          color: Colors.white38,
                                          fontSize: 12,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              ElevatedButton(
                                onPressed: () => _unblockUser(userId, index),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(
                                    0xFFEF4444,
                                  ).withValues(alpha: 0.15),
                                  foregroundColor: const Color(0xFFEF4444),
                                  elevation: 0,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 8,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(20),
                                    side: const BorderSide(
                                      color: Color(0xFFEF4444),
                                      width: 1,
                                    ),
                                  ),
                                ),
                                child: const Text(
                                  'Unblock',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
      ),
    );
  }
}
