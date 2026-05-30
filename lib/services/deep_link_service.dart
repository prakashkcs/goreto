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

  void init(GlobalKey<NavigatorState> navigatorKey) {
    _navigatorKey = navigatorKey;
    _handleInitialLink();
    _sub = _appLinks.uriLinkStream.listen(_handleUri, onError: (_) {});
  }

  void dispose() {
    _sub?.cancel();
    _sub = null;
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
      WidgetsBinding.instance.addPostFrameCallback((_) => _handleUri(uri));
      return;
    }

    // 1. Check for post link first (takes priority over profile)
    final postId = _extractPostId(uri);
    if (postId != null && postId.isNotEmpty) {
      nav.push(MaterialPageRoute(
        builder: (_) => PostDetailScreen(postId: postId),
      ));
      return;
    }

    // 2. Check for direct userId (custom scheme or profile_preview.php?id=X)
    final userId = _extractUserId(uri);
    if (userId != null && userId.isNotEmpty) {
      nav.push(MaterialPageRoute(
        builder: (_) => ProfileScreen(userId: userId),
      ));
      return;
    }

    // 3. Username resolution — goreto.org/{username} or ?username=X
    final username = _extractUsername(uri);
    if (username != null && username.isNotEmpty) {
      _resolveUsernameAndNavigate(nav, username);
    }
  }

  /// goreto://post/{postId}
  /// https://goreto.org/{username}/{postId}
  /// https://goreto.org/ekloadmin/view_post.php?id={postId}
  /// https://goreto.org/ekloadmin/api/v1/...?post_id={postId}
  String? _extractPostId(Uri uri) {
    final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();

    if (uri.scheme == 'goreto') {
      if (segments.length >= 2 && segments[0] == 'post') return segments[1];
      return null;
    }

    if (!_isGoretoHost(uri)) return null;

    // view_post.php?id=123 or any page with ?post_id=
    final qId = uri.queryParameters['id'] ?? uri.queryParameters['post_id'];
    final lastSegment = segments.isNotEmpty ? segments.last : '';
    if (qId != null && qId.isNotEmpty &&
        (lastSegment.contains('post') || lastSegment.contains('view') || lastSegment.contains('share'))) {
      return qId;
    }

    // goreto.org/{username}/{postId}
    if (segments.length >= 2) {
      const skip = {'ekloadmin', 'profile', 'u', 'post', 'api'};
      if (!skip.contains(segments[0])) return segments[1];
    }
    return null;
  }

  /// goreto://profile/{userId}  or  profile_preview.php?id={userId}
  String? _extractUserId(Uri uri) {
    final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();

    // Custom scheme: goreto://profile/123
    if (uri.scheme == 'goreto' && segments.length >= 2 && segments[0] == 'profile') {
      return segments[1];
    }

    // HTTPS: .../profile_preview.php?id=123
    if (_isGoretoHost(uri)) {
      final id = uri.queryParameters['id'];
      if (id != null && id.isNotEmpty) return id;
    }

    return null;
  }

  /// Extracts a username from:
  ///   https://goreto.org/{username}   (single-segment, not a known path)
  ///   https://goreto.org/ekloadmin/profile_preview.php?username={username}
  String? _extractUsername(Uri uri) {
    if (!_isGoretoHost(uri)) return null;

    // ?username= query param (from profile_preview.php)
    final qUsername = uri.queryParameters['username'];
    if (qUsername != null && qUsername.isNotEmpty) return qUsername;

    // Single-segment path: goreto.org/{username}
    final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    if (segments.length == 1) {
      const skip = {'ekloadmin', 'profile', 'u', 'post', 'api', 'login', 'register'};
      if (!skip.contains(segments[0])) return segments[0];
    }

    return null;
  }

  bool _isGoretoHost(Uri uri) =>
      (uri.scheme == 'https' || uri.scheme == 'http') && uri.host == 'goreto.org';

  /// Calls goreto.org/profile.php?username=X&format=json to resolve username → userId,
  /// then navigates to ProfileScreen.
  Future<void> _resolveUsernameAndNavigate(
      NavigatorState nav, String username) async {
    try {
      final url = 'https://goreto.org/profile.php?username=${Uri.encodeComponent(username)}&format=json';
      final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 8));
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
    // Fallback: pass username directly — ProfileScreen may handle it
    nav.push(MaterialPageRoute(
      builder: (_) => ProfileScreen(userId: username),
    ));
  }
}
