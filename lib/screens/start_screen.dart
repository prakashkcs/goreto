import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:love_vibe_pro/providers/auth_provider.dart';
import 'package:love_vibe_pro/screens/home_screen.dart';
import 'package:love_vibe_pro/screens/guest_main_screen.dart';
import 'package:love_vibe_pro/screens/auth/login_screen.dart';
import 'package:love_vibe_pro/screens/onboarding/terms_acceptance_screen.dart';
import 'package:love_vibe_pro/screens/onboarding/profile_setup_screen.dart';
import 'package:love_vibe_pro/screens/splash_screen.dart';
import 'package:love_vibe_pro/services/api_service.dart';
import 'package:love_vibe_pro/services/fcm_service.dart';
import 'package:love_vibe_pro/main.dart' show navigatorKey;
import 'package:love_vibe_pro/services/deep_link_service.dart';

/// Start Screen - shows animated splash, runs auth check in parallel,
/// then routes to the correct destination.
class StartScreen extends StatefulWidget {
  const StartScreen({super.key});

  @override
  State<StartScreen> createState() => _StartScreenState();
}

class _StartScreenState extends State<StartScreen> {
  bool _splashDone = false;
  bool _authDone = false;
  bool _termsAccepted = false;
  bool _onboardingDone = false;
  bool _deferredStartupTriggered = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initApp();
    });
  }

  Future<void> _initApp() async {
    if (!mounted) return;

    final auth = Provider.of<AuthProvider>(context, listen: false);
    final prefs = await SharedPreferences.getInstance();
    final termsAccepted = prefs.getBool('terms_accepted') ?? false;
    bool onboardingDone = prefs.getBool('onboarding_done') ?? false;

    await auth.checkAuth();

    // Reinstall case: account exists on the server but local prefs are blank,
    // so onboardingDone is falsely false. If the server-side profile already
    // has the fields ProfileSetupScreen collects (gender on the match
    // profile), treat onboarding as done and skip back to HomeScreen.
    if (!onboardingDone && auth.isAuthenticated) {
      try {
        final p = await ApiService().getMyMatchProfile();
        final profileMap = p['profile'];
        final gender = profileMap is Map
            ? (profileMap['gender']?.toString().trim() ?? '')
            : '';
        if (gender.isNotEmpty) {
          onboardingDone = true;
          await prefs.setBool('onboarding_done', true);
        }
      } catch (_) {
        // Network failure: leave onboardingDone as-is. Worst case the user
        // sees the setup screen once and can skip through; better than
        // sending an already-onboarded user back to setup every reinstall.
      }
    }

    if (!mounted) return;
    setState(() {
      _termsAccepted = termsAccepted;
      _onboardingDone = onboardingDone;
      _authDone = true;
    });

    _maybeNavigate();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _deferNonCriticalStartup();
    });
  }

  void _onSplashComplete() {
    if (!mounted) return;
    setState(() => _splashDone = true);
    _maybeNavigate();
  }

  void _maybeNavigate() {
    // Only navigate once both splash animation AND auth check are done
    if (!_splashDone || !_authDone) return;

    final auth = Provider.of<AuthProvider>(context, listen: false);

    Widget destination;
    if (!_termsAccepted) {
      destination = TermsAcceptanceScreen(onAccepted: _onTermsAccepted);
    } else if (auth.isAuthenticated && !_onboardingDone) {
      // New user: run profile + privacy onboarding before entering the app
      destination = ProfileSetupScreen(
        onComplete: () {
          navigatorKey.currentState?.pushReplacement(
            MaterialPageRoute(builder: (_) => const HomeScreen()),
          );
        },
      );
    } else if (auth.isAuthenticated) {
      destination = const HomeScreen();
    } else if (auth.isGuest) {
      destination = const GuestMainScreen();
    } else {
      destination = const LoginScreen();
    }

    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => destination,
        transitionsBuilder: (_, animation, __, child) {
          return FadeTransition(opacity: animation, child: child);
        },
        transitionDuration: const Duration(milliseconds: 400),
      ),
    );

    // After the destination is on screen, fire any pending deep-link
    // navigation. We must do this AFTER pushReplacement so the home/guest
    // screen is already the base of the stack; pushing PostDetailScreen on
    // top then works correctly. The 450ms matches the fade transition duration.
    if (auth.isAuthenticated || auth.isGuest) {
      Future.delayed(const Duration(milliseconds: 450), () {
        DeepLinkService.instance.fireInitialLink();
      });
    }
  }

  void _onTermsAccepted() {
    // StartScreen is already off the stack (pushReplacement), so use the
    // global navigatorKey instead of the unmounted StartScreen context.
    final ctx = navigatorKey.currentContext;
    if (ctx == null) return;
    final auth = Provider.of<AuthProvider>(ctx, listen: false);
    Widget destination;
    if (auth.isAuthenticated && !_onboardingDone) {
      destination = ProfileSetupScreen(
        onComplete: () {
          navigatorKey.currentState?.pushReplacement(
            MaterialPageRoute(builder: (_) => const HomeScreen()),
          );
        },
      );
    } else if (auth.isAuthenticated) {
      destination = const HomeScreen();
    } else if (auth.isGuest) {
      destination = const GuestMainScreen();
    } else {
      destination = const LoginScreen();
    }
    navigatorKey.currentState?.pushReplacement(
      MaterialPageRoute(builder: (_) => destination),
    );
  }

  void _deferNonCriticalStartup() {
    if (_deferredStartupTriggered) return;
    _deferredStartupTriggered = true;

    Future.delayed(const Duration(milliseconds: 600), () async {
      try {
        await FCMService.instance.init();
      } catch (_) {}
    });
  }

  @override
  Widget build(BuildContext context) {
    return SplashScreen(onComplete: _onSplashComplete);
  }
}
