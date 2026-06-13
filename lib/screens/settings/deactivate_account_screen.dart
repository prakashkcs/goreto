import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:love_vibe_pro/services/api_service.dart';
import 'package:love_vibe_pro/providers/auth_provider.dart';
import 'package:provider/provider.dart';
import 'package:love_vibe_pro/widgets/neon_toast.dart';
import 'package:love_vibe_pro/screens/start_screen.dart';

class DeactivateAccountScreen extends StatefulWidget {
  const DeactivateAccountScreen({super.key});

  @override
  State<DeactivateAccountScreen> createState() => _DeactivateAccountScreenState();
}

class _DeactivateAccountScreenState extends State<DeactivateAccountScreen> {
  String? _selectedPeriod; // '1d', '7d', 'login'
  bool _isLoading = false;
  final ApiService _api = ApiService();

  static const _orange = Color(0xFFFF9500);
  static const _bg = Color(0xFF0A0A0A);

  final _periods = [
    {
      'value': '1d',
      'label': '1 Day',
      'desc': 'Reactivates automatically after 24 hours',
      'icon': Icons.timer_outlined,
    },
    {
      'value': '7d',
      'label': '1 Week',
      'desc': 'Reactivates automatically after 7 days',
      'icon': Icons.date_range_outlined,
    },
    {
      'value': 'login',
      'label': 'Until Next Login',
      'desc': 'Reactivates the moment you log back in',
      'icon': Icons.login_rounded,
    },
  ];

  Future<void> _confirm() async {
    if (_selectedPeriod == null) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: _orange.withValues(alpha: 0.5), width: 1.2),
        ),
        title: const Row(
          children: [
            Icon(Icons.pause_circle_outline, color: _orange),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Deactivate Account?',
                style: TextStyle(color: Colors.white, fontSize: 17),
              ),
            ),
          ],
        ),
        content: const Text(
          'Your profile will be hidden and others won\'t be able to find or message you during this period. '
          'Your data is safe and will be restored when you come back.',
          style: TextStyle(color: Colors.white70, height: 1.5, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: _orange,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Deactivate'),
          ),
        ],
      ),
    );

    if (ok != true || !mounted) return;

    HapticFeedback.mediumImpact();
    setState(() => _isLoading = true);

    try {
      await _api.deactivateAccount(_selectedPeriod!);
      if (!mounted) return;

      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF1A1A1A),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: _orange.withValues(alpha: 0.5), width: 1.2),
          ),
          title: const Row(
            children: [
              Icon(Icons.check_circle, color: Color(0xFF22C55E)),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Account Deactivated',
                  style: TextStyle(color: Colors.white, fontSize: 16),
                ),
              ),
            ],
          ),
          content: const Text(
            'Your account is now hidden from others. '
            'Log back in anytime to restore it.',
            style: TextStyle(color: Colors.white70, height: 1.5),
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx),
              style: ElevatedButton.styleFrom(
                backgroundColor: _orange,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('OK'),
            ),
          ],
        ),
      );

      // Deactivation hides the account from others — log the user out so the
      // account is actually inaccessible until they sign back in (which
      // reactivates it). Navigate to the auth/start screen.
      if (!mounted) return;
      await context.read<AuthProvider>().logout();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const StartScreen()),
        (route) => false,
      );
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        NeonToast.error(context, 'Error: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        leading: const BackButton(color: Colors.white),
        title: const Text(
          'Deactivate Account',
          style: TextStyle(color: Colors.white),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Info card
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _orange.withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: _orange.withValues(alpha: 0.25)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.pause_circle_outline, color: _orange, size: 26),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Temporary Deactivation',
                            style: TextStyle(
                              color: _orange,
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            'Your profile, posts, and messages stay intact. '
                            'Others won\'t be able to see or contact you until you return.',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.65),
                              fontSize: 13,
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 28),

              const Text(
                'How long do you want to be away?',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),

              const SizedBox(height: 14),

              ..._periods.map((p) => _PeriodCard(
                value: p['value'] as String,
                label: p['label'] as String,
                desc: p['desc'] as String,
                icon: p['icon'] as IconData,
                selected: _selectedPeriod == p['value'],
                onTap: () => setState(() => _selectedPeriod = p['value'] as String),
              )),

              const SizedBox(height: 32),

              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: (_selectedPeriod != null && !_isLoading) ? _confirm : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _orange,
                    disabledBackgroundColor: _orange.withValues(alpha: 0.25),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: _selectedPeriod != null ? 6 : 0,
                    shadowColor: _orange.withValues(alpha: 0.4),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2.5,
                          ),
                        )
                      : const Text(
                          'Deactivate Account',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                ),
              ),

              const SizedBox(height: 16),

              Center(
                child: Text(
                  'You can reactivate anytime by logging back in',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.3),
                    fontSize: 12,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),

              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}

class _PeriodCard extends StatelessWidget {
  final String value;
  final String label;
  final String desc;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _PeriodCard({
    required this.value,
    required this.label,
    required this.desc,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  static const _orange = Color(0xFFFF9500);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: selected ? _orange.withValues(alpha: 0.12) : Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? _orange : Colors.white.withValues(alpha: 0.12),
            width: selected ? 1.5 : 1,
          ),
          boxShadow: selected
              ? [BoxShadow(color: _orange.withValues(alpha: 0.2), blurRadius: 12)]
              : null,
        ),
        child: Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: selected ? _orange.withValues(alpha: 0.2) : Colors.white.withValues(alpha: 0.06),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: selected ? _orange : Colors.white54, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      color: selected ? Colors.white : Colors.white.withValues(alpha: 0.85),
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    desc,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.45),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected ? _orange : Colors.white.withValues(alpha: 0.25),
                  width: 2,
                ),
                color: selected ? _orange : Colors.transparent,
              ),
              child: selected
                  ? const Icon(Icons.check, color: Colors.white, size: 13)
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}
