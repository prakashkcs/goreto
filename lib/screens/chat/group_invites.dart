import 'dart:async';
import 'package:flutter/material.dart';
import 'package:love_vibe_pro/models/group_chat.dart';
import 'package:love_vibe_pro/screens/chat/group_chat_screen.dart';
import 'package:love_vibe_pro/screens/chat/group_ui.dart';
import 'package:love_vibe_pro/services/group_chat_service.dart';
import 'package:love_vibe_pro/widgets/neon_toast.dart';
import 'package:love_vibe_pro/widgets/user_preview_sheet.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Add members — search friends by name / @username and send invitations.
// ═══════════════════════════════════════════════════════════════════════════

class AddMembersSheet extends StatefulWidget {
  final ChatGroup group;
  const AddMembersSheet({super.key, required this.group});

  /// Resolves to the number of invitations sent / people added.
  static Future<int?> show(BuildContext context, ChatGroup group) {
    return showGSheet<int>(context,
        builder: (_) => AddMembersSheet(group: group));
  }

  @override
  State<AddMembersSheet> createState() => _AddMembersSheetState();
}

class _AddMembersSheetState extends State<AddMembersSheet> {
  final _service = GroupChatService();
  final _searchCtrl = TextEditingController();
  Timer? _debounce;
  int _seq = 0;

  List<GroupInvitee> _results = [];
  final Map<int, GroupInvitee> _selected = {};
  final Map<int, String> _statusOverride = {};
  bool _loading = true;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _search('');
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onChanged(String v) {
    _debounce?.cancel();
    setState(() {});
    _debounce = Timer(const Duration(milliseconds: 350), () => _search(v));
  }

  Future<void> _search(String q) async {
    final seq = ++_seq;
    setState(() => _loading = true);
    final res = await _service.searchInvitees(widget.group.id, q);
    if (!mounted || seq != _seq) return;
    setState(() {
      _results = res;
      _loading = false;
    });
  }

  String _statusOf(GroupInvitee u) => _statusOverride[u.id] ?? u.status;

  void _toggle(GroupInvitee u) {
    if (_statusOf(u) != 'none') return;
    setState(() {
      if (_selected.containsKey(u.id)) {
        _selected.remove(u.id);
      } else {
        _selected[u.id] = u;
      }
    });
  }

