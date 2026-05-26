import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:love_vibe_pro/models/group_chat.dart';
import 'package:love_vibe_pro/config/app_env.dart';
import 'package:shared_preferences/shared_preferences.dart';

class GroupChatService {
  // Standard headers for all requests — User-Agent bypasses Imunify360 WAF.
  static const Map<String, String> _baseHeaders = {
    'User-Agent': 'GoretoApp/1.0 (Android; Flutter)',
    'Connection': 'close',
  };

  Future<String?> _getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('app_token');
  }

  Map<String, String> _authHeaders(String token) => {
        ..._baseHeaders,
        'Authorization': 'Bearer $token',
      };

  String _baseUrlSync(String baseUrl) {
    return baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
  }

  Future<List<ChatGroup>> listAllGroups({String? search}) async {
    final token = await _getToken();
    if (token == null) return [];

    final baseUrl = _baseUrlSync(await AppEnv.getBaseUrlAsync());
    final uri = Uri.parse('$baseUrl/group_chat.php').replace(
      queryParameters: {
        'action': 'list_all',
        if (search != null && search.isNotEmpty) 'search': search,
      },
    );
    final response = await http.get(
      uri,
      headers: _authHeaders(token),
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      if (data['status'] == 'success') {
        return (data['groups'] as List)
            .map((g) => ChatGroup.fromJson(g))
            .toList();
      }
    }
    return [];
  }

  static const String _myGroupsCacheKey = 'cached_my_groups';

  Future<List<ChatGroup>> getCachedGroups() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_myGroupsCacheKey);
      if (raw == null) return [];
      final list = json.decode(raw) as List<dynamic>;
      return list
          .map((g) => ChatGroup.fromJson(Map<String, dynamic>.from(g as Map)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<List<ChatGroup>> getMyGroups() async {
    final token = await _getToken();
    if (token == null) return [];

    final baseUrl = _baseUrlSync(await AppEnv.getBaseUrlAsync());
    final response = await http.get(
      Uri.parse('$baseUrl/group_chat.php?action=my_groups'),
      headers: _authHeaders(token),
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      if (data['status'] == 'success') {
        final groups = (data['groups'] as List)
            .map((g) => ChatGroup.fromJson(g))
            .toList();
        final prefs = await SharedPreferences.getInstance();
        prefs.setString(_myGroupsCacheKey, json.encode(data['groups']));
        return groups;
      }
    }
    return [];
  }

  Future<ChatGroup?> createGroup(
    String name, {
    String? username,
    String? bio,
    int joinFee = 0,
    int monthlyFee = 0,
    bool isPrivate = false,
    String? avatarPath,
  }) async {
    final token = await _getToken();
    if (token == null) {
      throw Exception('Authentication failed. Please login again.');
    }

    final baseUrl = _baseUrlSync(await AppEnv.getBaseUrlAsync());

    // Always use MultipartRequest for consistency with server
    var request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/group_chat.php?action=create'),
    );
    request.headers.addAll(_authHeaders(token));
    request.fields['name'] = name;
    if (username != null && username.isNotEmpty) {
      request.fields['username'] = username;
    }
    if (bio != null && bio.isNotEmpty) {
      request.fields['bio'] = bio;
    }
    request.fields['join_fee'] = joinFee.toString();
    request.fields['monthly_fee'] = monthlyFee.toString();
    request.fields['is_private'] = isPrivate ? '1' : '0';

    if (avatarPath != null && avatarPath.isNotEmpty) {
      try {
        request.files.add(
          await http.MultipartFile.fromPath('avatar', avatarPath),
        );
      } catch (_) {}
    }

    try {
      var response = await request.send();
      final body = await response.stream.bytesToString();

      if (response.statusCode == 200) {
        final data = json.decode(body);
        if (data['status'] == 'success' && data['group'] != null) {
          return ChatGroup.fromJson(data['group']);
        }
        throw Exception(data['message']?.toString() ?? 'Unknown error');
      } else {
        String msg = 'Failed to create group (${response.statusCode})';
        try {
          final err = json.decode(body);
          if (err['message'] != null) msg = err['message'].toString();
        } catch (_) {}
        throw Exception(msg);
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<Map<String, dynamic>> joinGroup(int groupId) async {
    final token = await _getToken();
    if (token == null) return {'success': false, 'msg': 'Auth error'};

    final baseUrl = _baseUrlSync(await AppEnv.getBaseUrlAsync());
    final response = await http.post(
      Uri.parse('$baseUrl/group_chat.php?action=join'),
      headers: {
        ..._authHeaders(token),
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'group_id': groupId}),
    );

    final data = json.decode(response.body);
    return {
      'success': response.statusCode == 200 && data['status'] == 'success',
      'msg': data['message'] ?? 'Error joining group',
    };
  }

  Future<bool> leaveGroup(int groupId) async {
    final token = await _getToken();
    if (token == null) return false;

    final baseUrl = _baseUrlSync(await AppEnv.getBaseUrlAsync());
    final response = await http.post(
      Uri.parse('$baseUrl/group_chat.php?action=leave'),
      headers: {
        ..._authHeaders(token),
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'group_id': groupId}),
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      return data['status'] == 'success';
    }
    return false;
  }

  Future<ChatGroup?> getGroupDetails(int groupId) async {
    final token = await _getToken();
    if (token == null) return null;

    final baseUrl = _baseUrlSync(await AppEnv.getBaseUrlAsync());
    final response = await http.get(
      Uri.parse('$baseUrl/group_chat.php?action=get_group&group_id=$groupId'),
      headers: _authHeaders(token),
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      if (data['status'] == 'success' && data['group'] != null) {
        return ChatGroup.fromJson(data['group']);
      }
    }
    return null;
  }

  Future<List<GroupMessage>> syncMessages(int groupId, {int lastId = 0}) async {
    final token = await _getToken();
    if (token == null) return [];

    final baseUrl = _baseUrlSync(await AppEnv.getBaseUrlAsync());
    final response = await http.get(
      Uri.parse(
        '$baseUrl/group_chat.php?action=sync&group_id=$groupId&last_id=$lastId',
      ),
      headers: _authHeaders(token),
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      if (data['status'] == 'success' && data['messages'] != null) {
        return (data['messages'] as List)
            .map((m) => GroupMessage.fromJson(m))
            .toList();
      }
    }
    return [];
  }

  Future<void> sendMessage(
    int groupId,
    String message, {
    String type = 'text',
  }) async {
    final token = await _getToken();
    if (token == null) return;

    final baseUrl = _baseUrlSync(await AppEnv.getBaseUrlAsync());
    await http.post(
      Uri.parse('$baseUrl/group_chat.php?action=send'),
      headers: {
        ..._authHeaders(token),
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'group_id': groupId, 'message': message, 'type': type}),
    );
  }

  Future<Map<String, dynamic>> sendVoiceMessage(
    int groupId,
    String audioPath,
    Duration duration,
  ) async {
    final token = await _getToken();
    if (token == null) return {'success': false, 'msg': 'Auth error'};

    final baseUrl = _baseUrlSync(await AppEnv.getBaseUrlAsync());
    var request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/group_chat.php?action=send_media'),
    );
    request.headers.addAll(_authHeaders(token));
    request.fields['group_id'] = groupId.toString();
    request.fields['type'] = 'audio';
    request.fields['voice_duration'] = duration.inSeconds.toString();
    request.files.add(await http.MultipartFile.fromPath('media', audioPath));

    final response = await request.send();
    final body = await response.stream.bytesToString();
    if (response.statusCode == 200) {
      final data = json.decode(body);
      return {'success': data['status'] == 'success', 'msg': data['message'] ?? ''};
    }
    return {'success': false, 'msg': 'Server error: ${response.statusCode}'};
  }

  Future<Map<String, dynamic>> sendMedia(
    int groupId,
    String path,
    String type,
  ) async {
    final token = await _getToken();
    if (token == null) return {'success': false, 'msg': 'Auth error'};

    final baseUrl = _baseUrlSync(await AppEnv.getBaseUrlAsync());
    var request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/group_chat.php?action=send_media'),
    );
    request.headers.addAll(_authHeaders(token));
    request.fields['group_id'] = groupId.toString();
    request.fields['type'] = type;
    request.files.add(await http.MultipartFile.fromPath('media', path));

    var response = await request.send();
    final body = await response.stream.bytesToString();

    if (response.statusCode == 200) {
      final data = json.decode(body);
      return {
        'success': data['status'] == 'success',
        'msg': data['message'] ?? '',
      };
    }
    return {'success': false, 'msg': 'Server error: ${response.statusCode}'};
  }

  Future<List<ChatGroupMember>> getMembers(int groupId) async {
    final token = await _getToken();
    if (token == null) return [];

    final baseUrl = _baseUrlSync(await AppEnv.getBaseUrlAsync());
    final response = await http.get(
      Uri.parse('$baseUrl/group_chat.php?action=get_members&group_id=$groupId'),
      headers: _authHeaders(token),
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      if (data['status'] == 'success') {
        return (data['members'] as List)
            .map((m) => ChatGroupMember.fromJson(m))
            .toList();
      }
    }
    return [];
  }

  Future<bool> updateSettings(
    int groupId, {
    String? name,
    String? username,
    String? bio,
    String? avatarPath,
    bool? isPrivate,
    int? joinFee,
    int? monthlyFee,
    int? messageDelay,
    GroupPermissions? permissions,
  }) async {
    final token = await _getToken();
    if (token == null) return false;

    final baseUrl = _baseUrlSync(await AppEnv.getBaseUrlAsync());

    if (avatarPath != null) {
      var request = http.MultipartRequest(
        'POST',
        Uri.parse('$baseUrl/group_chat.php?action=update_settings'),
      );
      request.headers.addAll(_authHeaders(token));
      request.fields['group_id'] = groupId.toString();
      if (name != null) request.fields['name'] = name;
      if (username != null) request.fields['username'] = username;
      if (bio != null) request.fields['bio'] = bio;
      if (isPrivate != null) {
        request.fields['is_private'] = isPrivate ? '1' : '0';
      }
      if (joinFee != null) request.fields['join_fee'] = joinFee.toString();
      if (monthlyFee != null) {
        request.fields['monthly_fee'] = monthlyFee.toString();
      }
      if (messageDelay != null) {
        request.fields['message_delay'] = messageDelay.toString();
      }
      if (permissions != null) {
        request.fields['permissions'] = jsonEncode(permissions.toJson());
      }
      request.files.add(
        await http.MultipartFile.fromPath('avatar', avatarPath),
      );

      var response = await request.send();
      if (response.statusCode == 200) {
        final body = await response.stream.bytesToString();
        final data = json.decode(body);
        return data['status'] == 'success';
      }
      return false;
    }

    final body = <String, dynamic>{'group_id': groupId};
    if (name != null) body['name'] = name;
    if (username != null) body['username'] = username;
    if (bio != null) body['bio'] = bio;
    if (isPrivate != null) body['is_private'] = isPrivate ? '1' : '0';
    if (joinFee != null) body['join_fee'] = joinFee;
    if (monthlyFee != null) body['monthly_fee'] = monthlyFee;
    if (messageDelay != null) body['message_delay'] = messageDelay;
    if (permissions != null) body['permissions'] = permissions.toJson();

    final response = await http.post(
      Uri.parse('$baseUrl/group_chat.php?action=update_settings'),
      headers: {
        ..._authHeaders(token),
        'Content-Type': 'application/json',
      },
      body: jsonEncode(body),
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      return data['status'] == 'success';
    }
    return false;
  }

  Future<Map<String, dynamic>> getGroupMembers(int groupId) async {
    final token = await _getToken();
    if (token == null) {
      return {'my_role': 'member', 'members': <ChatGroupMember>[]};
    }

    final baseUrl = _baseUrlSync(await AppEnv.getBaseUrlAsync());
    final response = await http.get(
      Uri.parse('$baseUrl/group_chat.php?action=get_members&group_id=$groupId'),
      headers: _authHeaders(token),
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      if (data['status'] == 'success') {
        return {
          'my_role': data['my_role'] ?? 'member',
          'members': (data['members'] as List?)
                  ?.map((m) => ChatGroupMember.fromJson(m))
                  .toList() ??
              <ChatGroupMember>[],
        };
      }
    }
    return {'my_role': 'member', 'members': <ChatGroupMember>[]};
  }

  Future<bool> deleteGroup(int groupId) async {
    final token = await _getToken();
    if (token == null) return false;

    final baseUrl = _baseUrlSync(await AppEnv.getBaseUrlAsync());
    final response = await http.post(
      Uri.parse('$baseUrl/group_chat.php?action=delete_group'),
      headers: {
        ..._authHeaders(token),
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'group_id': groupId}),
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      return data['status'] == 'success';
    }
    return false;
  }

  Future<bool> clearMyChat(int groupId) async {
    final token = await _getToken();
    if (token == null) return false;

    final baseUrl = _baseUrlSync(await AppEnv.getBaseUrlAsync());
    final response = await http.post(
      Uri.parse('$baseUrl/group_chat.php?action=clear_my_chat'),
      headers: {
        ..._authHeaders(token),
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'group_id': groupId}),
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      return data['status'] == 'success';
    }
    return false;
  }

  Future<bool> kickMember(int groupId, int userId) async {
    final token = await _getToken();
    if (token == null) return false;

    final baseUrl = _baseUrlSync(await AppEnv.getBaseUrlAsync());
    final response = await http.post(
      Uri.parse('$baseUrl/group_chat.php?action=kick'),
      headers: {
        ..._authHeaders(token),
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'group_id': groupId, 'target_id': userId}),
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      return data['status'] == 'success';
    }
    return false;
  }

  Future<bool> banMember(int groupId, int userId) async {
    final token = await _getToken();
    if (token == null) return false;

    final baseUrl = _baseUrlSync(await AppEnv.getBaseUrlAsync());
    final response = await http.post(
      Uri.parse('$baseUrl/group_chat.php?action=ban'),
      headers: {
        ..._authHeaders(token),
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'group_id': groupId, 'target_id': userId}),
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      return data['status'] == 'success';
    }
    return false;
  }

  Future<bool> setRole(int groupId, int userId, String role) async {
    final token = await _getToken();
    if (token == null) return false;

    final baseUrl = _baseUrlSync(await AppEnv.getBaseUrlAsync());
    final response = await http.post(
      Uri.parse('$baseUrl/group_chat.php?action=set_role'),
      headers: {
        ..._authHeaders(token),
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'group_id': groupId,
        'target_id': userId,
        'role': role,
      }),
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      return data['status'] == 'success';
    }
    return false;
  }

  Future<Map<String, dynamic>> inviteByUsername(
    int groupId,
    String username,
  ) async {
    final token = await _getToken();
    if (token == null) return {'success': false, 'msg': 'Auth error'};

    final baseUrl = _baseUrlSync(await AppEnv.getBaseUrlAsync());
    final response = await http.post(
      Uri.parse('$baseUrl/group_chat.php?action=invite'),
      headers: {
        ..._authHeaders(token),
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'group_id': groupId, 'username': username}),
    );

    final data = json.decode(response.body);
    return {
      'success': data['status'] == 'success',
      'msg': data['message'] ?? '',
    };
  }

  Future<List<Map<String, dynamic>>> searchUsers(String query) async {
    if (query.trim().isEmpty) return [];
    final token = await _getToken();
    if (token == null) return [];

    final baseUrl = _baseUrlSync(await AppEnv.getBaseUrlAsync());
    final uri = Uri.parse('$baseUrl/search.php').replace(
      queryParameters: {'action': 'users', 'q': query.trim()},
    );
    try {
      final response = await http.get(uri, headers: _authHeaders(token));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'success') {
          final raw = data['users'] ?? data['results'] ?? [];
          return List<Map<String, dynamic>>.from(raw);
        }
      }
    } catch (_) {}
    return [];
  }

  Future<Map<String, dynamic>> inviteByUserId(
    int groupId,
    int userId,
  ) async {
    final token = await _getToken();
    if (token == null) return {'success': false, 'msg': 'Auth error'};

    final baseUrl = _baseUrlSync(await AppEnv.getBaseUrlAsync());
    final response = await http.post(
      Uri.parse('$baseUrl/group_chat.php?action=invite'),
      headers: {
        ..._authHeaders(token),
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'group_id': groupId, 'user_id': userId}),
    );

    final data = json.decode(response.body);
    return {
      'success': data['status'] == 'success',
      'msg': data['message'] ?? '',
    };
  }
}
