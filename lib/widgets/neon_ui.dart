import 'package:flutter/material.dart';

/// Global Style Tokens for Liquid Love UI
class LiquidLoveTokens {
  // Colors
  static const Color background = Color(0xFF05030A);
  static const Color accentPink = Color(0xFFFF2FB2);
  static const Color accentPurple = Color(0xFFA855F7);
  static const Color accentCyan = Color(0xFF22D3EE);
  static const Color glassCard = Color(0x1AFFFFFF); // white 10%
  static const Color glassFill = Color(0x0FFFFFFF); // white 6%
  static const Color glassBorder = Color(0x1AFFFFFF); // white 10%

  // Radii
  static const double radiusCard = 28;
  static const double radiusButton = 22;
  static const double radiusInput = 18;

  static const double paddingH = 24;
  static const double paddingV = 18;

  // Typography
  static const TextStyle titleStyle = TextStyle(
    fontSize: 34,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.4,
    color: Colors.white,
  );

  static const TextStyle subtitleStyle = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w500,
    color: Color(0xB3FFFFFF), // 70% opacity
  );

  static const TextStyle buttonStyle = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w700,
    color: Colors.white,
  );

  static const TextStyle inputStyle = TextStyle(
    fontSize: 16,
    color: Colors.white,
  );

  // Shadows
  static List<BoxShadow> glowShadow(
    Color color, {
    double opacity = 0.35,
    double blur = 28,
    double spread = 2,
  }) {
    return [
      BoxShadow(
        color: color.withValues(alpha: opacity),
        blurRadius: blur,
        spreadRadius: spread,
      ),
    ];
  }

  // Gradients
  static const LinearGradient neonGradient = LinearGradient(
    colors: [accentPink, accentPurple, accentCyan],
  );

  static const LinearGradient buttonGradient = LinearGradient(
    colors: [accentPink, accentPurple],
  );
}

/// Neon Gradient Border Container
/// A container with a gradient border using custom painter
class NeonGradientBorderContainer extends StatelessWidget {
  final Widget child;
  final double radius;
  final double borderWidth;
  final double? width;
  final double? height;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final Color? backgroundColor;
  final List<Color>? gradientColors;

  const NeonGradientBorderContainer({
    super.key,
    required this.child,
    this.radius = LiquidLoveTokens.radiusCard,
    this.borderWidth = 1.2,
    this.width,
    this.height,
    this.padding,
    this.margin,
    this.backgroundColor,
    this.gradientColors,
  });

  @override
  Widget build(BuildContext context) {
    final colors =
        gradientColors ??
        [
          LiquidLoveTokens.accentPink,
          LiquidLoveTokens.accentPurple,
          LiquidLoveTokens.accentCyan,
        ];

    return Container(
      width: width,
      height: height,
      margin: margin,
      child: CustomPaint(
        painter: _GradientBorderPainter(
          radius: radius,
          strokeWidth: borderWidth,
          gradientColors: colors,
          backgroundColor: backgroundColor ?? LiquidLoveTokens.glassCard,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(radius),
          child: Container(
            padding: padding ?? const EdgeInsets.all(LiquidLoveTokens.paddingH),
            child: child,
          ),
        ),
      ),
    );
  }
}

class _GradientBorderPainter extends CustomPainter {
  final double radius;
  final double strokeWidth;
  final List<Color> gradientColors;
  final Color backgroundColor;

