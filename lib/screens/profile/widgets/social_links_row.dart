import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:love_vibe_pro/widgets/neon_toast.dart';

/// Social links row with icons for Facebook, YouTube, Instagram, X
class SocialLinksRow extends StatelessWidget {
  final Map<String, String> links;

  static const List<String> _orderedKeys = <String>[
    'facebook',
    'instagram',
    'youtube',
    'x',
  ];

  const SocialLinksRow({super.key, required this.links});

  @override
  Widget build(BuildContext context) {
    final normalized = <String, String>{};
    for (final entry in links.entries) {
      final key = entry.key.trim().toLowerCase();
      final value = entry.value.trim();
      if (key.isNotEmpty && value.isNotEmpty) {
        normalized[key] = value;
      }
    }

    final visibleEntries = _orderedKeys
        .map((key) {
          if (key == 'x') {
            final xUrl = normalized['x'];
            if (xUrl != null && xUrl.isNotEmpty) return MapEntry('x', xUrl);
            final twitterUrl = normalized['twitter'];
            if (twitterUrl != null && twitterUrl.isNotEmpty) {
              return MapEntry('x', twitterUrl);
            }
            return null;
          }

          final url = normalized[key];
          if (url != null && url.isNotEmpty) {
            return MapEntry(key, url);
          }
          return null;
        })
        .whereType<MapEntry<String, String>>()
        .toList();

    if (visibleEntries.isEmpty) {
      return const SizedBox.shrink();
    }

    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 12,
      runSpacing: 8,
      children: visibleEntries
          .map((entry) => _buildSocialIcon(context, entry.key, entry.value))
          .toList(),
    );
  }

  Widget _buildSocialIcon(BuildContext context, String key, String link) {
    final normalizedKey = key.trim().toLowerCase();
    final icon = _iconForKey(normalizedKey);
    final color = _colorForKey(normalizedKey);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _openLink(context, link),
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color.withValues(alpha: 0.15),
          border: Border.all(color: color, width: 1.5),
          boxShadow: [BoxShadow(color: color.withValues(alpha: 0.3), blurRadius: 10)],
        ),
        child: Icon(icon, color: color, size: 20),
      ),
    );
  }

  IconData _iconForKey(String key) {
    switch (key) {
      case 'facebook':
        return Icons.facebook;
      case 'youtube':
        return Icons.play_circle_fill;
      case 'instagram':
        return Icons.camera_alt;
      case 'x':
      case 'twitter':
        return Icons.close;
      default:
        return Icons.link;
    }
  }

  Color _colorForKey(String key) {
    switch (key) {
      case 'facebook':
        return const Color(0xFF1877F2);
      case 'youtube':
        return const Color(0xFFFF0000);
      case 'instagram':
        return const Color(0xFFE4405F);
      case 'x':
      case 'twitter':
        return Colors.white;
      default:
        return const Color(0xFF00E5FF);
    }
  }

  Future<void> _openLink(BuildContext context, String rawUrl) async {
    var url = rawUrl.trim();
    if (url.isEmpty) return;
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      url = 'https://$url';
    }

    final uri = Uri.tryParse(url);
    if (uri == null) return;

    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && context.mounted) {
      NeonToast.error(context, 'Could not open link');
    }
  }
}
