import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:love_vibe_pro/services/api_service.dart';
import 'package:love_vibe_pro/services/profile_service.dart';
import 'package:love_vibe_pro/utils/formatters.dart';
import 'package:love_vibe_pro/widgets/neon_toast.dart';

class ProposalsScreen extends StatefulWidget {
  const ProposalsScreen({super.key});

  @override
  State<ProposalsScreen> createState() => _ProposalsScreenState();
}

class _ProposalsScreenState extends State<ProposalsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isLoading = true;
  List<dynamic> _receivedProposals = [];
  List<dynamic> _sentProposals = [];
  List<dynamic> _acceptedConnections = [];
  final ApiService _apiService = ApiService();
  final Set<String> _localBlockedIds = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _fetchData();
    _apiService.markProposalsRead();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _fetchData() async {
    setState(() => _isLoading = true);
    try {
      final received = await _apiService.getMyProposals(type: 'received');
      final sent = await _apiService.getMyProposals(type: 'sent');
      final connections = await _apiService.getConnections();

      if (mounted) {
        setState(() {
          _receivedProposals = received
              .where((p) =>
                  p['status'] == 'pending' &&
                  !_localBlockedIds.contains(p['sender_id']?.toString()))
              .toList();
          _sentProposals = sent.where((p) => p['status'] == 'pending').toList();
          _acceptedConnections = connections;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        NeonToast.show(context, 'Error loading proposals',
            type: NeonToastType.error);
      }
    }
  }

  Future<void> _acceptProposal(dynamic proposal) async {
    try {
      final id = proposal['proposal_id'];
      final parsedId = id is int ? id : int.parse(id.toString());
      await _apiService.acceptProposal(proposalId: parsedId);
      try {
        await ProfileService.instance.clearCachedProfile();
      } catch (_) {}
      if (mounted) {
        NeonToast.show(context, 'Proposal accepted! 💕',
            type: NeonToastType.success);
      }
      _fetchData();
    } catch (e) {
      if (mounted) {
        NeonToast.show(context, e.toString(), type: NeonToastType.error);
      }
    }
  }

  Future<void> _rejectProposal(dynamic proposal) async {
    try {
      final id = proposal['proposal_id'];
      final parsedId = id is int ? id : int.parse(id.toString());
      await _apiService.rejectProposal(proposalId: parsedId);
      try {
        await ProfileService.instance.clearCachedProfile();
      } catch (_) {}
      if (mounted) {
        NeonToast.show(context, 'Proposal rejected', type: NeonToastType.info);
      }
      _fetchData();
    } catch (e) {
      if (mounted) {
        NeonToast.show(context, 'Error rejecting proposal',
            type: NeonToastType.error);
      }
    }
  }

  Future<void> _blockUser(dynamic proposal) async {
    final senderId = proposal['sender_id']?.toString() ?? '';
    final senderName = proposal['sender_name'] ?? 'this user';
    if (senderId.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Block User', style: TextStyle(color: Colors.white)),
        content: Text(
          'Block $senderName? Their proposal will be rejected and they won\'t be able to contact you.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child:
                const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
            child: const Text('Block'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _apiService.blockUser(blockedId: senderId);
      try {
        final id = proposal['proposal_id'];
        final parsedId = id is int ? id : int.parse(id.toString());
        await _apiService.rejectProposal(proposalId: parsedId);
      } catch (_) {}

      setState(() => _localBlockedIds.add(senderId));
      if (mounted) {
        NeonToast.show(context, '$senderName blocked',
            type: NeonToastType.info);
      }
      _fetchData();
    }
  }

  Future<void> _disconnect(dynamic connection) async {
    try {
      await _apiService.disconnectProposal(
          targetUserId: connection['connected_user_id'].toString());
      try {
        await ProfileService.instance.clearCachedProfile();
      } catch (_) {}
      if (mounted) {
        NeonToast.show(context, 'Disconnected successfully',
            type: NeonToastType.info);
      }
      _fetchData();
    } catch (e) {
      if (mounted) {
        NeonToast.show(context, 'Error disconnecting',
            type: NeonToastType.error);
      }
    }
  }

  Future<void> _togglePublic(dynamic connection, bool value) async {
    final proposalIdStr = connection['proposal_id']?.toString();
    if (proposalIdStr == null || proposalIdStr.isEmpty) return;
    try {
      await _apiService.setProposalPublic(
          proposalId: int.parse(proposalIdStr), isPublic: value);
      try {
        await ProfileService.instance.clearCachedProfile();
      } catch (_) {}
      if (mounted) {
        NeonToast.show(
            context, value ? 'Showing on profile' : 'Hidden from profile',
            type: NeonToastType.info);
      }
      _fetchData();
    } catch (e) {
      if (mounted) {
        NeonToast.show(context, e.toString(), type: NeonToastType.error);
      }
    }
  }

  // ── RECEIVED TAB ──
  Widget _buildReceivedTab() {
    if (_isLoading) {
      return const Center(
          child: CircularProgressIndicator(color: Color(0xFFFF007F)));
    }
    if (_receivedProposals.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [
                    const Color(0xFFFF007F).withValues(alpha: 0.2),
                    const Color(0xFFD946EF).withValues(alpha: 0.1),
                  ],
                ),
              ),
              child: Icon(Icons.favorite_border,
                  size: 40,
                  color: const Color(0xFFFF007F).withValues(alpha: 0.6)),
            ),
            const SizedBox(height: 20),
            const Text('No pending proposals',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text(
              'When someone sends you a proposal, it\'ll appear here.',
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.4), fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _fetchData,
      color: const Color(0xFFFF007F),
      backgroundColor: const Color(0xFF1E1E1E),
      child: ListView.builder(
        itemCount: _receivedProposals.length,
        padding: const EdgeInsets.all(16),
        itemBuilder: (context, index) {
          final p = _receivedProposals[index];
          return _buildReceivedCard(p);
        },
      ),
    );
  }

  Widget _buildReceivedCard(dynamic p) {
    final name = p['sender_name'] ?? 'Someone';
    final avatar = p['sender_avatar']?.toString();
    final age = p['age']?.toString();
    final gender = p['gender']?.toString();
    final bio = p['bio']?.toString();
    final city = p['city']?.toString();
    final distance = p['distance_km']?.toString();
    final rating = double.tryParse(p['rating']?.toString() ?? '');
    final isUnread = p['is_read']?.toString() != '1';
    final incomeStatus = p['income_status']?.toString() ?? '';
    final income = p['income']?.toString();
    final List<String> interests = List<String>.from(p['interests'] ?? []);
    final List<String> lookingFor = List<String>.from(p['looking_for'] ?? []);
    final List<String> qualities = List<String>.from(p['qualities'] ?? []);
    final bool isIncomeVerified =
        incomeStatus == 'verified' || incomeStatus == 'approved';

    String subtitle = '';
    if (age != null && age.isNotEmpty && age != 'null') {
      subtitle = '$age yrs';
      if (gender != null && gender.isNotEmpty && gender != 'null') {
        subtitle += ' • ${gender[0].toUpperCase()}${gender.substring(1)}';
      }
    }
    if (city != null && city.isNotEmpty && city != 'null') {
      subtitle += ' • $city';
    }
    if (distance != null && distance.isNotEmpty && distance != 'null') {
      subtitle += ' • ${Formatters.formatDistance(distance)} away';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: isUnread
            ? const Color(0xFFFF007F).withValues(alpha: 0.06)
            : Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isUnread
              ? const Color(0xFFFF007F).withValues(alpha: 0.25)
              : Colors.white.withValues(alpha: 0.06),
        ),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 10,
              offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Row: Avatar + Info + Menu
          ListTile(
            contentPadding: const EdgeInsets.fromLTRB(16, 10, 8, 0),
            leading: Stack(
              children: [
                _buildAvatar(avatar, 28),
                if (isUnread)
                  Positioned(
                    top: 0,
                    right: 0,
                    child: Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF007F),
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: const Color(0xFF0F0F1A), width: 2),
                      ),
                    ),
                  ),
              ],
            ),
            title: Row(
              children: [
                Flexible(
                  child: Text(name,
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16),
                      overflow: TextOverflow.ellipsis),
                ),
                if (isIncomeVerified) ...[
                  const SizedBox(width: 6),
                  const Icon(Icons.verified,
                      color: Color(0xFF00E5FF), size: 16),
                ],
                if (rating != null) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF007F).withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.star_rounded,
                            color: Color(0xFFFF007F), size: 12),
                        const SizedBox(width: 2),
                        Text(
                          rating.toStringAsFixed(1),
                          style: const TextStyle(
                              color: Color(0xFFFF007F),
                              fontSize: 11,
                              fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
            subtitle: subtitle.isNotEmpty
                ? Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(
                      children: [
                        if (distance != null &&
                            distance.isNotEmpty &&
                            distance != 'null')
                          const Icon(Icons.location_on,
                              color: Color(0xFF00E5FF), size: 13),
                        if (distance != null &&
                            distance.isNotEmpty &&
                            distance != 'null')
                          const SizedBox(width: 3),
                        Expanded(
                          child: Text(subtitle,
                              style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.5),
                                  fontSize: 12),
                              overflow: TextOverflow.ellipsis),
                        ),
                      ],
                    ),
                  )
                : null,
            trailing: PopupMenuButton<String>(
              icon: Icon(Icons.more_vert,
                  color: Colors.white.withValues(alpha: 0.4), size: 20),
              color: const Color(0xFF1A1A2E),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              onSelected: (value) {
                if (value == 'block') _blockUser(p);
              },
              itemBuilder: (_) => [
                const PopupMenuItem(
                  value: 'block',
                  child: Row(
                    children: [
                      Icon(Icons.block, color: Colors.redAccent, size: 18),
                      SizedBox(width: 10),
                      Text('Block User',
                          style: TextStyle(color: Colors.redAccent)),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Verified Income Row
          if (isIncomeVerified &&
              income != null &&
              income.isNotEmpty &&
              income != 'null')
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: const Color(0xFF00E5FF).withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: const Color(0xFF00E5FF).withValues(alpha: 0.2)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.verified,
                        color: Color(0xFF00E5FF), size: 14),
                    const SizedBox(width: 6),
                    Text(
                      'Verified Income: Rs. $income/month',
                      style: const TextStyle(
                          color: Color(0xFF00E5FF),
                          fontSize: 11,
                          fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ),

          // Interests / Looking For / Qualities tags
          if (interests.isNotEmpty ||
              lookingFor.isNotEmpty ||
              qualities.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Wrap(
                spacing: 6,
                runSpacing: 5,
                children: [
                  ...interests.take(3).map((i) => _buildTag(
                      i, Colors.white.withValues(alpha: 0.1), Colors.white70)),
                  ...lookingFor.take(2).map((l) => _buildTag(
                      l,
                      const Color(0xFFFF007F).withValues(alpha: 0.12),
                      const Color(0xFFFF007F))),
                  ...qualities.take(2).map((q) => _buildTag(
                      q,
                      const Color(0xFF00E5FF).withValues(alpha: 0.12),
                      const Color(0xFF00E5FF))),
                ],
              ),
            ),

          // Bio
          if (bio != null && bio.isNotEmpty && bio != 'null')
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text(
                bio,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.35),
                    fontSize: 12,
                    fontStyle: FontStyle.italic),
              ),
            ),

          // Accept / Reject buttons
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
            child: Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => _rejectProposal(p),
                    child: Container(
                      height: 44,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                            color: Colors.white.withValues(alpha: 0.1)),
                      ),
                      child: const Center(
                        child: Text('Reject',
                            style: TextStyle(
                                color: Colors.white60,
                                fontWeight: FontWeight.w600,
                                fontSize: 14)),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: GestureDetector(
                    onTap: () => _acceptProposal(p),
                    child: Container(
                      height: 44,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFFFF007F), Color(0xFFD946EF)],
                        ),
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                            color:
                                const Color(0xFFFF007F).withValues(alpha: 0.3),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: const Center(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.favorite, color: Colors.white, size: 18),
                            SizedBox(width: 6),
                            Text('Accept',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTag(String text, Color bg, Color textColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: textColor.withValues(alpha: 0.15)),
      ),
      child: Text(
        text,
        style: TextStyle(
            color: textColor, fontSize: 11, fontWeight: FontWeight.w500),
      ),
    );
  }

  // ── SENT TAB ──
  Widget _buildSentTab() {
    if (_isLoading) {
      return const Center(
          child: CircularProgressIndicator(color: Color(0xFF00E5FF)));
    }
    if (_sentProposals.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [
                    const Color(0xFF00E5FF).withValues(alpha: 0.2),
                    const Color(0xFFD946EF).withValues(alpha: 0.1),
                  ],
                ),
              ),
              child: Icon(Icons.send_rounded,
                  size: 36,
                  color: const Color(0xFF00E5FF).withValues(alpha: 0.6)),
            ),
            const SizedBox(height: 20),
            const Text('No sent proposals',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text(
              'Proposals you send will appear here.',
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.4), fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _fetchData,
      color: const Color(0xFF00E5FF),
      backgroundColor: const Color(0xFF1E1E1E),
      child: ListView.builder(
        itemCount: _sentProposals.length,
        padding: const EdgeInsets.all(16),
        itemBuilder: (context, index) {
          final p = _sentProposals[index];
          final name = p['receiver_name'] ?? 'Someone';
          final avatar = p['receiver_avatar']?.toString();
          final city = p['city']?.toString();
          final distance = p['distance_km']?.toString();
          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.03),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
            ),
            child: ListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              leading: _buildAvatar(avatar, 24),
              title: Text(name,
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold)),
              subtitle: Text(
                [
                  'Pending...',
                  if (city != null && city != 'null') city,
                  if (distance != null && distance != 'null')
                    Formatters.formatDistance(distance),
                ].join(' • '),
                style: const TextStyle(color: Color(0xFF00E5FF), fontSize: 12),
              ),
              trailing: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF00E5FF).withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: const Color(0xFF00E5FF).withValues(alpha: 0.2)),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.schedule, color: Color(0xFF00E5FF), size: 14),
                    SizedBox(width: 4),
                    Text('Waiting',
                        style: TextStyle(
                            color: Color(0xFF00E5FF),
                            fontSize: 11,
                            fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // ── ACCEPTED TAB ──
  /// Returns the correct pronoun label based on gender.
  /// gender: 'male' → 'He', 'female' → 'She', else 'They'
  String _pronoun(String? gender) {
    final g = (gender ?? '').toLowerCase().trim();
    if (g == 'male') return 'He';
    if (g == 'female') return 'She';
    return 'They';
  }

  Widget _buildAcceptedTab() {
    if (_isLoading) {
      return const Center(
          child: CircularProgressIndicator(color: Color(0xFFD946EF)));
    }

    // Only show connections where BOTH sides have connected (mutual).
    // The backend should already filter this, but we double-check on the
    // client by requiring both_connected == true (or == 1).
    final mutual = _acceptedConnections.where((c) {
      final bothConnected = c['both_connected'];
      if (bothConnected == null) return true; // legacy: trust backend
      if (bothConnected is bool) return bothConnected;
      final s = bothConnected.toString().toLowerCase().trim();
      return s == '1' || s == 'true';
    }).toList();

    if (mutual.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [
                    const Color(0xFFD946EF).withValues(alpha: 0.2),
                    const Color(0xFFFF007F).withValues(alpha: 0.1),
                  ],
                ),
              ),
              child: Icon(Icons.people_outline,
                  size: 36,
                  color: const Color(0xFFD946EF).withValues(alpha: 0.6)),
            ),
            const SizedBox(height: 20),
            const Text('No mutual connections yet',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text(
              'Both of you need to connect for it to show here.',
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.4), fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _fetchData,
      color: const Color(0xFFD946EF),
      backgroundColor: const Color(0xFF1E1E1E),
      child: ListView.builder(
        itemCount: mutual.length,
        padding: const EdgeInsets.all(16),
        itemBuilder: (context, index) {
          final c = mutual[index];

          // Use the correct name field from the backend.
          // The backend returns 'partner_name' (the other person's name as
          // seen by the current user) and 'my_name' (current user's name).
          final partnerName =
              (c['partner_name'] ?? c['name'] ?? 'Match').toString();
          final partnerGender =
              (c['partner_gender'] ?? c['gender'] ?? '').toString();
          final avatar = (c['partner_avatar'] ?? c['profile_pic'])?.toString();
          final isPublic = (c['show_on_profile']?.toString() == '1');
          final pronoun = _pronoun(partnerGender);

          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.03),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
            ),
            child: Column(
              children: [
                ListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  leading: _buildAvatar(avatar, 24),
                  title: Text(partnerName,
                      style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.bold)),
                  subtitle: Text(
                    '$pronoun connected with you 💕',
                    style:
                        const TextStyle(color: Color(0xFFD946EF), fontSize: 13),
                  ),
                  trailing: TextButton(
                    onPressed: () => _disconnect(c),
                    child: const Text('Disconnect',
                        style:
                            TextStyle(color: Colors.redAccent, fontSize: 12)),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Show on profile',
                          style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.6),
                              fontSize: 13)),
                      Switch(
                        value: isPublic,
                        activeThumbColor: Colors.pinkAccent,
                        onChanged: (val) {
                          setState(
                              () => c['show_on_profile'] = val ? '1' : '0');
                          _togglePublic(c, val).catchError((_) {
                            if (mounted) {
                              setState(() =>
                                  c['show_on_profile'] = isPublic ? '1' : '0');
                            }
                          });
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildAvatar(String? url, double radius) {
    return CircleAvatar(
      radius: radius,
      backgroundColor: const Color(0xFF2A2A3E),
      backgroundImage: url != null && url.startsWith('http')
          ? CachedNetworkImageProvider(url)
          : null,
      child: (url == null || !url.startsWith('http'))
          ? const Icon(Icons.person, color: Colors.white54, size: 22)
          : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F1A),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: ShaderMask(
          shaderCallback: (bounds) => const LinearGradient(
            colors: [Color(0xFFFF007F), Color(0xFFD946EF)],
          ).createShader(bounds),
          child: const Text('Proposals',
              style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 22)),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: const Color(0xFFFF007F),
          indicatorWeight: 3,
          indicatorSize: TabBarIndicatorSize.label,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white38,
          labelStyle:
              const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
          dividerColor: Colors.transparent,
          tabs: [
            Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Received'),
                  if (_receivedProposals.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                            colors: [Color(0xFFFF007F), Color(0xFFD946EF)]),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${_receivedProposals.length}',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const Tab(text: 'Sent'),
            const Tab(text: 'Connected'),
          ],
        ),
      ),
      body: SafeArea(
        child: TabBarView(
          controller: _tabController,
          children: [
            _buildReceivedTab(),
            _buildSentTab(),
            _buildAcceptedTab(),
          ],
        ),
      ),
    );
  }
}
