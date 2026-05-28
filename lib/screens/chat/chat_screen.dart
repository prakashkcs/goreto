import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:image_picker/image_picker.dart';
import 'package:record/record.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:love_vibe_pro/core/theme.dart';
import 'package:love_vibe_pro/models/message.dart';
import 'package:love_vibe_pro/services/chat_service.dart';
import 'package:love_vibe_pro/models/call_session.dart';
import 'package:love_vibe_pro/screens/chat/call/webrtc_call_screen.dart';
import 'package:love_vibe_pro/widgets/neon_toast.dart';
import 'package:love_vibe_pro/services/subscription_plan_service.dart';
import 'package:love_vibe_pro/services/sound_service.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:love_vibe_pro/config/app_env.dart';
import 'package:love_vibe_pro/widgets/manage_user_sheet.dart';
import 'package:love_vibe_pro/services/api_service.dart';
import 'package:love_vibe_pro/services/socket_service.dart';
import 'package:love_vibe_pro/services/ppm_session_service.dart';
import 'package:love_vibe_pro/screens/profile_screen.dart';
import 'package:dio/dio.dart';
import 'package:gal/gal.dart';
import 'package:video_thumbnail/video_thumbnail.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';

class ChatScreen extends StatefulWidget {
  final String userId;
  final String userName;
  final String? userAvatar;

