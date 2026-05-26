import 'dart:io';

void main() {
  void fixFile(String path, Map<String, String> lineReplacements) {
    final file = File(path);
    if (!file.existsSync()) return;
    final lines = file.readAsLinesSync();
    bool changed = false;
    for (int i = 0; i < lines.length; i++) {
      for (var entry in lineReplacements.entries) {
        if (lines[i].contains(entry.key)) {
          lines[i] = entry.value;
          changed = true;
          print('Fixed line in $path: contains "${entry.key}"');
        }
      }
    }
    if (changed) {
      file.writeAsStringSync(lines.join('\r\n'));
    }
  }

  // 1. edit_profile_screen.dart
  fixFile('lib/screens/profile/edit_profile_screen.dart', {
    "'Cooking": "    'Cooking 🍳',",
    "'Serious Relationship": "    'Serious Relationship 💍',",
    "'Friendship": "    'Friendship 🤝',",
    "'Adventure Buddy": "    'Adventure Buddy 🏔️',",
  });

  // 2. match_tab.dart
  fixFile('lib/screens/match_tab.dart', {
    "NeonToast.success(context, 'Proposal sent!": "      NeonToast.success(context, 'Proposal sent! 🌹');",
  });

  // 3. home_screen.dart
  fixFile('lib/screens/home_screen.dart', {
    "'ðŸ“  Live Location": "              '📍 Live Location: \${position.latitude.toStringAsFixed(5)}, \${position.longitude.toStringAsFixed(5)}',",
  });

  print('Comprehensive line fix done.');
}
