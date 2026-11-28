import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:chewie/chewie.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gal/gal.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:record/record.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:video_player/video_player.dart';
import 'package:video_thumbnail/video_thumbnail.dart';
import 'package:love_vibe_pro/models/group_chat.dart';
import 'package:love_vibe_pro/providers/auth_provider.dart';
import 'package:love_vibe_pro/screens/chat/group_invites.dart';
import 'package:love_vibe_pro/screens/chat/group_settings_screen.dart';
import 'package:love_vibe_pro/screens/chat/group_ui.dart';
import 'package:love_vibe_pro/services/group_chat_service.dart';
import 'package:love_vibe_pro/widgets/neon_toast.dart';
import 'package:love_vibe_pro/widgets/user_preview_sheet.dart';
import 'package:love_vibe_pro/services/fast_audio_source.dart';

class GroupChatScreen extends StatefulWidget {
  final ChatGroup group;

  const GroupChatScreen({super.key, required this.group});

  @override
  State<GroupChatScreen> createState() => _GroupChatScreenState();
}

/// An item in the message list: either a message or a day separator.
class _Entry {
  final GroupMessage? msg;
  final DateTime? day;
  final bool firstInRun;
  final bool lastInRun;
  const _Entry.message(this.msg, {this.firstInRun = true, this.lastInRun = true})
      : day = null;
  const _Entry.day(this.day)
      : msg = null,
        firstInRun = false,
        lastInRun = false;
}

