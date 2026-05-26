import 'dart:convert';

String buildUploadsUrl(
  String baseUrl,
  String fileName, {
  String folder = '',
}) {
  final root = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
  final cleanFolder = folder.trim().replaceAll(RegExp(r'^/+|/+$'), '');
  final cleanName = fileName
      .trim()
      .replaceAll('\\', '/')
      .split('/')
      .where((p) => p.isNotEmpty)
      .last;

  final folderPart = cleanFolder.isEmpty ? '' : '$cleanFolder/';
  return '$root/uploads/$folderPart$cleanName';
}

String normalizeMediaUrl(
  dynamic raw, {
  required String baseUrl,
  String folder = '',
}) {
  if (raw == null) return '';

  var value = raw.toString().trim();
  if (value.isEmpty || value.toLowerCase() == 'null') return '';

  // Handle JSON-array style values like: ["https://..."]
  if (value.startsWith('[') && value.endsWith(']')) {
    try {
      final decoded = jsonDecode(value);
      if (decoded is List && decoded.isNotEmpty) {
        value = decoded.first.toString().trim();
      }
    } catch (_) {}
  }

  // Remove wrapping quotes
  if ((value.startsWith('"') && value.endsWith('"')) ||
      (value.startsWith("'") && value.endsWith("'"))) {
    value = value.substring(1, value.length - 1).trim();
  }

  final fileName = _extractFileName(value);

  // Extract URL candidates from malformed markdown-ish strings
  final urlMatches = RegExp(r'https?://[^\s\]"\)]+', caseSensitive: false)
      .allMatches(value)
      .toList();

  if (urlMatches.isNotEmpty) {
    final urlCandidate = urlMatches.last.group(0)!.trim();

    if (_looksLikeMediaFile(urlCandidate)) {
      return urlCandidate;
    }

    if (fileName.isNotEmpty) {
      if (urlCandidate.endsWith('/')) {
        return '$urlCandidate$fileName';
      }
      if (urlCandidate.contains('/uploads/')) {
        return '$urlCandidate/$fileName';
      }
      return buildUploadsUrl(baseUrl, fileName, folder: folder);
    }

    return urlCandidate;
  }

  if (_isAbsoluteUrl(value)) return value;
  if (fileName.isNotEmpty) {
    return buildUploadsUrl(baseUrl, fileName, folder: folder);
  }

  return '';
}

bool isLikelyVideoPost(Map<String, dynamic> post, [String? mediaUrl]) {
  final type = (post['type'] ?? '').toString().toLowerCase();
  if (type == 'video' || type == 'reel' || type == 'reels') return true;

  final url = (mediaUrl ??
          post['video_url'] ??
          post['file_url'] ??
          post['media_url'] ??
          '')
      .toString()
      .toLowerCase();

  return url.endsWith('.mp4') ||
      url.endsWith('.mov') ||
      url.endsWith('.m4v') ||
      url.endsWith('.webm');
}

String _extractFileName(String input) {
  final cleaned = input.trim().replaceAll('\\', '/');

  final extMatches = RegExp(
    r'([A-Za-z0-9._-]+\.(?:jpg|jpeg|png|gif|webp|mp4|mov|m4v|webm))',
    caseSensitive: false,
  ).allMatches(cleaned).toList();

  if (extMatches.isNotEmpty) {
    return extMatches.last.group(1) ?? '';
  }

  // Fallback for plain filename values without slashes
  if (!cleaned.contains('/') &&
      !cleaned.contains(' ') &&
      !cleaned.contains('(') &&
      !cleaned.contains(')') &&
      cleaned.length < 180) {
    return cleaned;
  }

  return '';
}

bool _isAbsoluteUrl(String value) =>
    RegExp(r'^https?://', caseSensitive: false).hasMatch(value);

bool _looksLikeMediaFile(String value) =>
    RegExp(r'\.(jpg|jpeg|png|gif|webp|mp4|mov|m4v|webm)(\?.*)?$',
            caseSensitive: false)
        .hasMatch(value);
