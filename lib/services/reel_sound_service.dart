import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/reel_sound.dart';
import '../config/app_env.dart';

class ReelSoundService {
  static final ReelSoundService _i = ReelSoundService._();
  factory ReelSoundService() => _i;
  ReelSoundService._();

  /// api_sounds.php lives one level above api/v1/, at the ekloadmin root.
  /// AppEnv.baseUrl is e.g. "https://goreto.org/ekloadmin/api/v1/"
  /// so we strip the trailing api/v1 segment.
  String get _base {
    final root = AppEnv.baseUrl
        .replaceAll(RegExp(r'/api/v1/?$'), '')
        .replaceAll(RegExp(r'/$'), '');
    return '$root/api_sounds.php';
  }

  Future<Map<String, String>> _headers() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');
    return {
      'Content-Type': 'application/json',
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
  }

  /// Fetch paginated list of sounds (newest first)
  Future<List<ReelSound>> fetchSounds({int limit = 30, int offset = 0}) async {
    final uri = Uri.parse('$_base?action=list&limit=$limit&offset=$offset');
    final res = await http
        .get(uri, headers: await _headers())
        .timeout(const Duration(seconds: 15));
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    if (body['status'] != 'success') return [];
    return (body['sounds'] as List)
        .map((e) => ReelSound.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Fetch trending sounds (most used)
  Future<List<ReelSound>> fetchTrending({int limit = 30}) async {
    final uri = Uri.parse('$_base?action=trending&limit=$limit');
    final res = await http
        .get(uri, headers: await _headers())
        .timeout(const Duration(seconds: 15));
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    if (body['status'] != 'success') return [];
    return (body['sounds'] as List)
        .map((e) => ReelSound.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Search sounds by title
  Future<List<ReelSound>> search(String query, {int limit = 30}) async {
    final uri = Uri.parse(
        '$_base?action=search&q=${Uri.encodeComponent(query)}&limit=$limit');
    final res = await http
        .get(uri, headers: await _headers())
        .timeout(const Duration(seconds: 15));
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    if (body['status'] != 'success') return [];
    return (body['sounds'] as List)
        .map((e) => ReelSound.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Extract audio from an uploaded video post (server-side FFmpeg).
  /// Call this right after a reel is uploaded, passing the new post_id.
  Future<ReelSound?> extractFromPost(int postId, {String title = ''}) async {
    final res = await http
        .post(
          Uri.parse(_base),
          headers: await _headers(),
          body: jsonEncode(
              {'action': 'extract', 'post_id': postId, 'title': title}),
        )
        .timeout(const Duration(seconds: 60));
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    if (body['status'] != 'success') return null;
    return ReelSound.fromJson(body['sound'] as Map<String, dynamic>);
  }

  /// Record that a post is using a sound (increments use_count on server).
  Future<bool> recordUse(int soundId, int postId) async {
    final res = await http
        .post(
          Uri.parse(_base),
          headers: await _headers(),
          body: jsonEncode(
              {'action': 'use', 'sound_id': soundId, 'post_id': postId}),
        )
        .timeout(const Duration(seconds: 15));
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    return body['status'] == 'success';
  }
}
