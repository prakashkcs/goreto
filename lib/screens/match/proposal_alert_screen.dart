import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:love_vibe_pro/services/api_service.dart';
import 'package:love_vibe_pro/services/profile_service.dart';
import 'package:love_vibe_pro/widgets/neon_toast.dart';
import 'package:love_vibe_pro/screens/profile_screen.dart';
import 'package:love_vibe_pro/screens/profile/widgets/neon_button.dart';

class ProposalAlertScreen extends StatefulWidget {
  final String senderId;
  final String senderName;
  final String senderAvatar;

  const ProposalAlertScreen({
    super.key,
    required this.senderId,
    this.senderName = 'Someone',
    this.senderAvatar = '',
  });

  @override
  State<ProposalAlertScreen> createState() => _ProposalAlertScreenState();
}

class _ProposalAlertScreenState extends State<ProposalAlertScreen> with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  bool _isLoading = true;
  dynamic _proposalData;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _fetchProposalData();
  }

  Future<void> _fetchProposalData() async {
    try {
      final received = await ApiService().getMyProposals(type: 'received');
      if (mounted) {
        setState(() {
          _proposalData = received.firstWhere(
            (p) => 
              p['sender_id']?.toString() == widget.senderId && 
              p['status']?.toString() == 'pending',
            orElse: () => null,
          );
          _isLoading = false;
        });

        // Show a message if no pending proposal was found
        if (_proposalData == null) {
          NeonToast.show(context, 'This proposal is no longer pending.', type: NeonToastType.info);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _acceptProposal() async {
    if (_proposalData == null) return;
    setState(() => _isLoading = true);
    try {
      final id = _proposalData['proposal_id'];
      final parsedId = id is int ? id : int.parse(id.toString());
      await ApiService().acceptProposal(proposalId: parsedId);
      try { await ProfileService.instance.clearCachedProfile(); } catch (_) {}
      
      if (mounted) {
        NeonToast.success(context, 'Proposal accepted! 💕');
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        NeonToast.error(context, 'Error accepting proposal: $e');
      }
    }
  }

  Future<void> _rejectProposal() async {
    if (_proposalData == null) {
      Navigator.of(context).pop();
      return;
    }
    
    setState(() => _isLoading = true);
    try {
      final id = _proposalData['proposal_id'];
      final parsedId = id is int ? id : int.parse(id.toString());
      await ApiService().rejectProposal(proposalId: parsedId);
      try { await ProfileService.instance.clearCachedProfile(); } catch (_) {}
      
      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        NeonToast.error(context, 'Error rejecting proposal');
      }
    }
  }

  Future<void> _blockUser() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Block User', style: TextStyle(color: Colors.white)),
        content: Text(
          'Block ${widget.senderName}? Their proposal will be rejected and they won\'t be able to contact you.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            child: const Text('Block'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      setState(() => _isLoading = true);
      try {
        await ApiService().blockUser(blockedId: widget.senderId);
        if (_proposalData != null) {
          final id = _proposalData['proposal_id'];
          final parsedId = id is int ? id : int.parse(id.toString());
          await ApiService().rejectProposal(proposalId: parsedId);
        }
        if (mounted) {
          NeonToast.info(context, '${widget.senderName} blocked');
          Navigator.of(context).pop();
        }
      } catch (e) {
        if (mounted) {
          setState(() => _isLoading = false);
          NeonToast.error(context, 'Error blocking user');
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F1A),
      body: Stack(
        children: [
          // Background Gradient effect
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  colors: [
                    const Color(0xFFFF007F).withValues(alpha: 0.15),
                    const Color(0xFF0F0F1A),
                  ],
                  radius: 1.2,
                  center: const Alignment(0, -0.2),
                ),
              ),
            ),
          ),
          
          SafeArea(
            child: Column(
              children: [
                // Top Action Bar
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back, color: Colors.white),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                      IconButton(
                        icon: const Icon(Icons.block, color: Colors.redAccent),
                        onPressed: _blockUser,
                        tooltip: 'Block User',
                      ),
                    ],
                  ),
                ),
                
                const Spacer(),
                
                // Pulsing Avatar
                GestureDetector(
                  onTap: () {
                    if (widget.senderId.isNotEmpty) {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => ProfileScreen(userId: widget.senderId),
                        ),
                      );
                    }
                  },
                  child: ScaleTransition(
                    scale: _pulseAnimation,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: const LinearGradient(
                          colors: [Color(0xFFFF007F), Color(0xFF00E5FF)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFFFF007F).withValues(alpha: 0.5),
                            blurRadius: 30,
                            spreadRadius: 10,
                          ),
                        ],
                      ),
                      child: CircleAvatar(
                        radius: 70,
                        backgroundColor: Colors.black,
                        backgroundImage: widget.senderAvatar.isNotEmpty
                            ? CachedNetworkImageProvider(widget.senderAvatar)
                            : null,
                        child: widget.senderAvatar.isEmpty
                            ? const Icon(Icons.person, size: 60, color: Colors.white)
                            : null,
                      ),
                    ),
                  ),
                ),
                
                const SizedBox(height: 40),
                
                // Text Info
                Text(
                  '${widget.senderName} sent you a proposal!',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'They would like to connect with you.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.6),
                    fontSize: 16,
                  ),
                ),
                
                if (_isLoading && _proposalData == null)
                  const Padding(
                    padding: EdgeInsets.only(top: 30),
                    child: CircularProgressIndicator(color: Color(0xFFFF007F)),
                  ),
                  
                const Spacer(),
                
                // Bottom Buttons
                if (!_isLoading || _proposalData != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 40),
                    child: Row(
                      children: [
                        Expanded(
                          flex: 1,
                          child: NeonButton(
                            label: 'Reject',
                            icon: Icons.close,
                            neonColor: Colors.grey,
                            isFilled: false,
                            height: 56,
                            onTap: _isLoading ? null : _rejectProposal,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          flex: 2,
                          child: NeonButton(
                            label: 'Accept',
                            icon: Icons.favorite,
                            neonColor: const Color(0xFFFF007F),
                            isFilled: true,
                            height: 56,
                            isLoading: _isLoading,
                            onTap: _isLoading ? null : _acceptProposal,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
