import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:love_vibe_pro/providers/auth_provider.dart';
import 'package:love_vibe_pro/widgets/neon_toast.dart';

/// Shown after a password login when the account has email 2FA enabled.
/// The server has already emailed a 6-digit code; the user enters it here.
/// Pops `true` once the session is established.
class TwoFactorLoginScreen extends StatefulWidget {
  final String email;

  /// Re-triggers the login request so the server emails a fresh code.
  final Future<void> Function() onResend;

  const TwoFactorLoginScreen({
    super.key,
    required this.email,
    required this.onResend,
  });

  @override
  State<TwoFactorLoginScreen> createState() => _TwoFactorLoginScreenState();
}

class _TwoFactorLoginScreenState extends State<TwoFactorLoginScreen> {
  final _codeCtrl = TextEditingController();
  bool _verifying = false;
  bool _resending = false;

  static const _pink = Color(0xFFFF007F);
  static const _bg = Color(0xFF0A0A0A);

  @override
  void dispose() {
    _codeCtrl.dispose();
    super.dispose();
  }

  String get _maskedEmail {
    final e = widget.email;
    final at = e.indexOf('@');
    if (at <= 1) return e;
    final name = e.substring(0, at);
    final masked = name.length <= 2
        ? '${name[0]}*'
        : '${name[0]}${'*' * (name.length - 2)}${name[name.length - 1]}';
    return '$masked${e.substring(at)}';
  }

  Future<void> _verify() async {
    final code = _codeCtrl.text.trim();
    if (code.length < 4) {
      NeonToast.error(context, 'Enter the 6-digit code');
      return;
    }
    setState(() => _verifying = true);
    try {
      final auth = Provider.of<AuthProvider>(context, listen: false);
      await auth.verifyTwoFactor(widget.email, code);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        NeonToast.error(context, e.toString().replaceAll('Exception: ', ''));
        setState(() => _verifying = false);
      }
    }
  }

  Future<void> _resend() async {
    setState(() => _resending = true);
    try {
      await widget.onResend();
      if (mounted) NeonToast.success(context, 'A new code has been sent');
    } catch (e) {
      if (mounted) {
        NeonToast.error(context, e.toString().replaceAll('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _resending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        leading: const BackButton(color: Colors.white),
        title: const Text('Verify it\'s you',
            style: TextStyle(color: Colors.white)),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: _pink.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.mark_email_unread_outlined,
                    color: _pink, size: 28),
              ),
              const SizedBox(height: 20),
              const Text(
                'Two-factor authentication',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Text(
                'We emailed a 6-digit code to $_maskedEmail. Enter it below to finish signing in.',
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.55),
                    fontSize: 14,
                    height: 1.5),
              ),
              const SizedBox(height: 28),
              TextField(
                controller: _codeCtrl,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(6),
                ],
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 12),
                decoration: InputDecoration(
                  hintText: '------',
                  hintStyle: TextStyle(
                      color: Colors.white.withValues(alpha: 0.2),
                      letterSpacing: 12),
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.05),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide:
                        BorderSide(color: _pink.withValues(alpha: 0.3)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: _pink, width: 1.5),
                  ),
                ),
                onSubmitted: (_) => _verify(),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _verifying ? null : _verify,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _pink,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: _pink.withValues(alpha: 0.3),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                  ),
                  child: _verifying
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2.5))
                      : const Text('Verify & sign in',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w700)),
                ),
              ),
              const SizedBox(height: 16),
              Center(
                child: TextButton(
                  onPressed: _resending ? null : _resend,
                  child: Text(
                    _resending ? 'Sending…' : 'Didn\'t get it? Resend code',
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.6),
                        fontSize: 13),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
