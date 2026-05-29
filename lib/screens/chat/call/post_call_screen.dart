import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:love_vibe_pro/services/api_service.dart';

/// Shown after a random video call ends.
/// Displays both users' profile cards and lets them connect.
class PostCallScreen extends StatefulWidget {
  final String myUserId;
  final String myName;
  final String? myAvatar;

  final String otherUserId;
  final String otherName;
  final String? otherAvatar;

  final int callDurationSeconds;

  const PostCallScreen({
    super.key,
    required this.myUserId,
    required this.myName,
    this.myAvatar,
    required this.otherUserId,
    required this.otherName,
    this.otherAvatar,
    required this.callDurationSeconds,
  });

  @override
  State<PostCallScreen> createState() => _PostCallScreenState();
}

class _PostCallScreenState extends State<PostCallScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _fade;
  late Animation<Offset> _slide;

  bool _proposalSent = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.12),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  String _formatDuration(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  Future<void> _sendProposal() async {
    // Guard: random calls used to navigate here with an empty otherUserId in
    // some edge cases (CallSession receiverId left blank), which then sent
    // the proposal to user 0 and the backend rejected it silently. Show a
    // concrete error instead of the generic 'try again' so we can debug.
    final target = widget.otherUserId.trim();
    if (target.isEmpty || target == '0') {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Cannot send proposal — partner ID missing.'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }
    try {
      final result = await ApiService().sendProposal(targetUserId: target);
      if (mounted) {
        setState(() => _proposalSent = true);
        final matched = result['matched'] == true;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(matched
                ? "It's a Match with ${widget.otherName}! 💕"
                : 'Proposal sent to ${widget.otherName}!'),
            backgroundColor: const Color(0xFFFF007F),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        // Surface backend error messages so 'already sent', 'invalid target',
        // etc. are visible instead of a generic retry prompt.
        final msg = e.toString().replaceFirst('Exception: ', '');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(msg.isEmpty
                ? 'Could not send proposal. Try again.'
                : msg),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Blurred background from other user's avatar
          if (widget.otherAvatar != null && widget.otherAvatar!.isNotEmpty) ...[
            Opacity(
              opacity: 0.25,
              child: CachedNetworkImage(
                imageUrl: widget.otherAvatar!,
                fit: BoxFit.cover,
                errorWidget: (_, __, ___) => const SizedBox(),
              ),
            ),
            BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
              child: Container(color: Colors.black.withValues(alpha: 0.6)),
            ),
          ] else
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF1A0A2E), Color(0xFF0A0A0A)],
                ),
              ),
            ),

          SafeArea(
            child: FadeTransition(
              opacity: _fade,
              child: SlideTransition(
                position: _slide,
                child: Column(
                  children: [
                    const SizedBox(height: 32),

                    // Header
                    const Text(
                      'Call Ended',
                      style: TextStyle(
                        color: Colors.white54,
                        fontSize: 14,
                        letterSpacing: 2,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _formatDuration(widget.callDurationSeconds),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 36,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 2,
                      ),
                    ),

                    const SizedBox(height: 40),

                    // Two profile cards side by side
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Row(
                        children: [
                          Expanded(
                            child: _ProfileCard(
                              name: widget.myName,
                              avatarUrl: widget.myAvatar,
                              label: 'You',
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: _ProfileCard(
                              name: widget.otherName,
                              avatarUrl: widget.otherAvatar,
                              label: 'Matched with',
                            ),
                          ),
                        ],
                      ),
                    ),

                    const Spacer(),

                    // Action buttons
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32),
                      child: Column(
                        children: [
                          // Send Proposal
                          SizedBox(
                            width: double.infinity,
                            height: 54,
                            child: ElevatedButton.icon(
                              onPressed: _proposalSent ? null : _sendProposal,
                              icon: Icon(
                                _proposalSent
                                    ? Icons.check_circle
                                    : Icons.favorite,
                                size: 20,
                              ),
                              label: Text(
                                _proposalSent
                                    ? 'Proposal Sent!'
                                    : 'Send Proposal',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _proposalSent
                                    ? Colors.grey[700]
                                    : const Color(0xFFFF007F),
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                elevation: 0,
                              ),
                            ),
                          ),

                          const SizedBox(height: 12),

                          // Close / Continue
                          SizedBox(
                            width: double.infinity,
                            height: 54,
                            child: OutlinedButton(
                              onPressed: () => Navigator.of(context).pop(),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.white,
                                side: const BorderSide(
                                  color: Colors.white24,
                                  width: 1.5,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                              child: const Text(
                                'Continue',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileCard extends StatelessWidget {
  final String name;
  final String? avatarUrl;
  final String label;

  const _ProfileCard({
    required this.name,
    this.avatarUrl,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white12, width: 1),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Colors.white38,
              fontSize: 11,
              letterSpacing: 1.2,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: const Color(0xFFFF007F).withValues(alpha: 0.6),
                width: 2.5,
              ),
            ),
            child: ClipOval(
              child: (avatarUrl != null && avatarUrl!.isNotEmpty)
                  ? CachedNetworkImage(
                      imageUrl: avatarUrl!,
                      fit: BoxFit.cover,
                      placeholder: (_, __) =>
                          Container(color: Colors.grey[900]),
                      errorWidget: (_, __, ___) => _defaultAvatar(name),
                    )
                  : _defaultAvatar(name),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _defaultAvatar(String name) {
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
    return Container(
      color: const Color(0xFF2C0B3E),
      child: Center(
        child: Text(
          initial,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 32,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}
