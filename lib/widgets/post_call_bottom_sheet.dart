import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:love_vibe_pro/models/call_session.dart';
import 'package:love_vibe_pro/screens/profile_screen.dart';

import 'package:love_vibe_pro/models/user_profile.dart';
import 'package:love_vibe_pro/services/profile_service.dart';

class PostCallBottomSheet extends StatefulWidget {
  final CallSession session;
  final Duration callDuration;

  const PostCallBottomSheet({
    super.key,
    required this.session,
    required this.callDuration,
  });

  static void show(
    BuildContext context,
    CallSession session,
    Duration duration,
  ) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) =>
          PostCallBottomSheet(session: session, callDuration: duration),
    );
  }

  @override
  State<PostCallBottomSheet> createState() => _PostCallBottomSheetState();
}

class _PostCallBottomSheetState extends State<PostCallBottomSheet> {
  late Future<UserProfile> _profileFuture;
  late String _otherId;
  late String _fallbackName;
  String? _fallbackAvatar;

  @override
  void initState() {
    super.initState();
    _otherId = widget.session.isOutgoing
        ? widget.session.receiverId
        : widget.session.callerId;
    _fallbackName = widget.session.isOutgoing
        ? widget.session.receiverName
        : widget.session.callerName;
    _fallbackAvatar = widget.session.isOutgoing
        ? widget.session.receiverAvatar
        : widget.session.callerAvatar;

    // Fetch the real profile data so we don't just show "Random User"
    _profileFuture = ProfileService.instance.getUserProfile(_otherId);
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.callDuration.inMinutes;
    final s = widget.callDuration.inSeconds % 60;
    final timeStr = '$m:${s.toString().padLeft(2, '0')}';

    return Container(
      padding: const EdgeInsets.only(left: 24, right: 24, top: 32, bottom: 40),
      decoration: BoxDecoration(
        color: const Color(0xFF161622),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        border: Border.all(color: const Color(0xFF8B5CF6).withValues(alpha: 0.3)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF8B5CF6).withValues(alpha: 0.15),
            blurRadius: 30,
            spreadRadius: 2,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag Handle
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 24),

          Text(
            'Call Ended ($timeStr)',
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 24),

          FutureBuilder<UserProfile>(
            future: _profileFuture,
            builder: (context, snapshot) {
              final isLoading =
                  snapshot.connectionState == ConnectionState.waiting;
              final realName = snapshot.data?.name ?? _fallbackName;
              final realAvatar =
                  snapshot.data?.profilePicUrl ?? _fallbackAvatar;

              return Column(
                children: [
                  // Avatar
                  Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: const Color(0xFF8B5CF6),
                        width: 3,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF8B5CF6).withValues(alpha: 0.4),
                          blurRadius: 15,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: ClipOval(
                      child: isLoading
                          ? const Center(
                              child: CircularProgressIndicator(
                                color: Color(0xFF8B5CF6),
                              ),
                            )
                          : (realAvatar != null && realAvatar.isNotEmpty)
                          ? CachedNetworkImage(
                              imageUrl: realAvatar,
                              fit: BoxFit.cover,
                              placeholder: (_, __) => Container(
                                color: const Color(0xFF2A2A2A),
                                child: const Icon(
                                  Icons.person,
                                  color: Colors.white38,
                                  size: 40,
                                ),
                              ),
                              errorWidget: (_, __, ___) => Container(
                                color: const Color(0xFF2A2A2A),
                                child: const Icon(
                                  Icons.person,
                                  color: Colors.white38,
                                  size: 40,
                                ),
                              ),
                            )
                          : Container(
                              color: const Color(0xFF2A2A2A),
                              child: const Icon(
                                Icons.person,
                                color: Colors.white38,
                                size: 40,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Name
                  Text(
                    isLoading ? 'Loading...' : realName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 32),

          // Action Buttons
          Row(
            children: [
              // Visit Profile
              Expanded(
                child: GestureDetector(
                  onTap: () {
                    Navigator.pop(context); // Close sheet
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ProfileScreen(userId: _otherId),
                      ),
                    );
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      color: const Color(0xFF8B5CF6).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: const Color(0xFF8B5CF6).withValues(alpha: 0.5),
                      ),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.person_search,
                          color: Color(0xFF8B5CF6),
                          size: 20,
                        ),
                        SizedBox(width: 8),
                        Text(
                          'View Profile',
                          style: TextStyle(
                            color: Color(0xFF8B5CF6),
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),

              // Send Gift (We can route to profile which has gift option, or just pop and the user can go to chat)
              // We will just open the profile for now which is the entry to chat/gift
              Expanded(
                child: GestureDetector(
                  onTap: () {
                    Navigator.pop(context); // Close sheet
                    // Sending a gift usually routes through the chat or profile.
                    // Let's take them to the profile for now since the app has gifts there.
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ProfileScreen(userId: _otherId),
                      ),
                    );
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFD946EF), Color(0xFF9333EA)],
                      ),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFD946EF).withValues(alpha: 0.3),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.card_giftcard,
                          color: Colors.white,
                          size: 20,
                        ),
                        SizedBox(width: 8),
                        Text(
                          'Send Gift',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
