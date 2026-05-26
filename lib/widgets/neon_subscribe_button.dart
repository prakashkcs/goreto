import 'package:flutter/material.dart';

/// A button shown on feed posts for the viewer to follow or subscribe to the author.
///
/// [showSubscribeMode]     — when true, shows a "Subscribe" button (pink→purple gradient);
///                           when false (default), shows a "Follow +" button.
/// [isSubscribed]          — when true, shows "Following ✓" / "Subscribed ✓" state.
/// [isOwnPost]             — hides the button entirely on the viewer's own posts.
/// [hasSubscriptionPlan]   — when false, Subscribe button is greyed out and non-tappable.
class NeonSubscribeButton extends StatelessWidget {
  final VoidCallback? onTap;
  final bool isSubscribed;
  final bool isOwnPost;
  final bool showSubscribeMode;
  final bool hasSubscriptionPlan;

  const NeonSubscribeButton({
    super.key,
    this.onTap,
    this.isSubscribed = false,
    this.isOwnPost = false,
    this.showSubscribeMode = false,
    this.hasSubscriptionPlan = true,
  });

  @override
  Widget build(BuildContext context) {
    // Hide entirely on own posts
    if (isOwnPost) return const SizedBox.shrink();

    if (isSubscribed) {
      // ── Already following / subscribed ──────────────────────────────────
      final color =
          showSubscribeMode ? const Color(0xFFD946EF) : const Color(0xFF00E5FF);
      return GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: color.withValues(alpha: 0.6), width: 1),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.25),
                blurRadius: 6,
                spreadRadius: 0,
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.check_circle_rounded, color: color, size: 12),
              const SizedBox(width: 4),
              Text(
                showSubscribeMode ? 'Subscribed' : 'Following',
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w700,
                  fontSize: 11,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (showSubscribeMode) {
      // ── Subscribe button — disabled (grey) when creator has no plan ──────
      if (!hasSubscriptionPlan) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            color: Colors.white.withValues(alpha: 0.08),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.2),
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.star_rounded,
                  color: Colors.white.withValues(alpha: 0.3), size: 12),
              const SizedBox(width: 4),
              Text(
                'Subscribe',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.3),
                  fontWeight: FontWeight.w700,
                  fontSize: 11,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        );
      }

      // ── Subscribe button — premium pink→purple gradient ─────────────────
      return GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: const LinearGradient(
              colors: [Color(0xFFFF007F), Color(0xFFD946EF), Color(0xFF9333EA)],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFFF007F).withValues(alpha: 0.55),
                blurRadius: 12,
                spreadRadius: 0,
                offset: const Offset(0, 2),
              ),
              BoxShadow(
                color: const Color(0xFF9333EA).withValues(alpha: 0.35),
                blurRadius: 8,
                spreadRadius: 0,
              ),
            ],
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.star_rounded, color: Colors.white, size: 12),
              SizedBox(width: 4),
              Text(
                'Subscribe',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 11,
                  letterSpacing: 0.5,
                  shadows: [Shadow(color: Colors.black38, blurRadius: 4)],
                ),
              ),
            ],
          ),
        ),
      );
    }

    // ── Default Follow button — cyan neon outline ────────────────────────
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: LinearGradient(
            colors: [
              const Color(0xFF00E5FF).withValues(alpha: 0.15),
              const Color(0xFF3B82F6).withValues(alpha: 0.15),
            ],
          ),
          border: Border.all(
            color: const Color(0xFF00E5FF).withValues(alpha: 0.8),
            width: 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF00E5FF).withValues(alpha: 0.3),
              blurRadius: 8,
              spreadRadius: 0,
            ),
          ],
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.add_rounded,
              color: Color(0xFF00E5FF),
              size: 13,
            ),
            SizedBox(width: 3),
            Text(
              'Follow',
              style: TextStyle(
                color: Color(0xFF00E5FF),
                fontWeight: FontWeight.w700,
                fontSize: 11,
                letterSpacing: 0.4,
                shadows: [Shadow(color: Colors.black54, blurRadius: 4)],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