  Future<void> _send() async {
    if (_selected.isEmpty || _sending) return;
    setState(() => _sending = true);
    final res = await _service.inviteUsers(widget.group.id, _selected.keys.toList());
    if (!mounted) return;
    setState(() => _sending = false);
    if (res['success'] == true) {
      final results = res['results'] as Map<int, String>;
      NeonToast.success(context, res['msg'].toString());
      Navigator.pop(context, results.values.where((s) => s == 'invited' || s == 'member').length);
    } else {
      NeonToast.error(context, res['msg'].toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.of(context).size.height * 0.86;
    final query = _searchCtrl.text.trim();

    return SizedBox(
      height: height,
      child: Column(
        children: [
          GSheetHeader(
            title: 'Add members',
            subtitle:
                'Search friends by name or @username. They\'ll get an invitation to accept.',
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: GTextField(
              controller: _searchCtrl,
              hint: 'Search name or @username',
              onChanged: _onChanged,
              prefix: const Icon(Icons.search_rounded, color: GUI.textLo),
              suffix: query.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close_rounded,
                          color: GUI.textLo, size: 20),
                      onPressed: () {
                        _searchCtrl.clear();
                        _onChanged('');
                      },
                    ),
            ),
          ),

          // Selected people
          AnimatedSize(
            duration: const Duration(milliseconds: 180),
            child: _selected.isEmpty
                ? const SizedBox(width: double.infinity)
                : SizedBox(
                    height: 88,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                      children: _selected.values.map((u) {
                        return GestureDetector(
                          onTap: () => _toggle(u),
                          child: Padding(
                            padding: const EdgeInsets.only(right: 14),
                            child: Column(
                              children: [
                                Stack(
                                  clipBehavior: Clip.none,
                                  children: [
                                    UserAvatar(
                                        url: u.avatar,
                                        name: u.name,
                                        seed: u.id,
                                        size: 48),
                                    Positioned(
                                      right: -2,
                                      top: -2,
                                      child: Container(
                                        padding: const EdgeInsets.all(2),
                                        decoration: const BoxDecoration(
                                            color: GUI.surface2,
                                            shape: BoxShape.circle),
                                        child: const Icon(Icons.close_rounded,
                                            size: 12, color: GUI.textHi),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 5),
                                SizedBox(
                                  width: 56,
                                  child: Text(u.name.split(' ').first,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                          color: GUI.textMid, fontSize: 11.5)),
                                ),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
          ),

          GSectionLabel(query.isEmpty ? 'Suggested · people you follow' : 'Results'),

          Expanded(
            child: _loading && _results.isEmpty
                ? const Center(
                    child: CircularProgressIndicator(
                        color: GUI.accent, strokeWidth: 2))
                : _results.isEmpty
                    ? _empty(query)
                    : ListView.builder(
                        padding: const EdgeInsets.only(bottom: 12),
                        itemCount: _results.length,
                        itemBuilder: (_, i) => _row(_results[i]),
                      ),
          ),

          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: GPrimaryButton(
              label: _selected.isEmpty
                  ? 'Select people to invite'
                  : 'Send invite${_selected.length == 1 ? '' : 's'} (${_selected.length})',
              icon: Icons.send_rounded,
              loading: _sending,
              onPressed: _selected.isEmpty ? null : _send,
            ),
          ),
        ],
      ),
    );
  }

  Widget _empty(String query) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const GIconBox(Icons.person_search_rounded, size: 52),
            const SizedBox(height: 14),
            Text(
              query.isEmpty ? 'No suggestions yet' : 'No one found for "$query"',
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: GUI.textHi, fontSize: 15, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Text(
              query.isEmpty
                  ? 'Search by name or @username to find people.'
                  : 'Check the spelling or try their @username.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: GUI.textLo, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(GroupInvitee u) {
    final status = _statusOf(u);
    final selected = _selected.containsKey(u.id);
    final selectable = status == 'none';

    Widget trailing;
    if (selectable) {
      trailing = AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: selected ? GUI.gradient : null,
          border: selected ? null : Border.all(color: GUI.textLo, width: 1.6),
        ),
        child: selected
            ? const Icon(Icons.check_rounded, color: Colors.white, size: 16)
            : null,
      );
    } else {
      final label = switch (status) {
        'member' => 'Member',
        'invited' => 'Invited',
        'requested' => 'Requested',
        'banned' => 'Banned',
        _ => '',
      };
      trailing = Text(label,
          style: TextStyle(
              color: status == 'banned' ? GUI.danger : GUI.textLo,
              fontSize: 12.5,
              fontWeight: FontWeight.w600));
    }

    return InkWell(
      onTap: selectable ? () => _toggle(u) : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 9),
        child: Row(
          children: [
            UserAvatar(url: u.avatar, name: u.name, seed: u.id, size: 46),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(u.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: selectable ? GUI.textHi : GUI.textMid,
                                fontSize: 15,
                                fontWeight: FontWeight.w600)),
                      ),
                      if (u.isFriend) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: GUI.success.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text('Friend',
                              style: TextStyle(
                                  color: GUI.success,
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w700)),
                        ),
                      ],
                    ],
                  ),
                  if (u.username.isNotEmpty)
                    Text('@${u.username}',
                        style:
                            const TextStyle(color: GUI.textLo, fontSize: 13)),
                ],
              ),
            ),
            const SizedBox(width: 10),
            trailing,
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Invitations the current user received.
// ═══════════════════════════════════════════════════════════════════════════

class GroupInvitesScreen extends StatefulWidget {
  const GroupInvitesScreen({super.key});

  @override
  State<GroupInvitesScreen> createState() => _GroupInvitesScreenState();
}

class _GroupInvitesScreenState extends State<GroupInvitesScreen> {
  final _service = GroupChatService();
  List<GroupInvite> _invites = [];
  bool _loading = true;
  final Set<int> _busy = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await _service.getMyInvites();
    if (!mounted) return;
    setState(() {
      _invites = list;
      _loading = false;
    });
  }

  Future<void> _respond(GroupInvite inv, bool accept) async {
    setState(() => _busy.add(inv.inviteId));
    final r = await _service.respondInvite(inv.inviteId, accept);
    if (!mounted) return;
    setState(() => _busy.remove(inv.inviteId));
    if (!r.success) {
      NeonToast.error(context, r.message);
      _load();
      return;
    }
    setState(() => _invites.removeWhere((i) => i.inviteId == inv.inviteId));
    if (!accept) {
      NeonToast.info(context, 'Invitation declined');
    } else if (r.state == 'requested') {
      NeonToast.info(context, 'Request sent. An admin needs to approve it.');
    } else {
      NeonToast.success(context, 'You joined ${inv.group.name}');
      Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => GroupChatScreen(group: r.group ?? inv.group)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: GUI.bg,
      appBar: AppBar(
        backgroundColor: GUI.bg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: const Text('Group invitations',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: GUI.accent, strokeWidth: 2))
          : RefreshIndicator(
              color: GUI.accent,
              backgroundColor: GUI.surface,
              onRefresh: _load,
              child: _invites.isEmpty
                  ? ListView(
                      children: const [
                        SizedBox(height: 140),
                        _EmptyState(
                          icon: Icons.mark_email_read_outlined,
                          title: 'No pending invitations',
                          message:
                              'When someone invites you to a group, it shows up here.',
                        ),
                      ],
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                      itemCount: _invites.length,
                      itemBuilder: (_, i) => _card(_invites[i]),
                    ),
            ),
    );
  }

  Widget _card(GroupInvite inv) {
    final g = inv.group;
    final busy = _busy.contains(inv.inviteId);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: GUI.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: GUI.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              GroupAvatar.of(g, size: 54),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(g.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: GUI.textHi,
                            fontSize: 16,
                            fontWeight: FontWeight.w700)),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Icon(g.isPrivate ? Icons.lock_rounded : Icons.public_rounded,
                            size: 13, color: GUI.textLo),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            '${g.isPrivate ? 'Private' : 'Public'} · ${formatMemberCount(g.memberCount)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: GUI.textLo, fontSize: 12.5),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          if ((g.bio ?? '').isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(g.bio!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: GUI.textMid, fontSize: 13.5, height: 1.35)),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              UserAvatar(
                  url: inv.inviterAvatar,
                  name: inv.inviterName,
                  seed: inv.inviterId,
                  size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text.rich(
                  TextSpan(children: [
                    TextSpan(
                        text: inv.inviterName,
                        style: const TextStyle(
                            color: GUI.textHi, fontWeight: FontWeight.w600)),
                    TextSpan(text: ' invited you · ${timeAgo(inv.invitedAt)}'),
                  ]),
                  style: const TextStyle(color: GUI.textLo, fontSize: 12.5),
                ),
              ),
            ],
          ),
          if (g.joinFee > 0) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.monetization_on_rounded,
                    color: GUI.warning, size: 14),
                const SizedBox(width: 5),
                Text('Join fee: ${g.joinFee} coins (may apply)',
                    style: const TextStyle(color: GUI.warning, fontSize: 12)),
              ],
            ),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 42,
                  child: OutlinedButton(
                    onPressed: busy ? null : () => _respond(inv, false),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0x33FFFFFF)),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('Decline',
                        style: TextStyle(
                            color: GUI.textMid, fontWeight: FontWeight.w600)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: GPrimaryButton(
                  label: 'Accept',
                  height: 42,
                  loading: busy,
                  onPressed: () => _respond(inv, true),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Admin: join requests and outgoing invites.
// ═══════════════════════════════════════════════════════════════════════════

class GroupRequestsScreen extends StatefulWidget {
  final int groupId;
  final String groupName;
  const GroupRequestsScreen(
      {super.key, required this.groupId, this.groupName = ''});

  @override
  State<GroupRequestsScreen> createState() => _GroupRequestsScreenState();
}

class _GroupRequestsScreenState extends State<GroupRequestsScreen> {
  final _service = GroupChatService();
  List<GroupPendingUser> _requests = [];
  List<GroupPendingUser> _invites = [];
  bool _loading = true;
  final Set<int> _busy = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final data = await _service.getRequests(widget.groupId);
    if (!mounted) return;
    setState(() {
      _requests = data['requests'] ?? [];
      _invites = data['invites'] ?? [];
      _loading = false;
    });
  }

  Future<void> _handle(GroupPendingUser r, bool approve) async {
    setState(() => _busy.add(r.id));
    final res = await _service.handleRequest(r.id, approve);
    if (!mounted) return;
    setState(() => _busy.remove(r.id));
    if (res.success) {
      setState(() => _requests.removeWhere((x) => x.id == r.id));
      NeonToast.success(
          context, approve ? '${r.name} was added' : 'Request declined');
    } else {
      NeonToast.error(context, res.message);
    }
  }

  Future<void> _cancelInvite(GroupPendingUser inv) async {
    setState(() => _busy.add(-inv.id));
    final ok = await _service.cancelInvite(inv.id);
    if (!mounted) return;
    setState(() => _busy.remove(-inv.id));
    if (ok) {
      setState(() => _invites.removeWhere((x) => x.id == inv.id));
      NeonToast.info(context, 'Invitation cancelled');
    } else {
      NeonToast.error(context, 'Could not cancel invitation');
    }
  }

  void _preview(GroupPendingUser u) {
    UserPreviewSheet.show(context,
        userId: u.userId.toString(),
        name: u.name,
        username: u.username,
        avatar: u.avatar);
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: GUI.bg,
        appBar: AppBar(
          backgroundColor: GUI.bg,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Requests & invites',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
              if (widget.groupName.isNotEmpty)
                Text(widget.groupName,
                    style: const TextStyle(color: GUI.textLo, fontSize: 12.5)),
            ],
          ),
          bottom: TabBar(
            indicatorColor: GUI.accent,
            indicatorSize: TabBarIndicatorSize.label,
            labelColor: GUI.textHi,
            unselectedLabelColor: GUI.textLo,
            dividerColor: GUI.border,
            tabs: [
              Tab(text: 'Join requests${_requests.isEmpty ? '' : ' (${_requests.length})'}'),
              Tab(text: 'Invited${_invites.isEmpty ? '' : ' (${_invites.length})'}'),
            ],
          ),
        ),
        body: _loading
            ? const Center(
                child:
                    CircularProgressIndicator(color: GUI.accent, strokeWidth: 2))
            : TabBarView(
                children: [
                  _list(
                    _requests,
                    empty: const _EmptyState(
                      icon: Icons.how_to_reg_outlined,
                      title: 'No pending requests',
                      message:
                          'People asking to join this group will appear here for approval.',
                    ),
                    builder: _requestRow,
                  ),
                  _list(
                    _invites,
                    empty: const _EmptyState(
                      icon: Icons.outgoing_mail,
                      title: 'No pending invitations',
                      message: 'Invitations waiting for a reply show up here.',
                    ),
                    builder: _inviteRow,
                  ),
                ],
              ),
      ),
    );
  }

  Widget _list(List<GroupPendingUser> items,
      {required Widget empty,
      required Widget Function(GroupPendingUser) builder}) {
    return RefreshIndicator(
      color: GUI.accent,
      backgroundColor: GUI.surface,
      onRefresh: _load,
      child: items.isEmpty
          ? ListView(children: [const SizedBox(height: 120), empty])
          : ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: items.length,
              separatorBuilder: (_, __) => const Divider(
                  height: 1, indent: 80, color: Color(0x0FFFFFFF)),
              itemBuilder: (_, i) => builder(items[i]),
            ),
    );
  }

  Widget _person(GroupPendingUser u, String subtitle, Widget actions) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => _preview(u),
            child: UserAvatar(url: u.avatar, name: u.name, seed: u.userId, size: 50),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: GestureDetector(
              onTap: () => _preview(u),
              behavior: HitTestBehavior.opaque,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(u.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: GUI.textHi,
                          fontSize: 15,
                          fontWeight: FontWeight.w600)),
                  if (u.username.isNotEmpty)
                    Text('@${u.username}',
                        style: const TextStyle(color: GUI.textLo, fontSize: 12.5)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: GUI.textLo, fontSize: 12)),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          actions,
        ],
      ),
    );
  }

  Widget _requestRow(GroupPendingUser r) {
    final busy = _busy.contains(r.id);
    final sub = r.invitedByName != null && r.invitedByName!.isNotEmpty
        ? 'Invited by ${r.invitedByName} · ${timeAgo(r.createdAt)}'
        : 'Requested ${timeAgo(r.createdAt)}';
    return _person(
      r,
      sub,
      busy
          ? const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2, color: GUI.accent))
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                GPillButton(
                    label: 'Decline',
                    filled: false,
                    onTap: () => _handle(r, false)),
                const SizedBox(width: 8),
                GPillButton(label: 'Approve', onTap: () => _handle(r, true)),
              ],
            ),
    );
  }

  Widget _inviteRow(GroupPendingUser inv) {
    final sub = inv.invitedByName != null && inv.invitedByName!.isNotEmpty
        ? 'Invited by ${inv.invitedByName} · ${timeAgo(inv.createdAt)}'
        : 'Invited ${timeAgo(inv.createdAt)}';
    return _person(
      inv,
      sub,
      GPillButton(
        label: 'Cancel',
        filled: false,
        loading: _busy.contains(-inv.id),
        onTap: () => _cancelInvite(inv),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  const _EmptyState(
      {required this.icon, required this.title, required this.message});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          GIconBox(icon, size: 56),
          const SizedBox(height: 16),
          Text(title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: GUI.textHi, fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: GUI.textLo, fontSize: 13.5, height: 1.4)),
        ],
      ),
    );
  }
}
