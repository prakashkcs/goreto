import 'package:intl/intl.dart';

class DateUtil {
  /// Parses backend timestamps as UTC and converts to local device time.
  /// The server always stores in UTC (or naive timestamps treated as UTC).
  static DateTime parseServerTime(String? dateStr) {
    if (dateStr == null || dateStr.trim().isEmpty) {
      return DateTime.now();
    }

    try {
      var formatted = dateStr.trim();
      final hasTimezone = RegExp(r'(Z|[+-]\d{2}:?\d{2})$').hasMatch(formatted);

      // MySQL datetime format uses space separator — convert to ISO 8601
      if (formatted.contains(' ') && !formatted.contains('T')) {
        formatted = formatted.replaceFirst(' ', 'T');
      }

      // If no timezone info, treat as UTC (server stores UTC)
      if (!hasTimezone) {
        formatted = '${formatted}Z';
      }

      return DateTime.parse(formatted).toLocal();
    } catch (_) {
      return DateTime.now();
    }
  }

  static String formatShortDate(DateTime date) {
    return DateFormat('MMM d, yyyy h:mm a').format(date.toLocal());
  }

  static String formatTimeAgo(DateTime date, {DateTime? now}) {
    final localDate = date.toLocal();
    final current = (now ?? DateTime.now()).toLocal();
    final diff = current.difference(localDate);

    if (diff.inSeconds < 10) return 'Just now';
    if (diff.inMinutes < 1) return '${diff.inSeconds}s ago';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return DateFormat('MMM d, yyyy').format(localDate);
  }

  static String formatUsernameAvailability(String? dateStr) {
    if (dateStr == null || dateStr.trim().isEmpty) {
      return 'After 30 days from your last username change';
    }

    final parsed = parseServerTime(dateStr);
    return DateFormat('MMM d, yyyy • h:mm a').format(parsed);
  }

  /// Returns a human-readable countdown string like "23 days, 4 hours left"
  /// until [dateStr] (a UTC server timestamp). Returns null if already past.
  static String? timeRemainingUntil(String? dateStr) {
    if (dateStr == null || dateStr.trim().isEmpty) return null;
    try {
      final target = parseServerTime(dateStr);
      final now = DateTime.now();
      final diff = target.difference(now);
      if (diff.isNegative) return null;

      final days = diff.inDays;
      final hours = diff.inHours % 24;
      final minutes = diff.inMinutes % 60;

      if (days > 0) {
        return '$days day${days == 1 ? '' : 's'}'
            '${hours > 0 ? ', $hours hr${hours == 1 ? '' : 's'}' : ''} left';
      }
      if (hours > 0) {
        return '$hours hr${hours == 1 ? '' : 's'}'
            '${minutes > 0 ? ', $minutes min${minutes == 1 ? '' : 's'}' : ''} left';
      }
      return '$minutes min${minutes == 1 ? '' : 's'} left';
    } catch (_) {
      return null;
    }
  }
}