  _GradientBorderPainter({
    required this.radius,
    required this.strokeWidth,
    required this.gradientColors,
    required this.backgroundColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(
      rect.deflate(strokeWidth / 2),
      Radius.circular(radius),
    );

    // Background
    final bgPaint = Paint()..color = backgroundColor;
    canvas.drawRRect(rrect, bgPaint);

    // Gradient border
    final gradient = LinearGradient(
      colors: gradientColors,
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    );

    final borderPaint = Paint()
      ..shader = gradient.createShader(rect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;

    canvas.drawRRect(rrect, borderPaint);
  }

  @override
  bool shouldRepaint(covariant _GradientBorderPainter oldDelegate) {
    return oldDelegate.radius != radius ||
        oldDelegate.strokeWidth != strokeWidth ||
        oldDelegate.backgroundColor != backgroundColor;
  }
}

/// Primary Neon Button with gradient fill
class NeonButtonPrimary extends StatefulWidget {
  final String text;
  final VoidCallback? onTap;
  final bool isLoading;
  final double height;
  final double radius;

  const NeonButtonPrimary({
    super.key,
    required this.text,
    this.onTap,
    this.isLoading = false,
    this.height = 54,
    this.radius = LiquidLoveTokens.radiusButton,
  });

  @override
  State<NeonButtonPrimary> createState() => _NeonButtonPrimaryState();
}

class _NeonButtonPrimaryState extends State<NeonButtonPrimary> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) => setState(() => _isPressed = false),
      onTapCancel: () => setState(() => _isPressed = false),
      onTap: widget.isLoading ? null : widget.onTap,
      child: AnimatedScale(
        scale: _isPressed ? 0.98 : 1.0,
        duration: const Duration(milliseconds: 100),
        child: Container(
          height: widget.height,
          decoration: BoxDecoration(
            gradient: LiquidLoveTokens.buttonGradient,
            borderRadius: BorderRadius.circular(widget.radius),
            boxShadow: LiquidLoveTokens.glowShadow(
              LiquidLoveTokens.accentPink,
              opacity: 0.4,
              blur: 26,
            ),
          ),
          child: Center(
            child: widget.isLoading
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  )
                : Text(widget.text, style: LiquidLoveTokens.buttonStyle),
          ),
        ),
      ),
    );
  }
}

/// Glass Button with optional icon
class GlassButton extends StatefulWidget {
  final String text;
  final Widget? icon;
  final VoidCallback? onTap;
  final double height;
  final double radius;
  final bool isOutlined;

  const GlassButton({
    super.key,
    required this.text,
    this.icon,
    this.onTap,
    this.height = 54,
    this.radius = LiquidLoveTokens.radiusButton,
    this.isOutlined = false,
  });

  @override
  State<GlassButton> createState() => _GlassButtonState();
}

