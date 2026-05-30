import 'package:flutter/material.dart';
import 'package:love_vibe_pro/services/chat_package_service.dart';
import 'package:love_vibe_pro/widgets/coin_icon.dart';

/// Animated session-timer bar shown above the chat composer.
/// Shows a gradient countdown bar with spinning coin icon that grows /
/// shrinks with the remaining time.  Also listens to [coinDeductedNotifier]
/// to fire a flying-coins animation when a session is purchased.
class ChatTimerBar extends StatefulWidget {
  final int sellerId;
  final int targetPkgCount;
  final int freeMinLeft;
  final VoidCallback? onBuyPackage;

  const ChatTimerBar({
    super.key,
    required this.sellerId,
    required this.targetPkgCount,
    required this.freeMinLeft,
    this.onBuyPackage,
  });

  @override
  State<ChatTimerBar> createState() => _ChatTimerBarState();
}

class _ChatTimerBarState extends State<ChatTimerBar>
    with TickerProviderStateMixin {
  late final AnimationController _pulseCtrl;
  late final AnimationController _coinFlyCtrl;
  late final Animation<double> _coinFlyAnim;
  int _lastCoinDeducted = 0;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat(reverse: true);

    _coinFlyCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _coinFlyAnim = CurvedAnimation(
      parent: _coinFlyCtrl,
      curve: Curves.easeOutCubic,
    );

    ChatPackageService.instance.coinDeductedNotifier
        .addListener(_onCoinDeducted);
  }

  void _onCoinDeducted() {
    final coins = ChatPackageService.instance.coinDeductedNotifier.value;
    if (coins > 0 && mounted) {
      setState(() => _lastCoinDeducted = coins);
      _coinFlyCtrl.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _coinFlyCtrl.dispose();
    ChatPackageService.instance.coinDeductedNotifier
        .removeListener(_onCoinDeducted);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ChatSessionState?>(
      valueListenable: ChatPackageService.instance.sessionNotifier,
      builder: (_, session, __) {
        final hasPkgs = widget.targetPkgCount > 0;
        final isMySession = session != null &&
            session.active &&
            session.sellerId == widget.sellerId;

        if (isMySession) {
          return _buildActiveTimer(session);
        }

        if (!hasPkgs) return const SizedBox.shrink();

        // No active session — offer to start one
        return _buildStartPrompt();
      },
    );
  }

  Widget _buildActiveTimer(ChatSessionState session) {
    final frac = session.progressFraction;
    final isUrgent = session.secondsLeft < 60;

    final List<Color> colors = isUrgent
        ? [const Color(0xFFEF4444), const Color(0xFFFF6B9D)]
        : [const Color(0xFF00E5FF), const Color(0xFFD946EF)];

    return Stack(
      children: [
        Container(
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A28),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
                color: colors.first.withValues(alpha: 0.35), width: 1.2),
          ),
          child: Column(
            children: [
              // Progress bar
              ClipRRect(
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(13)),
                child: SizedBox(
                  height: 3,
                  child: AnimatedBuilder(
                    animation: _pulseCtrl,
                    builder: (_, __) {
                      return LinearProgressIndicator(
                        value: frac,
                        backgroundColor: Colors.white.withValues(alpha: 0.08),
                        valueColor: AlwaysStoppedAnimation<Color>(
                          isUrgent
                              ? Color.lerp(const Color(0xFFEF4444),
                                  const Color(0xFFFF6B9D), _pulseCtrl.value)!
                              : colors.first,
                        ),
                      );
                    },
                  ),
                ),
              ),
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: Row(
                  children: [
                    // Animated coin spinning
                    AnimatedBuilder(
                      animation: _pulseCtrl,
                      builder: (_, __) {
                        return Transform.scale(
                          scale: 1.0 + (_pulseCtrl.value * 0.15),
                          child: CoinIcon(
                            size: 22,
                            color: isUrgent
                                ? Color.lerp(const Color(0xFFEF4444),
                                    Colors.amber, _pulseCtrl.value)!
                                : Colors.amber,
                          ),
                        );
                      },
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              // Countdown
                              Text(
                                session.timeDisplay,
                                style: TextStyle(
                                  color: isUrgent
                                      ? const Color(0xFFEF4444)
                                      : Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 1.5,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures()
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '/ ${session.minutesTotal}min',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.4),
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                          if (session.coinsPaid > 0)
                            Text(
                              '${session.coinsPaid} coins',
                              style: TextStyle(
                                color: Colors.amber.withValues(alpha: 0.7),
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (isUrgent)
                      AnimatedBuilder(
                        animation: _pulseCtrl,
                        builder: (_, __) => Opacity(
                          opacity: 0.6 + (_pulseCtrl.value * 0.4),
                          child: const Text(
                            'LOW',
                            style: TextStyle(
                              color: Color(0xFFEF4444),
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.2,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        // Flying coins animation overlay
        if (_lastCoinDeducted > 0)
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _coinFlyAnim,
              builder: (_, __) {
                if (_coinFlyAnim.value == 0) return const SizedBox.shrink();
                return Opacity(
                  opacity: (1 - _coinFlyAnim.value).clamp(0.0, 1.0),
                  child: Transform.translate(
                    offset: Offset(0, -40 * _coinFlyAnim.value),
                    child: Center(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const CoinIcon(size: 20, color: Colors.amber),
                          const SizedBox(width: 6),
                          Text(
                            '-$_lastCoinDeducted',
                            style: const TextStyle(
                              color: Colors.amber,
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }

  Widget _buildStartPrompt() {
    final hasFree = widget.freeMinLeft > 0;
    return GestureDetector(
      onTap: widget.onBuyPackage,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              const Color(0xFFFF007F).withValues(alpha: 0.12),
              const Color(0xFFD946EF).withValues(alpha: 0.08),
            ],
          ),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: const Color(0xFFFF007F).withValues(alpha: 0.3),
              width: 1.2),
        ),
        child: Row(
          children: [
            const Icon(Icons.timer_rounded,
                color: Color(0xFFFF007F), size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                hasFree
                    ? '${widget.freeMinLeft} min free remaining'
                    : 'Buy a chat time package',
                style: const TextStyle(color: Colors.white, fontSize: 13),
              ),
            ),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFFF007F), Color(0xFFD946EF)],
                ),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                hasFree ? 'Start Free' : 'Buy',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
