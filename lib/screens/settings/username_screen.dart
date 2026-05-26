import 'dart:async';
import 'package:flutter/material.dart';
import 'package:love_vibe_pro/services/api_service.dart';
import 'package:love_vibe_pro/utils/date_util.dart';
import 'package:love_vibe_pro/widgets/neon_toast.dart';

class UsernameScreen extends StatefulWidget {
  const UsernameScreen({super.key});

  @override
  State<UsernameScreen> createState() => _UsernameScreenState();
}

class _UsernameScreenState extends State<UsernameScreen> {
  final _ctrl = TextEditingController();
  final _api = ApiService();

  bool _loading = true;
  bool _saving = false;
  bool? _available;
  bool _canChange = true;
  String? _canChangeAt;
  String? _timeRemaining;
  String? _currentUsername;
  String? _checkMsg;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await _api.getUsernameInfo();
      if (mounted) {
        setState(() {
          _currentUsername = res['username'];
          _canChange = res['can_change'] == true;
          _canChangeAt = res['can_change_at'];
          _timeRemaining = res['time_remaining']?.toString();
          _ctrl.text = _currentUsername ?? '';
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _onChanged(String val) {
    setState(() {
      _available = null;
      _checkMsg = null;
    });
    _debounce?.cancel();
    if (val.trim().length < 3) return;
    _debounce =
        Timer(const Duration(milliseconds: 600), () => _check(val.trim()));
  }

  Future<void> _check(String username) async {
    if (!_isValidFormat(username)) {
      setState(() {
        _available = false;
        _checkMsg = '3–30 chars: letters, numbers, underscores only';
      });
      return;
    }
    try {
      final res =
          await _api.postUsername({'action': 'check', 'username': username});
      if (mounted) {
        setState(() {
          _available = res['available'] == true;
          _checkMsg = _available! ? 'Available ✓' : 'Already taken';
        });
      }
    } catch (_) {}
  }

  bool _isValidFormat(String v) =>
      RegExp(r'^[a-z0-9_]{3,30}$').hasMatch(v.toLowerCase());

  /// Returns a human-readable countdown like "23 days, 4 hours left"
  String _buildCooldownText() {
    // Use DateUtil which correctly treats server timestamps as UTC
    final remaining = DateUtil.timeRemainingUntil(_canChangeAt);
    if (remaining != null) {
      return 'Can change in $remaining';
    }
    // If server gave us a pre-formatted string, fall back to it
    if (_timeRemaining != null && _timeRemaining!.isNotEmpty) {
      return 'Can change in $_timeRemaining';
    }
    if (_canChangeAt == null) {
      return 'You can change your username in 30 days.';
    }
    return 'Next change: ${DateUtil.formatUsernameAvailability(_canChangeAt)}';
  }

  Future<void> _save() async {
    final username = _ctrl.text.trim().toLowerCase();
    if (!_isValidFormat(username)) {
      NeonToast.error(
          context, '3–30 chars: letters, numbers, underscores only');
      return;
    }
    if (_available == false) {
      NeonToast.error(context, 'Username is taken');
      return;
    }
    setState(() => _saving = true);
    try {
      final res =
          await _api.postUsername({'action': 'update', 'username': username});
      if (mounted) {
        if (res['success'] == true) {
          NeonToast.success(context, res['msg'] ?? 'Username updated!');
          setState(() {
            _currentUsername = username;
            _canChange = false;
          });
          Navigator.pop(context, username);
        } else {
          NeonToast.error(context, res['msg'] ?? 'Failed to update');
        }
      }
    } catch (e) {
      if (mounted) NeonToast.error(context, 'Error: $e');
    }
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF111111),
        title: const Text('Username', style: TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFFD946EF)))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Info card
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A1A1A),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.alternate_email,
                            color: Color(0xFFD946EF), size: 22),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Your unique @username',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _canChange
                                    ? 'You can change it once every 30 days.'
                                    : _buildCooldownText(),
                                style: TextStyle(
                                  color: _canChange
                                      ? Colors.white54
                                      : const Color(0xFFFF6B6B),
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 28),

                  // Input
                  const Text('@username',
                      style: TextStyle(color: Colors.white70, fontSize: 13)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _ctrl,
                    enabled: _canChange,
                    onChanged: _onChanged,
                    style: const TextStyle(color: Colors.white, fontSize: 16),
                    decoration: InputDecoration(
                      prefixText: '@',
                      prefixStyle: const TextStyle(
                          color: Color(0xFFD946EF), fontSize: 16),
                      hintText: 'yourname',
                      hintStyle: const TextStyle(color: Colors.white24),
                      filled: true,
                      fillColor: const Color(0xFF1A1A1A),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: _available == null
                              ? Colors.white12
                              : _available!
                                  ? const Color(0xFF30D158)
                                  : const Color(0xFFFF3B30),
                          width: 1.5,
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: _available == null
                              ? const Color(0xFFD946EF)
                              : _available!
                                  ? const Color(0xFF30D158)
                                  : const Color(0xFFFF3B30),
                          width: 1.5,
                        ),
                      ),
                      suffixIcon: _ctrl.text.length >= 3
                          ? Icon(
                              _available == null
                                  ? Icons.hourglass_empty
                                  : _available!
                                      ? Icons.check_circle
                                      : Icons.cancel,
                              color: _available == null
                                  ? Colors.white38
                                  : _available!
                                      ? const Color(0xFF30D158)
                                      : const Color(0xFFFF3B30),
                            )
                          : null,
                    ),
                  ),

                  if (_checkMsg != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _checkMsg!,
                      style: TextStyle(
                        color: _available == true
                            ? const Color(0xFF30D158)
                            : const Color(0xFFFF3B30),
                        fontSize: 13,
                      ),
                    ),
                  ],

                  const SizedBox(height: 8),
                  const Text(
                    'Only letters (a–z), numbers, and underscores. 3–30 characters.',
                    style: TextStyle(color: Colors.white38, fontSize: 12),
                  ),

                  const SizedBox(height: 36),

                  // Save button
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: (_canChange && !_saving) ? _save : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFD946EF),
                        disabledBackgroundColor: Colors.white12,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                        elevation: 0,
                      ),
                      child: _saving
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                  color: Colors.white, strokeWidth: 2),
                            )
                          : Text(
                              _canChange
                                  ? 'Save Username'
                                  : 'Cannot Change Yet',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