class _GlassButtonState extends State<GlassButton> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) => setState(() => _isPressed = false),
      onTapCancel: () => setState(() => _isPressed = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _isPressed ? 0.98 : 1.0,
        duration: const Duration(milliseconds: 100),
        child: Container(
          height: widget.height,
          decoration: BoxDecoration(
            color: widget.isOutlined ? null : LiquidLoveTokens.glassCard,
            borderRadius: BorderRadius.circular(widget.radius),
            border: widget.isOutlined
                ? Border.all(color: LiquidLoveTokens.accentCyan, width: 1.5)
                : Border.all(color: LiquidLoveTokens.glassBorder, width: 1),
          ),
          child: Center(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (widget.icon != null) ...[
                  widget.icon!,
                  const SizedBox(width: 12),
                ],
                Text(
                  widget.text,
                  style: LiquidLoveTokens.buttonStyle.copyWith(
                    color: widget.isOutlined
                        ? LiquidLoveTokens.accentCyan
                        : Colors.white,
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

/// Neon Text Field with gradient focus border
class NeonTextField extends StatefulWidget {
  final TextEditingController? controller;
  final String? hintText;
  final String? labelText;
  final Widget? prefixIcon;
  final Widget? suffixIcon;
  final bool obscureText;
  final TextInputType? keyboardType;
  final String? Function(String?)? validator;
  final ValueChanged<String>? onChanged;
  final bool enabled;

  const NeonTextField({
    super.key,
    this.controller,
    this.hintText,
    this.labelText,
    this.prefixIcon,
    this.suffixIcon,
    this.obscureText = false,
    this.keyboardType,
    this.validator,
    this.onChanged,
    this.enabled = true,
  });

  @override
  State<NeonTextField> createState() => _NeonTextFieldState();
}

class _NeonTextFieldState extends State<NeonTextField> {
  final _focusNode = FocusNode();
  bool _isFocused = false;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(() {
      setState(() => _isFocused = _focusNode.hasFocus);
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 54,
      decoration: BoxDecoration(
        color: LiquidLoveTokens.glassFill,
        borderRadius: BorderRadius.circular(LiquidLoveTokens.radiusInput),
        border: _isFocused
            ? Border.all(color: LiquidLoveTokens.accentPink, width: 1.5)
            : Border.all(color: LiquidLoveTokens.glassBorder, width: 1),
        boxShadow: _isFocused
            ? LiquidLoveTokens.glowShadow(
                LiquidLoveTokens.accentPink,
                opacity: 0.2,
                blur: 16,
              )
            : null,
      ),
      child: TextFormField(
        controller: widget.controller,
        focusNode: _focusNode,
        obscureText: widget.obscureText,
        keyboardType: widget.keyboardType,
        validator: widget.validator,
        onChanged: widget.onChanged,
        enabled: widget.enabled,
        style: LiquidLoveTokens.inputStyle,
        decoration: InputDecoration(
          hintText: widget.hintText,
          labelText: widget.labelText,
          hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.4)),
          labelStyle: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
          prefixIcon: widget.prefixIcon != null
              ? Padding(
                  padding: const EdgeInsets.only(left: 16, right: 12),
                  child: widget.prefixIcon,
                )
              : null,
          suffixIcon: widget.suffixIcon != null
              ? Padding(
                  padding: const EdgeInsets.only(right: 16),
                  child: widget.suffixIcon,
                )
              : null,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 18,
            vertical: 16,
          ),
        ),
      ),
    );
  }
}

/// Background Blobs Widget for Liquid Love theme
class LiquidBackgroundBlobs extends StatelessWidget {
  const LiquidBackgroundBlobs({super.key});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Radial gradient background
        Container(
          decoration: const BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(-1, -1),
              radius: 1.2,
              colors: [
                Color(0x8C2A0A3D), // #2A0A3D at 55%
                LiquidLoveTokens.background,
              ],
              stops: [0.0, 1.0],
            ),
          ),
        ),

        // Pink glow blob (top-left)
        Positioned(
          top: -80,
          left: -60,
          child: Container(
            width: 260,
            height: 260,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: LiquidLoveTokens.accentPink.withValues(alpha: 0.35),
                  blurRadius: 80,
                  spreadRadius: 20,
                ),
              ],
            ),
          ),
        ),

        // Purple glow blob (top-right)
        Positioned(
          top: 120,
          right: -80,
          child: Container(
            width: 300,
            height: 300,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: LiquidLoveTokens.accentPurple.withValues(alpha: 0.35),
                  blurRadius: 90,
                  spreadRadius: 25,
                ),
              ],
            ),
          ),
        ),

        // Cyan glow blob (bottom)
        Positioned(
          bottom: -120,
          left: 40,
          child: Container(
            width: 340,
            height: 340,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: LiquidLoveTokens.accentCyan.withValues(alpha: 0.35),
                  blurRadius: 100,
                  spreadRadius: 30,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Animated floating glow widget
class FloatingGlow extends StatefulWidget {
  final Color color;
  final double size;
  final Duration duration;

  const FloatingGlow({
    super.key,
    required this.color,
    this.size = 200,
    this.duration = const Duration(seconds: 8),
  });

  @override
  State<FloatingGlow> createState() => _FloatingGlowState();
}

class _FloatingGlowState extends State<FloatingGlow>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration)
      ..repeat(reverse: true);

    _animation = Tween<double>(begin: 0.8, end: 1.2).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOutSine),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Transform.scale(
          scale: _animation.value,
          child: Container(
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: widget.color.withValues(alpha: 0.3),
                  blurRadius: 60,
                  spreadRadius: 15,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