  const ChatScreen({
    super.key,
    required this.userId,
    required this.userName,
    this.userAvatar,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with WidgetsBindingObserver {
  final ChatService _chatService = ChatService.instance;
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();
  final AudioRecorder _audioRecorder = AudioRecorder();
  final AudioPlayer _audioPlayer = AudioPlayer();
  final ImagePicker _picker = ImagePicker();

  List<Message> _messages = [];
  bool _isLoading = true;
  bool _isRecording = false;
  bool _isSending = false;
  bool _isRestricted = false;
  bool _isCheckedRestriction = false;
  Duration _recordDuration = Duration.zero;
  Timer? _recordTimer;
  String? _recordedFilePath;

  // Message being played
  String? _playingMessageId;
  Duration _playPosition = Duration.zero;
  StreamSubscription? _positionSub;
  StreamSubscription? _completionSub;

  // Live Sync
  Timer? _liveSyncTimer;
  bool _isSyncingMessages = false;
  int _emptyPollStreak = 0;

  bool _isBlockedByMe = false;
  bool _isBlockedByThem = false;

  bool _isFriend = false;
  String _requestStatus = 'none';

  bool _isDownloading = false;
  final Map<String, Uint8List?> _thumbCache = {};

  // Socket / real-time
  final SocketService _socket = SocketService.instance;
  bool _otherUserOnline = false;
  DateTime? _otherUserLastSeen;
  bool _isOtherTyping = false;
  Timer? _typingResetTimer;
  final List<StreamSubscription<dynamic>> _socketSubs = [];

  // Pay-per-minute target settings — fetched once on init from profile.
  bool _targetPpmEnabled = false;
  int _targetPpmRate = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadMessages();
    _checkInitialRestriction();
    _startLiveSync();
    _initSocket();
    _loadTargetPpmSettings();
  }

  Future<void> _loadTargetPpmSettings() async {
    try {
      // Hit profile_v19.php directly so we can read raw pay_per_min_* fields
      // without piping them through the typed UserProfile model.
      final dio = await ApiService().getDioClient();
      final res = await dio.get(
        'profile_v19.php',
        queryParameters: {'user_id': widget.userId},
      );
      dynamic body = res.data;
      if (body is String) body = body.isEmpty ? null : null;
      // dio normally decodes JSON automatically; fall back to res.data direct.
      final data = res.data is Map ? res.data as Map : <String, dynamic>{};
      final user = data['user'] is Map ? data['user'] as Map : data;
      final enabledRaw = user['pay_per_min_enabled'];
      final rateRaw = user['pay_per_min_rate'];
      if (!mounted) return;
      setState(() {
        _targetPpmEnabled = enabledRaw == 1 || enabledRaw == '1' ||
            enabledRaw == true || enabledRaw == 'true';
        _targetPpmRate = int.tryParse(rateRaw?.toString() ?? '') ?? 0;
      });
    } catch (_) {
      // Profile fetch failures don't gate chat — PPM CTA just won't show.
    }
  }

  void _startLiveSync() {
    _liveSyncTimer?.cancel();
    // When socket is connected, use a slow fallback (10s) — socket handles real-time.
    // When socket is disconnected, use adaptive polling (500ms → 1500ms).
    final Duration interval;
    if (_socket.isConnected) {
      interval = const Duration(seconds: 10);
    } else {
      interval = _emptyPollStreak > 10
          ? const Duration(milliseconds: 1500)
          : const Duration(milliseconds: 500);
    }
    _liveSyncTimer = Timer(interval, () {
      if (!mounted) return;
      _syncNewMessages().then((_) => _startLiveSync());
    });
  }

  Future<void> _syncNewMessages() async {
    if (!mounted || _isRestricted || _isSyncingMessages) return;
    _isSyncingMessages = true;

    // Find the highest message ID we currently know about
    String lastId = '0';
    if (_messages.isNotEmpty) {
      int maxVal = 0;
      for (var m in _messages) {
        final val = int.tryParse(m.id) ?? 0;
        if (val > maxVal) maxVal = val;
      }
      lastId = maxVal.toString();
    }

    try {
      final convId = _getConversationId();
      final newMsgs = await _chatService.getNewMessages(convId, lastId, withUserId: widget.userId);

      if (mounted) {
        final cached = _chatService.getCachedMessages(convId);
        setState(() {
          // Merge: preserve locally-added messages (socket-sent) not yet
          // reflected in the HTTP cache, so they don't vanish mid-sync.
          final cachedReversed = List<Message>.from(cached.reversed);
          final cachedIds = cachedReversed.map((m) => m.id).toSet();
          final pendingLocal =
              _messages.where((m) => !cachedIds.contains(m.id)).toList();
          _messages = [...pendingLocal, ...cachedReversed];
        });

        if (newMsgs.isNotEmpty) {
          _emptyPollStreak = 0;
          if (newMsgs.any((m) => m.senderId != _chatService.currentUserId)) {
            SoundService().playMessageNotification();
          }
          _chatService.markAsRead(convId);
        } else {
          _emptyPollStreak++;
        }
      }
    } catch (_) {
    } finally {
      _isSyncingMessages = false;
    }
  }

  Future<void> _checkInitialRestriction() async {
    try {
      final creatorId = int.tryParse(widget.userId);
      if (creatorId == null) return;

      // 1. Check if there are already messages (if so, no restriction)
      if (_messages.isNotEmpty) {
        if (mounted) setState(() => _isCheckedRestriction = true);
        return;
      }

      // 2. Check if creator has restriction
      final hasRestriction =
          await SubscriptionPlanService().checkMessagingRestriction(creatorId);
      if (!hasRestriction) {
        if (mounted) setState(() => _isCheckedRestriction = true);
        return;
      }

      // 3. User has restriction and no messages, check if current user is subscribed
      final isSubscribed = await SubscriptionPlanService().isSubscribedTo(
        creatorId,
      );
      if (mounted) {
        setState(() {
          _isRestricted = !isSubscribed;
          _isCheckedRestriction = true;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isCheckedRestriction = true);
    }
  }

  void _initSocket() {
    // Subscribe to other user's online status
    _socket.subscribeStatus(widget.userId);

    // Online status changes
    _socketSubs.add(_socket.onOnlineStatus.listen((data) {
      if (!mounted) return;
      final uid = data['user_id']?.toString();
      if (uid != widget.userId) return;
      final online = data['is_online'] == true;
      final rawLastSeen = data['last_seen']?.toString();
      setState(() {
        _otherUserOnline = online;
        if (!online) {
          // Use server-provided last_seen (null when privacy_show_last_seen = 0)
          _otherUserLastSeen = rawLastSeen != null
              ? DateTime.tryParse(rawLastSeen)
              : null;
        }
      });
    }));

    // Incoming messages
    _socketSubs.add(_socket.onNewMessage.listen((msg) {
      if (!mounted) return;
      if (msg.senderId != widget.userId) return;
      setState(() {
        if (!_messages.any((m) => m.id == msg.id)) {
          _messages.insert(0, msg);
          _emptyPollStreak = 0;
        }
      });
      SoundService().playMessageNotification();
      _socket.markRead(widget.userId);
    }));

    // Read receipts (other user read our messages)
    _socketSubs.add(_socket.onReadReceipt.listen((data) {
      if (!mounted) return;
      final readerId = data['reader_id']?.toString();
      if (readerId != widget.userId) return;
      setState(() {
        _messages = _messages
            .map((m) => m.senderId == _socket.currentUserId &&
                    m.status != MessageStatus.read
                ? m.copyWith(
                    status: MessageStatus.read, readAt: DateTime.now())
                : m)
            .toList();
      });
    }));

    // Delivered receipts
    _socketSubs.add(_socket.onDelivered.listen((data) {
      if (!mounted) return;
      final msgId = data['message_id']?.toString();
      if (msgId == null) return;
      setState(() {
        _messages = _messages
            .map((m) => m.id == msgId && m.status == MessageStatus.sent
                ? m.copyWith(status: MessageStatus.delivered)
                : m)
            .toList();
      });
    }));

    // Typing indicator
    _socketSubs.add(_socket.onTyping.listen((data) {
      if (!mounted) return;
      final sid = data['sender_id']?.toString();
      if (sid != widget.userId) return;
      final typing = data['is_typing'] == true;
      setState(() => _isOtherTyping = typing);
      if (typing) {
        _typingResetTimer?.cancel();
        _typingResetTimer = Timer(const Duration(seconds: 4), () {
          if (mounted) setState(() => _isOtherTyping = false);
        });
      }
    }));

    // Mark existing messages as read on open
    _socket.markRead(widget.userId);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _liveSyncTimer?.cancel();
    _messageController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    _recordTimer?.cancel();
    _typingResetTimer?.cancel();
    _myTypingTimer?.cancel();
    _positionSub?.cancel();
    _completionSub?.cancel();
    _audioRecorder.dispose();
    _audioPlayer.dispose();
    for (final sub in _socketSubs) {
      sub.cancel();
    }
    _socket.unsubscribeStatus(widget.userId);
    _socket.sendTyping(widget.userId, isTyping: false);
    super.dispose();
  }

  Future<void> _loadMessages() async {
    try {
      final convId = _getConversationId();
      final messages = await _chatService.getMessages(convId, withUserId: widget.userId);
      if (mounted) {
        setState(() {
          _messages = messages.reversed.toList();
          _isLoading = false;
          _isBlockedByMe = _chatService.isBlockedByMe(widget.userId);
          _isBlockedByThem = _chatService.isBlockedByThem(widget.userId);
          _isFriend = _chatService.isFriend(widget.userId);
          _requestStatus = _chatService.requestStatus(widget.userId);
        });
        _chatService.markAsRead(convId);

        // After loading, if we have messages, we are definitely NOT restricted
        if (_messages.isNotEmpty) {
          setState(() {
            _isRestricted = false;
            _isCheckedRestriction = true;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        NeonToast.error(context, 'Error loading messages: $e');
      }
    }
  }

  String _getConversationId() {
    final ids = [_chatService.currentUserId, widget.userId]..sort();
    return 'conv_${ids[0]}_${ids[1]}';
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (!_socket.isConnected) _socket.connect();
      _startLiveSync();
    }
  }

  void _hapticFeedback() {}

  // Typing indicator: send while user is typing, clear 2s after they stop
  Timer? _myTypingTimer;

  void _onTextChanged(String _) {
    if (!_socket.isConnected) return;
    _socket.sendTyping(widget.userId, isTyping: true);
    _myTypingTimer?.cancel();
    _myTypingTimer = Timer(const Duration(seconds: 2), () {
      if (_socket.isConnected) {
        _socket.sendTyping(widget.userId, isTyping: false);
      }
    });
  }

  Future<void> _sendTextMessage() async {
    if (_isSending) return;
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    _messageController.clear();
    _myTypingTimer?.cancel();
    if (_socket.isConnected) _socket.sendTyping(widget.userId, isTyping: false);
    _hapticFeedback();

    // Optimistic: show message immediately with "sending" status
    final tempId = '${DateTime.now().millisecondsSinceEpoch}';
    final optimisticMsg = Message(
      id: 'tmp_$tempId',
      senderId: _chatService.currentUserId,
      receiverId: widget.userId,
      type: MessageType.text,
      content: text,
      status: MessageStatus.sending,
      createdAt: DateTime.now(),
    );
    setState(() {
      _messages.insert(0, optimisticMsg);
      _isSending = true;
    });

    try {
      // Try socket first, fall back to HTTP
      Message? message;
      if (_socket.isConnected) {
        message = await _socket.sendMessage(
          receiverId: widget.userId,
          content: text,
          tempId: tempId,
        );
      }
      message ??= await _chatService.sendMessage(
        receiverId: widget.userId,
        content: text,
      );

      if (mounted) {
        setState(() {
          final idx = _messages.indexWhere((m) => m.id == optimisticMsg.id);
          if (idx != -1) {
            _messages[idx] = message!;
          } else if (!_messages.any((m) => m.id == message!.id)) {
            _messages.insert(0, message!);
          }
          _isSending = false;
          _emptyPollStreak = 0;
        });
        if (!_socket.isConnected) _syncNewMessages();
      }
    } catch (e) {
      if (mounted) {
        // Remove the optimistic message on failure
        setState(() {
          _messages.removeWhere((m) => m.id == optimisticMsg.id);
          _isSending = false;
        });
        String errMsg = e.toString();
        if (e is DioException && e.response?.data != null) {
          final dynamic data = e.response!.data;
          if (data is Map && data['message'] != null) {
            errMsg = data['message'].toString();
          }
        }
        NeonToast.error(context, errMsg);
        if (errMsg.toLowerCase().contains("block") ||
            errMsg.toLowerCase().contains("unavail")) {
          _loadMessages();
        }
      }
    }
  }

  Future<void> _pickAndSendMedia(
    ImageSource source, {
    bool isVideo = false,
  }) async {
    if (_isSending) return;
    try {
      final XFile? file = isVideo
          ? await _picker.pickVideo(source: source)
          : await _picker.pickImage(source: source, imageQuality: 80);

      if (file == null) return;

      _hapticFeedback();
      setState(() => _isSending = true);

      final message = await _chatService.sendMediaMessage(
        receiverId: widget.userId,
        type: isVideo ? MessageType.video : MessageType.image,
        mediaPath: file.path,
      );

      setState(() {
        _messages.insert(0, message);
        _isSending = false;
      });
    } catch (e) {
      setState(() => _isSending = false);
      NeonToast.error(context, 'Failed to send media: $e');
    }
  }

  Future<void> _startRecording() async {
    final status = await Permission.microphone.request();
    if (!status.isGranted) {
      _showPermissionDialog('microphone');
      return;
    }

    try {
      if (await _audioRecorder.hasPermission()) {
        final dir = await getTemporaryDirectory();
        final path = p.join(
          dir.path,
          'voice_${DateTime.now().millisecondsSinceEpoch}.m4a',
        );
        await _audioRecorder.start(const RecordConfig(), path: path);

        setState(() {
          _isRecording = true;
          _recordDuration = Duration.zero;
        });

        _recordTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
          setState(() {
            _recordDuration = Duration(seconds: _recordDuration.inSeconds + 1);
          });
        });
      }
    } catch (e) {
      NeonToast.error(context, 'Failed to start recording: $e');
    }
  }

  Future<void> _stopAndSendRecording() async {
    if (_isSending || !_isRecording) return;
    _isRecording = false; // Toggle immediately to prevent double-calls
    _recordTimer?.cancel();

    try {
      final path = await _audioRecorder.stop();
      if (path != null && _recordDuration.inSeconds > 0) {
        _hapticFeedback();
        setState(() => _isSending = true);

        final message = await _chatService.sendVoiceMessage(
          receiverId: widget.userId,
          audioPath: path,
          duration: _recordDuration,
        );

        setState(() {
          _messages.insert(0, message);
          _isRecording = false;
          _isSending = false;
          _recordDuration = Duration.zero;
        });
      } else {
        setState(() {
          _isRecording = false;
          _recordDuration = Duration.zero;
        });
      }
    } catch (e) {
      setState(() {
        _isRecording = false;
        _isSending = false;
        _recordDuration = Duration.zero;
      });
      NeonToast.error(context, 'Failed to send voice message: $e');
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

  Future<void> _playVoiceMessage(Message message) async {
    if (_playingMessageId == message.id) {
      await _audioPlayer.pause();
      _positionSub?.cancel();
      _completionSub?.cancel();
      setState(() => _playingMessageId = null);
      return;
    }
    _positionSub?.cancel();
    _completionSub?.cancel();
    try {
      if (message.mediaUrl != null) {
        String url = message.mediaUrl!;
        if (!url.startsWith('http')) {
          final baseUrl = AppEnv.baseUrl.replaceAll('/api/v1/', '/');
          url = '$baseUrl$url';
        }
        setState(() {
          _playingMessageId = message.id;
          _playPosition = Duration.zero;
        });
        _positionSub = _audioPlayer.onPositionChanged.listen((pos) {
          if (mounted) setState(() => _playPosition = pos);
        });
        _completionSub = _audioPlayer.onPlayerComplete.listen((_) {
          if (mounted) setState(() { _playingMessageId = null; _playPosition = Duration.zero; });
        });
        await _audioPlayer.play(UrlSource(url));
      }
    } catch (e) {
      _positionSub?.cancel();
      _completionSub?.cancel();
      if (mounted) setState(() => _playingMessageId = null);
      if (mounted) NeonToast.error(context, 'Error playing audio');
    }
  }

  Future<Uint8List?> _getVideoThumbnail(String url) async {
    if (_thumbCache.containsKey(url)) return _thumbCache[url];
    try {
      final data = await VideoThumbnail.thumbnailData(
        video: url,
        maxWidth: 480,
        quality: 75,
      );
      _thumbCache[url] = data;
      return data;
    } catch (_) {
      _thumbCache[url] = null;
      return null;
    }
  }

  Future<String> _addWatermark(String imagePath) async {
    final bytes = await File(imagePath).readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final src = frame.image;
    final w = src.width.toDouble();
    final h = src.height.toDouble();

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawImage(src, Offset.zero, Paint());

    const label = 'goreto';
    const fontSize = 22.0;
    final pb = ui.ParagraphBuilder(ui.ParagraphStyle(
      textAlign: TextAlign.left,
      fontSize: fontSize,
      fontWeight: FontWeight.bold,
    ))
      ..pushStyle(ui.TextStyle(
          color: Colors.white, fontSize: fontSize, fontWeight: FontWeight.bold))
      ..addText(label);
    final para = pb.build()
      ..layout(const ui.ParagraphConstraints(width: 200));

    const pillH = 36.0;
    const hPad = 16.0;
    final pillW = para.longestLine + hPad * 2 + 8;
    final rx = w - pillW - 16;
    final ry = h - pillH - 16;

    canvas.drawRRect(
      RRect.fromLTRBR(rx, ry, rx + pillW, ry + pillH, const Radius.circular(8)),
      Paint()..color = Colors.black.withValues(alpha: 0.55),
    );
    canvas.drawRRect(
      RRect.fromLTRBR(rx, ry, rx + 4, ry + pillH, const Radius.circular(4)),
      Paint()..color = const Color(0xFFD946EF),
    );
    canvas.drawParagraph(para, Offset(rx + hPad + 4, ry + (pillH - fontSize) / 2));

    final picture = recorder.endRecording();
    final img = await picture.toImage(src.width, src.height);
    final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
    final wmPath = '${imagePath}_wm.png';
    await File(wmPath).writeAsBytes(byteData!.buffer.asUint8List());
    return wmPath;
  }

  Future<void> _downloadMedia(String url, String type) async {
    if (_isDownloading) return;
    setState(() => _isDownloading = true);
    try {
      final hasAccess = await Gal.requestAccess(toAlbum: true);
      if (!hasAccess) {
        if (mounted) NeonToast.error(context, 'Gallery permission denied');
        return;
      }
      final dir = await getTemporaryDirectory();
      final ext = type == 'image' ? 'jpg' : 'mp4';
      final path =
          '${dir.path}/goreto_${DateTime.now().millisecondsSinceEpoch}.$ext';
      await Dio().download(url, path);
      if (type == 'image') {
        final wmPath = await _addWatermark(path);
        await Gal.putImage(wmPath, album: 'Goreto');
      } else {
        await Gal.putVideo(path, album: 'Goreto');
      }
      if (mounted) NeonToast.success(context, 'Saved to gallery ✓');
    } catch (_) {
      if (mounted) NeonToast.error(context, 'Download failed');
    } finally {
      if (mounted) setState(() => _isDownloading = false);
    }
  }

  void _openMediaViewer(String url, String type) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _ChatMediaViewerScreen(
          url: url,
          type: type,
          onDownload: () => _downloadMedia(url, type),
        ),
      ),
    );
  }

  void _showPermissionDialog(String type) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: GalacticTheme.laserPink, width: 1.5),
        ),
        title: const Row(
          children: [
            Icon(Icons.warning_amber, color: GalacticTheme.laserPink),
            SizedBox(width: 8),
            Text('Permission Required', style: TextStyle(color: Colors.white)),
          ],
        ),
        content: Text(
          'Please grant $type permission to use this feature.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Colors.white54),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              openAppSettings();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: GalacticTheme.laserPink,
            ),
            child: const Text(
              'Open Settings',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _startCall(bool isVideo) async {
    _hapticFeedback();
    SoundService().playOutgoingCallRingOnce();

    // Check permissions
    if (isVideo) {
      final cameraStatus = await Permission.camera.request();
      if (!cameraStatus.isGranted) {
        _showPermissionDialog('camera');
        return;
      }
    }
    final micStatus = await Permission.microphone.request();
    if (!micStatus.isGranted) {
      _showPermissionDialog('microphone');
      return;
    }

    final callSession = CallSession(
      callerId: _chatService.currentUserId,
      callerName: 'You',
      receiverId: widget.userId,
      receiverName: widget.userName,
      receiverAvatar: widget.userAvatar,
      type: isVideo ? CallType.video : CallType.audio,
      state: CallState.outgoing,
    );

    final duration = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => WebRTCCallScreen(
          callSession: callSession,
          isOutgoing: true,
          isTargetOnline: _otherUserOnline,
        ),
      ),
    );

    if (duration != null && duration is int) {
      String callLog = '';
      if (duration == 0) {
        callLog = 'Missed ${isVideo ? 'video' : 'voice'} call';
      } else {
        final m = duration ~/ 60;
        final s = duration % 60;
        callLog =
            '${isVideo ? 'Video' : 'Voice'} call • $m:${s.toString().padLeft(2, '0')}';
      }

      try {
        final msg = await _chatService.sendMessage(
          receiverId: widget.userId,
          type: MessageType.call,
          content: callLog,
        );
        // Insert immediately so the call log appears without waiting for next sync tick
        if (mounted) {
          setState(() => _messages.insert(0, msg));
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_scrollController.hasClients) {
              _scrollController.jumpTo(0);
            }
          });
        }
      } catch (_) {
        // If network fails, the call log will appear on next message poll
      }
    }
  }

  void _showAttachOptions() {
    _hapticFeedback();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        decoration: const BoxDecoration(
          color: Color(0xFF121212),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          border: Border(top: BorderSide(color: Color(0xFFD946EF), width: 1)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Attach Media',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildAttachOption(
                  icon: Icons.photo_library,
                  label: 'Gallery',
                  color: const Color(0xFFD946EF),
                  onTap: () {
                    Navigator.pop(context);
                    _pickAndSendMedia(ImageSource.gallery);
                  },
                ),
                _buildAttachOption(
                  icon: Icons.camera_alt,
                  label: 'Camera',
                  color: const Color(0xFF06B6D4),
                  onTap: () {
                    Navigator.pop(context);
                    _pickAndSendMedia(ImageSource.camera);
                  },
                ),
                _buildAttachOption(
                  icon: Icons.videocam,
                  label: 'Video',
                  color: const Color(0xFFF97316),
                  onTap: () {
                    Navigator.pop(context);
                    _pickAndSendMedia(ImageSource.gallery, isVideo: true);
                  },
                ),
              ],
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildAttachOption({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              shape: BoxShape.circle,
              border: Border.all(color: color.withValues(alpha: 0.3)),
            ),
            child: Icon(icon, color: color, size: 28),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;
    final isKeyboardOpen = keyboardHeight > 0;
    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: _buildAppBar(),
      body: Padding(
        padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top),
        child: Column(
          children: [
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: GalacticTheme.laserPink,
                      ),
                    )
                  : _buildMessageList(),
            ),
            if (_isRestricted)
              _buildRestrictedInput()
            else if (!_isCheckedRestriction && _messages.isEmpty)
              const SizedBox(
                height: 80,
                child: Center(
                  child: CircularProgressIndicator(
                    color: GalacticTheme.laserPink,
                  ),
                ),
              )
            else if (_requestStatus == 'pending_received')
              _buildRequestPendingBar()
            else
              _buildInputArea(),
          ],
        ),
      ),
    );
  }

  Widget _buildRequestPendingBar() {
    final navPadding = MediaQuery.of(context).padding.bottom;
    final bottomPadding = navPadding > 0 ? navPadding + 10.0 : 20.0;
    return Container(
      padding: EdgeInsets.only(left: 16, right: 16, top: 16, bottom: bottomPadding),
      decoration: BoxDecoration(
        color: const Color(0xFF0E0E14),
        border: Border(
          top: BorderSide(color: const Color(0xFFF97316).withValues(alpha: 0.3)),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.mail_outline, color: Color(0xFFF97316), size: 28),
          const SizedBox(height: 8),
          Text(
            '${widget.userName} sent you a message request',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
          const SizedBox(height: 4),
          const Text(
            'Accept to reply, call, and use all features.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white38, fontSize: 11),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _declineRequest,
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.red),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: const Text('Decline',
                      style: TextStyle(color: Colors.red)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: _acceptRequest,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFF97316),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: const Text('Accept',
                      style: TextStyle(
                          color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _acceptRequest() async {
    try {
      await _chatService.acceptRequest(widget.userId);
      if (mounted) {
        setState(() {
          _requestStatus = 'accepted';
          _isFriend = _chatService.isFriend(widget.userId);
        });
        NeonToast.success(context, 'Message request accepted!');
      }
    } catch (e) {
      if (mounted) NeonToast.error(context, 'Failed to accept request');
    }
  }

  Future<void> _declineRequest() async {
    try {
      await _chatService.declineRequest(widget.userId);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) NeonToast.error(context, 'Failed to decline request');
    }
  }

  Widget _buildRestrictedInput() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        border: Border(
          top: BorderSide(
            color: GalacticTheme.laserPink.withValues(alpha: 0.2),
            width: 1,
          ),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.lock_outline,
            color: GalacticTheme.laserPink,
            size: 32,
          ),
          const SizedBox(height: 12),
          const Text(
            'Message Restricted',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Only subscribers can initiate a conversation with ${widget.userName}.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.6),
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: () {
                // Show subscription plans
                _showPlansSheet();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: GalacticTheme.laserPink,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
              ),
              child: const Text(
                'Subscribe to Message',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }

  void _showPlansSheet() {
    // We can use the existing _ProfilePlansSheet from ProfileScreen if available,
    // or redirect to profile screen.
    // For now, let's just show a simple bottom sheet or redirect.
    Navigator.pop(context); // Close chat
    // The user likely came from profile or search, so popping might take them back.
    NeonToast.info(
      context,
      'Please subscribe from the user\'s profile to message them.',
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: const Color(0xFF0A0A0A),
      elevation: 0,
      leading: GestureDetector(
        onTap: () => Navigator.pop(context),
        child: Container(
          margin: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A1A),
            shape: BoxShape.circle,
            border: Border.all(
              color: GalacticTheme.laserPink.withValues(alpha: 0.5),
              width: 1.5,
            ),
          ),
          child: const Icon(Icons.arrow_back, color: Colors.white, size: 20),
        ),
      ),
      title: GestureDetector(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ProfileScreen(userId: widget.userId),
          ),
        ),
        child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFFD946EF), width: 2),
            ),
            child: ClipOval(
              child: widget.userAvatar != null
                  ? CachedNetworkImage(
                      imageUrl: widget.userAvatar!,
                      width: 36,
                      height: 36,
                      fit: BoxFit.cover,
                      memCacheWidth: 144,
                      memCacheHeight: 144,
                      placeholder: (_, __) => Container(
                        color: const Color(0xFF2A2A2A),
                        child: const Icon(
                          Icons.person,
                          color: Colors.white38,
                          size: 20,
                        ),
                      ),
                      errorWidget: (_, __, ___) => Container(
                        color: const Color(0xFF2A2A2A),
                        child: const Icon(
                          Icons.person,
                          color: Colors.white38,
                          size: 20,
                        ),
                      ),
                    )
                  : Container(
                      width: 36,
                      height: 36,
                      color: const Color(0xFF2A2A2A),
                      child: const Icon(
                        Icons.person,
                        color: Colors.white38,
                        size: 20,
                      ),
                    ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.userName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (_isOtherTyping)
                  const Text(
                    'typing...',
                    style: TextStyle(
                        color: Color(0xFFD946EF),
                        fontSize: 11,
                        fontStyle: FontStyle.italic),
                  )
                else if (_isFriend && _otherUserOnline)
                  const Text(
                    'Friends • Online',
                    style: TextStyle(color: Color(0xFF22C55E), fontSize: 11),
                  )
                else if (_isFriend)
                  Text(
                    _otherUserLastSeen != null
                        ? 'Friends • last seen ${_formatLastSeen(_otherUserLastSeen!)}'
                        : 'Friends',
                    style: const TextStyle(color: Color(0xFF22C55E), fontSize: 11),
                  )
                else if (_requestStatus == 'pending_received')
                  const Text(
                    'Message Request',
                    style: TextStyle(color: Color(0xFFF97316), fontSize: 11),
                  )
                else if (_requestStatus == 'pending_sent')
                  const Text(
                    'Request Sent',
                    style: TextStyle(color: Colors.white38, fontSize: 11),
                  )
                else if (_otherUserOnline)
                  const Text(
                    'Online',
                    style: TextStyle(color: Color(0xFF22C55E), fontSize: 11),
                  )
                else if (_otherUserLastSeen != null)
                  Text(
                    'last seen ${_formatLastSeen(_otherUserLastSeen!)}',
                    style: const TextStyle(
                        color: Color(0xFF888888), fontSize: 11),
                  ),
              ],
            ),
          ),
        ],
        ),
      ),
      actions: [
        _buildCallButton(Icons.call, false),
        _buildCallButton(Icons.videocam, true),
        GestureDetector(
          onTap: () => ManageUserSheet.show(
            context,
            userId: widget.userId,
            userName: widget.userName,
            userAvatar: widget.userAvatar,
            onActionTaken: () {
              _loadMessages();
            },
          ),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 4),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A1A),
              shape: BoxShape.circle,
              border: Border.all(
                color: const Color(0xFF6366F1).withValues(alpha: 0.5),
                width: 1.5,
              ),
            ),
            child: const Icon(Icons.more_vert, color: Colors.white, size: 18),
          ),
        ),
        const SizedBox(width: 4),
      ],
    );
  }

  bool get _bothHaveMessaged {
    if (_messages.isEmpty) return false;
    final myId = _chatService.currentUserId;
    return _messages.any((m) => m.senderId == myId) &&
        _messages.any((m) => m.senderId == widget.userId);
  }

  Widget _buildCallButton(IconData icon, bool isVideo) {
    final canCall = _isFriend || _requestStatus == 'accepted' || _bothHaveMessaged;
    if (!canCall) return const SizedBox.shrink();
    return GestureDetector(
      onTap: () => _startCall(isVideo),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A1A),
          shape: BoxShape.circle,
          border: Border.all(
            color: isVideo ? const Color(0xFF06B6D4) : const Color(0xFFD946EF),
            width: 1.5,
          ),
        ),
        child: Icon(icon, color: Colors.white, size: 20),
      ),
    );
  }

  Widget _buildMessageList() {
    return ListView.builder(
      controller: _scrollController,
      reverse: true,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      itemCount: _messages.length,
      itemBuilder: (context, index) {
        final message = _messages[index];
        final isMe = message.senderId == _chatService.currentUserId;
        final showDate = index == _messages.length - 1 ||
            !_isSameDay(_messages[index + 1].createdAt, message.createdAt);

        return Column(
          children: [
            if (showDate) _buildDateDivider(message.createdAt),
            _buildMessageBubble(message, isMe),
          ],
        );
      },
    );
  }

  String _formatLastSeen(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    final timeStr = DateFormat('h:mm a').format(dt); // e.g. "2:35 PM"

    if (diff.inSeconds < 60) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (_isSameDay(dt, now)) return 'today at $timeStr';
    if (_isSameDay(dt, now.subtract(const Duration(days: 1)))) {
      return 'yesterday at $timeStr';
    }
    if (diff.inDays < 7) return '${DateFormat('EEEE').format(dt)} at $timeStr'; // "Monday at 9:04 AM"
    return DateFormat('MMM d').format(dt); // "Jan 5"
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  Widget _buildDateDivider(DateTime date) {
    final now = DateTime.now();
    String text;
    if (_isSameDay(date, now)) {
      text = 'Today';
    } else if (_isSameDay(date, now.subtract(const Duration(days: 1)))) {
      text = 'Yesterday';
    } else {
      text = DateFormat.MMMd().format(date);
    }

    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 16),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              const Color(0xFFD946EF).withValues(alpha: 0.12),
              const Color(0xFF06B6D4).withValues(alpha: 0.12),
            ],
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: const Color(0xFFD946EF).withValues(alpha: 0.2),
          ),
        ),
        child: Text(
          text,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.7),
            fontSize: 11,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }

  Widget _buildMessageBubble(Message message, bool isMe) {
    final timeText = DateFormat.jm().format(message.createdAt);
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 3),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.78,
        ),
        child: Container(
          padding: _getBubblePadding(message),
          decoration: BoxDecoration(
            gradient: isMe
                ? const LinearGradient(
                    colors: [
                      Color(0xFFB93FD1),
                      Color(0xFF5B44E0),
                      Color(0xFF0EA5D9),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  )
                : const LinearGradient(
                    colors: [Color(0xFF1E1E2E), Color(0xFF1A1A28)],
                  ),
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(18),
              topRight: const Radius.circular(18),
              bottomLeft: Radius.circular(isMe ? 18 : 4),
              bottomRight: Radius.circular(isMe ? 4 : 18),
            ),
            border: isMe
                ? null
                : Border.all(color: Colors.white.withValues(alpha: 0.08)),
            boxShadow: [
              BoxShadow(
                color: isMe
                    ? const Color(0xFFD946EF).withValues(alpha: 0.12)
                    : Colors.black.withValues(alpha: 0.2),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment:
                isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              _buildMessageContent(message, isMe),
              const SizedBox(height: 3),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    timeText,
                    style: TextStyle(
                      color: isMe
                          ? Colors.white.withValues(alpha: 0.65)
                          : Colors.white.withValues(alpha: 0.4),
                      fontSize: 10,
                    ),
                  ),
                  if (isMe) ...[
                    const SizedBox(width: 4),
                    _buildTick(message),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  EdgeInsets _getBubblePadding(Message message) {
    switch (message.type) {
      case MessageType.image:
      case MessageType.video:
        return const EdgeInsets.all(4);
      case MessageType.voice:
      case MessageType.call:
        return const EdgeInsets.symmetric(horizontal: 12, vertical: 8);
      default:
        return const EdgeInsets.symmetric(horizontal: 16, vertical: 10);
    }
  }

  /// Single tick  = sent to server (recipient offline)
  /// Double tick gray = delivered to device (recipient online / status=delivered)
  /// Double tick blue = seen (status=read)
  Widget _buildTick(Message message) {
    if (message.status == MessageStatus.read) {
      return const Icon(Icons.done_all, color: Color(0xFF29B6F6), size: 14);
    }
    if (message.status == MessageStatus.delivered ||
        (message.status == MessageStatus.sent && _otherUserOnline)) {
      return Icon(Icons.done_all, color: Colors.white.withValues(alpha: 0.55), size: 14);
    }
    // sent + recipient offline, or still sending
    return Icon(Icons.done, color: Colors.white.withValues(alpha: 0.35), size: 14);
  }

  Widget _buildMessageContent(Message message, bool isMe) {
    switch (message.type) {
      case MessageType.image:
        return _buildImageMessage(message);
      case MessageType.video:
        return _buildVideoMessage(message);
      case MessageType.voice:
        return _buildVoiceMessage(message, isMe);
      case MessageType.call:
        return _buildCallMessage(message, isMe);
      case MessageType.text:
      default:
        return Text(
          message.content ?? '',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            height: 1.3,
          ),
        );
    }
  }

  Widget _buildCallMessage(Message message, bool isMe) {
    final isVideo = message.content?.contains('video') == true ||
        message.content?.contains('Video') == true;
    final isMissed = message.content?.contains('Missed') == true;

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: isMissed
                ? Colors.red.withValues(alpha: 0.15)
                : isMe
                    ? Colors.white.withValues(alpha: 0.2)
                    : GalacticTheme.laserPink.withValues(alpha: 0.15),
            shape: BoxShape.circle,
          ),
          child: Icon(
            isVideo ? Icons.videocam : Icons.call,
            color: isMissed ? Colors.redAccent : Colors.white,
            size: 18,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          message.content ?? 'Call',
          style: TextStyle(
            color: isMissed ? Colors.red.shade200 : Colors.white,
            fontSize: 14,
            fontWeight: isMissed ? FontWeight.w500 : FontWeight.normal,
          ),
        ),
      ],
    );
  }

  Widget _buildImageMessage(Message message) {
    final url = message.mediaUrl;
    if (url == null) {
      return Container(
        width: 200, height: 150,
        decoration: BoxDecoration(
          color: const Color(0xFF2A2A2A),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.image, color: Colors.white38),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Stack(
        children: [
          GestureDetector(
            onTap: () => _openMediaViewer(url, 'image'),
            child: url.startsWith('http')
                ? CachedNetworkImage(
                    imageUrl: url,
                    width: 200,
                    fit: BoxFit.cover,
                    memCacheWidth: 600,
                    memCacheHeight: 600,
                    placeholder: (_, __) => Container(
                      width: 200,
                      height: 150,
                      color: const Color(0xFF2A2A2A),
                      child: const Center(
                          child: CircularProgressIndicator(
                              color: Color(0xFFD946EF))),
                    ),
                  )
                : Image.file(File(url), width: 200, fit: BoxFit.cover),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.fromLTRB(8, 20, 8, 6),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.7)
                  ],
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  GestureDetector(
                    onTap: () => _downloadMedia(url, 'image'),
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.5),
                        shape: BoxShape.circle,
                      ),
                      child: _isDownloading
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                  color: Colors.white, strokeWidth: 2))
                          : const Icon(Icons.download_rounded,
                              color: Colors.white, size: 16),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVideoMessage(Message message) {
    final url = message.mediaUrl;
    if (url == null) {
      return Container(
        width: 200, height: 150,
        decoration: BoxDecoration(
          color: const Color(0xFF2A2A2A),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.videocam_off, color: Colors.white38),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: 200,
        height: 150,
        child: Stack(
          fit: StackFit.expand,
          children: [
            FutureBuilder<Uint8List?>(
              future: _getVideoThumbnail(url),
              builder: (context, snapshot) {
                if (snapshot.hasData && snapshot.data != null) {
                  return Image.memory(snapshot.data!, fit: BoxFit.cover);
                }
                if (message.mediaThumbnail != null) {
                  return CachedNetworkImage(
                    imageUrl: message.mediaThumbnail!,
                    fit: BoxFit.cover,
                    memCacheWidth: 600,
                    memCacheHeight: 450,
                  );
                }
                return Container(color: const Color(0xFF2A2A2A));
              },
            ),
            Container(color: Colors.black.withValues(alpha: 0.35)),
            Center(
              child: GestureDetector(
                onTap: () => _openMediaViewer(url, 'video'),
                child: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                        colors: [Color(0xFFD946EF), Color(0xFF7C3AED)]),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color:
                            const Color(0xFFD946EF).withValues(alpha: 0.4),
                        blurRadius: 12,
                      )
                    ],
                  ),
                  child: const Icon(Icons.play_arrow_rounded,
                      color: Colors.white, size: 28),
                ),
              ),
            ),
            Positioned(
              right: 8,
              bottom: 8,
              child: GestureDetector(
                onTap: () => _downloadMedia(url, 'video'),
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.6),
                    shape: BoxShape.circle,
                  ),
                  child: _isDownloading
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2))
                      : const Icon(Icons.download_rounded,
                          color: Colors.white, size: 16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVoiceMessage(Message message, bool isMe) {
    final isPlaying = _playingMessageId == message.id;
    final total = message.voiceDuration ?? Duration.zero;
    final totalMs = total.inMilliseconds > 0 ? total.inMilliseconds : 1;
    final posMs = isPlaying ? _playPosition.inMilliseconds : 0;
    final progress = (posMs / totalMs).clamp(0.0, 1.0);

    String fmt(Duration d) =>
        '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

    return GestureDetector(
      onTap: () => _playVoiceMessage(message),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
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
                      .withValues(alpha: 0.2),
                  blurRadius: 8,
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
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 140,
                height: 34,
                child: CustomPaint(
                  painter: _WaveformPainter(
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
    );
  }

  Widget _buildInputArea() {
    final navPadding = MediaQuery.of(context).padding.bottom;
    final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;
    final double bottomPadding = navPadding > 0 ? navPadding + 10.0 : 20.0;

    if (_isBlockedByMe) {
      return Container(
        width: double.infinity,
        padding: EdgeInsets.only(
          left: 12,
          right: 12,
          top: 16,
          bottom: bottomPadding + 6.0,
        ),
        color: const Color(0xFF0E0E14),
        child: Column(
          children: [
            const Text(
              'You have blocked this user.',
              style: TextStyle(color: Colors.white54, fontSize: 13),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () async {
                try {
                  await ApiService().unblockUser(blockedId: widget.userId);
                  NeonToast.success(context, 'User unblocked!');
                  setState(() {
                    _isBlockedByMe = false;
                  });
                } catch (e) {
                  NeonToast.error(context, 'Failed to unblock.');
                }
              },
              child: const Text(
                'Unblock',
                style: TextStyle(
                  color: GalacticTheme.laserPink,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (_isBlockedByThem) {
      return Container(
        width: double.infinity,
        padding: EdgeInsets.only(
          left: 12,
          right: 12,
          top: 20,
          bottom: bottomPadding + 10,
        ),
        color: const Color(0xFF0E0E14),
        child: const Center(
          child: Text(
            'User is unavailable.',
            style: TextStyle(color: Colors.white54, fontSize: 14),
          ),
        ),
      );
    }

    return Container(
      padding: EdgeInsets.only(
        left: 12,
        right: 12,
        top: 10,
        bottom: bottomPadding,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFF0E0E14),
        border: Border(
          top: BorderSide(
            color: const Color(0xFFD946EF).withValues(alpha: 0.15),
          ),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildPpmBar(),
          _isRecording ? _buildRecordingUI() : _buildNormalInputUI(),
        ],
      ),
    );
  }

  /// Pay-per-minute banner shown above the composer. Three states:
  ///   - target has PPM off → nothing
  ///   - target has PPM on, no session → "Start paid chat (X coins/min)"
  ///   - session active → running minutes + balance + Stop button
  Widget _buildPpmBar() {
    return ValueListenableBuilder<PpmSessionState?>(
      valueListenable: PpmSessionService.instance.stateNotifier,
      builder: (_, session, __) {
        final isMineActive = session != null &&
            session.active &&
            session.sellerId.toString() == widget.userId;
        if (isMineActive) {
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF00E5FF), Color(0xFFD946EF)],
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(Icons.timer_outlined,
                    color: Colors.white, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Paid chat ${session.minutesCharged}m  •  ${session.totalCoinsCharged} coins  •  Balance ${session.balance}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                TextButton(
                  style: TextButton.styleFrom(
                    backgroundColor: Colors.white.withValues(alpha: 0.2),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 4),
                  ),
                  onPressed: () async {
                    await PpmSessionService.instance.stop();
                    if (mounted) NeonToast.info(context, 'Paid chat ended');
                  },
                  child: const Text('Stop',
                      style: TextStyle(
                          color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          );
        }
        if (!_targetPpmEnabled || _targetPpmRate <= 0) {
          return const SizedBox.shrink();
        }
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFFFF007F).withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: const Color(0xFFFF007F).withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              const Icon(Icons.monetization_on_outlined,
                  color: Color(0xFFFF007F), size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Paid chat: $_targetPpmRate coins/min',
                  style: const TextStyle(
                      color: Colors.white, fontSize: 12),
                ),
              ),
              TextButton(
                style: TextButton.styleFrom(
                  backgroundColor: const Color(0xFFFF007F),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 4),
                ),
                onPressed: _startPpmSession,
                child: const Text('Start',
                    style: TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _startPpmSession() async {
    final sellerId = int.tryParse(widget.userId);
    if (sellerId == null) return;
    try {
      await PpmSessionService.instance.start(sellerId);
      if (mounted) NeonToast.success(context, 'Paid chat started');
    } catch (e) {
      if (mounted) {
        NeonToast.error(
            context, e.toString().replaceAll('Exception: ', ''));
      }
    }
  }

  Widget _buildNormalInputUI() {
    final hasText = _messageController.text.isNotEmpty;
    return Row(
      children: [
        // Attach button
        GestureDetector(
          onTap: _showAttachOptions,
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A28),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: const Color(0xFFD946EF).withValues(alpha: 0.3),
              ),
            ),
            child: const Icon(
              Icons.add_rounded,
              color: Color(0xFFD946EF),
              size: 22,
            ),
          ),
        ),
        const SizedBox(width: 8),
        // Text input
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A28),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: _focusNode.hasFocus
                    ? const Color(0xFFD946EF).withValues(alpha: 0.4)
                    : Colors.white.withValues(alpha: 0.06),
              ),
            ),
            child: TextField(
              controller: _messageController,
              focusNode: _focusNode,
              onChanged: (text) {
                setState(() {});
                _onTextChanged(text);
              },
              style: const TextStyle(color: Colors.white, fontSize: 15),
              decoration: InputDecoration(
                hintText: 'Type a message...',
                hintStyle: TextStyle(
                  color: Colors.white.withValues(alpha: 0.3),
                  fontSize: 15,
                ),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 11),
              ),
              maxLines: 4,
              minLines: 1,
            ),
          ),
        ),
        const SizedBox(width: 8),
        // Send/Mic button
        GestureDetector(
          onTap: hasText ? _sendTextMessage : _startRecording,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              gradient: hasText
                  ? const LinearGradient(
                      colors: [
                        Color(0xFFD946EF),
                        Color(0xFF7C3AED),
                        Color(0xFF06B6D4),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    )
                  : null,
              color: hasText ? null : const Color(0xFF1A1A28),
              borderRadius: BorderRadius.circular(14),
              boxShadow: hasText
                  ? [
                      BoxShadow(
                        color: const Color(0xFFD946EF).withValues(alpha: 0.35),
                        blurRadius: 10,
                        offset: const Offset(0, 2),
                      ),
                    ]
                  : null,
            ),
            child: Icon(
              hasText ? Icons.send_rounded : Icons.mic_rounded,
              color: hasText ? Colors.white : const Color(0xFFD946EF),
              size: 22,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRecordingUI() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFD946EF).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: const Color(0xFFD946EF).withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          // Recording indicator
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: const Color(0xFFFF007F),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFFF007F).withValues(alpha: 0.5),
                  blurRadius: 8,
                  spreadRadius: 2,
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // Duration
          Text(
            '${_recordDuration.inMinutes}:${(_recordDuration.inSeconds % 60).toString().padLeft(2, '0')}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            'Recording...',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.6),
              fontSize: 14,
            ),
          ),
          const Spacer(),
          // Cancel button
          GestureDetector(
            onTap: _cancelRecording,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
              ),
              child: const Text(
                'Cancel',
                style: TextStyle(
                  color: Colors.red,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          // Send button
          GestureDetector(
            onTap: _stopAndSendRecording,
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFFD946EF), Color(0xFF06B6D4)],
                ),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.send, color: Colors.white, size: 20),
            ),
          ),
        ],
      ),
    );
  }
}

