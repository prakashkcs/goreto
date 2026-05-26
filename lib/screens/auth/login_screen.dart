import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:love_vibe_pro/providers/auth_provider.dart';
import 'package:love_vibe_pro/screens/auth/signup_screen.dart';
import 'package:love_vibe_pro/screens/auth/forgot_password_screen.dart';
import 'package:love_vibe_pro/widgets/neon_toast.dart';
import 'package:love_vibe_pro/screens/start_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with TickerProviderStateMixin {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _obscurePassword = true;
  bool _isLoading = false;

  // ── Animations ──────────────────────────────────────────────────────────────
  late final AnimationController _bgCtrl;
  late final AnimationController _enterCtrl;
  late final AnimationController _pulseCtrl;
  late final AnimationController _shimmerCtrl;

  late final Animation<double> _logoScale;
  late final Animation<double> _logoFade;
  late final Animation<Offset> _cardSlide;
  late final Animation<double> _cardFade;
  late final Animation<double> _pulse;
  late final Animation<double> _shimmer;

  // focus state for field glow
  final FocusNode _emailFocus = FocusNode();
  final FocusNode _passwordFocus = FocusNode();
  bool _emailFocused = false;
  bool _passwordFocused = false;

  @override
  void initState() {
    super.initState();

    _bgCtrl = AnimationController(
        vsync: this, duration: const Duration(seconds: 12))
      ..repeat();

    _pulseCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 2400))
      ..repeat(reverse: true);
    _pulse = Tween(begin: 0.85, end: 1.0).animate(
        CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));

    _shimmerCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1800))
      ..repeat();
    _shimmer = Tween(begin: -1.5, end: 2.5).animate(
        CurvedAnimation(parent: _shimmerCtrl, curve: Curves.easeInOut));

    _enterCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1100));

    _logoScale = TweenSequence([
      TweenSequenceItem(
          tween: Tween(begin: 0.5, end: 1.08)
              .chain(CurveTween(curve: Curves.easeOutBack)),
          weight: 70),
      TweenSequenceItem(
          tween: Tween(begin: 1.08, end: 1.0), weight: 30),
    ]).animate(_enterCtrl);

    _logoFade = Tween(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(
            parent: _enterCtrl,
            curve: const Interval(0.0, 0.5, curve: Curves.easeOut)));

    _cardSlide = Tween(begin: const Offset(0, 0.18), end: Offset.zero).animate(
        CurvedAnimation(
            parent: _enterCtrl,
            curve: const Interval(0.25, 1.0, curve: Curves.easeOutCubic)));

    _cardFade = Tween(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(
            parent: _enterCtrl,
            curve: const Interval(0.25, 0.8, curve: Curves.easeOut)));

    _emailFocus.addListener(() =>
        setState(() => _emailFocused = _emailFocus.hasFocus));
    _passwordFocus.addListener(() =>
        setState(() => _passwordFocused = _passwordFocus.hasFocus));

    _enterCtrl.forward();
  }

  @override
  void dispose() {
    _bgCtrl.dispose();
    _enterCtrl.dispose();
    _pulseCtrl.dispose();
    _shimmerCtrl.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _emailFocus.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    try {
      final auth = Provider.of<AuthProvider>(context, listen: false);
      await auth.loginWithEmail(
        _emailController.text.trim(),
        _passwordController.text,
      );
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const StartScreen()),
          (route) => false,
        );
      }
    } catch (e) {
      if (mounted) NeonToast.error(context, e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleGoogleLogin() async {
    setState(() => _isLoading = true);
    try {
      final auth = Provider.of<AuthProvider>(context, listen: false);
      await auth.loginWithGoogle();
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const StartScreen()),
          (route) => false,
        );
      }
    } catch (e) {
      if (mounted) NeonToast.error(context, e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _continueAsGuest() {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    auth.enterGuestMode();
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const StartScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isTablet = size.width > 600;
    final hPad = isTablet ? size.width * 0.12 : 22.0;

    return Scaffold(
      backgroundColor: const Color(0xFF07050F),
      resizeToAvoidBottomInset: true,
      body: Stack(
        children: [
          // ── Animated gradient background ───────────────────────────
          AnimatedBuilder(
            animation: _bgCtrl,
            builder: (_, __) => CustomPaint(
              size: size,
              painter: _AuraBgPainter(_bgCtrl.value),
            ),
          ),

          // ── Content ────────────────────────────────────────────────
          SafeArea(
            child: Form(
              key: _formKey,
              child: SingleChildScrollView(
                padding: EdgeInsets.symmetric(horizontal: hPad),
                physics: const BouncingScrollPhysics(),
                child: ConstrainedBox(
                  constraints:
                      BoxConstraints(minHeight: size.height - 100),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(height: isTablet ? 60 : 44),

                      // ── Logo ───────────────────────────────────────
                      FadeTransition(
                        opacity: _logoFade,
                        child: ScaleTransition(
                          scale: _logoScale,
                          child: _buildLogo(isTablet),
                        ),
                      ),

                      SizedBox(height: isTablet ? 36 : 28),

                      // ── Card ───────────────────────────────────────
                      FadeTransition(
                        opacity: _cardFade,
                        child: SlideTransition(
                          position: _cardSlide,
                          child: _buildCard(isTablet),
                        ),
                      ),

                      SizedBox(height: isTablet ? 28 : 20),

                      // ── Guest ──────────────────────────────────────
                      FadeTransition(
                        opacity: _cardFade,
                        child: _buildGuestLink(),
                      ),

                      const SizedBox(height: 16),

                      // ── Sign up link ───────────────────────────────
                      FadeTransition(
                        opacity: _cardFade,
                        child: _buildSignupLink(),
                      ),

                      SizedBox(height: isTablet ? 48 : 32),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogo(bool isTablet) {
    return AnimatedBuilder(
      animation: _pulse,
      builder: (_, child) => Container(
        width: isTablet ? 90 : 72,
        height: isTablet ? 90 : 72,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFFF2FB2).withValues(alpha: 0.35 * _pulse.value),
              blurRadius: 40 * _pulse.value,
              spreadRadius: 6 * _pulse.value,
            ),
            BoxShadow(
              color: const Color(0xFF9B5DE5).withValues(alpha: 0.2 * _pulse.value),
              blurRadius: 60 * _pulse.value,
              spreadRadius: 12 * _pulse.value,
            ),
          ],
        ),
        child: child,
      ),
      child: ClipOval(
        child: Image.asset('assets/images/goreto.png', fit: BoxFit.cover),
      ),
    );
  }

  Widget _buildCard(bool isTablet) {
    final maxWidth = isTablet ? 480.0 : double.infinity;
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(32),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withValues(alpha: 0.09),
                Colors.white.withValues(alpha: 0.04),
              ],
            ),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.13),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFFF2FB2).withValues(alpha: 0.07),
                blurRadius: 40,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(32),
            child: Padding(
              padding: EdgeInsets.all(isTablet ? 32 : 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Title ──────────────────────────────────────
                  _buildShimmerTitle('Sign in'),
                  const SizedBox(height: 6),
                  Text(
                    'Welcome back to Goreto',
                    style: TextStyle(
                      fontSize: isTablet ? 16 : 14,
                      color: Colors.white.withValues(alpha: 0.55),
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                  SizedBox(height: isTablet ? 32 : 24),

                  // ── Email ─────────────────────────────────────
                  _AuthField(
                    controller: _emailController,
                    focusNode: _emailFocus,
                    isFocused: _emailFocused,
                    hint: 'Email address',
                    icon: Icons.alternate_email_rounded,
                    keyboardType: TextInputType.emailAddress,
                    validator: (v) {
                      if (v == null || v.isEmpty) return 'Enter your email';
                      if (!v.contains('@')) return 'Enter a valid email';
                      return null;
                    },
                  ),
                  const SizedBox(height: 14),

                  // ── Password ──────────────────────────────────
                  _AuthField(
                    controller: _passwordController,
                    focusNode: _passwordFocus,
                    isFocused: _passwordFocused,
                    hint: 'Password',
                    icon: Icons.lock_outline_rounded,
                    obscureText: _obscurePassword,
                    onToggleObscure: () =>
                        setState(() => _obscurePassword = !_obscurePassword),
                    validator: (v) {
                      if (v == null || v.isEmpty) return 'Enter your password';
                      if (v.length < 6) return 'Min 6 characters';
                      return null;
                    },
                  ),
                  const SizedBox(height: 10),

                  // ── Forgot ────────────────────────────────────
                  Align(
                    alignment: Alignment.centerRight,
                    child: GestureDetector(
                      onTap: () => Navigator.push(
                        context,
                        _fadeRoute(const ForgotPasswordScreen()),
                      ),
                      child: const Text(
                        'Forgot Password?',
                        style: TextStyle(
                          color: Color(0xFFFF2FB2),
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 22),

                  // ── Login button ──────────────────────────────
                  _GradientButton(
                    label: 'Login',
                    isLoading: _isLoading,
                    onTap: _handleLogin,
                  ),
                  const SizedBox(height: 22),

                  // ── Divider ───────────────────────────────────
                  _OrDivider(),
                  const SizedBox(height: 22),

                  // ── Google ────────────────────────────────────
                  _GoogleButton(onTap: _handleGoogleLogin),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildShimmerTitle(String text) {
    return AnimatedBuilder(
      animation: _shimmer,
      builder: (_, __) {
        return ShaderMask(
          shaderCallback: (bounds) => LinearGradient(
            begin: Alignment(_shimmer.value - 1, 0),
            end: Alignment(_shimmer.value, 0),
            colors: const [
              Colors.white,
              Color(0xFFFFFFFF),
              Color(0xFFFF2FB2),
              Color(0xFF9B5DE5),
              Colors.white,
            ],
            stops: const [0.0, 0.35, 0.5, 0.65, 1.0],
          ).createShader(bounds),
          blendMode: BlendMode.srcIn,
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.5,
              color: Colors.white,
            ),
          ),
        );
      },
    );
  }

  Widget _buildGuestLink() {
    return GestureDetector(
      onTap: _continueAsGuest,
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: const Color(0xFF22D3EE).withValues(alpha: 0.35),
          ),
          color: const Color(0xFF22D3EE).withValues(alpha: 0.06),
        ),
        child: const Text(
          'Continue as Guest',
          style: TextStyle(
            color: Color(0xFF22D3EE),
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _buildSignupLink() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          "Don't have an account? ",
          style: TextStyle(
              color: Colors.white.withValues(alpha: 0.5), fontSize: 14),
        ),
        GestureDetector(
          onTap: () => Navigator.push(context, _slideRoute(const SignupScreen())),
          child: const Text(
            'Sign up',
            style: TextStyle(
              color: Color(0xFFFF2FB2),
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

// ── Signup Screen ──────────────────────────────────────────────────────────────

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen>
    with TickerProviderStateMixin {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  bool _isLoading = false;

  late final AnimationController _bgCtrl;
  late final AnimationController _enterCtrl;
  late final AnimationController _pulseCtrl;
  late final AnimationController _shimmerCtrl;

  late final Animation<double> _logoScale;
  late final Animation<double> _logoFade;
  late final Animation<Offset> _cardSlide;
  late final Animation<double> _cardFade;
  late final Animation<double> _pulse;
  late final Animation<double> _shimmer;

  final FocusNode _nameFocus = FocusNode();
  final FocusNode _emailFocus = FocusNode();
  final FocusNode _passwordFocus = FocusNode();
  final FocusNode _confirmFocus = FocusNode();
  bool _nameFocused = false;
  bool _emailFocused = false;
  bool _passwordFocused = false;
  bool _confirmFocused = false;

  @override
  void initState() {
    super.initState();

    _bgCtrl = AnimationController(
        vsync: this, duration: const Duration(seconds: 12))
      ..repeat();

    _pulseCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 2400))
      ..repeat(reverse: true);
    _pulse = Tween(begin: 0.85, end: 1.0).animate(
        CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));

    _shimmerCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1800))
      ..repeat();
    _shimmer = Tween(begin: -1.5, end: 2.5).animate(
        CurvedAnimation(parent: _shimmerCtrl, curve: Curves.easeInOut));

    _enterCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1100));

    _logoScale = TweenSequence([
      TweenSequenceItem(
          tween: Tween(begin: 0.5, end: 1.08)
              .chain(CurveTween(curve: Curves.easeOutBack)),
          weight: 70),
      TweenSequenceItem(tween: Tween(begin: 1.08, end: 1.0), weight: 30),
    ]).animate(_enterCtrl);

    _logoFade = Tween(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(
            parent: _enterCtrl,
            curve: const Interval(0.0, 0.5, curve: Curves.easeOut)));

    _cardSlide = Tween(begin: const Offset(0, 0.18), end: Offset.zero).animate(
        CurvedAnimation(
            parent: _enterCtrl,
            curve: const Interval(0.25, 1.0, curve: Curves.easeOutCubic)));

    _cardFade = Tween(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(
            parent: _enterCtrl,
            curve: const Interval(0.25, 0.8, curve: Curves.easeOut)));

    _nameFocus.addListener(
        () => setState(() => _nameFocused = _nameFocus.hasFocus));
    _emailFocus.addListener(
        () => setState(() => _emailFocused = _emailFocus.hasFocus));
    _passwordFocus.addListener(
        () => setState(() => _passwordFocused = _passwordFocus.hasFocus));
    _confirmFocus.addListener(
        () => setState(() => _confirmFocused = _confirmFocus.hasFocus));

    _enterCtrl.forward();
  }

  @override
  void dispose() {
    _bgCtrl.dispose();
    _enterCtrl.dispose();
    _pulseCtrl.dispose();
    _shimmerCtrl.dispose();
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    _nameFocus.dispose();
    _emailFocus.dispose();
    _passwordFocus.dispose();
    _confirmFocus.dispose();
    super.dispose();
  }

  Future<void> _handleSignup() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    try {
      final auth = Provider.of<AuthProvider>(context, listen: false);
      await auth.signupWithEmail(
        _nameController.text.trim(),
        _emailController.text.trim(),
        _passwordController.text,
      );
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const StartScreen()),
          (route) => false,
        );
      }
    } catch (e) {
      if (mounted) NeonToast.error(context, e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleGoogleLogin() async {
    setState(() => _isLoading = true);
    try {
      final auth = Provider.of<AuthProvider>(context, listen: false);
      await auth.loginWithGoogle();
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const StartScreen()),
          (route) => false,
        );
      }
    } catch (e) {
      if (mounted) NeonToast.error(context, e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isTablet = size.width > 600;
    final hPad = isTablet ? size.width * 0.12 : 22.0;

    return Scaffold(
      backgroundColor: const Color(0xFF07050F),
      resizeToAvoidBottomInset: true,
      body: Stack(
        children: [
          AnimatedBuilder(
            animation: _bgCtrl,
            builder: (_, __) => CustomPaint(
              size: size,
              painter: _AuraBgPainter(_bgCtrl.value, reversed: true),
            ),
          ),
          SafeArea(
            child: Form(
              key: _formKey,
              child: SingleChildScrollView(
                padding: EdgeInsets.symmetric(horizontal: hPad),
                physics: const BouncingScrollPhysics(),
                child: Column(
                  children: [
                    SizedBox(height: isTablet ? 24 : 18),

                    // ── Back button ──────────────────────────────
                    FadeTransition(
                      opacity: _logoFade,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: _BackButton(onTap: () => Navigator.pop(context)),
                      ),
                    ),

                    SizedBox(height: isTablet ? 24 : 16),

                    // ── Logo ─────────────────────────────────────
                    FadeTransition(
                      opacity: _logoFade,
                      child: ScaleTransition(
                        scale: _logoScale,
                        child: _buildLogo(isTablet),
                      ),
                    ),

                    SizedBox(height: isTablet ? 28 : 20),

                    // ── Card ─────────────────────────────────────
                    FadeTransition(
                      opacity: _cardFade,
                      child: SlideTransition(
                        position: _cardSlide,
                        child: _buildCard(isTablet),
                      ),
                    ),

                    const SizedBox(height: 20),

                    // ── Login link ───────────────────────────────
                    FadeTransition(
                      opacity: _cardFade,
                      child: _buildLoginLink(),
                    ),

                    SizedBox(height: isTablet ? 48 : 36),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogo(bool isTablet) {
    return AnimatedBuilder(
      animation: _pulse,
      builder: (_, child) => Container(
        width: isTablet ? 80 : 64,
        height: isTablet ? 80 : 64,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF9B5DE5).withValues(alpha: 0.35 * _pulse.value),
              blurRadius: 40 * _pulse.value,
              spreadRadius: 6 * _pulse.value,
            ),
          ],
        ),
        child: child,
      ),
      child: ClipOval(
        child: Image.asset('assets/images/goreto.png', fit: BoxFit.cover),
      ),
    );
  }

  Widget _buildCard(bool isTablet) {
    final maxWidth = isTablet ? 480.0 : double.infinity;
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(32),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withValues(alpha: 0.09),
                Colors.white.withValues(alpha: 0.04),
              ],
            ),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.13),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF9B5DE5).withValues(alpha: 0.07),
                blurRadius: 40,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(32),
            child: Padding(
              padding: EdgeInsets.all(isTablet ? 32 : 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildShimmerTitle('Create account'),
                  const SizedBox(height: 6),
                  Text(
                    'Join Goreto in seconds',
                    style: TextStyle(
                      fontSize: isTablet ? 16 : 14,
                      color: Colors.white.withValues(alpha: 0.55),
                    ),
                  ),
                  SizedBox(height: isTablet ? 28 : 22),

                  _AuthField(
                    controller: _nameController,
                    focusNode: _nameFocus,
                    isFocused: _nameFocused,
                    hint: 'Full Name',
                    icon: Icons.person_outline_rounded,
                    keyboardType: TextInputType.name,
                    accentColor: const Color(0xFF9B5DE5),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return 'Enter your full name';
                      final parts = v.trim().split(RegExp(r'\s+'));
                      if (parts.length < 2) return 'Enter first and last name';
                      return null;
                    },
                  ),
                  const SizedBox(height: 14),

                  _AuthField(
                    controller: _emailController,
                    focusNode: _emailFocus,
                    isFocused: _emailFocused,
                    hint: 'Email address',
                    icon: Icons.alternate_email_rounded,
                    keyboardType: TextInputType.emailAddress,
                    accentColor: const Color(0xFF9B5DE5),
                    validator: (v) {
                      if (v == null || v.isEmpty) return 'Enter your email';
                      if (!v.contains('@')) return 'Enter a valid email';
                      return null;
                    },
                  ),
                  const SizedBox(height: 14),

                  _AuthField(
                    controller: _passwordController,
                    focusNode: _passwordFocus,
                    isFocused: _passwordFocused,
                    hint: 'Password',
                    icon: Icons.lock_outline_rounded,
                    obscureText: _obscurePassword,
                    accentColor: const Color(0xFF9B5DE5),
                    onToggleObscure: () =>
                        setState(() => _obscurePassword = !_obscurePassword),
                    validator: (v) {
                      if (v == null || v.isEmpty) return 'Enter a password';
                      if (v.length < 6) return 'Min 6 characters';
                      return null;
                    },
                  ),
                  const SizedBox(height: 14),

                  _AuthField(
                    controller: _confirmController,
                    focusNode: _confirmFocus,
                    isFocused: _confirmFocused,
                    hint: 'Confirm Password',
                    icon: Icons.lock_outline_rounded,
                    obscureText: _obscureConfirm,
                    accentColor: const Color(0xFF9B5DE5),
                    onToggleObscure: () =>
                        setState(() => _obscureConfirm = !_obscureConfirm),
                    validator: (v) {
                      if (v == null || v.isEmpty) return 'Confirm your password';
                      if (v != _passwordController.text) return 'Passwords do not match';
                      return null;
                    },
                  ),
                  const SizedBox(height: 24),

                  _GradientButton(
                    label: 'Create Account',
                    isLoading: _isLoading,
                    onTap: _handleSignup,
                    gradient: const LinearGradient(
                      colors: [Color(0xFF9B5DE5), Color(0xFFFF2FB2)],
                    ),
                  ),
                  const SizedBox(height: 22),
                  _OrDivider(),
                  const SizedBox(height: 22),
                  _GoogleButton(onTap: _handleGoogleLogin),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildShimmerTitle(String text) {
    return AnimatedBuilder(
      animation: _shimmer,
      builder: (_, __) {
        return ShaderMask(
          shaderCallback: (bounds) => LinearGradient(
            begin: Alignment(_shimmer.value - 1, 0),
            end: Alignment(_shimmer.value, 0),
            colors: const [
              Colors.white,
              Colors.white,
              Color(0xFF9B5DE5),
              Color(0xFFFF2FB2),
              Colors.white,
            ],
            stops: const [0.0, 0.35, 0.5, 0.65, 1.0],
          ).createShader(bounds),
          blendMode: BlendMode.srcIn,
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.5,
              color: Colors.white,
            ),
          ),
        );
      },
    );
  }

  Widget _buildLoginLink() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          'Already have an account? ',
          style: TextStyle(
              color: Colors.white.withValues(alpha: 0.5), fontSize: 14),
        ),
        GestureDetector(
          onTap: () => Navigator.pushReplacement(
              context, _slideRoute(const LoginScreen())),
          child: const Text(
            'Login',
            style: TextStyle(
              color: Color(0xFFFF2FB2),
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

// ── Shared Widgets ─────────────────────────────────────────────────────────────

class _AuthField extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool isFocused;
  final String hint;
  final IconData icon;
  final bool obscureText;
  final VoidCallback? onToggleObscure;
  final TextInputType? keyboardType;
  final String? Function(String?)? validator;
  final Color accentColor;

  const _AuthField({
    required this.controller,
    required this.focusNode,
    required this.isFocused,
    required this.hint,
    required this.icon,
    this.obscureText = false,
    this.onToggleObscure,
    this.keyboardType,
    this.validator,
    this.accentColor = const Color(0xFFFF2FB2),
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: Colors.white.withValues(alpha: isFocused ? 0.1 : 0.06),
        border: Border.all(
          color: isFocused
              ? accentColor.withValues(alpha: 0.7)
              : Colors.white.withValues(alpha: 0.1),
          width: isFocused ? 1.5 : 1.0,
        ),
        boxShadow: isFocused
            ? [
                BoxShadow(
                  color: accentColor.withValues(alpha: 0.18),
                  blurRadius: 16,
                  spreadRadius: 0,
                )
              ]
            : [],
      ),
      child: TextFormField(
        controller: controller,
        focusNode: focusNode,
        obscureText: obscureText,
        keyboardType: keyboardType,
        validator: validator,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 15,
          fontWeight: FontWeight.w500,
        ),
        cursorColor: accentColor,
        cursorWidth: 1.8,
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(
            color: Colors.white.withValues(alpha: 0.35),
            fontSize: 15,
          ),
          prefixIcon: Padding(
            padding: const EdgeInsets.only(left: 14, right: 10),
            child: Icon(
              icon,
              color: isFocused
                  ? accentColor
                  : Colors.white.withValues(alpha: 0.4),
              size: 19,
            ),
          ),
          prefixIconConstraints:
              const BoxConstraints(minWidth: 44, minHeight: 44),
          suffixIcon: onToggleObscure != null
              ? GestureDetector(
                  onTap: onToggleObscure,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 14),
                    child: Icon(
                      obscureText
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                      color: Colors.white.withValues(alpha: 0.4),
                      size: 19,
                    ),
                  ),
                )
              : null,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
              vertical: 16, horizontal: 16),
          errorStyle: const TextStyle(
              color: Color(0xFFFF6B6B), fontSize: 11),
        ),
      ),
    );
  }
}

