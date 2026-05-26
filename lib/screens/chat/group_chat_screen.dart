import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:love_vibe_pro/core/theme.dart';
import 'package:love_vibe_pro/models/group_chat.dart';
import 'package:love_vibe_pro/providers/auth_provider.dart';
import 'package:love_vibe_pro/services/group_chat_service.dart';
import 'package:love_vibe_pro/services/profile_service.dart';
import 'package:love_vibe_pro/utils/date_util.dart';
import 'package:love_vibe_pro/screens/chat/group_settings_screen.dart';
import 'package:love_vibe_pro/config/app_env.dart';
import 'package:love_vibe_pro/screens/match/profile_preview_screen.dart';
import 'package:love_vibe_pro/models/match_user.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:image_picker/image_picker.dart';
import 'package:love_vibe_pro/widgets/neon_toast.dart';
import 'package:record/record.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import 'package:dio/dio.dart';
import 'package:gal/gal.dart';
import 'package:video_thumbnail/video_thumbnail.dart';

class GroupChatScreen extends StatefulWidget {
  final ChatGroup group;

  const GroupChatScreen({super.key, required this.group});

  @override
  State<GroupChatScreen> createState() => _GroupChatScreenState();
}

class _GroupChatScreenState extends State<GroupChatScreen> {
  late GroupChatService _service;
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _msgController = TextEditingController();

  final List<GroupMessage> _messages = [];
  bool _isLoading = true;
  bool _isSending = false;
  bool _isSyncing = false;
  bool _isDownloading = false;
  Timer? _timer;
  Timer? _delayTimer;
  int _myId = 0;
  GroupPermissions _permissions = const GroupPermissions();
  int _messageDelay = 0;
  DateTime? _lastMessageTime;
  final Map<String, Uint8List?> _thumbCache = {};

  // ── Voice recording ──────────────────────────────────────────────────────
  final AudioRecorder _audioRecorder = AudioRecorder();
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isRecording = false;
  Duration _recordDuration = Duration.zero;
  Timer? _recordTimer;
  bool _hasText = false;

  // ── Voice playback ───────────────────────────────────────────────────────
  int? _playingMsgId;
  Duration _playPosition = Duration.zero;
  StreamSubscription? _positionSub;
  StreamSubscription? _completionSub;

  @override
  void initState() {
    super.initState();
    final auth = Provider.of<AuthProvider>(context, listen: false);
    _myId = int.tryParse(auth.currentUserId ?? '0') ?? 0;
    _service = GroupChatService();
    _msgController.addListener(() {
      final has = _msgController.text.trim().isNotEmpty;
      if (has != _hasText) setState(() => _hasText = has);
    });
    _loadMessages();
    _loadGroupSettings();
    _timer = Timer.periodic(const Duration(seconds: 2), (_) {
      _loadMessages(showLoading: false);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _delayTimer?.cancel();
    _recordTimer?.cancel();
    _positionSub?.cancel();
    _completionSub?.cancel();
    _scrollController.dispose();
    _msgController.dispose();
    _audioRecorder.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }

  String _getMediaUrl(String path) {
    if (path.startsWith('http')) return path;
    final base = AppEnv.liveBaseUrl.endsWith('/')
        ? AppEnv.liveBaseUrl.substring(0, AppEnv.liveBaseUrl.length - 1)
        : AppEnv.liveBaseUrl;
    return '$base${path.startsWith('/') ? path : '/$path'}';
  }

  Future<void> _loadGroupSettings() async {
    try {
      final group = await _service.getGroupDetails(widget.group.id);
      if (mounted && group != null) {
        setState(() {
          _permissions = group.permissions;
          _messageDelay = group.messageDelay;
        });
      }
    } catch (_) {}
  }

  Future<void> _loadMessages({bool showLoading = true}) async {
    if (_isSyncing) return;
    _isSyncing = true;
    if (showLoading && mounted) setState(() => _isLoading = true);
    try {
      final lastId = _messages.isNotEmpty ? _messages.last.id : 0;
      final newMessages = await _service.syncMessages(
        widget.group.id,
        lastId: lastId,
      );

      if (mounted && newMessages.isNotEmpty) {
        setState(() {
          _messages.addAll(newMessages);
          _isLoading = false;
        });
        _scrollToBottom();
      } else if (mounted) {
        setState(() => _isLoading = false);
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    } finally {
      _isSyncing = false;
    }
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      Future.delayed(const Duration(milliseconds: 100), () {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  bool _canSendMessage() {
    if (_messageDelay > 0 && _lastMessageTime != null) {
      final elapsed = DateTime.now().difference(_lastMessageTime!).inSeconds;
      if (elapsed < _messageDelay) {
        final remaining = _messageDelay - elapsed;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Please wait $remaining seconds before sending another message'),
          backgroundColor: Colors.orange,
        ));
        return false;
      }
    }
    return true;
  }

  void _viewUserProfile(int userId) async {
    try {
      setState(() => _isLoading = true);
      final profileService = ProfileService();
      final userProfile = await profileService.getUserProfile(userId.toString());
      if (mounted) setState(() => _isLoading = false);
      if (mounted) {
        final matchUser = MatchUser.fromJson(userProfile.toJson());
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => ProfilePreviewScreen(user: matchUser)),
        );
      } else if (mounted) {
        NeonToast.error(context, 'Could not load user profile');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        NeonToast.error(context, 'Error loading profile');
      }
    }
  }

  void _sendMessage() async {
    if (_isSending) return;
    if (!_permissions.canSendText) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Text messaging is disabled in this group'),
        backgroundColor: Colors.orange,
      ));
      return;
    }
    if (!_canSendMessage()) return;

