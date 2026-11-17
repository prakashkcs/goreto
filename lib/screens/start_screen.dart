import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:love_vibe_pro/providers/auth_provider.dart';
import 'package:love_vibe_pro/screens/home_screen.dart';
import 'package:love_vibe_pro/screens/onboarding/terms_acceptance_screen.dart';
import 'package:love_vibe_pro/screens/onboarding/profile_setup_screen.dart';
import 'package:love_vibe_pro/screens/splash_screen.dart';
import 'package:love_vibe_pro/services/api_service.dart';
import 'package:love_vibe_pro/services/settings_store.dart';
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
  bool _navigated = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initApp();
    });
    // Hard safety net: if anything stalls, force navigation after 9s so the
    // app can never be stuck on the splash forever.
    Future.delayed(const Duration(seconds: 9), () {
      if (!mounted || _navigated) return;
      setState(() {
        _splashDone = true;
        _authDone = true;
      });
      _maybeNavigate();
    });
  }

  Future<void> _initApp() async {
    if (!mounted) return;

    final auth = Provider.of<AuthProvider>(context, listen: false);
    var termsAccepted = false;
    var onboardingDone = false;

    // The whole startup check is wrapped so a thrown error or a hung network
    // can NEVER leave the app stuck on the splash — _authDone is always set.
    try {
      final prefs = await SharedPreferences.getInstance();
      // Auth check with a timeout (token read / socket connect can stall).
      await auth
          .checkAuth()
          .timeout(const Duration(seconds: 8), onTimeout: () {});

      termsAccepted = prefs.getBool('terms_accepted') ?? false;
      if (auth.isAuthenticated) {
        if (!termsAccepted) {
          try {
            if (await ApiService()
                .getTermsStatus()
                .timeout(const Duration(seconds: 8))) {
              termsAccepted = true;
              await prefs.setBool('terms_accepted', true);
            }
          } catch (_) {}
        } else if (!(prefs.getBool('terms_server_synced') ?? false)) {
          ApiService().acceptTermsOnServer();
          await prefs.setBool('terms_server_synced', true);
        }
      }

      onboardingDone = prefs.getBool('onboarding_done') ?? false;
      if (!onboardingDone &&
          auth.isAuthenticated &&
          !(prefs.getBool('onboarding_server_checked') ?? false)) {
        try {
          final p = await ApiService()
              .getMyMatchProfile()
              .timeout(const Duration(seconds: 8));
          final profileMap = p['profile'];
          final gender = profileMap is Map
              ? (profileMap['gender']?.toString().trim() ?? '')
              : '';
          if (gender.isNotEmpty) {
            onboardingDone = true;
            await prefs.setBool('onboarding_done', true);
          }
          await prefs.setBool('onboarding_server_checked', true);
        } catch (_) {}
      }
    } catch (_) {
      // Swallow — never block startup on an error.
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
    if (!_splashDone || !_authDone || _navigated) return;
    _navigated = true;

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
    } else {
      // Not logged in → browse as a guest by default (no forced login screen).
      // Guests get the same HomeScreen as everyone else so the app doesn't
      // change shape after signing in; HomeScreen already gates the Match /
      // Chat / Profile tabs and posting behind LoginRequiredSheet.
      destination = const HomeScreen();
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
    // Fire any pending deep link once we're on a browse screen (Home or the
    // guest experience) — not while on the Terms/Onboarding gates.
    final onBrowseScreen =
        _termsAccepted && !(auth.isAuthenticated && !_onboardingDone);
    if (onBrowseScreen) {
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
      destination = const HomeScreen();
    } else {
      // First visit / signed out: go straight to guest browsing instead of
      // forcing account creation. Any activity (like, comment, message, post…)
      // prompts sign-up from within guest mode.
      auth.enterGuestMode();
      destination = const HomeScreen();
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

    // Pre-fetch wallet balance so Settings and other screens that read
    // from SettingsStore show the real balance immediately without the
    // user having to open the Wallet page first.
    Future.delayed(const Duration(milliseconds: 800), () async {
      final auth = Provider.of<AuthProvider>(navigatorKey.currentContext!, listen: false);
      if (!auth.isAuthenticated) return;
      try {
        final walletInfo = await ApiService().getWalletBalanceRemote();
        final store = await SettingsStore.getInstance();
        await store.setWalletBalance(walletInfo.coins.toDouble());
      } catch (_) {}
    });
  }

  @override
  Widget build(BuildContext context) {
    return SplashScreen(onComplete: _onSplashComplete);
  }
}