class _GradientButton extends StatefulWidget {
  final String label;
  final bool isLoading;
  final VoidCallback onTap;
  final Gradient gradient;

  const _GradientButton({
    required this.label,
    required this.isLoading,
    required this.onTap,
    this.gradient = const LinearGradient(
      colors: [Color(0xFFFF2FB2), Color(0xFF9B5DE5)],
    ),
  });

  @override
  State<_GradientButton> createState() => _GradientButtonState();
}

class _GradientButtonState extends State<_GradientButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pressCtrl;
  late final Animation<double> _press;

  @override
  void initState() {
    super.initState();
    _pressCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 120));
    _press =
        Tween(begin: 1.0, end: 0.96).animate(CurvedAnimation(
      parent: _pressCtrl,
      curve: Curves.easeOut,
    ));
  }

  @override
  void dispose() {
    _pressCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _pressCtrl.forward(),
      onTapUp: (_) {
        _pressCtrl.reverse();
        if (!widget.isLoading) widget.onTap();
      },
      onTapCancel: () => _pressCtrl.reverse(),
      child: ScaleTransition(
        scale: _press,
        child: Container(
          width: double.infinity,
          height: 52,
          decoration: BoxDecoration(
            gradient: widget.gradient,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFFF2FB2).withValues(alpha: 0.4),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Center(
            child: widget.isLoading
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: Colors.white,
                    ),
                  )
                : Text(
                    widget.label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.3,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

class _GoogleButton extends StatefulWidget {
  final VoidCallback onTap;
  const _GoogleButton({required this.onTap});

  @override
  State<_GoogleButton> createState() => _GoogleButtonState();
}

class _GoogleButtonState extends State<_GoogleButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 100));
    _scale = Tween(begin: 1.0, end: 0.96)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _ctrl.forward(),
      onTapUp: (_) { _ctrl.reverse(); widget.onTap(); },
      onTapCancel: () => _ctrl.reverse(),
      child: ScaleTransition(
        scale: _scale,
        child: Container(
          width: double.infinity,
          height: 52,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.15),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 22,
                height: 22,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white,
                ),
                child: const Center(
                  child: Text(
                    'G',
                    style: TextStyle(
                      color: Color(0xFF4285F4),
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                'Continue with Google',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.85),
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OrDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Expanded(
          child: Container(height: 1,
              color: Colors.white.withValues(alpha: 0.12))),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Text(
          'OR',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.4),
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.5,
          ),
        ),
      ),
      Expanded(
          child: Container(height: 1,
              color: Colors.white.withValues(alpha: 0.12))),
    ]);
  }
}

