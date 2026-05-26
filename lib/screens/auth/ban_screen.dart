import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class BanScreen extends StatelessWidget {
  final String status;
  final String title;
  final String reason;
  final String? bannedAt;

  const BanScreen({
    super.key,
    required this.status,
    required this.title,
    required this.reason,
    this.bannedAt,
  });

  @override
  Widget build(BuildContext context) {
    final isDevice = status == 'device_banned';
    final isPending = status == 'pending_delete';

    return PopScope(
      canPop: false,
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light,
        child: Scaffold(
          backgroundColor: const Color(0xFF0D0D0D),
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
              child: Column(
                children: [
                  const Spacer(),
                  _BanIcon(isPending: isPending, isDevice: isDevice),
                  const SizedBox(height: 32),
                  _BanTitle(title: title, isPending: isPending),
                  const SizedBox(height: 16),
                  _BanSubtitle(isPending: isPending, isDevice: isDevice),
                  const SizedBox(height: 28),
                  _ReasonCard(reason: reason, bannedAt: bannedAt),
                  const SizedBox(height: 20),
                  _SupportNote(isPending: isPending),
                  const Spacer(),
                  const _CloseButton(),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BanIcon extends StatelessWidget {
  final bool isPending;
  final bool isDevice;
  const _BanIcon({required this.isPending, required this.isDevice});

  @override
  Widget build(BuildContext context) {
    final icon = isPending
        ? Icons.schedule_rounded
        : isDevice
            ? Icons.phonelink_off_rounded
            : Icons.gavel_rounded;

    final color = isPending
        ? const Color(0xFFFF9800)
        : const Color(0xFFE53935);

    return Container(
      width: 100,
      height: 100,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withValues(alpha: 0.12),
        border: Border.all(color: color.withValues(alpha: 0.4), width: 2),
      ),
      child: Icon(icon, size: 48, color: color),
    );
  }
}

class _BanTitle extends StatelessWidget {
  final String title;
  final bool isPending;
  const _BanTitle({required this.title, required this.isPending});

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      textAlign: TextAlign.center,
      style: TextStyle(
        fontSize: 26,
        fontWeight: FontWeight.bold,
        color: isPending ? const Color(0xFFFF9800) : const Color(0xFFE53935),
        letterSpacing: 0.3,
      ),
    );
  }
}

class _BanSubtitle extends StatelessWidget {
  final bool isPending;
  final bool isDevice;
  const _BanSubtitle({required this.isPending, required this.isDevice});

  @override
  Widget build(BuildContext context) {
    final text = isPending
        ? 'Your account is scheduled for permanent deletion.'
        : isDevice
            ? 'This device has been restricted from accessing the platform.'
            : 'Your account has been suspended from the platform.';

    return Text(
      text,
      textAlign: TextAlign.center,
      style: const TextStyle(
        fontSize: 15,
        color: Color(0xFFAAAAAA),
        height: 1.5,
      ),
    );
  }
}

class _ReasonCard extends StatelessWidget {
  final String reason;
  final String? bannedAt;
  const _ReasonCard({required this.reason, this.bannedAt});

  @override
  Widget build(BuildContext context) {
    final hasReason = reason.isNotEmpty;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF2A2A2A)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.info_outline_rounded, size: 16, color: Color(0xFF888888)),
              SizedBox(width: 6),
              Text(
                'REASON',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF888888),
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            hasReason ? reason : 'No specific reason was provided by the administrator.',
            style: TextStyle(
              fontSize: 15,
              color: hasReason ? Colors.white : const Color(0xFF777777),
              height: 1.5,
              fontStyle: hasReason ? FontStyle.normal : FontStyle.italic,
            ),
          ),
          if (bannedAt != null && bannedAt!.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Divider(color: Color(0xFF2A2A2A), height: 1),
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(Icons.access_time_rounded, size: 14, color: Color(0xFF666666)),
                const SizedBox(width: 6),
                Text(
                  'Since: ${bannedAt!.length > 10 ? bannedAt!.substring(0, 10) : bannedAt!}',
                  style: const TextStyle(fontSize: 13, color: Color(0xFF666666)),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _SupportNote extends StatelessWidget {
  final bool isPending;
  const _SupportNote({required this.isPending});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF141414),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.mail_outline_rounded, size: 16, color: Color(0xFF666666)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              isPending
                  ? 'Contact support to cancel deletion before the scheduled date.'
                  : 'If you believe this is a mistake, contact support to appeal.',
              style: const TextStyle(fontSize: 12, color: Color(0xFF666666), height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

class _CloseButton extends StatelessWidget {
  const _CloseButton();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        onPressed: () => Navigator.of(context).pushNamedAndRemoveUntil(
          '/login',
          (_) => false,
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF1E1E1E),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          elevation: 0,
          side: const BorderSide(color: Color(0xFF333333)),
        ),
        child: const Text(
          'Close',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, letterSpacing: 0.3),
        ),
      ),
    );
  }
}