class _WaveformPainter extends CustomPainter {
  final double progress;
  final Color color;

  static const List<double> _heights = [
    8, 14, 10, 22, 7, 18, 28, 12, 20, 6,
    26, 11, 17, 8, 24, 15, 9, 22, 7, 18,
    13, 20, 6, 24, 16, 10, 8, 19, 28, 11,
  ];

  const _WaveformPainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    const bars = 30;
    const barW = 2.5;
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
          ..color = isActive ? color : color.withValues(alpha: 0.22)
          ..strokeWidth = barW
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _WaveformPainter old) =>
      progress != old.progress || color != old.color;
}

class _ChatMediaViewerScreen extends StatefulWidget {
  final String url;
  final String type;
  final VoidCallback onDownload;

  const _ChatMediaViewerScreen({
    required this.url,
    required this.type,
    required this.onDownload,
  });

  @override
  State<_ChatMediaViewerScreen> createState() =>
      _ChatMediaViewerScreenState();
}

class _ChatMediaViewerScreenState extends State<_ChatMediaViewerScreen> {
  VideoPlayerController? _vpCtrl;
  ChewieController? _chewieCtrl;

  @override
  void initState() {
    super.initState();
    if (widget.type == 'video') {
      _vpCtrl =
          VideoPlayerController.networkUrl(Uri.parse(widget.url));
      _vpCtrl!.initialize().then((_) {
        if (!mounted) return;
        _chewieCtrl = ChewieController(
          videoPlayerController: _vpCtrl!,
          autoPlay: true,
          looping: false,
          materialProgressColors: ChewieProgressColors(
            playedColor: const Color(0xFFD946EF),
            handleColor: const Color(0xFFFF007F),
            bufferedColor: Colors.white24,
            backgroundColor: Colors.black26,
          ),
        );
        setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _chewieCtrl?.dispose();
    _vpCtrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.download_rounded),
            onPressed: widget.onDownload,
            tooltip: 'Save to gallery',
          ),
        ],
      ),
      body: Center(
        child: widget.type == 'video'
            ? (_chewieCtrl != null
                ? Chewie(controller: _chewieCtrl!)
                : const CircularProgressIndicator(
                    color: Color(0xFFD946EF)))
            : InteractiveViewer(
                minScale: 0.5,
                maxScale: 5.0,
                child: CachedNetworkImage(
                  imageUrl: widget.url,
                  fit: BoxFit.contain,
                  placeholder: (_, __) => const CircularProgressIndicator(
                      color: Color(0xFFD946EF)),
                  errorWidget: (_, __, ___) => const Icon(
                      Icons.broken_image,
                      color: Colors.white38,
                      size: 64),
                ),
              ),
      ),
    );
  }
}
