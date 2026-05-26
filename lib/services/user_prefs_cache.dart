import 'package:shared_preferences/shared_preferences.dart';

/// Singleton cache for frequently-accessed SharedPreferences values.
/// Eliminates per-widget async SharedPreferences.getInstance() calls
/// which cause disk I/O on every feed item mount.
class UserPrefsCache {
  UserPrefsCache._();
  static final UserPrefsCache _instance = UserPrefsCache._();
  static UserPrefsCache get instance => _instance;

  SharedPreferences? _prefs;
  bool _initialized = false;

  String? _userId;
  String? _authToken;
  Set<String> _likedPostIds = {};

  // ── Getters (synchronous — no disk I/O) ─────────────────────────────────
  String? get userId => _userId;
  String? get authToken => _authToken;
  bool get isInitialized => _initialized;

  bool isPostLiked(dynamic postId) =>
      _likedPostIds.contains(postId?.toString());

  // ── Initialize (call once at startup) ───────────────────────────────────
  Future<void> init() async {
    if (_initialized) return;
    _prefs = await SharedPreferences.getInstance();
    _userId =
        _prefs!.getString('user_id') ?? _prefs!.getInt('user_id')?.toString();
    _authToken =
        _prefs!.getString('auth_token') ?? _prefs!.getString('app_token');
    _likedPostIds = (_prefs!.getStringList('liked_post_ids') ?? []).toSet();
    _initialized = true;
  }

  // ── Mutators (write-through) ────────────────────────────────────────────
  Future<void> setUserId(String id) async {
    _userId = id;
    await _prefs?.setString('user_id', id);
  }

  Future<void> setAuthToken(String token) async {
    _authToken = token;
    await _prefs?.setString('auth_token', token);
  }

  void addLikedPost(dynamic postId) {
    final pid = postId?.toString();
    if (pid == null) return;
    _likedPostIds.add(pid);
    _prefs?.setStringList('liked_post_ids', _likedPostIds.toList());
  }

  void removeLikedPost(dynamic postId) {
    final pid = postId?.toString();
    if (pid == null) return;
    _likedPostIds.remove(pid);
    _prefs?.setStringList('liked_post_ids', _likedPostIds.toList());
  }

  /// Re-read prefs from disk (e.g. after login)
  Future<void> refresh() async {
    _initialized = false;
    await init();
  }
}
