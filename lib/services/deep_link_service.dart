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

  Uri? _pendingUri;

  // True once fireInitialLink() has been called (home screen is on screen).
  // Stream links that arrive before this point are queued, not routed
  // immediately — otherwise they land on top of StartScreen and get buried
  // when StartScreen calls pushReplacement(HomeScreen).
  bool _appReady = false;

  // Stored so fireInitialLink() can await it even if getInitialLink() is
  // still in-flight when the 450ms StartScreen delay fires.
  Future<void>? _initialLinkFuture;

  void init(GlobalKey<NavigatorState> navigatorKey) {
    _navigatorKey = navigatorKey;

    // Kick off getInitialLink() immediately and store the future.
    // We do NOT await here — we want main() to proceed to runApp().
    _initialLinkFuture = _appLinks
        .getInitialLink()
        .then((uri) {
          if (uri != null) {
            debugPrint('[DeepLink] cold-start URI: $uri');
            _pendingUri = uri;
          }
        })
        .catchError((_) {});

    // Stream handles warm/hot links (app already fully running).
    _sub = _appLinks.uriLinkStream.listen(_handleUri, onError: (_) {});
  }

  void dispose() {
    _sub?.cancel();
    _sub = null;
  }

  /// Called by StartScreen once the home/guest screen is on screen.
  /// Awaits getInitialLink() in case it hasn't resolved yet, then routes.
  Future<void> fireInitialLink() async {
    _appReady = true;

    // Await the initial link future. On slow devices getInitialLink() may
    // still be in-flight when the 450ms StartScreen delay fires.
    if (_initialLinkFuture != null) {
      await _initialLinkFuture;
      _initialLinkFuture = null;
    }

    final uri = _pendingUri;
    if (uri == null) return;

    final nav = _navigatorKey?.currentState;
    if (nav == null) {
      // Navigator not mounted yet — retry next frame.
      WidgetsBinding.instance.addPostFrameCallback((_) => fireInitialLink());
      return;
    }
    _pendingUri = null;
    debugPrint('[DeepLink] routing cold-start URI: $uri');
    _route(nav, uri);
  }

  void _handleUri(Uri uri) {
    debugPrint('[DeepLink] stream URI (appReady=$_appReady): $uri');

    if (!_appReady) {
      // Cold start: app hasn't navigated to the home screen yet.
      // Queue and let fireInitialLink() dispatch it.
      _pendingUri = uri;
      return;
    }

    final nav = _navigatorKey?.currentState;
    if (nav == null) {
      _pendingUri = uri;
      return;
    }
    _route(nav, uri);
  }

  void _route(NavigatorState nav, Uri uri) {
    // 1. Post link (highest priority — must beat profile ?id= check)
    final postId = _extractPostId(uri);
    if (postId != null && postId.isNotEmpty) {
      debugPrint('[DeepLink] → PostDetailScreen(postId=$postId)');
      nav.push(MaterialPageRoute(
        builder: (_) => PostDetailScreen(postId: postId),
      ));
      return;
    }

    // 2. Direct userId — only from goreto:// scheme or profile_preview.php
    final userId = _extractUserId(uri);
    if (userId != null && userId.isNotEmpty) {
      debugPrint('[DeepLink] → ProfileScreen(userId=$userId)');
      nav.push(MaterialPageRoute(
        builder: (_) => ProfileScreen(userId: userId),
      ));
      return;
    }

    // 3. Username resolution
    final username = _extractUsername(uri);
    if (username != null && username.isNotEmpty) {
      debugPrint('[DeepLink] → resolving username=$username');
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

    // goreto.org/{username}/{postId}  — 2-segment paths where first isn't a reserved word
    if (segs.length == 2) {
      const skip = {'ekloadmin', 'profile', 'u', 'post', 'api', 'admin'};
      if (!skip.contains(segs[0].toLowerCase())) return segs[1];
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

    if (_isGoretoHost(uri)) {
      // Path-based: .../profile/{userId} or .../u/{userId}
      //   e.g. https://goreto.org/ekloadmin/profile/16  (the share/copy-link
      //   format produced by manage_user_sheet.dart). Match a "profile"/"u"
      //   segment followed by an id segment anywhere in the path.
      for (var i = 0; i < segs.length - 1; i++) {
        final s = segs[i].toLowerCase();
        if (s == 'profile' || s == 'u') {
          final candidate = segs[i + 1];
          if (candidate.isNotEmpty) return candidate;
        }
      }

      // Query-based: .../profile_preview.php?id=123  or  .../profile.php?id=123
      // Only match when the path explicitly mentions "profile" — never match
      // view_post.php or other pages that also use ?id=.
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
      if (!skip.contains(segs[0].toLowerCase())) return segs[0];
    }

    return null;
  }

  bool _isGoretoHost(Uri uri) =>
      (uri.scheme == 'https' || uri.scheme == 'http') &&
      uri.host == 'goreto.org';

  Future<void> _resolveUsernameAndNavigate(
      NavigatorState nav, String username) async {
    // Try the ekloadmin profile_preview endpoint with username param
    const ekloadmin = 'https://goreto.org/ekloadmin';
    final candidates = [
      '$ekloadmin/profile_preview.php?username=${Uri.encodeComponent(username)}&format=json',
      '$ekloadmin/api/v1/profile_v19.php?action=get&username=${Uri.encodeComponent(username)}',
    ];
    for (final url in candidates) {
      try {
        final response =
            await http.get(Uri.parse(url)).timeout(const Duration(seconds: 6));
        if (response.statusCode == 200) {
          final body = response.body.trim();
          if (body.startsWith('{') || body.startsWith('[')) {
            final data = jsonDecode(body);
            final userId = (data is Map)
                ? (data['user_id'] ?? data['id'] ?? data['data']?['id'])
                    ?.toString()
                : null;
            if (userId != null && userId.isNotEmpty && userId != '0') {
              debugPrint('[DeepLink] resolved username=$username → userId=$userId');
              nav.push(MaterialPageRoute(
                builder: (_) => ProfileScreen(userId: userId),
              ));
              return;
            }
          }
        }
      } catch (_) {}
    }
    // Last resort: pass username directly — ProfileScreen may handle it
    debugPrint('[DeepLink] username resolution failed, passing as userId: $username');
    nav.push(MaterialPageRoute(
      builder: (_) => ProfileScreen(userId: username),
    ));
  }
}
