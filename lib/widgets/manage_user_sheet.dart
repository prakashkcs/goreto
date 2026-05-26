import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:provider/provider.dart';
import 'package:love_vibe_pro/services/api_service.dart';
import 'package:love_vibe_pro/providers/match_provider.dart';
import 'package:love_vibe_pro/widgets/neon_toast.dart';

/// A premium bottom sheet for managing interactions with another user.
/// Shows options like Block, Mute, Report, Disconnect Proposal, Share.
class ManageUserSheet extends StatefulWidget {
  final String userId;
  final String userName;
  final String? userAvatar;

  /// Callback when a destructive action is taken (block, disconnect) —
  /// parent may want to pop or refresh.
  final VoidCallback? onActionTaken;

  const ManageUserSheet({
    super.key,
    required this.userId,
    required this.userName,
    this.userAvatar,
    this.onActionTaken,
  });

  /// Convenience method to show the sheet from anywhere.
  static void show(
    BuildContext context, {
    required String userId,
    required String userName,
    String? userAvatar,
    VoidCallback? onActionTaken,
  }) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => ManageUserSheet(
        userId: userId,
        userName: userName,
        userAvatar: userAvatar,
        onActionTaken: onActionTaken,
      ),
    );
  }

  @override
  State<ManageUserSheet> createState() => _ManageUserSheetState();
}

class _ManageUserSheetState extends State<ManageUserSheet> {
  final ApiService _api = ApiService();

  bool _isLoading = true;
  bool _isBlocked = false;
  bool _isMuted = false;
  bool _isProposalConnected = false;
  bool _isActionLoading = false;

  @override
  void initState() {
    super.initState();
    _loadStatus();
  }

