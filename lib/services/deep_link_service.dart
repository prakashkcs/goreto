import 'dart:async';
import 'dart:convert';
import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:love_vibe_pro/screens/profile/post_detail_screen.dart';
import 'package:love_vibe_pro/screens/profile_screen.dart';

/// Handles incoming deep links in two scenarios:
///   • Cold start  — app was not running; the link that launched it
///   • Warm/hot    — app already running; a new link arrives
///
/// Supported URL patterns (custom scheme + HTTPS):
///   goreto://post/{postId}
///   goreto://profile/{userId}
///   https://goreto.org/ekloadmin/view_post.php?id={postId}
///   https://goreto.org/ekloadmin/api/v1/view_post.php?id={postId}
///   https://goreto.org/{username}/{postId}
///   https://goreto.org/{username}
///   https://goreto.org/ekloadmin/profile_preview.php?id={userId}
///   https://goreto.org/ekloadmin/profile_preview.php?username={username}
class DeepLinkService {
  DeepLinkService._();
  static final DeepLinkService instance = DeepLinkService._();

  final AppLinks _appLinks = AppLinks();
  StreamSubscription<Uri>? _sub;
  GlobalKey<NavigatorState>? _navigatorKey;

  // Pend the initial link if the navigator isn't ready yet; retry on each frame
  Uri? _pendingUri;

  void init(GlobalKey<NavigatorState> navigatorKey) {
    _navigatorKey = navigatorKey;
    _handleInitialLink();
    _sub = _appLinks.uriLinkStream.listen(_handleUri, onError: (_) {});
  }

  void dispose() {
    _sub?.cancel();
    _sub = null;
  }

  /// Called by StartScreen once the home/guest screen is on screen.
  /// Routes any URI captured during cold start that couldn't be handled yet.
  void fireInitialLink() {
    final uri = _pendingUri;
    if (uri == null) return;
    final nav = _navigatorKey?.currentState;
    if (nav == null) {
      // Home screen transition hasn't finished yet — retry next frame.
      WidgetsBinding.instance.addPostFrameCallback((_) => fireInitialLink());
      return;
    }
    _pendingUri = null;
    _route(nav, uri);
  }

  Future<void> _handleInitialLink() async {
    try {
      final uri = await _appLinks.getInitialLink();
      if (uri != null) _handleUri(uri);
    } catch (_) {}
  }

  void _handleUri(Uri uri) {
    final nav = _navigatorKey?.currentState;
    if (nav == null) {
      // Cold start: navigator not mounted yet. Store the URI and wait for
      // StartScreen to call fireInitialLink() after the auth flow completes.
      // Do NOT auto-retry here — StartScreen.pushReplacement() would wipe any
      // screen we push now anyway.
      _pendingUri = uri;
      return;
    }
    // Warm/hot link (app already running): route immediately.
    _route(nav, uri);
  }

  void _route(NavigatorState nav, Uri uri) {
    // 1. Post link (highest priority — must beat profile ?id= check)
    final postId = _extractPostId(uri);
    if (postId != null && postId.isNotEmpty) {
      nav.push(MaterialPageRoute(
        builder: (_) => PostDetailScreen(postId: postId),
      ));
      return;
    }

    // 2. Direct userId — only from goreto:// scheme or profile_preview.php
    final userId = _extractUserId(uri);
    if (userId != null && userId.isNotEmpty) {
      nav.push(MaterialPageRoute(
        builder: (_) => ProfileScreen(userId: userId),
      ));
      return;
    }

    // 3. Username resolution
    final username = _extractUsername(uri);
    if (username != null && username.isNotEmpty) {
      _resolveUsernameAndNavigate(nav, username);
    }
  }

  // ── Extractors ────────────────────────────────────────────────────────────

  /// Post patterns:
  ///   goreto://post/{postId}
  ///   https://goreto.org/ekloadmin[/api/v1]/view_post.php?id={postId}
  ///   https://goreto.org/{username}/{postId}   (2-segment, first not a known prefix)
  String? _extractPostId(Uri uri) {
    final segs = uri.pathSegments.where((s) => s.isNotEmpty).toList();

    // Custom scheme
    if (uri.scheme == 'goreto') {
      if (segs.length >= 2 && segs[0] == 'post') return segs[1];
      return null;
    }

    if (!_isGoretoHost(uri)) return null;

    // Any URL whose path ends in a known post-page filename + has ?id=
    final last = segs.isNotEmpty ? segs.last.toLowerCase() : '';
    final qId = uri.queryParameters['id'] ?? uri.queryParameters['post_id'];
    const postPages = {'view_post.php', 'post_preview.php', 'share.php', 'post.php'};
    if (qId != null && qId.isNotEmpty && postPages.contains(last)) {
      return qId;
    }

    // goreto.org/{username}/{postId}  (no leading ekloadmin)
    if (segs.length == 2) {
      const skip = {'ekloadmin', 'profile', 'u', 'post', 'api', 'admin'};
      if (!skip.contains(segs[0])) return segs[1];
    }

    return null;
  }

  /// Profile patterns:
  ///   goreto://profile/{userId}
  ///   .../profile_preview.php?id={userId}    ← only when path explicitly says "profile"
  String? _extractUserId(Uri uri) {
    final segs = uri.pathSegments.where((s) => s.isNotEmpty).toList();

    // Custom scheme: goreto://profile/123
    if (uri.scheme == 'goreto' && segs.length >= 2 && segs[0] == 'profile') {
      return segs[1];
    }

    // HTTPS: .../profile_preview.php?id=123  or  .../profile.php?id=123
    // Only match when the path explicitly mentions "profile" — never match
    // view_post.php or other pages that also use ?id=.
    if (_isGoretoHost(uri)) {
      final last = segs.isNotEmpty ? segs.last.toLowerCase() : '';
      if (last.contains('profile')) {
        final id = uri.queryParameters['id'];
        if (id != null && id.isNotEmpty) return id;
      }
    }

    return null;
  }

  String? _extractUsername(Uri uri) {
    if (!_isGoretoHost(uri)) return null;

    final qUsername = uri.queryParameters['username'];
    if (qUsername != null && qUsername.isNotEmpty) return qUsername;

    final segs = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    if (segs.length == 1) {
      const skip = {'ekloadmin', 'profile', 'u', 'post', 'api', 'login', 'register', 'admin'};
      if (!skip.contains(segs[0])) return segs[0];
    }

    return null;
  }

  bool _isGoretoHost(Uri uri) =>
      (uri.scheme == 'https' || uri.scheme == 'http') &&
      uri.host == 'goreto.org';

  Future<void> _resolveUsernameAndNavigate(
      NavigatorState nav, String username) async {
    try {
      final url =
          'https://goreto.org/profile.php?username=${Uri.encodeComponent(username)}&format=json';
      final response =
          await http.get(Uri.parse(url)).timeout(const Duration(seconds: 8));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final userId = data['user_id']?.toString() ?? '';
        if (userId.isNotEmpty) {
          nav.push(MaterialPageRoute(
            builder: (_) => ProfileScreen(userId: userId),
          ));
          return;
        }
      }
    } catch (_) {}
    nav.push(MaterialPageRoute(
      builder: (_) => ProfileScreen(userId: username),
    ));
  }
}
