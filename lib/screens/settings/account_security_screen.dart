import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:love_vibe_pro/services/api_service.dart';
import 'package:love_vibe_pro/widgets/neon_toast.dart';
import 'package:love_vibe_pro/screens/auth/forgot_password_screen.dart';

class AccountSecurityScreen extends StatefulWidget {
  const AccountSecurityScreen({super.key});

  @override
  State<AccountSecurityScreen> createState() => _AccountSecurityScreenState();
}

class _AccountSecurityScreenState extends State<AccountSecurityScreen> {
  String _email = '';

  @override
  void initState() {
    super.initState();
    _loadEmail();
  }

  Future<void> _loadEmail() async {
    final prefs = await SharedPreferences.getInstance();
    final e = prefs.getString('user_email') ?? '';
    if (mounted) setState(() => _email = e);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A0A0A),
        leading: const BackButton(color: Colors.white),
        title: const Text('Account Security',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (_email.isNotEmpty)
              Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                ),
                child: Row(children: [
                  const Icon(Icons.email_outlined, color: Colors.white38, size: 18),
                  const SizedBox(width: 10),
                  Text('Logged in as $_email',
                      style: const TextStyle(color: Colors.white54, fontSize: 13)),
                ]),
              ),
            _tile(
              icon: Icons.email_outlined,
              label: 'Change Email',
              subtitle: _email.isNotEmpty ? 'Current: $_email' : 'Update your email address',
              color: const Color(0xFF06B6D4),
              onTap: _showChangeEmailDialog,
            ),
            const SizedBox(height: 12),
            _tile(
              icon: Icons.lock_outline,
              label: 'Change Password',
              subtitle: 'Update your password',
              color: const Color(0xFFD946EF),
              onTap: _showChangePasswordDialog,
            ),
            const SizedBox(height: 12),
            _tile(
              icon: Icons.lock_reset,
              label: 'Forgot Password',
              subtitle: _email.isNotEmpty
                  ? 'Reset password for $_email'
                  : 'Reset password via email',
              color: const Color(0xFF8B5CF6),
              onTap: () {
                // Pre-fill the email — no need to ask for it when it's known
                if (_email.isNotEmpty) {
                  Navigator.push(context, MaterialPageRoute(
                    builder: (_) => ForgotPasswordScreen(prefillEmail: _email),
                  ));
                } else {
                  Navigator.push(context, MaterialPageRoute(
                    builder: (_) => const ForgotPasswordScreen(),
                  ));
                }
              },
            ),
            const SizedBox(height: 12),
            _tile(
              icon: Icons.devices,
              label: 'Active Sessions',
              subtitle: 'View and manage logged-in devices',
              color: const Color(0xFFF97316),
              onTap: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const _SessionsScreen())),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tile({
    required IconData icon,
    required String label,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.mediumImpact();
        onTap();
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label,
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w600, fontSize: 15)),
              const SizedBox(height: 2),
              Text(subtitle,
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.5), fontSize: 12)),
            ]),
          ),
          Icon(Icons.chevron_right, color: Colors.white.withValues(alpha: 0.3)),
        ]),
      ),
    );
  }

  void _showChangeEmailDialog() {
    final emailController = TextEditingController();
    final passwordController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: Color(0xFF06B6D4), width: 1.2),
        ),
        title: const Text('Change Email', style: TextStyle(color: Colors.white)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          if (_email.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(children: [
                const Icon(Icons.info_outline, color: Colors.white38, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('Current: $_email',
                      style: const TextStyle(color: Colors.white54, fontSize: 12)),
                ),
              ]),
            ),
          _input(emailController, 'New email address', TextInputType.emailAddress),
          const SizedBox(height: 12),
          _input(passwordController, 'Current password', TextInputType.text, obscure: true),
        ]),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF06B6D4),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () async {
              final newEmail = emailController.text.trim();
              final password = passwordController.text;
              if (newEmail.isEmpty || password.isEmpty) return;
              Navigator.pop(ctx);
              try {
                await ApiService().changeEmail(newEmail, password);
                if (mounted) {
                  NeonToast.success(context, 'Email updated successfully');
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.setString('user_email', newEmail);
                  setState(() => _email = newEmail);
                }
              } catch (e) {
                if (mounted) NeonToast.error(context, e.toString().replaceAll('Exception: ', ''));
              }
            },
            child: const Text('Update'),
          ),
        ],
      ),
    );
  }

  void _showChangePasswordDialog() {
    final currentPwController = TextEditingController();
    final newPwController = TextEditingController();
    final confirmPwController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: Color(0xFFD946EF), width: 1.2),
        ),
        title: const Text('Change Password', style: TextStyle(color: Colors.white)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          _input(currentPwController, 'Current password', TextInputType.text, obscure: true),
          const SizedBox(height: 12),
          _input(newPwController, 'New password (min 6 chars)', TextInputType.text, obscure: true),
          const SizedBox(height: 12),
          _input(confirmPwController, 'Confirm new password', TextInputType.text, obscure: true),
        ]),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFD946EF),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () async {
              final current = currentPwController.text;
              final newPw = newPwController.text;
              final confirm = confirmPwController.text;
              if (current.isEmpty || newPw.isEmpty) return;
              if (newPw != confirm) {
                NeonToast.error(context, 'Passwords do not match');
                return;
              }
              if (newPw.length < 6) {
                NeonToast.error(context, 'Password must be at least 6 characters');
                return;
              }
              Navigator.pop(ctx);
              try {
                await ApiService().changePassword(current, newPw);
                if (mounted) NeonToast.success(context, 'Password updated successfully');
              } catch (e) {
                if (mounted) NeonToast.error(context, e.toString().replaceAll('Exception: ', ''));
              }
            },
            child: const Text('Update'),
          ),
        ],
      ),
    );
  }

  Widget _input(TextEditingController ctrl, String hint, TextInputType type,
      {bool obscure = false}) {
    return TextField(
      controller: ctrl,
      obscureText: obscure,
      keyboardType: type,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.3)),
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.05),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}