    final text = _msgController.text.trim();
    if (text.isEmpty) return;
    setState(() => _isSending = true);
    _msgController.clear();
    await _service.sendMessage(widget.group.id, text);
    _lastMessageTime = DateTime.now();
    if (mounted) setState(() => _isSending = false);
    _loadMessages(showLoading: false);
  }

  Future<void> _pickImage() async {
    if (!_permissions.canSendMedia) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Media sharing is disabled in this group'),
        backgroundColor: Colors.orange,
      ));
      return;
    }

    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery, imageQuality: 70);
    if (pickedFile != null) {
      setState(() => _isSending = true);
      final result = await _service.sendMedia(widget.group.id, pickedFile.path, 'image');
      if (mounted) {
        setState(() => _isSending = false);
        if (result['success'] == true) {
          NeonToast.success(context, 'Media sent');
          _loadMessages(showLoading: false);
        } else {
          NeonToast.error(context, result['msg'] ?? 'Failed to send media');
        }
      }
    }
  }

  // ── Voice recording ────────────────────────────────────────────────────────
  Future<void> _startRecording() async {
    if (!_permissions.canSendVoice) {
      NeonToast.error(context, 'Voice messages are disabled in this group');
      return;
    }
    final status = await Permission.microphone.request();
    if (!mounted) return;
    if (!status.isGranted) {
      NeonToast.error(context, 'Microphone permission required');
      return;
    }
    try {
      if (await _audioRecorder.hasPermission()) {
        final dir = await getTemporaryDirectory();
        final path = '${dir.path}/grp_voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
        await _audioRecorder.start(const RecordConfig(), path: path);
        if (!mounted) return;
        setState(() {
          _isRecording = true;
          _recordDuration = Duration.zero;
        });
        _recordTimer = Timer.periodic(const Duration(seconds: 1), (_) {
          setState(() => _recordDuration = Duration(seconds: _recordDuration.inSeconds + 1));
        });
      }
    } catch (e) {
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
        setState(() => _isSending = true);
        final result = await _service.sendVoiceMessage(widget.group.id, path, _recordDuration);
        if (mounted) {
          setState(() { _isSending = false; _recordDuration = Duration.zero; });
          if (result['success'] == true) {
            _loadMessages(showLoading: false);
          } else {
            NeonToast.error(context, result['msg'] ?? 'Failed to send voice');
          }
        }
      } else {
        setState(() => _recordDuration = Duration.zero);
      }
    } catch (_) {
      if (mounted) setState(() { _isSending = false; _recordDuration = Duration.zero; });
    }
  }

  void _cancelRecording() {
    _recordTimer?.cancel();
    _audioRecorder.stop();
    setState(() { _isRecording = false; _recordDuration = Duration.zero; });
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
      final url = _getMediaUrl(msg.message);
      setState(() {
        _playingMsgId = msg.id;
        _playPosition = Duration.zero;
      });
      _positionSub = _audioPlayer.onPositionChanged.listen((pos) {
        if (mounted) setState(() => _playPosition = pos);
      });
      _completionSub = _audioPlayer.onPlayerComplete.listen((_) {
        if (mounted) setState(() { _playingMsgId = null; _playPosition = Duration.zero; });
      });
      await _audioPlayer.play(UrlSource(url));
    } catch (e) {
      _positionSub?.cancel();
      _completionSub?.cancel();
      if (mounted) setState(() => _playingMsgId = null);
      if (mounted) NeonToast.error(context, 'Error playing audio');
    }
  }

  // ── Video thumbnail ────────────────────────────────────────────────────────
  Future<Uint8List?> _getVideoThumbnail(String url) async {
    if (_thumbCache.containsKey(url)) return _thumbCache[url];
    try {
      final data = await VideoThumbnail.thumbnailData(
        video: url,
        imageFormat: ImageFormat.JPEG,
        maxWidth: 480,
        quality: 70,
      );
      _thumbCache[url] = data;
      return data;
    } catch (_) {
      _thumbCache[url] = null;
      return null;
    }
  }

  // ── Download + watermark ───────────────────────────────────────────────────
  Future<void> _downloadMedia(String url, String type) async {
    if (_isDownloading) return;
    setState(() => _isDownloading = true);
    if (mounted) NeonToast.success(context, 'Saving…');
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
        final watermarked = await _addWatermark(raw);
        final wmPath = '${tmpDir.path}/goreto_wm_$ts.png';
        await File(wmPath).writeAsBytes(watermarked);
        await Gal.putImage(wmPath, album: 'Goreto');
      } else {
        await Gal.putVideo(dlPath, album: 'Goreto');
      }

      if (mounted) NeonToast.success(context, 'Saved to gallery ✓');
    } catch (e) {
      if (mounted) NeonToast.error(context, 'Download failed');
    } finally {
      if (mounted) setState(() => _isDownloading = false);
    }
  }

  Future<Uint8List> _addWatermark(Uint8List bytes) async {
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
        Rect.fromLTWH(rx, ry, tw + pad * 2, th + pad * 2),
        const Radius.circular(24),
      ),
      Paint()..color = const Color(0xAA000000),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(rx, ry, 4, th + pad * 2),
        const Radius.circular(24),
      ),
      Paint()..color = const Color(0xFFD946EF),
    );
    canvas.drawParagraph(para, Offset(rx + pad, ry + pad));

    final picture = recorder.endRecording();
    final result = await picture.toImage(image.width, image.height);
    final byteData = await result.toByteData(format: ui.ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
  }

  // ── Fullscreen viewer ──────────────────────────────────────────────────────
  void _openMediaViewer(String url, String type) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _GrpMediaViewerScreen(url: url, type: type),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        backgroundColor: const Color(0xFF0A0A0A),
        appBar: AppBar(
          titleSpacing: 0,
          title: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: const Color(0xFFD946EF),
                backgroundImage: widget.group.avatarUrl != null
                    ? CachedNetworkImageProvider(widget.group.avatarUrl!)
                    : null,
                child: widget.group.avatarUrl == null
                    ? Text(widget.group.name[0].toUpperCase(),
                        style: const TextStyle(color: Colors.white, fontSize: 12))
                    : null,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  widget.group.name,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.info_outline, color: Colors.white),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => GroupSettingsScreen(group: widget.group)),
              ).then((_) => _loadMessages(showLoading: false)),
            ),
          ],
          backgroundColor: const Color(0xFF1A1A1A),
          elevation: 0,
          automaticallyImplyLeading: true,
        ),
        body: Column(
          children: [
            Expanded(
              child: _isLoading && _messages.isEmpty
                  ? const Center(
                      child: CircularProgressIndicator(color: GalacticTheme.laserPink),
                    )
                  : ListView.builder(
                      controller: _scrollController,
                      padding: EdgeInsets.only(
                        left: MediaQuery.of(context).size.width * 0.03,
                        right: MediaQuery.of(context).size.width * 0.03,
                        top: 16,
                        bottom: 16,
                      ),
                      itemCount: _messages.length,
                      itemBuilder: (context, i) {
                        final isMe = _messages[i].senderId == _myId;
                        return _buildMessageBubble(_messages[i], isMe);
                      },
                    ),
            ),
            _buildInputArea(),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageBubble(GroupMessage msg, bool isMe) {
    final screenWidth = MediaQuery.of(context).size.width;
    final maxMediaWidth = screenWidth * 0.62;

    if (msg.type == 'system') {
      return Center(
        child: Container(
          margin: const EdgeInsets.only(bottom: 20),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white12,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(msg.message,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              textAlign: TextAlign.center),
        ),
      );
    }

    final noPadding = msg.type == 'image' || msg.type == 'video' ||
        (msg.message.contains('/uploads/chat') && msg.type != 'audio' && msg.type != 'text');

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isMe)
            Padding(
              padding: const EdgeInsets.only(right: 6.0),
              child: GestureDetector(
                onTap: () => _viewUserProfile(msg.senderId),
                child: CircleAvatar(
                  radius: 14,
                  backgroundColor: Colors.blueGrey,
                  backgroundImage: msg.senderAvatarUrl != null
                      ? CachedNetworkImageProvider(msg.senderAvatarUrl!)
                      : null,
                  child: msg.senderAvatarUrl == null
                      ? Text(
                          msg.senderName.isNotEmpty ? msg.senderName[0].toUpperCase() : '?',
                          style: const TextStyle(color: Colors.white, fontSize: 10))
                      : null,
                ),
              ),
            ),
          Flexible(
            child: Container(
              constraints: BoxConstraints(maxWidth: maxMediaWidth + 40),
              padding: noPadding ? EdgeInsets.zero : const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: noPadding
                    ? Colors.transparent
                    : (isMe ? const Color(0xFFD946EF) : const Color(0xFF1E1E1E)),
                borderRadius: BorderRadius.circular(18).copyWith(
                  bottomRight: isMe ? const Radius.circular(2) : const Radius.circular(18),
                  bottomLeft: isMe ? const Radius.circular(18) : const Radius.circular(2),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!isMe && !noPadding)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Text(msg.senderName,
                          style: const TextStyle(
                              color: GalacticTheme.laserPink,
                              fontSize: 12,
                              fontWeight: FontWeight.bold)),
                    ),
                  if (msg.type == 'audio')
                    _buildVoiceBubble(msg, isMe)
                  else if (msg.type == 'image' ||
                      (msg.message.contains('/uploads/chat') && msg.type != 'audio'))
                    _buildImageBubble(msg, isMe, maxMediaWidth)
                  else if (msg.type == 'video')
                    _buildVideoBubble(msg, isMe, maxMediaWidth)
                  else
                    Text(msg.message,
                        style: const TextStyle(color: Colors.white, fontSize: 15)),
                  if (!noPadding) ...[
                    const SizedBox(height: 4),
                    Text(
                      DateUtil.formatShortDate(msg.createdAt),
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.5), fontSize: 10),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Voice bubble ───────────────────────────────────────────────────────────
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
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Play / pause button
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: isMe
                      ? [
                          Colors.white.withValues(alpha: 0.35),
                          Colors.white.withValues(alpha: 0.15),
                        ]
                      : [const Color(0xFFD946EF), const Color(0xFF9B5DE5)],
                ),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: (isMe ? Colors.white : const Color(0xFFD946EF))
                        .withValues(alpha: 0.25),
                    blurRadius: 10,
                  ),
                ],
              ),
              child: Icon(
                isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                color: Colors.white,
                size: 22,
              ),
            ),
            const SizedBox(width: 10),
            // Waveform + timer column
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 140,
                  height: 34,
                  child: CustomPaint(
                    painter: _GrpWaveformPainter(
                      progress: progress,
                      color: isMe ? Colors.white : const Color(0xFFD946EF),
                    ),
                  ),
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Text(
                      isPlaying ? fmt(_playPosition) : fmt(total),
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.9),
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    if (total.inSeconds > 0)
                      Text(
                        ' / ${fmt(total)}',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.4),
                          fontSize: 10,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── Image bubble ───────────────────────────────────────────────────────────
  Widget _buildImageBubble(GroupMessage msg, bool isMe, double maxW) {
    final url = _getMediaUrl(msg.message);
    return GestureDetector(
      onTap: () => _openMediaViewer(url, 'image'),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16).copyWith(
          bottomRight: isMe ? const Radius.circular(2) : const Radius.circular(16),
          bottomLeft: isMe ? const Radius.circular(16) : const Radius.circular(2),
        ),
        child: Stack(
          children: [
            CachedNetworkImage(
              imageUrl: url,
              width: maxW,
              height: maxW * 0.75,
              fit: BoxFit.cover,
              placeholder: (_, __) => Container(
                width: maxW,
                height: maxW * 0.75,
                color: const Color(0xFF1E1E2A),
                child: const Center(
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Color(0xFFD946EF)),
                ),
              ),
              errorWidget: (_, __, ___) => Container(
                width: maxW,
                height: maxW * 0.75,
                color: const Color(0xFF1E1E2A),
                child: const Center(
                    child: Icon(Icons.broken_image, color: Colors.white38, size: 40)),
              ),
            ),
            // Gradient overlay
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Colors.black.withValues(alpha: 0.75)],
                  ),
                ),
                child: Row(
                  children: [
                    // Sender name for others
                    if (!isMe) ...[
                      Text(msg.senderName,
                          style: const TextStyle(
                              color: GalacticTheme.laserPink,
                              fontSize: 11,
                              fontWeight: FontWeight.bold)),
                      const Spacer(),
                    ] else
                      const Spacer(),
                    // Timestamp
                    Text(
                      DateUtil.formatShortDate(msg.createdAt),
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.6), fontSize: 10),
                    ),
                    const SizedBox(width: 8),
                    // Download button
                    GestureDetector(
                      onTap: () => _downloadMedia(url, 'image'),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.55),
                          borderRadius: BorderRadius.circular(20),
                          border:
                              Border.all(color: Colors.white.withValues(alpha: 0.25)),
                        ),
                        child: _isDownloading
                            ? const SizedBox(
                                width: 12,
                                height: 12,
                                child: CircularProgressIndicator(
                                    strokeWidth: 1.5, color: Colors.white))
                            : const Row(mainAxisSize: MainAxisSize.min, children: [
                                Icon(Icons.download_rounded,
                                    color: Colors.white, size: 13),
                                SizedBox(width: 3),
                                Text('Save',
                                    style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold)),
                              ]),
                      ),
                    ),
                    const SizedBox(width: 6),
                    // Fullscreen icon
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.55),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.fullscreen_rounded,
                          color: Colors.white, size: 14),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Video bubble ───────────────────────────────────────────────────────────
  Widget _buildVideoBubble(GroupMessage msg, bool isMe, double maxW) {
    final url = _getMediaUrl(msg.message);
    return GestureDetector(
      onTap: () => _openMediaViewer(url, 'video'),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16).copyWith(
          bottomRight: isMe ? const Radius.circular(2) : const Radius.circular(16),
          bottomLeft: isMe ? const Radius.circular(16) : const Radius.circular(2),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Thumbnail
            FutureBuilder<Uint8List?>(
              future: _getVideoThumbnail(url),
              builder: (ctx, snap) {
                if (snap.connectionState == ConnectionState.done &&
                    snap.data != null) {
                  return Image.memory(snap.data!,
                      width: maxW, height: maxW * 0.65, fit: BoxFit.cover);
                }
                return Container(
                  width: maxW,
                  height: maxW * 0.65,
                  color: const Color(0xFF12121E),
                  child: const Center(
                      child: Icon(Icons.movie_creation_outlined,
                          color: Colors.white12, size: 56)),
                );
              },
            ),
            // Dark scrim
            Container(
              width: maxW,
              height: maxW * 0.65,
              color: Colors.black.withValues(alpha: 0.3),
            ),
            // Play button
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                    colors: [Color(0xFFD946EF), Color(0xFF9B5DE5)]),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                      color: const Color(0xFFD946EF).withValues(alpha: 0.45),
                      blurRadius: 20)
                ],
              ),
              child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 30),
            ),
            // Bottom bar
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Colors.black.withValues(alpha: 0.8)],
                  ),
                ),
                child: Row(
                  children: [
                    if (!isMe)
                      Text(msg.senderName,
                          style: const TextStyle(
                              color: GalacticTheme.laserPink,
                              fontSize: 11,
                              fontWeight: FontWeight.bold)),
                    const Spacer(),
                    Text(DateUtil.formatShortDate(msg.createdAt),
                        style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.6), fontSize: 10)),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: () => _downloadMedia(url, 'video'),
                      child: Container(
                        padding:
                            const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.55),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                              color: Colors.white.withValues(alpha: 0.25)),
                        ),
                        child: _isDownloading
                            ? const SizedBox(
                                width: 12,
                                height: 12,
                                child: CircularProgressIndicator(
                                    strokeWidth: 1.5, color: Colors.white))
                            : const Row(mainAxisSize: MainAxisSize.min, children: [
                                Icon(Icons.download_rounded,
                                    color: Colors.white, size: 13),
                                SizedBox(width: 3),
                                Text('Save',
                                    style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold)),
                              ]),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInputArea() {
    final canSendText = _permissions.canSendText;
    final canSendMedia = _permissions.canSendMedia;

    return Builder(
      builder: (context) {
        final bottomInset = MediaQuery.of(context).viewInsets.bottom;
        final bottomPadding = MediaQuery.of(context).padding.bottom;
        return Container(
          padding: EdgeInsets.only(
            left: 8,
            right: 8,
            top: 8,
            bottom: 8 + bottomInset + (bottomInset > 0 ? 0 : bottomPadding + 20),
          ),
          decoration: const BoxDecoration(
            color: Color(0xFF1A1A1A),
            border: Border(top: BorderSide(color: Colors.white12)),
          ),
          child: Row(
            children: [
              IconButton(
                icon: Icon(Icons.attach_file,
                    color: canSendMedia ? GalacticTheme.laserPink : Colors.grey),
                onPressed: canSendMedia ? _pickImage : null,
              ),
              Expanded(
                child: Container(
                  height: 50,
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F0F0F),
                    borderRadius: BorderRadius.circular(25),
                    border:
                        Border.all(color: Colors.white.withValues(alpha: 0.1)),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: TextField(
                    controller: _msgController,
                    enabled: canSendText,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText:
                          canSendText ? 'Type a message…' : 'Messaging disabled',
                      hintStyle:
                          TextStyle(color: Colors.white.withValues(alpha: 0.4)),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding:
                          const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onSubmitted: canSendText ? (_) => _sendMessage() : null,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              if (_isRecording) ...[
                Expanded(
                  child: Container(
                    height: 50,
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A0A0A),
                      borderRadius: BorderRadius.circular(25),
                      border: Border.all(
                          color: const Color(0xFFD946EF).withValues(alpha: 0.5)),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        const Icon(Icons.mic, color: Color(0xFFD946EF), size: 18),
                        const SizedBox(width: 8),
                        Text(
                          '${_recordDuration.inMinutes}:${(_recordDuration.inSeconds % 60).toString().padLeft(2, '0')}',
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 14),
                        ),
                        const Spacer(),
                        GestureDetector(
                          onTap: _cancelRecording,
                          child: const Icon(Icons.close,
                              color: Colors.white38, size: 20),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                GestureDetector(
                  onTap: _stopAndSendRecording,
                  child: Container(
                    width: 46,
                    height: 46,
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                          colors: [Color(0xFFD946EF), Color(0xFFFF007F)]),
                      shape: BoxShape.circle,
                    ),
                    child: _isSending
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2))
                        : const Icon(Icons.send_rounded,
                            color: Colors.white, size: 22),
                  ),
                ),
              ] else ...[
                const SizedBox(width: 4),
                GestureDetector(
                  onTap: _hasText
                      ? (canSendText ? _sendMessage : null)
                      : (_permissions.canSendVoice ? _startRecording : null),
                  child: Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      gradient: (canSendText || _permissions.canSendVoice)
                          ? const LinearGradient(
                              colors: [Color(0xFFD946EF), Color(0xFFFF007F)])
                          : null,
                      color: (canSendText || _permissions.canSendVoice)
                          ? null
                          : Colors.grey,
                      shape: BoxShape.circle,
                    ),
                    child: _isSending
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2))
                        : Icon(
                            _hasText ? Icons.send_rounded : Icons.mic,
                            color: Colors.white,
                            size: 22,
                          ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
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

  @override
  void initState() {
    super.initState();
    if (widget.type == 'video') _initVideo();
  }

  Future<void> _initVideo() async {
    _vpCtrl = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    await _vpCtrl!.initialize();
    if (mounted) {
      _chewieCtrl = ChewieController(
        videoPlayerController: _vpCtrl!,
        autoPlay: true,
        looping: false,
        allowFullScreen: true,
        allowMuting: true,
        materialProgressColors: ChewieProgressColors(
          playedColor: const Color(0xFFD946EF),
          handleColor: const Color(0xFFD946EF),
          backgroundColor: Colors.white24,
          bufferedColor: Colors.white38,
        ),
      );
      setState(() => _videoReady = true);
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
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Gallery permission required'),
            backgroundColor: Colors.orange,
          ));
        }
        return;
      }

      final tmpDir = await getTemporaryDirectory();
      final ts = DateTime.now().millisecondsSinceEpoch;
      final ext = widget.type == 'video' ? 'mp4' : 'jpg';
      final dlPath = '${tmpDir.path}/goreto_$ts.$ext';
      await Dio().download(widget.url, dlPath);

      if (widget.type == 'image') {
        final raw = await File(dlPath).readAsBytes();
        final wm = await _addWatermark(raw);
        final wmPath = '${tmpDir.path}/goreto_wm_$ts.png';
        await File(wmPath).writeAsBytes(wm);
        await Gal.putImage(wmPath, album: 'Goreto');
      } else {
        await Gal.putVideo(dlPath, album: 'Goreto');
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Saved to gallery ✓'),
          backgroundColor: Color(0xFFD946EF),
        ));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Download failed'),
          backgroundColor: Colors.red,
        ));
      }
    } finally {
      if (mounted) setState(() => _isDownloading = false);
    }
  }

  Future<Uint8List> _addWatermark(Uint8List bytes) async {
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
          Rect.fromLTWH(rx, ry, tw + pad * 2, th + pad * 2),
          const Radius.circular(24)),
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
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white)),
            )
          else
            IconButton(
              icon: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                      colors: [Color(0xFFD946EF), Color(0xFF9B5DE5)]),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.download_rounded,
                    color: Colors.white, size: 18),
              ),
              onPressed: _download,
              tooltip: 'Save with watermark',
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
                  child: Hero(
                    tag: widget.url,
                    child: CachedNetworkImage(
                      imageUrl: widget.url,
                      fit: BoxFit.contain,
                      placeholder: (_, __) => const Center(
                          child: CircularProgressIndicator(
                              color: Color(0xFFD946EF))),
                      errorWidget: (_, __, ___) => const Icon(
                          Icons.broken_image,
                          color: Colors.white38,
                          size: 64),
                    ),
                  ),
                ),
              ),
      ),
    );
  }

  Widget _buildVideoPlayer() {
    if (!_videoReady || _chewieCtrl == null) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: Color(0xFFD946EF)),
            SizedBox(height: 14),
            Text('Loading video…',
                style: TextStyle(color: Colors.white54, fontSize: 13)),
          ],
        ),
      );
    }
    return Chewie(controller: _chewieCtrl!);
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Waveform painter — natural-looking bars, progress fill
// ═══════════════════════════════════════════════════════════════════════════

class _GrpWaveformPainter extends CustomPainter {
  final double progress;
  final Color color;

  // Deterministic natural waveform heights
  static const List<double> _heights = [
    8, 14, 10, 22, 7, 18, 28, 12, 20, 6,
    26, 11, 17, 8, 24, 15, 9, 22, 7, 18,
    13, 20, 6, 24, 16, 10, 8, 19, 28, 11,
  ];

  const _GrpWaveformPainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    const bars = 30;
    const barW = 2.5;
    final gap = (size.width - bars * barW) / (bars - 1);

    for (int i = 0; i < bars; i++) {
      final isActive = (i / bars) <= progress;
      final rawH = _heights[i];
      final h = rawH.clamp(4.0, size.height);
      final x = i * (barW + gap) + barW / 2;
      final y1 = (size.height - h) / 2;

      canvas.drawLine(
        Offset(x, y1),
        Offset(x, y1 + h),
        Paint()
          ..color = isActive ? color : color.withValues(alpha: 0.22)
          ..strokeWidth = barW
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(_GrpWaveformPainter old) =>
      progress != old.progress || color != old.color;
}