class _GroupChatScreenState extends State<GroupChatScreen>
    with WidgetsBindingObserver {
  final GroupChatService _service = GroupChatService();
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _msgController = TextEditingController();
  final FocusNode _inputFocus = FocusNode();

  late ChatGroup _group;
  final List<GroupMessage> _messages = [];
  bool _isLoading = true;
  bool _isSending = false;
  bool _isSyncing = false;
  bool _notMember = false;
  String? _serverTime;
  Timer? _timer;
  int _myId = 0;
  DateTime? _lastMessageTime;
  final Map<String, Future<Uint8List?>> _thumbCache = {};

  // Editing
  GroupMessage? _editing;

  // Upload progress
  double? _uploadProgress;
  String _uploadLabel = '';

  // Voice recording
  final AudioRecorder _audioRecorder = AudioRecorder();
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isRecording = false;
  Duration _recordDuration = Duration.zero;
  Timer? _recordTimer;
  bool _hasText = false;

  // Voice playback
  int? _playingMsgId;
  Duration _playPosition = Duration.zero;
  StreamSubscription? _positionSub;
  StreamSubscription? _completionSub;

  bool get _isAdmin => _group.isAdmin;
  GroupPermissions get _permissions =>
      _isAdmin ? const GroupPermissions() : _group.permissions;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final auth = Provider.of<AuthProvider>(context, listen: false);
    _myId = int.tryParse(auth.currentUserId ?? '0') ?? 0;
    _group = widget.group;
    _msgController.addListener(() {
      final has = _msgController.text.trim().isNotEmpty;
      if (has != _hasText) setState(() => _hasText = has);
    });
    _loadMessages();
    _refreshGroup();
    _startPolling();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _startPolling();
      _loadMessages(showLoading: false);
    } else if (state == AppLifecycleState.paused) {
      _timer?.cancel();
    }
  }

  void _startPolling() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 2), (_) {
      _loadMessages(showLoading: false);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _recordTimer?.cancel();
    _positionSub?.cancel();
    _completionSub?.cancel();
    _scrollController.dispose();
    _msgController.dispose();
    _inputFocus.dispose();
    _audioRecorder.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }

  String _mediaUrl(String path) => resolveGroupFile(path);

  Future<void> _refreshGroup() async {
    final g = await _service.getGroupDetails(_group.id);
    if (!mounted || g == null) return;
    setState(() => _group = g);
  }

  Future<void> _loadMessages({bool showLoading = true}) async {
    if (_isSyncing || _notMember) return;
    _isSyncing = true;
    if (showLoading && mounted && _messages.isEmpty) {
      setState(() => _isLoading = true);
    }
    try {
      final lastId = _messages.isNotEmpty ? _messages.last.id : 0;
      final res = await _service.syncMessages(_group.id,
          lastId: lastId, since: _serverTime);
      if (!mounted) return;
      if (res.notMember) {
        setState(() {
          _notMember = true;
          _isLoading = false;
        });
        _timer?.cancel();
        return;
      }
      if (res.serverTime != null) _serverTime = res.serverTime;

      bool changed = false;
      if (res.messages.isNotEmpty) {
        final known = _messages.map((m) => m.id).toSet();
        final fresh = res.messages.where((m) => !known.contains(m.id));
        if (fresh.isNotEmpty) {
          _messages.addAll(fresh);
          changed = true;
        }
      }
      for (final c in res.changes) {
        final i = _messages.indexWhere((m) => m.id == c.id);
        if (i == -1) continue;
        final m = _messages[i];
        if (m.message != c.message ||
            m.isDeleted != c.isDeleted ||
            m.isEdited != c.isEdited) {
          _messages[i] = m.copyWith(
              message: c.message, isEdited: c.isEdited, isDeleted: c.isDeleted);
          changed = true;
        }
      }
      if (changed || _isLoading) {
        setState(() => _isLoading = false);
      }
    } catch (_) {
      if (mounted && _isLoading) setState(() => _isLoading = false);
    } finally {
      _isSyncing = false;
    }
  }

  void _scrollToBottom() {
    if (!_scrollController.hasClients) return;
    _scrollController.animateTo(0,
        duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
  }

  bool _canSendNow() {
    if (_isAdmin) return true;
    final delay = _group.messageDelay;
    if (delay > 0 && _lastMessageTime != null) {
      final elapsed = DateTime.now().difference(_lastMessageTime!).inSeconds;
      if (elapsed < delay) {
        NeonToast.info(context,
            'Slow mode is on. Wait ${delay - elapsed}s before sending again.');
        return false;
      }
    }
    return true;
  }

  // ── Navigation ────────────────────────────────────────────────────────────

  Future<void> _openInfo() async {
    final result = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => GroupSettingsScreen(
          group: _group,
          onGroupUpdated: (g) {
            if (mounted) setState(() => _group = g);
          },
        ),
      ),
    );
    if (!mounted) return;
    if (result == GroupSettingsResult.left ||
        result == GroupSettingsResult.deleted) {
      Navigator.pop(context);
      return;
    }
    if (result == GroupSettingsResult.cleared) {
      setState(() {
        _messages.clear();
        _serverTime = null;
      });
    }
    _refreshGroup();
    _loadMessages(showLoading: false);
  }

  Future<void> _addMembers() async {
    final n = await AddMembersSheet.show(context, _group);
    if (n != null && n > 0) _refreshGroup();
  }

  Future<void> _openRequests() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            GroupRequestsScreen(groupId: _group.id, groupName: _group.name),
      ),
    );
    _refreshGroup();
  }

  void _viewUser(GroupMessage msg) {
    UserPreviewSheet.show(
      context,
      userId: msg.senderId.toString(),
      name: msg.senderName,
      username: msg.senderUsername,
      avatar: msg.senderAvatarUrl,
      isMe: msg.senderId == _myId,
      roleLabel: msg.senderId == _group.createdBy ? 'Owner' : null,
    );
  }

  // ── Sending ───────────────────────────────────────────────────────────────

  Future<void> _sendMessage() async {
    if (_isSending) return;
    final text = _msgController.text.trim();
    if (text.isEmpty) return;

    if (_editing != null) {
      await _submitEdit(text);
      return;
    }
    if (!_permissions.canSendText) {
      NeonToast.info(context, 'Only admins can send messages in this group');
      return;
    }
    if (!_canSendNow()) return;

    setState(() => _isSending = true);
    _msgController.clear();
    final r = await _service.sendMessage(_group.id, text);
    if (!mounted) return;
    setState(() => _isSending = false);
    if (r.success) {
      _lastMessageTime = DateTime.now();
      await _loadMessages(showLoading: false);
      _scrollToBottom();
    } else {
      _msgController.text = text;
      NeonToast.error(context, r.message);
    }
  }

  Future<void> _pickMedia(String type, ImageSource source) async {
    if (!_permissions.canSendMedia) {
      NeonToast.info(context, 'Only admins can share media in this group');
      return;
    }
    if (!_canSendNow()) return;
    final picker = ImagePicker();
    final XFile? file = type == 'video'
        ? await picker.pickVideo(
            source: source, maxDuration: const Duration(minutes: 5))
        : await picker.pickImage(
            source: source, maxWidth: 2048, maxHeight: 2048, imageQuality: 80);
    if (file == null || !mounted) return;

    setState(() {
      _uploadProgress = 0;
      _uploadLabel = type == 'video' ? 'Sending video' : 'Sending photo';
    });
    final result = await _service.sendMedia(
      _group.id,
      file.path,
      type,
      onProgress: (p) {
        if (mounted) setState(() => _uploadProgress = p);
      },
    );
    if (!mounted) return;
    setState(() => _uploadProgress = null);
    if (result['success'] == true) {
      _lastMessageTime = DateTime.now();
      await _loadMessages(showLoading: false);
      _scrollToBottom();
    } else {
      NeonToast.error(context, (result['msg'] ?? 'Failed to send').toString());
    }
  }

  void _showAttachSheet() {
    if (!_permissions.canSendMedia) {
      NeonToast.info(context, 'Only admins can share media in this group');
      return;
    }
    // Close the keyboard first so the sheet isn't pushed up under the notch.
    FocusScope.of(context).unfocus();
    showGSheet<void>(
      context,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
        child: Row(
          children: [
            _attachOption(ctx, Icons.photo_rounded, 'Photo', GUI.accent,
                () => _pickMedia('image', ImageSource.gallery)),
            _attachOption(ctx, Icons.videocam_rounded, 'Video', GUI.info,
                () => _pickMedia('video', ImageSource.gallery)),
            _attachOption(ctx, Icons.photo_camera_rounded, 'Camera',
                GUI.success, () => _pickMedia('image', ImageSource.camera)),
            _attachOption(ctx, Icons.video_call_rounded, 'Record', GUI.warning,
                () => _pickMedia('video', ImageSource.camera)),
          ],
        ),
      ),
    );
  }

  Widget _attachOption(BuildContext ctx, IconData icon, String label,
      Color color, VoidCallback onTap) {
    return Expanded(
      child: GestureDetector(
        onTap: () {
          Navigator.pop(ctx);
          onTap();
        },
        child: Column(
          children: [
            GIconBox(icon, color: color, size: 56),
            const SizedBox(height: 8),
            Text(label,
                style: const TextStyle(color: GUI.textMid, fontSize: 12.5)),
          ],
        ),
      ),
    );
  }

  // ── Message actions ───────────────────────────────────────────────────────

  void _showMessageActions(GroupMessage msg) {
    if (msg.isSystem) return;
    HapticFeedback.selectionClick();
    final isMe = msg.senderId == _myId;
    final isMedia = ['image', 'video'].contains(msg.type);
    final canEdit = isMe && msg.type == 'text' && !msg.isDeleted;
    final canUnsendAll = !msg.isDeleted && (isMe || _isAdmin);

    showGSheet<void>(
      context,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (msg.type == 'text' && !msg.isDeleted)
              Container(
                margin: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                padding: const EdgeInsets.all(12),
                width: double.infinity,
                decoration: BoxDecoration(
                  color: GUI.surface2,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(msg.message,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: GUI.textMid, fontSize: 14)),
              ),
            if (msg.type == 'text' && !msg.isDeleted)
              GSheetAction(
                icon: Icons.copy_rounded,
                label: 'Copy',
                onTap: () {
                  Navigator.pop(ctx);
                  Clipboard.setData(ClipboardData(text: msg.message));
                  NeonToast.success(context, 'Copied');
                },
              ),
            if (canEdit)
              GSheetAction(
                icon: Icons.edit_outlined,
                label: 'Edit',
                onTap: () {
                  Navigator.pop(ctx);
                  _startEdit(msg);
                },
              ),
            if (isMedia && !msg.isDeleted)
              GSheetAction(
                icon: Icons.download_rounded,
                label: 'Save to gallery',
                onTap: () {
                  Navigator.pop(ctx);
                  _downloadMedia(_mediaUrl(msg.message), msg.type);
                },
              ),
            if (!isMe)
              GSheetAction(
                icon: Icons.person_outline_rounded,
                label: 'View ${msg.senderName.split(' ').first}\'s profile',
                onTap: () {
                  Navigator.pop(ctx);
                  _viewUser(msg);
                },
              ),
            GSheetAction(
              icon: Icons.delete_outline_rounded,
              label: canUnsendAll ? 'Unsend' : 'Delete for me',
              destructive: true,
              onTap: () {
                Navigator.pop(ctx);
                if (canUnsendAll) {
                  _showUnsendOptions(msg, isMe);
                } else {
                  _deleteForMe(msg);
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showUnsendOptions(GroupMessage msg, bool isMe) {
    showGSheet<void>(
      context,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.only(top: 4, bottom: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            GSheetHeader(
              title: 'Unsend message?',
              subtitle: isMe
                  ? 'Choose who this message is removed for.'
                  : 'As an admin you can remove this message for everyone.',
            ),
            GSheetAction(
              icon: Icons.groups_outlined,
              label: 'Unsend for everyone',
              subtitle: 'Removed for all members of the group',
              destructive: true,
              onTap: () {
                Navigator.pop(ctx);
                _unsendForEveryone(msg);
              },
            ),
            GSheetAction(
              icon: Icons.person_outline_rounded,
              label: 'Delete for me',
              subtitle: 'Others will still see it',
              onTap: () {
                Navigator.pop(ctx);
                _deleteForMe(msg);
              },
            ),
            GSheetAction(
              icon: Icons.close_rounded,
              label: 'Cancel',
              color: GUI.textLo,
              onTap: () => Navigator.pop(ctx),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteForMe(GroupMessage msg) async {
    final idx = _messages.indexWhere((m) => m.id == msg.id);
    if (idx == -1) return;
    setState(() => _messages.removeAt(idx));
    final r = await _service.deleteMessage(msg.id, scope: 'me');
    if (!mounted) return;
    if (!r.success) {
      setState(() {
        _messages.insert(idx.clamp(0, _messages.length), msg);
      });
      NeonToast.error(context, r.message);
    }
  }

  Future<void> _unsendForEveryone(GroupMessage msg) async {
    final idx = _messages.indexWhere((m) => m.id == msg.id);
    if (idx == -1) return;
    setState(() =>
        _messages[idx] = msg.copyWith(message: '', isDeleted: true));
    final r = await _service.deleteMessage(msg.id, scope: 'everyone');
    if (!mounted) return;
    if (!r.success) {
      final j = _messages.indexWhere((m) => m.id == msg.id);
      if (j != -1) setState(() => _messages[j] = msg);
      NeonToast.error(context, r.message);
    }
  }

  void _startEdit(GroupMessage msg) {
    setState(() => _editing = msg);
    _msgController.value = TextEditingValue(
      text: msg.message,
      selection: TextSelection.collapsed(offset: msg.message.length),
    );
    _inputFocus.requestFocus();
  }

  void _cancelEdit() {
    setState(() => _editing = null);
    _msgController.clear();
  }

  Future<void> _submitEdit(String text) async {
    final msg = _editing!;
    if (text == msg.message) {
      _cancelEdit();
      return;
    }
    final idx = _messages.indexWhere((m) => m.id == msg.id);
    setState(() {
      _editing = null;
      if (idx != -1) {
        _messages[idx] = msg.copyWith(message: text, isEdited: true);
      }
    });
    _msgController.clear();
    final r = await _service.editMessage(msg.id, text);
    if (!mounted) return;
    if (!r.success) {
      final j = _messages.indexWhere((m) => m.id == msg.id);
      if (j != -1) setState(() => _messages[j] = msg);
      NeonToast.error(context, r.message);
    }
  }

  // ── Voice recording ───────────────────────────────────────────────────────

  Future<void> _startRecording() async {
    if (!_permissions.canSendVoice) {
      NeonToast.info(context, 'Only admins can send voice messages here');
      return;
    }
    if (!_canSendNow()) return;
    final status = await Permission.microphone.request();
    if (!mounted) return;
    if (!status.isGranted) {
      NeonToast.error(context, 'Microphone permission required');
      return;
    }
    try {
      if (await _audioRecorder.hasPermission()) {
        final dir = await getTemporaryDirectory();
        final path =
            '${dir.path}/grp_voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
        await _audioRecorder.start(const RecordConfig(), path: path);
        if (!mounted) return;
        HapticFeedback.mediumImpact();
        setState(() {
          _isRecording = true;
          _recordDuration = Duration.zero;
        });
        _recordTimer = Timer.periodic(const Duration(seconds: 1), (_) {
          if (mounted) {
            setState(() =>
                _recordDuration = Duration(seconds: _recordDuration.inSeconds + 1));
          }
        });
      }
    } catch (_) {
      if (mounted) NeonToast.error(context, 'Failed to start recording');
    }
  }

  Future<void> _stopAndSendRecording() async {
    if (_isSending || !_isRecording) return;
    _recordTimer?.cancel();
    setState(() => _isRecording = false);
    try {
      final path = await _audioRecorder.stop();
      if (path != null && _recordDuration.inSeconds > 0) {
        setState(() {
          _uploadProgress = 0;
          _uploadLabel = 'Sending voice message';
        });
        final result = await _service.sendVoiceMessage(
            _group.id, path, _recordDuration);
        if (!mounted) return;
        setState(() {
          _uploadProgress = null;
          _recordDuration = Duration.zero;
        });
        if (result['success'] == true) {
          _lastMessageTime = DateTime.now();
          await _loadMessages(showLoading: false);
          _scrollToBottom();
        } else {
          NeonToast.error(context, (result['msg'] ?? 'Failed to send voice').toString());
        }
      } else {
        setState(() => _recordDuration = Duration.zero);
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _uploadProgress = null;
          _recordDuration = Duration.zero;
        });
      }
    }
  }

  void _cancelRecording() {
    _recordTimer?.cancel();
    _audioRecorder.stop();
    setState(() {
      _isRecording = false;
      _recordDuration = Duration.zero;
    });
  }

  Future<void> _playVoiceMessage(GroupMessage msg) async {
    if (_playingMsgId == msg.id) {
      await _audioPlayer.pause();
      _positionSub?.cancel();
      _completionSub?.cancel();
      setState(() => _playingMsgId = null);
      return;
    }
    _positionSub?.cancel();
    _completionSub?.cancel();
    try {
      final url = _mediaUrl(msg.message);
      setState(() {
        _playingMsgId = msg.id;
        _playPosition = Duration.zero;
      });
      _positionSub = _audioPlayer.onPositionChanged.listen((pos) {
        if (mounted) setState(() => _playPosition = pos);
      });
      _completionSub = _audioPlayer.onPlayerComplete.listen((_) {
        if (mounted) {
          setState(() {
            _playingMsgId = null;
            _playPosition = Duration.zero;
          });
        }
      });
      await _audioPlayer.play(await FastAudio.source(url));
    } catch (_) {
      _positionSub?.cancel();
      _completionSub?.cancel();
      if (mounted) {
        setState(() => _playingMsgId = null);
        NeonToast.error(context, 'Error playing audio');
      }
    }
  }

  // ── Media helpers ─────────────────────────────────────────────────────────

  Future<Uint8List?> _videoThumb(String url) {
    return _thumbCache.putIfAbsent(url, () async {
      try {
        return await VideoThumbnail.thumbnailData(
          video: url,
          imageFormat: ImageFormat.JPEG,
          maxWidth: 480,
          quality: 70,
        );
      } catch (_) {
        return null;
      }
    });
  }

  Future<void> _downloadMedia(String url, String type) async {
    NeonToast.info(context, 'Saving…');
    try {
      final hasAccess = await Gal.requestAccess(toAlbum: true);
      if (!hasAccess) {
        if (mounted) NeonToast.error(context, 'Gallery permission required');
        return;
      }
      final tmpDir = await getTemporaryDirectory();
      final ts = DateTime.now().millisecondsSinceEpoch;
      final ext = type == 'video' ? 'mp4' : 'jpg';
      final dlPath = '${tmpDir.path}/goreto_$ts.$ext';
      await Dio().download(url, dlPath);
      if (type == 'image') {
        final raw = await File(dlPath).readAsBytes();
        final wm = await addGoretoWatermark(raw);
        final wmPath = '${tmpDir.path}/goreto_wm_$ts.png';
        await File(wmPath).writeAsBytes(wm);
        await Gal.putImage(wmPath, album: 'Goreto');
      } else {
        await Gal.putVideo(dlPath, album: 'Goreto');
      }
      if (mounted) NeonToast.success(context, 'Saved to gallery');
    } catch (_) {
      if (mounted) NeonToast.error(context, 'Download failed');
    }
  }

  void _openMediaViewer(String url, String type) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => _GrpMediaViewerScreen(url: url, type: type)),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  List<_Entry> _buildEntries() {
    final entries = <_Entry>[];
    DateTime? lastDay;
    for (var i = 0; i < _messages.length; i++) {
      final m = _messages[i];
      final day = DateTime(m.createdAt.year, m.createdAt.month, m.createdAt.day);
      if (lastDay == null || day != lastDay) {
        entries.add(_Entry.day(day));
        lastDay = day;
      }
      bool sameRun(GroupMessage? a, GroupMessage b) =>
          a != null &&
          !a.isSystem &&
          !b.isSystem &&
          a.senderId == b.senderId &&
          b.createdAt.difference(a.createdAt).inMinutes.abs() < 5 &&
          a.createdAt.day == b.createdAt.day;
      final prev = i > 0 ? _messages[i - 1] : null;
      final next = i < _messages.length - 1 ? _messages[i + 1] : null;
      entries.add(_Entry.message(
        m,
        firstInRun: !sameRun(prev, m),
        lastInRun: next == null || !sameRun(m, next),
      ));
    }
    return entries.reversed.toList();
  }

  @override
  Widget build(BuildContext context) {
    final entries = _buildEntries();
    return Scaffold(
      backgroundColor: GUI.bg,
      appBar: _buildAppBar(),
      body: Column(
        children: [
          if (_isAdmin && _group.pendingRequests > 0) _requestsBanner(),
          Expanded(
            child: _isLoading && _messages.isEmpty
                ? const Center(
                    child: CircularProgressIndicator(
                        color: GUI.accent, strokeWidth: 2))
                : _messages.isEmpty
                    ? _emptyChat()
                    : ListView.builder(
                        controller: _scrollController,
                        reverse: true,
                        keyboardDismissBehavior:
                            ScrollViewKeyboardDismissBehavior.onDrag,
                        padding: const EdgeInsets.fromLTRB(10, 12, 10, 12),
                        itemCount: entries.length,
                        itemBuilder: (_, i) {
                          final e = entries[i];
                          if (e.day != null) return _daySeparator(e.day!);
                          return _buildMessage(e);
                        },
                      ),
          ),
          if (_uploadProgress != null) _uploadBar(),
          _notMember ? _notMemberBar() : _buildComposer(),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    final canInvite = _isAdmin || _group.membersCanInvite;
    return AppBar(
      backgroundColor: GUI.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      titleSpacing: 0,
      shape: const Border(bottom: BorderSide(color: GUI.border)),
      title: InkWell(
        onTap: _openInfo,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              GroupAvatar.of(_group, size: 40),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_group.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: GUI.textHi,
                            fontWeight: FontWeight.w700,
                            fontSize: 16.5)),
                    const SizedBox(height: 1),
                    Row(
                      children: [
                        if (_group.isPrivate) ...[
                          const Icon(Icons.lock_rounded,
                              size: 11, color: GUI.textLo),
                          const SizedBox(width: 3),
                        ],
                        Flexible(
                          child: Text(
                            _group.memberCount > 0
                                ? formatMemberCount(_group.memberCount)
                                : 'Tap for group info',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: GUI.textLo, fontSize: 12.5),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        if (canInvite && !_notMember)
          IconButton(
            tooltip: 'Add members',
            icon: const Icon(Icons.person_add_alt_1_outlined, color: GUI.textHi),
            onPressed: _addMembers,
          ),
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert_rounded, color: GUI.textHi),
          color: GUI.surface2,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          onSelected: (v) {
            switch (v) {
              case 'info':
                _openInfo();
                break;
              case 'add':
                _addMembers();
                break;
              case 'requests':
                _openRequests();
                break;
            }
          },
          itemBuilder: (_) => [
            _menuItem('info', Icons.info_outline_rounded, 'Group info'),
            if (canInvite && !_notMember)
              _menuItem('add', Icons.person_add_alt_1_outlined, 'Add members'),
            if (_isAdmin)
              _menuItem('requests', Icons.how_to_reg_outlined,
                  _group.pendingRequests > 0
                      ? 'Join requests (${_group.pendingRequests})'
                      : 'Requests & invites'),
          ],
        ),
      ],
    );
  }

  PopupMenuItem<String> _menuItem(String value, IconData icon, String label) {
    return PopupMenuItem<String>(
      value: value,
      child: Row(
        children: [
          Icon(icon, color: GUI.textMid, size: 20),
          const SizedBox(width: 12),
          Text(label, style: const TextStyle(color: GUI.textHi)),
        ],
      ),
    );
  }

  Widget _requestsBanner() {
    final n = _group.pendingRequests;
    return Material(
      color: GUI.accent.withValues(alpha: 0.1),
      child: InkWell(
        onTap: _openRequests,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              const Icon(Icons.how_to_reg_rounded, color: GUI.accent, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  n == 1
                      ? '1 person wants to join'
                      : '$n people want to join',
                  style: const TextStyle(
                      color: GUI.textHi, fontSize: 13.5, fontWeight: FontWeight.w500),
                ),
              ),
              const Text('Review',
                  style: TextStyle(
                      color: GUI.accent, fontWeight: FontWeight.w700, fontSize: 13.5)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _emptyChat() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            GroupAvatar.of(_group, size: 76),
            const SizedBox(height: 16),
            Text(_group.name,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: GUI.textHi, fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            const Text('No messages yet. Say hi 👋',
                style: TextStyle(color: GUI.textLo, fontSize: 13.5)),
          ],
        ),
      ),
    );
  }

  Widget _daySeparator(DateTime day) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final diff = today.difference(day).inDays;
    final label = diff == 0
        ? 'Today'
        : diff == 1
            ? 'Yesterday'
            : diff < 7
                ? DateFormat.EEEE().format(day)
                : DateFormat('d MMM yyyy').format(day);
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 14),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: GUI.surface2,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(label,
            style: const TextStyle(
                color: GUI.textLo, fontSize: 11.5, fontWeight: FontWeight.w600)),
      ),
    );
  }

  Widget _uploadBar() {
    final p = (_uploadProgress ?? 0).clamp(0.0, 1.0);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      color: GUI.surface,
      child: Row(
        children: [
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2, color: GUI.accent),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                    p >= 0.999
                        ? '$_uploadLabel… processing'
                        : '$_uploadLabel… ${(p * 100).round()}%',
                    style: const TextStyle(color: GUI.textMid, fontSize: 12.5)),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: p >= 0.999 ? null : p,
                    minHeight: 3,
                    color: GUI.accent,
                    backgroundColor: GUI.surface2,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _notMemberBar() {
    return SafeArea(
      top: false,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: const BoxDecoration(
          color: GUI.surface,
          border: Border(top: BorderSide(color: GUI.border)),
        ),
        child: const Text(
          'You\'re no longer a member of this group.',
          textAlign: TextAlign.center,
          style: TextStyle(color: GUI.textLo, fontSize: 13.5),
        ),
      ),
    );
  }

  // ── Messages ──────────────────────────────────────────────────────────────

  Widget _buildMessage(_Entry e) {
    final msg = e.msg!;
    if (msg.isSystem) {
      return Center(
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 30),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(msg.message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: GUI.textLo, fontSize: 12)),
        ),
      );
    }

    final isMe = msg.senderId == _myId;
    final maxW = MediaQuery.of(context).size.width * 0.72;
    final showAvatar = !isMe && e.lastInRun;
    final showName = !isMe && e.firstInRun;

    final Widget content;
    if (msg.isDeleted) {
      content = _deletedBubble(msg, isMe, e);
    } else if (msg.type == 'audio') {
      content = _bubbleShell(
          isMe: isMe, e: e, showName: showName, msg: msg,
          child: _buildVoiceBubble(msg, isMe));
    } else if (msg.type == 'video') {
      content = _mediaShell(msg, isMe, e, showName, _buildVideo(msg, maxW));
    } else if (msg.type == 'image') {
      content = _mediaShell(msg, isMe, e, showName, _buildImage(msg, maxW));
    } else {
      content = _bubbleShell(
        isMe: isMe,
        e: e,
        showName: showName,
        msg: msg,
        child: Text(msg.message,
            style: const TextStyle(color: Colors.white, fontSize: 15, height: 1.3)),
      );
    }

    return Padding(
      padding: EdgeInsets.only(top: e.firstInRun ? 8 : 2),
      child: Row(
        mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isMe)
            SizedBox(
              width: 38,
              child: showAvatar
                  ? GestureDetector(
                      onTap: () => _viewUser(msg),
                      child: UserAvatar(
                          url: msg.senderAvatarUrl,
                          name: msg.senderName,
                          seed: msg.senderId,
                          size: 30),
                    )
                  : null,
            ),
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxW),
            child: GestureDetector(
              onLongPress: () => _showMessageActions(msg),
              child: content,
            ),
          ),
        ],
      ),
    );
  }

  BorderRadius _radius(bool isMe, _Entry e) {
    const big = Radius.circular(18);
    const small = Radius.circular(5);
    if (isMe) {
      return BorderRadius.only(
        topLeft: big,
        bottomLeft: big,
        topRight: e.firstInRun ? big : small,
        bottomRight: e.lastInRun ? big : small,
      );
    }
    return BorderRadius.only(
      topRight: big,
      bottomRight: big,
      topLeft: e.firstInRun ? big : small,
      bottomLeft: e.lastInRun ? big : small,
    );
  }

  Widget _meta(GroupMessage msg, {Color color = const Color(0x99FFFFFF)}) {
    return Text(
      '${msg.isEdited ? 'edited · ' : ''}${DateFormat.jm().format(msg.createdAt)}',
      style: TextStyle(color: color, fontSize: 10.5),
    );
  }

  Widget _senderName(GroupMessage msg) {
    final c = GUI.gradientFor(msg.senderId).last;
    return GestureDetector(
      onTap: () => _viewUser(msg),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 3),
        child: Text(msg.senderName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: c, fontSize: 12.5, fontWeight: FontWeight.w700)),
      ),
    );
  }

  Widget _bubbleShell({
    required bool isMe,
    required _Entry e,
    required bool showName,
    required GroupMessage msg,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 7),
      decoration: BoxDecoration(
        gradient: isMe
            ? const LinearGradient(
                colors: [Color(0xFFC03BDB), Color(0xFF7C4DEB)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight)
            : null,
        color: isMe ? null : GUI.surface2,
        borderRadius: _radius(isMe, e),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showName) _senderName(msg),
          child,
          const SizedBox(height: 3),
          Align(alignment: Alignment.bottomRight, widthFactor: 1, child: _meta(msg)),
        ],
      ),
    );
  }

  Widget _deletedBubble(GroupMessage msg, bool isMe, _Entry e) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 9, 12, 8),
      decoration: BoxDecoration(
        borderRadius: _radius(isMe, e),
        border: Border.all(color: const Color(0x26FFFFFF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!isMe && e.firstInRun) _senderName(msg),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.block_rounded, size: 14, color: GUI.textLo),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  isMe ? 'You unsent a message' : 'This message was unsent',
                  style: const TextStyle(
                      color: GUI.textLo, fontSize: 13.5, fontStyle: FontStyle.italic),
                ),
              ),
              const SizedBox(width: 8),
              _meta(msg, color: GUI.textLo),
            ],
          ),
        ],
      ),
    );
  }

  Widget _mediaShell(
      GroupMessage msg, bool isMe, _Entry e, bool showName, Widget media) {
    return Column(
      crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showName)
          Padding(padding: const EdgeInsets.only(left: 4), child: _senderName(msg)),
        ClipRRect(
          borderRadius: _radius(isMe, e),
          child: Stack(
            children: [
              media,
              Positioned(
                right: 8,
                bottom: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: _meta(msg, color: Colors.white),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildImage(GroupMessage msg, double maxW) {
    final url = _mediaUrl(msg.message);
    final w = maxW;
    final h = maxW * 0.8;
    final dpr = MediaQuery.of(context).devicePixelRatio;
    return GestureDetector(
      onTap: () => _openMediaViewer(url, 'image'),
      child: CachedNetworkImage(
        imageUrl: url,
        width: w,
        height: h,
        fit: BoxFit.cover,
        memCacheWidth: (w * dpr).round(),
        fadeInDuration: const Duration(milliseconds: 150),
        placeholder: (_, __) => Container(
          width: w,
          height: h,
          color: GUI.surface2,
          child: const Center(
            child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2, color: GUI.accent)),
          ),
        ),
        errorWidget: (_, __, ___) => Container(
          width: w,
          height: h,
          color: GUI.surface2,
          child: const Icon(Icons.broken_image_outlined, color: GUI.textLo, size: 36),
        ),
      ),
    );
  }

  Widget _buildVideo(GroupMessage msg, double maxW) {
    final url = _mediaUrl(msg.message);
    final w = maxW;
    final h = maxW * 0.62;
    return GestureDetector(
      onTap: () => _openMediaViewer(url, 'video'),
      child: SizedBox(
        width: w,
        height: h,
        child: Stack(
          fit: StackFit.expand,
          children: [
            FutureBuilder<Uint8List?>(
              future: _videoThumb(url),
              builder: (_, snap) {
                if (snap.hasData && snap.data != null && snap.data!.isNotEmpty) {
                  return Image.memory(snap.data!, fit: BoxFit.cover, gaplessPlayback: true);
                }
                return Container(
                  color: GUI.surface2,
                  child: const Icon(Icons.movie_outlined, color: GUI.textLo, size: 44),
                );
              },
            ),
            Container(color: Colors.black.withValues(alpha: 0.25)),
            Center(
              child: Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.5),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white.withValues(alpha: 0.8), width: 1.5),
                ),
                child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 32),
              ),
            ),
            Positioned(
              left: 8,
              bottom: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.videocam_rounded, color: Colors.white, size: 13),
                    SizedBox(width: 4),
                    Text('Video', style: TextStyle(color: Colors.white, fontSize: 10.5)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVoiceBubble(GroupMessage msg, bool isMe) {
    final isPlaying = _playingMsgId == msg.id;
    final total = msg.voiceDuration ?? Duration.zero;
    final totalMs = total.inMilliseconds > 0 ? total.inMilliseconds : 1;
    final posMs = isPlaying ? _playPosition.inMilliseconds : 0;
    final progress = (posMs / totalMs).clamp(0.0, 1.0);
    String fmt(Duration d) =>
        '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

    return GestureDetector(
      onTap: () => _playVoiceMessage(msg),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: isMe ? Colors.white.withValues(alpha: 0.22) : GUI.accent,
              shape: BoxShape.circle,
            ),
            child: Icon(isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                color: Colors.white, size: 22),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 130,
                height: 28,
                child: CustomPaint(
                  painter: _GrpWaveformPainter(
                      progress: progress,
                      color: isMe ? Colors.white : GUI.accent),
                ),
              ),
              Text(isPlaying ? fmt(_playPosition) : fmt(total),
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.8),
                      fontSize: 10.5,
                      fontFeatures: const [FontFeature.tabularFigures()])),
            ],
          ),
        ],
      ),
    );
  }

  // ── Composer ──────────────────────────────────────────────────────────────

  Widget _buildComposer() {
    final canText = _permissions.canSendText;
    final canMedia = _permissions.canSendMedia;
    final canVoice = _permissions.canSendVoice;
    final nothingAllowed = !canText && !canMedia && !canVoice;

    return Container(
      decoration: const BoxDecoration(
        color: GUI.surface,
        border: Border(top: BorderSide(color: GUI.border)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_editing != null)
              Container(
                padding: const EdgeInsets.fromLTRB(16, 10, 6, 0),
                child: Row(
                  children: [
                    const Icon(Icons.edit_rounded, color: GUI.accent, size: 18),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Edit message',
                              style: TextStyle(
                                  color: GUI.accent,
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700)),
                          Text(_editing!.message,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: GUI.textLo, fontSize: 12.5)),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, color: GUI.textLo, size: 20),
                      onPressed: _cancelEdit,
                    ),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
              child: nothingAllowed
                  ? const Padding(
                      padding: EdgeInsets.all(10),
                      child: Text('Only admins can send messages in this group',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: GUI.textLo, fontSize: 13.5)),
                    )
                  : _isRecording
                      ? _recordingRow()
                      : _inputRow(canText, canMedia, canVoice),
            ),
          ],
        ),
      ),
    );
  }

  Widget _inputRow(bool canText, bool canMedia, bool canVoice) {
    final showSend = _hasText || _editing != null;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (_editing == null)
          IconButton(
            icon: Icon(Icons.add_circle_outline_rounded,
                color: canMedia ? GUI.textMid : GUI.textLo.withValues(alpha: 0.3),
                size: 26),
            onPressed: canMedia ? _showAttachSheet : null,
          ),
        Expanded(
          child: Container(
            constraints: const BoxConstraints(minHeight: 44),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: GUI.surface2,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: GUI.border),
            ),
            child: TextField(
              controller: _msgController,
              focusNode: _inputFocus,
              enabled: canText || _editing != null,
              minLines: 1,
              maxLines: 5,
              textCapitalization: TextCapitalization.sentences,
              cursorColor: GUI.accent,
              style: const TextStyle(color: GUI.textHi, fontSize: 15),
              decoration: InputDecoration(
                hintText: canText ? 'Message' : 'Text messages are off',
                hintStyle: const TextStyle(color: GUI.textLo),
                border: InputBorder.none,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ),
        const SizedBox(width: 6),
        GestureDetector(
          onTap: showSend
              ? _sendMessage
              : (canVoice ? _startRecording : null),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              gradient: (showSend || canVoice) ? GUI.gradient : null,
              color: (showSend || canVoice) ? null : GUI.surface2,
              shape: BoxShape.circle,
            ),
            child: _isSending
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : Icon(
                    _editing != null
                        ? Icons.check_rounded
                        : (showSend ? Icons.send_rounded : Icons.mic_rounded),
                    color: Colors.white,
                    size: 21),
          ),
        ),
      ],
    );
  }

  Widget _recordingRow() {
    final d = _recordDuration;
    return Row(
      children: [
        IconButton(
          icon: const Icon(Icons.delete_outline_rounded, color: GUI.danger),
          onPressed: _cancelRecording,
        ),
        Expanded(
          child: Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: GUI.danger.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: GUI.danger.withValues(alpha: 0.35)),
            ),
            child: Row(
              children: [
                const Icon(Icons.fiber_manual_record_rounded,
                    color: GUI.danger, size: 14),
                const SizedBox(width: 8),
                Text(
                  '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}',
                  style: const TextStyle(
                      color: GUI.textHi,
                      fontSize: 15,
                      fontFeatures: [FontFeature.tabularFigures()]),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text('Recording…',
                      style: TextStyle(color: GUI.textLo, fontSize: 13)),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 6),
        GestureDetector(
          onTap: _stopAndSendRecording,
          child: Container(
            width: 44,
            height: 44,
            decoration:
                const BoxDecoration(gradient: GUI.gradient, shape: BoxShape.circle),
            child: const Icon(Icons.send_rounded, color: Colors.white, size: 21),
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Watermark helper (shared by the chat and the fullscreen viewer)
// ═══════════════════════════════════════════════════════════════════════════

Future<Uint8List> addGoretoWatermark(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes);
  final frame = await codec.getNextFrame();
  final image = frame.image;
  final w = image.width.toDouble();
  final h = image.height.toDouble();

  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, w, h));
  canvas.drawImage(image, Offset.zero, Paint());

  const wmText = 'goreto';
  const fontSize = 22.0;
  final builder = ui.ParagraphBuilder(ui.ParagraphStyle(
    textDirection: ui.TextDirection.ltr,
    fontSize: fontSize,
  ))
    ..pushStyle(ui.TextStyle(
      color: const Color(0xCCFFFFFF),
      fontSize: fontSize,
      fontWeight: ui.FontWeight.bold,
      letterSpacing: 2,
    ))
    ..addText(wmText);
  final para = builder.build()..layout(const ui.ParagraphConstraints(width: 300));
  final tw = para.longestLine;
  final th = para.height;

  const pad = 10.0;
  const margin = 16.0;
  final rx = w - tw - pad * 2 - margin;
  final ry = h - th - pad * 2 - margin;

  canvas.drawRRect(
    RRect.fromRectAndRadius(
        Rect.fromLTWH(rx, ry, tw + pad * 2, th + pad * 2), const Radius.circular(24)),
    Paint()..color = const Color(0xAA000000),
  );
  canvas.drawRRect(
    RRect.fromRectAndRadius(
        Rect.fromLTWH(rx, ry, 4, th + pad * 2), const Radius.circular(24)),
    Paint()..color = const Color(0xFFD946EF),
  );
  canvas.drawParagraph(para, Offset(rx + pad, ry + pad));

  final picture = recorder.endRecording();
  final result = await picture.toImage(image.width, image.height);
  final byteData = await result.toByteData(format: ui.ImageByteFormat.png);
  return byteData!.buffer.asUint8List();
}

// ═══════════════════════════════════════════════════════════════════════════
// Fullscreen media viewer (image + Chewie video)
// ═══════════════════════════════════════════════════════════════════════════

class _GrpMediaViewerScreen extends StatefulWidget {
  final String url;
  final String type; // 'image' | 'video'

  const _GrpMediaViewerScreen({required this.url, required this.type});

  @override
  State<_GrpMediaViewerScreen> createState() => _GrpMediaViewerScreenState();
}

class _GrpMediaViewerScreenState extends State<_GrpMediaViewerScreen> {
  VideoPlayerController? _vpCtrl;
  ChewieController? _chewieCtrl;
  bool _isDownloading = false;
  bool _videoReady = false;
  bool _videoError = false;

  @override
  void initState() {
    super.initState();
    if (widget.type == 'video') _initVideo();
  }

  Future<void> _initVideo() async {
    try {
      _vpCtrl = VideoPlayerController.networkUrl(Uri.parse(widget.url));
      await _vpCtrl!.initialize();
      if (!mounted) return;
      _chewieCtrl = ChewieController(
        videoPlayerController: _vpCtrl!,
        autoPlay: true,
        looping: false,
        allowFullScreen: true,
        allowMuting: true,
        materialProgressColors: ChewieProgressColors(
          playedColor: GUI.accent,
          handleColor: GUI.accent,
          backgroundColor: Colors.white24,
          bufferedColor: Colors.white38,
        ),
      );
      setState(() => _videoReady = true);
    } catch (_) {
      if (mounted) setState(() => _videoError = true);
    }
  }

  @override
  void dispose() {
    _chewieCtrl?.dispose();
    _vpCtrl?.dispose();
    super.dispose();
  }

  Future<void> _download() async {
    if (_isDownloading) return;
    setState(() => _isDownloading = true);
    try {
      final hasAccess = await Gal.requestAccess(toAlbum: true);
      if (!hasAccess) {
        if (mounted) NeonToast.error(context, 'Gallery permission required');
        return;
      }
      final tmpDir = await getTemporaryDirectory();
      final ts = DateTime.now().millisecondsSinceEpoch;
      final ext = widget.type == 'video' ? 'mp4' : 'jpg';
      final dlPath = '${tmpDir.path}/goreto_$ts.$ext';
      await Dio().download(widget.url, dlPath);
      if (widget.type == 'image') {
        final raw = await File(dlPath).readAsBytes();
        final wm = await addGoretoWatermark(raw);
        final wmPath = '${tmpDir.path}/goreto_wm_$ts.png';
        await File(wmPath).writeAsBytes(wm);
        await Gal.putImage(wmPath, album: 'Goreto');
      } else {
        await Gal.putVideo(dlPath, album: 'Goreto');
      }
      if (mounted) NeonToast.success(context, 'Saved to gallery');
    } catch (_) {
      if (mounted) NeonToast.error(context, 'Download failed');
    } finally {
      if (mounted) setState(() => _isDownloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black.withValues(alpha: 0.6),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          if (_isDownloading)
            const Padding(
              padding: EdgeInsets.all(14),
              child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
            )
          else
            IconButton(
              icon: const Icon(Icons.download_rounded, color: Colors.white),
              onPressed: _download,
              tooltip: 'Save to gallery',
            ),
        ],
      ),
      body: SafeArea(
        child: widget.type == 'video'
            ? _buildVideoPlayer()
            : InteractiveViewer(
                minScale: 0.5,
                maxScale: 5.0,
                child: Center(
                  child: CachedNetworkImage(
                    imageUrl: widget.url,
                    fit: BoxFit.contain,
                    placeholder: (_, __) => const Center(
                        child: CircularProgressIndicator(color: GUI.accent)),
                    errorWidget: (_, __, ___) =>
                        const Icon(Icons.broken_image, color: Colors.white38, size: 64),
                  ),
                ),
              ),
      ),
    );
  }

  Widget _buildVideoPlayer() {
    if (_videoError) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline_rounded, color: Colors.white38, size: 48),
            SizedBox(height: 12),
            Text('This video can\'t be played',
                style: TextStyle(color: Colors.white54, fontSize: 14)),
          ],
        ),
      );
    }
    if (!_videoReady || _chewieCtrl == null) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: GUI.accent),
            SizedBox(height: 14),
            Text('Loading video…', style: TextStyle(color: Colors.white54, fontSize: 13)),
          ],
        ),
      );
    }
    return Chewie(controller: _chewieCtrl!);
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Waveform painter
// ═══════════════════════════════════════════════════════════════════════════

class _GrpWaveformPainter extends CustomPainter {
  final double progress;
  final Color color;

  static const List<double> _heights = [
    8, 14, 10, 22, 7, 18, 26, 12, 20, 6,
    24, 11, 17, 8, 22, 15, 9, 20, 7, 18,
    13, 20, 6, 22, 16, 10, 8, 19, 24, 11,
  ];

  const _GrpWaveformPainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    const bars = 30;
    const barW = 2.4;
    final gap = (size.width - bars * barW) / (bars - 1);
    for (int i = 0; i < bars; i++) {
      final isActive = (i / bars) <= progress;
      final h = _heights[i].clamp(4.0, size.height);
      final x = i * (barW + gap) + barW / 2;
      final y1 = (size.height - h) / 2;
      canvas.drawLine(
        Offset(x, y1),
        Offset(x, y1 + h),
        Paint()
          ..color = isActive ? color : color.withValues(alpha: 0.3)
          ..strokeWidth = barW
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(_GrpWaveformPainter old) =>
      progress != old.progress || color != old.color;
}
