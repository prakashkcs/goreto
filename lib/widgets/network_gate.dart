import 'package:flutter/material.dart';
import 'package:love_vibe_pro/services/connectivity_service.dart';

class NetworkGate extends StatefulWidget {
  final Widget child;
  const NetworkGate({super.key, required this.child});

  @override
  State<NetworkGate> createState() => _NetworkGateState();
}

class _NetworkGateState extends State<NetworkGate>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  bool _isRetrying = false;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _retry() async {
    if (_isRetrying) return;
    setState(() => _isRetrying = true);
    await ConnectivityService.instance.recheck();
    if (mounted) setState(() => _isRetrying = false);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: ConnectivityService.instance,
      builder: (context, _) {
        final svc = ConnectivityService.instance;

        // Still doing the initial check — show the branded loading splash
        if (!svc.isInitialized) {
          return const _LoadingSplash();
        }

        // Online — show the normal app
        if (svc.isOnline) return widget.child;

        // Offline — block access with a full-screen no-internet screen
        return _NoInternetScreen(
          isRetrying: _isRetrying,
          pulseController: _pulseController,
          onRetry: _retry,
        );
      },
    );
  }
}

// ── Branded loading splash shown during the initial connectivity check ────────

class _LoadingSplash extends StatelessWidget {
  const _LoadingSplash();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xFF05030A),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _GoretoLogo(),
            SizedBox(height: 40),
            SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFD946EF)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── No-internet screen ────────────────────────────────────────────────────────

class _NoInternetScreen extends StatelessWidget {
  final bool isRetrying;
  final AnimationController pulseController;
  final VoidCallback onRetry;

  const _NoInternetScreen({
    required this.isRetrying,
    required this.pulseController,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF05030A),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const _GoretoLogo(),
                const SizedBox(height: 40),

                // Pulsing wifi-off icon
                AnimatedBuilder(
                  animation: pulseController,
                  builder: (_, __) => Opacity(
                    opacity: 0.5 + pulseController.value * 0.5,
                    child: Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0xFFEF4444).withValues(alpha: 0.12),
                      ),
                      child: const Icon(
                        Icons.wifi_off_rounded,
                        color: Color(0xFFEF4444),
                        size: 34,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 24),
                const Text(
                  'No Internet Connection',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 10),
                Text(
                  'Please check your Wi-Fi or mobile data and try again.',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.55),
                    fontSize: 14,
                    height: 1.5,
                  ),
                  textAlign: TextAlign.center,
                ),

                const SizedBox(height: 36),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: isRetrying ? null : onRetry,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFD946EF),
                      disabledBackgroundColor:
                          const Color(0xFFD946EF).withValues(alpha: 0.4),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(25),
                      ),
                      elevation: 0,
                    ),
                    child: isRetrying
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor:
                                  AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : const Text(
                            'Try Again',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
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

// ── Shared logo widget ─────────────────────────────────────────────────────────

class _GoretoLogo extends StatelessWidget {
  const _GoretoLogo();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const RadialGradient(
              colors: [Color(0xFF2A0A3A), Color(0xFF0A030F)],
            ),
            border: Border.all(
              color: const Color(0xFFD946EF).withValues(alpha: 0.35),
              width: 1.5,
            ),
          ),
          child: ClipOval(
            child: Image.asset(
              'assets/images/goreto.png',
              fit: BoxFit.cover,
            ),
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          'Goreto',
          style: TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }
}
