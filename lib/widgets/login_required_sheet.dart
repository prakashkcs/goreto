import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:love_vibe_pro/providers/auth_provider.dart';
import 'package:love_vibe_pro/widgets/neon_ui.dart';
import 'package:love_vibe_pro/screens/auth/login_screen.dart';

/// Premium iOS-26 "Liquid Love" Login Required Sheet
/// Shown when guest user tries to access restricted features
class LoginRequiredSheet extends StatelessWidget {
  final String? message;
  final String? feature;

  const LoginRequiredSheet({super.key, this.message, this.feature});

  /// Static method to show the sheet
  static Future<void> show(BuildContext context, {String? feature}) {
    return showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => LoginRequiredSheet(feature: feature),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.55,
      ),
      decoration: const BoxDecoration(
        color: Color(0xEB0B0713), // #0B0713 with 92% opacity
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
        border: Border(top: BorderSide(width: 1.2, color: Colors.transparent)),
      ),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
          gradient: LinearGradient(
            colors: [
              LiquidLoveTokens.accentPink.withValues(alpha: 0.15),
              LiquidLoveTokens.accentPurple.withValues(alpha: 0.08),
              LiquidLoveTokens.accentCyan.withValues(alpha: 0.05),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Drag handle
                Container(
                  width: 44,
                  height: 5,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(2.5),
                  ),
                ),
                const SizedBox(height: 28),

                // Lock icon
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [
                        LiquidLoveTokens.accentPink.withValues(alpha: 0.2),
                        LiquidLoveTokens.accentPurple.withValues(alpha: 0.1),
                      ],
                    ),
                    border: Border.all(
                      color: LiquidLoveTokens.accentPink.withValues(alpha: 0.5),
                      width: 2,
                    ),
                  ),
                  child: const Icon(
                    Icons.lock_outline_rounded,
                    size: 32,
                    color: LiquidLoveTokens.accentPink,
                  ),
                ),
                const SizedBox(height: 20),

                // Title
                const Text(
                  'Login required',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 12),

                // Message
                Text(
                  message ??
                      'Create an account to ${feature ?? "match, message, like, and post"}.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.7),
                    fontSize: 15,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 28),

                // Login button
                NeonButtonPrimary(
                  text: 'Login',
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const LoginScreen()),
                    );
                  },
                ),
                const SizedBox(height: 12),

                // Signup button
                GlassButton(
                  text: 'Sign up',
                  isOutlined: true,
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const SignupScreen()),
                    );
                  },
                ),
                const SizedBox(height: 16),

                // Continue browsing
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(
                    'Continue browsing',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.5),
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Helper function to check auth and show sheet if needed
/// Returns true if authenticated, false if guest (shows sheet)
bool requireAuth(BuildContext context, {String? feature}) {
  try {
    final authProvider = context.read<AuthProvider>();

    if (authProvider.isAuthenticated) {
      return true;
    }

    // Show login required sheet
    LoginRequiredSheet.show(context, feature: feature);
    return false;
  } catch (e) {
    // If AuthProvider is not available, return true to avoid blocking
    return true;
  }
}