  Future<void> _loadStatus() async {
    try {
      final status =
          await _api.getUserActionStatus(targetUserId: widget.userId);
      if (mounted) {
        setState(() {
          _isBlocked = status['is_blocked'] == true;
          _isMuted = status['is_muted'] == true;
          _isProposalConnected = (status['is_proposal_connected'] == true ||
              status['has_pending_proposal'] == true);
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _toggleBlock() async {
    final willBlock = !_isBlocked;
    final confirmed = await _showConfirmDialog(
      title: willBlock
          ? 'Block ${widget.userName}?'
          : 'Unblock ${widget.userName}?',
      message: willBlock
          ? 'They won\'t be able to find your profile, send you messages, or interact with you.'
          : 'They will be able to see your profile and interact with you again.',
      confirmText: willBlock ? 'Block' : 'Unblock',
      isDestructive: willBlock,
    );
    if (confirmed != true) return;

    setState(() => _isActionLoading = true);
    try {
      if (willBlock) {
        await _api.blockUser(blockedId: widget.userId);
      } else {
        await _api.unblockUser(blockedId: widget.userId);
      }
      if (mounted) {
        setState(() {
          _isBlocked = willBlock;
          _isActionLoading = false;
        });
        NeonToast.show(
          context,
          willBlock
              ? '${widget.userName} blocked'
              : '${widget.userName} unblocked',
          type: willBlock ? NeonToastType.error : NeonToastType.success,
        );

        // Globally flush the Nearby feed memory cache and re-pull from server
        // to securely banish the user graphics from all interactive menus
        try {
          Provider.of<MatchProvider>(context, listen: false).loadNearbyUsers();
        } catch (_) {}

        widget.onActionTaken?.call();
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isActionLoading = false);
        NeonToast.error(
            context, 'Failed to ${willBlock ? "block" : "unblock"} user');
      }
    }
  }

  Future<void> _toggleMute() async {
    final willMute = !_isMuted;
    setState(() => _isActionLoading = true);
    try {
      if (willMute) {
        await _api.muteUser(targetUserId: widget.userId);
      } else {
        await _api.unmuteUser(targetUserId: widget.userId);
      }
      if (mounted) {
        setState(() {
          _isMuted = willMute;
          _isActionLoading = false;
        });
        NeonToast.show(
          context,
          willMute ? '${widget.userName} muted' : '${widget.userName} unmuted',
          type: NeonToastType.info,
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isActionLoading = false);
        NeonToast.error(
            context, 'Failed to ${willMute ? "mute" : "unmute"} user');
      }
    }
  }

  Future<void> _disconnectProposal() async {
    final confirmed = await _showConfirmDialog(
      title: 'Disconnect from ${widget.userName}?',
      message:
          'This will break your proposal connection. You can send a new proposal later.',
      confirmText: 'Disconnect',
      isDestructive: true,
    );
    if (confirmed != true) return;

    setState(() => _isActionLoading = true);
    try {
      final result = await _api.disconnectProposal(targetUserId: widget.userId);
      if (mounted) {
        setState(() {
          _isProposalConnected = false;
          _isLoading = true; // Reload to get fresh status
          _isActionLoading = false;
        });
        _loadStatus();
        NeonToast.show(
          context,
          result['message'] ?? 'Proposal disconnected',
          type: NeonToastType.info,
        );
        widget.onActionTaken?.call();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isActionLoading = false);
        NeonToast.error(context, 'Failed to disconnect');
      }
    }
  }

  Future<void> _reportUser() async {
    final result = await _showReportDialog();
    if (result == null) return;

    setState(() => _isActionLoading = true);
    try {
      final response = await _api.reportUser(
        targetUserId: widget.userId,
        reason: result['reason']!,
        details: result['details'],
      );
      if (mounted) {
        setState(() => _isActionLoading = false);
        if (response['status'] == 'success') {
          NeonToast.success(context, 'Report submitted. Thank you.');
          if (mounted) Navigator.pop(context);
        } else {
          NeonToast.error(context, response['message'] ?? 'Failed to report');
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isActionLoading = false);
        final msg = e.toString().replaceFirst('Exception: ', '');
        NeonToast.error(context, msg);
      }
    }
  }

  void _shareProfile() {
    final profileUrl = 'https://goreto.org/ekloadmin/profile/${widget.userId}';
    Share.share(
      'Check out ${widget.userName}\'s profile on Goreto! $profileUrl',
      subject: '${widget.userName} on Goreto',
    );
  }

  void _copyProfileLink() {
    final profileUrl = 'https://goreto.org/ekloadmin/profile/${widget.userId}';
    Clipboard.setData(ClipboardData(text: profileUrl));
    NeonToast.success(context, 'Profile link copied!');
  }

  // ════════════════════════════════════════════════════════
  // DIALOGS
  // ════════════════════════════════════════════════════════

  Future<bool?> _showConfirmDialog({
    required String title,
    required String message,
    required String confirmText,
    bool isDestructive = false,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(
            color: isDestructive
                ? const Color(0xFFEF4444)
                : const Color(0xFF6366F1),
            width: 1.2,
          ),
        ),
        title: Text(title,
            style: const TextStyle(color: Colors.white, fontSize: 18)),
        content: Text(message,
            style: TextStyle(color: Colors.white.withValues(alpha: 0.7))),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child:
                const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: isDestructive
                  ? const Color(0xFFEF4444)
                  : const Color(0xFF6366F1),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child:
                Text(confirmText, style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Future<Map<String, String>?> _showReportDialog() {
    String? selectedReason;
    final detailsController = TextEditingController();
    final reasons = [
      'Spam',
      'Harassment',
      'Fake Profile',
      'Inappropriate Content',
      'Scam / Fraud',
      'Underage User',
      'Other',
    ];

    return showDialog<Map<String, String>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF1A1A2E),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: const BorderSide(color: Color(0xFFF59E0B), width: 1.2),
          ),
          title: Row(
            children: [
              const Icon(Icons.flag_rounded,
                  color: Color(0xFFF59E0B), size: 22),
              const SizedBox(width: 8),
              Text('Report ${widget.userName}',
                  style: const TextStyle(color: Colors.white, fontSize: 18)),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Select a reason:',
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.6), fontSize: 13),
                ),
                const SizedBox(height: 10),
                ...reasons.map((reason) => RadioListTile<String>(
                      value: reason,
                      groupValue: selectedReason,
                      onChanged: (v) =>
                          setDialogState(() => selectedReason = v),
                      title: Text(reason,
                          style: const TextStyle(
                              color: Colors.white, fontSize: 14)),
                      activeColor: const Color(0xFFF59E0B),
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      visualDensity:
                          const VisualDensity(horizontal: -4, vertical: -4),
                    )),
                const SizedBox(height: 12),
                TextField(
                  controller: detailsController,
                  maxLines: 3,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'Additional details (optional)',
                    hintStyle:
                        TextStyle(color: Colors.white.withValues(alpha: 0.3)),
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: 0.05),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                          color: Colors.white.withValues(alpha: 0.1)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                          color: Colors.white.withValues(alpha: 0.1)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFFF59E0B)),
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child:
                  const Text('Cancel', style: TextStyle(color: Colors.white54)),
            ),
            ElevatedButton(
              onPressed: selectedReason == null
                  ? null
                  : () => Navigator.pop(ctx, {
                        'reason': selectedReason!,
                        'details': detailsController.text.trim(),
                      }),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFF59E0B),
                disabledBackgroundColor: Colors.white.withValues(alpha: 0.1),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Submit Report',
                  style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  // ════════════════════════════════════════════════════════
  // BUILD
  // ════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF111118),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(
          top: BorderSide(color: Color(0xFF6366F1), width: 1.5),
        ),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle bar
            Container(
              margin: const EdgeInsets.only(top: 10, bottom: 4),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: const Color(0xFF2A2A3A),
                    backgroundImage: widget.userAvatar != null &&
                            widget.userAvatar!.startsWith('http')
                        ? NetworkImage(widget.userAvatar!)
                        : null,
                    child: widget.userAvatar == null ||
                            !widget.userAvatar!.startsWith('http')
                        ? const Icon(Icons.person,
                            color: Colors.white38, size: 20)
                        : null,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Manage ${widget.userName}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          'Choose an action below',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.4),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_isActionLoading)
                    const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Color(0xFF6366F1),
                      ),
                    ),
                ],
              ),
            ),
            const Divider(height: 1, color: Colors.white12),

            if (_isLoading)
              const Padding(
                padding: EdgeInsets.all(30),
                child: CircularProgressIndicator(color: Color(0xFF6366F1)),
              )
            else ...[
              // Block / Unblock
              _buildOption(
                icon: _isBlocked ? Icons.check_circle_outline : Icons.block,
                label: _isBlocked ? 'Unblock' : 'Block',
                subtitle: _isBlocked
                    ? 'Allow them to interact with you again'
                    : 'Prevent them from contacting you',
                color: const Color(0xFFEF4444),
                onTap: _isActionLoading ? null : _toggleBlock,
              ),

              // Mute / Unmute
              _buildOption(
                icon: _isMuted ? Icons.volume_up : Icons.volume_off,
                label: _isMuted ? 'Unmute' : 'Mute',
                subtitle: _isMuted
                    ? 'Receive notifications from them again'
                    : 'Stop notifications from this user',
                color: const Color(0xFFF59E0B),
                onTap: _isActionLoading ? null : _toggleMute,
              ),

              // Disconnect Proposal (only if connected)
              if (_isProposalConnected)
                _buildOption(
                  icon: Icons.heart_broken,
                  label: 'Disconnect Proposal',
                  subtitle: 'Break your proposal connection',
                  color: const Color(0xFFEC4899),
                  onTap: _isActionLoading ? null : _disconnectProposal,
                ),

              // Report
              _buildOption(
                icon: Icons.flag_rounded,
                label: 'Report',
                subtitle: 'Report inappropriate behavior',
                color: const Color(0xFFF97316),
                onTap: _isActionLoading ? null : _reportUser,
              ),

              const Divider(height: 1, color: Colors.white12, indent: 60),

              // Share
              _buildOption(
                icon: Icons.share_rounded,
                label: 'Share Profile',
                subtitle: 'Share this profile with friends',
                color: const Color(0xFF06B6D4),
                onTap: _shareProfile,
              ),

              // Copy Link
              _buildOption(
                icon: Icons.link_rounded,
                label: 'Copy Profile Link',
                subtitle: 'Copy the profile URL to clipboard',
                color: const Color(0xFF8B5CF6),
                onTap: _copyProfileLink,
              ),
            ],

            const SizedBox(height: 8),

            // Cancel button
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                      side: BorderSide(
                          color: Colors.white.withValues(alpha: 0.1)),
                    ),
                  ),
                  child: const Text(
                    'Cancel',
                    style: TextStyle(color: Colors.white54, fontSize: 15),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOption({
    required IconData icon,
    required String label,
    required String subtitle,
    required Color color,
    VoidCallback? onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        splashColor: color.withValues(alpha: 0.1),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.4),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: Colors.white.withValues(alpha: 0.2),
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