class _BackButton extends StatelessWidget {
  final VoidCallback onTap;
  const _BackButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
        ),
        child: Icon(
          Icons.arrow_back_ios_new_rounded,
          color: Colors.white.withValues(alpha: 0.8),
          size: 17,
        ),
      ),
    );
  }
}

// ── Animated aurora background painter ────────────────────────────────────────

class _AuraBgPainter extends CustomPainter {
  final double t;
  final bool reversed;
  _AuraBgPainter(this.t, {this.reversed = false});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..blendMode = BlendMode.screen;
    final phase = reversed ? 1.0 - t : t;

    // Background
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = const Color(0xFF07050F),
    );

    // Orb 1 — pink, top-left drift
    _drawOrb(
      canvas, paint,
      center: Offset(
        size.width * (0.15 + 0.12 * math.sin(phase * math.pi * 2)),
        size.height * (0.18 + 0.08 * math.cos(phase * math.pi * 2)),
      ),
      radius: size.width * 0.55,
      colors: [
        const Color(0xFFFF2FB2).withValues(alpha: 0.22),
        Colors.transparent,
      ],
    );

    // Orb 2 — purple, bottom-right drift
    _drawOrb(
      canvas, paint,
      center: Offset(
        size.width * (0.85 + 0.1 * math.cos(phase * math.pi * 2 + 1)),
        size.height * (0.72 + 0.1 * math.sin(phase * math.pi * 2 + 1)),
      ),
      radius: size.width * 0.6,
      colors: [
        const Color(0xFF9B5DE5).withValues(alpha: 0.18),
        Colors.transparent,
      ],
    );

    // Orb 3 — cyan, center drift
    _drawOrb(
      canvas, paint,
      center: Offset(
        size.width * (0.5 + 0.08 * math.sin(phase * math.pi * 2 + 2)),
        size.height * (0.45 + 0.07 * math.cos(phase * math.pi * 2 + 2)),
      ),
      radius: size.width * 0.35,
      colors: [
        const Color(0xFF22D3EE).withValues(alpha: 0.08),
        Colors.transparent,
      ],
    );
  }

  void _drawOrb(Canvas canvas, Paint paint,
      {required Offset center,
      required double radius,
      required List<Color> colors}) {
    paint.shader = RadialGradient(colors: colors)
        .createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawCircle(center, radius, paint);
  }

  @override
  bool shouldRepaint(_AuraBgPainter old) => old.t != t;
}

// ── Route helpers ──────────────────────────────────────────────────────────────

PageRoute _fadeRoute(Widget page) => PageRouteBuilder(
      pageBuilder: (_, __, ___) => page,
      transitionDuration: const Duration(milliseconds: 300),
      transitionsBuilder: (_, anim, __, child) =>
          FadeTransition(opacity: anim, child: child),
    );

PageRoute _slideRoute(Widget page) => PageRouteBuilder(
      pageBuilder: (_, __, ___) => page,
      transitionDuration: const Duration(milliseconds: 350),
      transitionsBuilder: (_, anim, __, child) => SlideTransition(
        position: Tween(begin: const Offset(1, 0), end: Offset.zero)
            .animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
        child: child,
      ),
    );
