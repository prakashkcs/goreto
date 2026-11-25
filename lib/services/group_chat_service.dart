import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart' as dio;
import 'package:http/http.dart' as http;
import 'package:love_vibe_pro/models/group_chat.dart';
import 'package:love_vibe_pro/config/app_env.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Result of a call that can fail with a user-facing message.
class GroupResult {
  final bool success;
  final String message;
  final String? state;
  final ChatGroup? group;
  final String? suggestion;

  const GroupResult({
    required this.success,
    this.message = '',
    this.state,
    this.group,
    this.suggestion,
  });
}

class GroupChatService {
  // Standard headers for all requests — User-Agent bypasses Imunify360 WAF.
  static const Map<String, String> _baseHeaders = {
    'User-Agent': 'GoretoApp/1.0 (Android; Flutter)',
    'Connection': 'close',
  };

  /// Largest video we try to upload; bigger files fail server-side anyway.
  static const int maxVideoBytes = 95 * 1024 * 1024;

  /// Pending invitation count from the last my_groups call.
  static int lastPendingInvites = 0;

  Future<String?> _getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('app_token');
  }

  Map<String, String> _authHeaders(String token) => {
        ..._baseHeaders,
        'Authorization': 'Bearer $token',
      };

  Map<String, String> _jsonHeaders(String token) => {
        ..._authHeaders(token),
        'Content-Type': 'application/json',
      };

  String _baseUrlSync(String baseUrl) {
    return baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
  }

  Future<Uri> _uri(String action, [Map<String, String>? query]) async {
    final baseUrl = _baseUrlSync(await AppEnv.getBaseUrlAsync());
    return Uri.parse('$baseUrl/group_chat.php').replace(
      queryParameters: {'action': action, ...?query},
    );
  }

  Map<String, dynamic> _decode(String body) {
    try {
      final d = json.decode(body);
      if (d is Map<String, dynamic>) return d;
      if (d is Map) return Map<String, dynamic>.from(d);
    } catch (_) {}
    return {};
  }

  /// GET helper. Returns the decoded body (empty map on failure).
  Future<Map<String, dynamic>> _get(String action,
      [Map<String, String>? query]) async {
    final token = await _getToken();
    if (token == null) return {};
    try {
      final res = await http
          .get(await _uri(action, query), headers: _authHeaders(token))
          .timeout(const Duration(seconds: 20));
      final data = _decode(res.body);
      data['_code'] = res.statusCode;
      return data;
    } catch (_) {
      return {};
    }
  }

  /// JSON POST helper. Returns the decoded body (empty map on failure).
  Future<Map<String, dynamic>> _post(
      String action, Map<String, dynamic> body) async {
    final token = await _getToken();
    if (token == null) return {'message': 'Please log in again'};
    try {
      final res = await http
          .post(await _uri(action),
              headers: _jsonHeaders(token), body: jsonEncode(body))
          .timeout(const Duration(seconds: 25));
      final data = _decode(res.body);
      data['_code'] = res.statusCode;
      return data;
    } catch (_) {
      return {'message': 'Network error. Please try again.'};
    }
  }

  bool _ok(Map<String, dynamic> d) => d['status'] == 'success';

  GroupResult _result(Map<String, dynamic> d, {String fallback = 'Something went wrong'}) {
    final g = d['group'];
    return GroupResult(
      success: _ok(d),
      message: (d['message'] ?? (_ok(d) ? '' : fallback)).toString(),
      state: d['state']?.toString(),
      group: g is Map ? ChatGroup.fromJson(Map<String, dynamic>.from(g)) : null,
      suggestion: d['suggestion']?.toString(),
    );
  }

  // ── Groups ────────────────────────────────────────────────────────────────

  Future<List<ChatGroup>> listAllGroups({String? search}) async {
    final data = await _get('list_all', {
      if (search != null && search.isNotEmpty) 'search': search,
    });
    if (_ok(data) && data['groups'] is List) {
      return (data['groups'] as List)
          .map((g) => ChatGroup.fromJson(Map<String, dynamic>.from(g)))
          .toList();
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
    final data = await _get('my_groups');
    if (_ok(data) && data['groups'] is List) {
      lastPendingInvites = int.tryParse('${data['pending_invites'] ?? 0}') ?? 0;
      final groups = (data['groups'] as List)
          .map((g) => ChatGroup.fromJson(Map<String, dynamic>.from(g)))
          .toList();
      final prefs = await SharedPreferences.getInstance();
      prefs.setString(_myGroupsCacheKey, json.encode(data['groups']));
      return groups;
    }
    throw Exception('Could not load groups');
  }

  Future<ChatGroup?> getGroupDetails(int groupId) async {
    final data = await _get('get_group', {'group_id': '$groupId'});
    if (_ok(data) && data['group'] is Map) {
      return ChatGroup.fromJson(Map<String, dynamic>.from(data['group']));
    }
    return null;
  }

  Future<UsernameCheck> checkUsername(String username,
      {int groupId = 0, String? name}) async {
    final data = await _get('check_username', {
      'username': username,
      if (groupId > 0) 'group_id': '$groupId',
      if (name != null && name.isNotEmpty) 'name': name,
    });
    return UsernameCheck(
      username: (data['username'] ?? username).toString(),
      valid: data['valid'] == true,
      available: data['available'] == true,
      message: data['message']?.toString(),
      suggestion: data['suggestion']?.toString(),
    );
  }

  Future<ChatGroup?> createGroup(
    String name, {
    String? username,
    String? bio,
    int joinFee = 0,
    int monthlyFee = 0,
    bool isPrivate = false,
    bool joinApproval = false,
    String? avatarPath,
  }) async {
    final token = await _getToken();
    if (token == null) {
      throw Exception('Authentication failed. Please login again.');
    }

    final request = http.MultipartRequest('POST', await _uri('create'));
    request.headers.addAll(_authHeaders(token));
    request.fields['name'] = name;
    if (username != null && username.isNotEmpty) {
      request.fields['username'] = username;
    }
    if (bio != null && bio.isNotEmpty) request.fields['bio'] = bio;
    request.fields['join_fee'] = joinFee.toString();
    request.fields['monthly_fee'] = monthlyFee.toString();
    request.fields['is_private'] = isPrivate ? '1' : '0';
    request.fields['join_approval'] = joinApproval ? '1' : '0';

    if (avatarPath != null && avatarPath.isNotEmpty) {
      request.files.add(await http.MultipartFile.fromPath('avatar', avatarPath));
    }

    final response = await request.send().timeout(const Duration(seconds: 60));
    final body = await response.stream.bytesToString();
    final data = _decode(body);
    if (response.statusCode == 200 && _ok(data) && data['group'] is Map) {
      return ChatGroup.fromJson(Map<String, dynamic>.from(data['group']));
    }
    throw Exception(data['message']?.toString() ??
        'Failed to create group (${response.statusCode})');
  }

  /// Joins a group, or files a join request when approval is required.
  /// `msg` is a user-facing message; `state` is joined | requested.
  Future<Map<String, dynamic>> joinGroup(int groupId) async {
    final data = await _post('join', {'group_id': groupId});
    return {
      'success': _ok(data),
      'state': data['state'] ?? (_ok(data) ? 'joined' : null),
      'msg': data['message'] ?? (_ok(data) ? '' : 'Error joining group'),
    };
  }

  Future<bool> cancelJoinRequest(int groupId) async =>
      _ok(await _post('cancel_request', {'group_id': groupId}));

  Future<bool> leaveGroup(int groupId) async =>
      _ok(await _post('leave', {'group_id': groupId}));

  Future<bool> deleteGroup(int groupId) async =>
      _ok(await _post('delete_group', {'group_id': groupId}));

  Future<bool> clearMyChat(int groupId) async =>
      _ok(await _post('clear_my_chat', {'group_id': groupId}));

  /// Updates group settings. Only non-null fields are sent. The returned
  /// [GroupResult.group] is the fresh server copy (e.g. with the new avatar).
  Future<GroupResult> updateSettings(
    int groupId, {
    String? name,
    String? username,
    String? bio,
    String? avatarPath,
    bool? isPrivate,
    bool? joinApproval,
    bool? membersCanInvite,
    int? joinFee,
    int? monthlyFee,
    int? messageDelay,
    GroupPermissions? permissions,
  }) async {
    final token = await _getToken();
    if (token == null) {
      return const GroupResult(success: false, message: 'Please log in again');
    }

    final fields = <String, dynamic>{'group_id': groupId};
    if (name != null) fields['name'] = name;
    if (username != null) fields['username'] = username;
    if (bio != null) fields['bio'] = bio;
    if (isPrivate != null) fields['is_private'] = isPrivate ? 1 : 0;
    if (joinApproval != null) fields['join_approval'] = joinApproval ? 1 : 0;
    if (membersCanInvite != null) {
      fields['members_can_invite'] = membersCanInvite ? 1 : 0;
    }
    if (joinFee != null) fields['join_fee'] = joinFee;
    if (monthlyFee != null) fields['monthly_fee'] = monthlyFee;
    if (messageDelay != null) fields['message_delay'] = messageDelay;
    if (permissions != null) fields['permissions'] = permissions.toJson();

    try {
      if (avatarPath != null) {
        final request =
            http.MultipartRequest('POST', await _uri('update_settings'));
        request.headers.addAll(_authHeaders(token));
        fields.forEach((k, v) {
          request.fields[k] = v is Map ? jsonEncode(v) : v.toString();
        });
        request.files
            .add(await http.MultipartFile.fromPath('avatar', avatarPath));
        final response =
            await request.send().timeout(const Duration(seconds: 60));
        final body = await response.stream.bytesToString();
        return _result(_decode(body), fallback: 'Could not update photo');
      }
      return _result(await _post('update_settings', fields),
          fallback: 'Could not save changes');
    } catch (_) {
      return const GroupResult(
          success: false, message: 'Network error. Please try again.');
    }
  }

  // ── Messages ──────────────────────────────────────────────────────────────

  Future<GroupSyncResult> syncMessages(int groupId,
      {int lastId = 0, String? since}) async {
    final data = await _get('sync', {
      'group_id': '$groupId',
      'last_id': '$lastId',
      if (since != null && since.isNotEmpty) 'since': since,
    });
    if (data['_code'] == 403) return const GroupSyncResult(notMember: true);
    if (!_ok(data)) return const GroupSyncResult();
    final msgs = (data['messages'] as List? ?? [])
        .map((m) => GroupMessage.fromJson(Map<String, dynamic>.from(m)))
        .toList();
    final changes = (data['changes'] as List? ?? [])
        .map((c) => GroupMessageChange.fromJson(Map<String, dynamic>.from(c)))
        .toList();
    return GroupSyncResult(
      messages: msgs,
      changes: changes,
      serverTime: data['server_time']?.toString(),
    );
  }

  Future<GroupResult> sendMessage(int groupId, String message,
      {String type = 'text'}) async {
    final data = await _post(
        'send', {'group_id': groupId, 'message': message, 'type': type});
    return _result(data, fallback: 'Message not sent');
  }

  Future<GroupResult> editMessage(int messageId, String text) async =>
      _result(await _post('edit_message', {'message_id': messageId, 'message': text}),
          fallback: 'Could not edit message');

  /// [scope] is `me` (hide for me) or `everyone` (unsend).
  Future<GroupResult> deleteMessage(int messageId, {required String scope}) async =>
      _result(await _post('delete_message', {'message_id': messageId, 'scope': scope}),
          fallback: 'Could not delete message');

  Future<Map<String, dynamic>> sendVoiceMessage(
    int groupId,
    String audioPath,
    Duration duration,
  ) =>
      sendMedia(groupId, audioPath, 'audio',
          extra: {'voice_duration': duration.inSeconds.toString()});

  /// Uploads an image / video / voice note with progress reporting.
  Future<Map<String, dynamic>> sendMedia(
    int groupId,
    String path,
    String type, {
    Map<String, String> extra = const {},
    void Function(double progress)? onProgress,
  }) async {
    final token = await _getToken();
    if (token == null) return {'success': false, 'msg': 'Please log in again'};

    final file = File(path);
    if (!await file.exists()) {
      return {'success': false, 'msg': 'File not found'};
    }
    final size = await file.length();
    if (type == 'video' && size > maxVideoBytes) {
      return {
        'success': false,
        'msg':
            'Video is too large (${(size / 1048576).toStringAsFixed(0)} MB). Please pick one under ${maxVideoBytes ~/ 1048576} MB.'
      };
    }

    final client = dio.Dio(dio.BaseOptions(
      connectTimeout: const Duration(seconds: 20),
      sendTimeout: const Duration(minutes: 10),
      receiveTimeout: const Duration(minutes: 2),
      headers: _authHeaders(token),
      validateStatus: (_) => true,
    ));
    try {
      final form = dio.FormData.fromMap({
        'group_id': groupId.toString(),
        'type': type,
        ...extra,
        'media': await dio.MultipartFile.fromFile(path,
            filename: path.split(Platform.pathSeparator).last.split('/').last),
      });
      final res = await client.post(
        (await _uri('send_media')).toString(),
        data: form,
        onSendProgress: (sent, total) {
          if (onProgress != null && total > 0) onProgress(sent / total);
        },
      );
      dynamic body = res.data;
      if (body is String) body = _decode(body);
      final data = body is Map ? Map<String, dynamic>.from(body) : <String, dynamic>{};
      if (res.statusCode == 413) {
        return {
          'success': false,
          'msg': data['message'] ?? 'File is too large for the server.'
        };
      }
      return {
        'success': _ok(data),
        'msg': data['message'] ??
            (_ok(data) ? '' : 'Upload failed (${res.statusCode})'),
      };
    } on dio.DioException catch (e) {
      final msg = e.type == dio.DioExceptionType.sendTimeout ||
              e.type == dio.DioExceptionType.receiveTimeout
          ? 'Upload timed out. Try a shorter video or a better connection.'
          : 'Upload failed. Check your connection and try again.';
      return {'success': false, 'msg': msg};
    } catch (_) {
      return {'success': false, 'msg': 'Upload failed. Please try again.'};
    } finally {
      client.close();
    }
  }

  // ── Members ───────────────────────────────────────────────────────────────

  Future<List<ChatGroupMember>> getMembers(int groupId) async =>
      (await getGroupMembers(groupId))['members'] as List<ChatGroupMember>;

  Future<Map<String, dynamic>> getGroupMembers(int groupId) async {
    final data = await _get('get_members', {'group_id': '$groupId'});
    if (_ok(data)) {
      return {
        'my_role': data['my_role'] ?? 'member',
        'owner_id': int.tryParse('${data['owner_id'] ?? 0}') ?? 0,
        'members': (data['members'] as List?)
                ?.map((m) => ChatGroupMember.fromJson(Map<String, dynamic>.from(m)))
                .toList() ??
            <ChatGroupMember>[],
      };
    }
    return {'my_role': 'member', 'owner_id': 0, 'members': <ChatGroupMember>[]};
  }

  Future<GroupResult> kickMember(int groupId, int userId) async =>
      _result(await _post('kick', {'group_id': groupId, 'target_id': userId}),
          fallback: 'Could not remove member');

  Future<GroupResult> banMember(int groupId, int userId) async =>
      _result(await _post('ban', {'group_id': groupId, 'target_id': userId}),
          fallback: 'Could not ban member');

  Future<GroupResult> setRole(int groupId, int userId, String role) async =>
      _result(
          await _post('set_role',
              {'group_id': groupId, 'target_id': userId, 'role': role}),
          fallback: 'Could not change role');

  // ── Invitations & join requests ───────────────────────────────────────────

  /// People to invite: suggestions (friends / follows) when [query] is empty,
  /// otherwise a name / @username search. Each carries its group status.
  Future<List<GroupInvitee>> searchInvitees(int groupId, String query) async {
    final data = await _get('search_invitees', {
      'group_id': '$groupId',
      'q': query.trim(),
    });
    if (_ok(data) && data['users'] is List) {
      return (data['users'] as List)
          .map((u) => GroupInvitee.fromJson(Map<String, dynamic>.from(u)))
          .toList();
    }
    return [];
  }

  /// Sends invitations. Returns the message plus a per-user status map.
  Future<Map<String, dynamic>> inviteUsers(int groupId, List<int> userIds) async {
    final data = await _post('invite', {'group_id': groupId, 'user_ids': userIds});
    final results = <int, String>{};
    final raw = data['results'];
    if (raw is Map) {
      raw.forEach((k, v) {
        final id = int.tryParse(k.toString());
        if (id != null) results[id] = v.toString();
      });
    }
    return {
      'success': _ok(data),
      'msg': data['message'] ?? (_ok(data) ? 'Invitations sent' : 'Could not send invitations'),
      'results': results,
    };
  }

  Future<Map<String, dynamic>> inviteByUserId(int groupId, int userId) async {
    final r = await inviteUsers(groupId, [userId]);
    return {'success': r['success'], 'msg': r['msg']};
  }

  Future<Map<String, dynamic>> inviteByUsername(int groupId, String username) async {
    final data = await _post('invite', {'group_id': groupId, 'username': username});
    return {'success': _ok(data), 'msg': data['message'] ?? ''};
  }

  Future<List<GroupInvite>> getMyInvites() async {
    final data = await _get('my_invites');
    if (_ok(data) && data['invites'] is List) {
      final list = (data['invites'] as List)
          .map((i) => GroupInvite.fromJson(Map<String, dynamic>.from(i)))
          .toList();
      lastPendingInvites = list.length;
      return list;
    }
    return [];
  }

  Future<GroupResult> respondInvite(int inviteId, bool accept) async =>
      _result(await _post('respond_invite', {'invite_id': inviteId, 'accept': accept}),
          fallback: 'Could not respond to invitation');

  Future<bool> cancelInvite(int inviteId) async =>
      _ok(await _post('cancel_invite', {'invite_id': inviteId}));

  /// Admin view: pending join requests and outgoing invites.
  Future<Map<String, List<GroupPendingUser>>> getRequests(int groupId) async {
    final data = await _get('get_requests', {'group_id': '$groupId'});
    List<GroupPendingUser> parse(dynamic v) => v is List
        ? v.map((e) => GroupPendingUser.fromJson(Map<String, dynamic>.from(e))).toList()
        : <GroupPendingUser>[];
    return {
      'requests': parse(data['requests']),
      'invites': parse(data['invites']),
    };
  }

  Future<GroupResult> handleRequest(int requestId, bool approve) async =>
      _result(await _post('handle_request', {'request_id': requestId, 'approve': approve}),
          fallback: 'Could not update request');
}
