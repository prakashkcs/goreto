import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Local-only store for users the current user has blocked from nearby alerts.
/// Blocked users will never trigger a nearby tray notification or in-app alert.
class NearbyBlockService {
  static final NearbyBlockService instance = NearbyBlockService._();
  NearbyBlockService._();

  static const _key = 'nearby_blocked_users_v1';

  Future<List<Map<String, String>>> getBlockedList() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_key) ?? [];
    return raw
        .map((s) {
          try {
            return Map<String, String>.from(
              (jsonDecode(s) as Map)
                  .map((k, v) => MapEntry(k.toString(), v.toString())),
            );
          } catch (_) {
            return <String, String>{};
          }
        })
        .where((m) => m.containsKey('id') && (m['id'] ?? '').isNotEmpty)
        .toList();
  }

  Future<bool> isBlocked(String userId) async {
    if (userId.isEmpty) return false;
    final list = await getBlockedList();
    return list.any((m) => m['id'] == userId);
  }

  Future<void> block(
    String userId, {
    String name = '',
    String avatar = '',
  }) async {
    if (userId.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final list = await getBlockedList();
    if (list.any((m) => m['id'] == userId)) return;
    list.add({'id': userId, 'name': name, 'avatar': avatar});
    await prefs.setStringList(_key, list.map(jsonEncode).toList());
  }

  Future<void> unblock(String userId) async {
    if (userId.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final list = await getBlockedList();
    list.removeWhere((m) => m['id'] == userId);
    await prefs.setStringList(_key, list.map(jsonEncode).toList());
  }
}