// ── Active Sessions Screen ─────────────────────────────────────────────────

class _SessionsScreen extends StatefulWidget {
  const _SessionsScreen();
  @override
  State<_SessionsScreen> createState() => _SessionsScreenState();
}

class _SessionsScreenState extends State<_SessionsScreen> {
  final ApiService _api = ApiService();
  List<dynamic> _sessions = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final sessions = await _api.getSessions();
    if (mounted) setState(() { _sessions = sessions; _isLoading = false; });
  }

  Future<void> _terminate(dynamic sessionId, int index) async {
    final ok = await _api.terminateSession(sessionId);
    if (!mounted) return;
    if (ok) {
      setState(() => _sessions.removeAt(index));
      NeonToast.success(context, 'Session terminated');
    } else {
      NeonToast.error(context, 'Failed to terminate session');
    }
  }

  Future<void> _logoutAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A28),
        title: const Text('Log out all other devices?',
            style: TextStyle(color: Colors.white, fontSize: 16)),
        content: const Text(
            'All sessions except this device will be signed out.',
            style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Log out all',
                  style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold))),
        ],
      ),
    );
    if (confirmed != true) return;
    final ok = await _api.logoutAllOtherSessions();
    if (!mounted) return;
    if (ok) {
      NeonToast.success(context, 'All other sessions terminated');
      _load();
    } else {
      NeonToast.error(context, 'Failed — try again');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A0A0A),
        leading: const BackButton(color: Colors.white),
        title: const Text('Active Sessions',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        actions: [
          if (!_isLoading && _sessions.length > 1)
            TextButton.icon(
              onPressed: _logoutAll,
              icon: const Icon(Icons.logout, size: 16, color: Colors.redAccent),
              label: const Text('Log out all',
                  style: TextStyle(color: Colors.redAccent, fontSize: 12)),
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFFD946EF)))
          : _sessions.isEmpty
              ? const Center(
                  child: Text('No active sessions',
                      style: TextStyle(color: Colors.white54)))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: _sessions.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final s = _sessions[index];
                      final device = (s['device'] ?? s['user_agent'] ?? 'Unknown device').toString();
                      final ip = (s['ip'] ?? s['ip_address'] ?? '').toString();
                      final lastActive = (s['last_active'] ?? s['created_at'] ?? '').toString();
                      final sessionId = s['id'] ?? s['session_id'];
                      final isCurrent = s['is_current'] == true;

                      return Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: isCurrent
                              ? const Color(0xFF22C55E).withValues(alpha: 0.08)
                              : const Color(0xFF1A1A1A),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: isCurrent
                                ? const Color(0xFF22C55E).withValues(alpha: 0.3)
                                : Colors.white.withValues(alpha: 0.08),
                          ),
                        ),
                        child: Row(children: [
                          Icon(
                            isCurrent ? Icons.phone_android : Icons.devices,
                            color: isCurrent ? const Color(0xFF22C55E) : Colors.white54,
                            size: 28,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(device,
                                      style: const TextStyle(
                                          color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis),
                                  if (ip.isNotEmpty)
                                    Text('IP: $ip',
                                        style: const TextStyle(color: Colors.white38, fontSize: 11)),
                                  if (lastActive.isNotEmpty)
                                    Text('Last active: $lastActive',
                                        style: const TextStyle(color: Colors.white38, fontSize: 11)),
                                  if (isCurrent)
                                    const Text('✓ This device',
                                        style: TextStyle(
                                            color: Color(0xFF22C55E),
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600)),
                                ]),
                          ),
                          if (!isCurrent && sessionId != null)
                            IconButton(
                              onPressed: () => _terminate(sessionId, index),
                              icon: const Icon(Icons.logout, color: Colors.redAccent, size: 20),
                              tooltip: 'Log out this device',
                            ),
                        ]),
                      );
                    },
                  ),
                ),
    );
  }
}
