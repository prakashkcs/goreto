import 'dart:io';

void main() {
  final file = File('lib/screens/profile/edit_profile_screen.dart');
  final lines = file.readAsLinesSync();
  bool changed = false;
  
  for (int i = 0; i < lines.length; i++) {
    // Fix Gender Male
    if (lines[i].contains("Male") && (lines[i].contains("â™‚") || lines[i].contains("child: Text("))) {
      if (lines[i].contains("'Male'") || lines[i].contains("Male'")) {
         lines[i] = lines[i].replaceAll(RegExp(r"'.*Male'"), "'♂️ Male'");
         changed = true;
      }
    }
    // Fix Gender Female
    if (lines[i].contains("Female") && (lines[i].contains("â™€") || lines[i].contains("child: Text("))) {
       if (lines[i].contains("'Female'") || lines[i].contains("Female'")) {
         lines[i] = lines[i].replaceAll(RegExp(r"'.*Female'"), "'♀️ Female'");
         changed = true;
       }
    }
    // Fix Sports
    if (lines[i].contains("'Sports") && lines[i].contains("âš½")) {
      lines[i] = "    'Sports ⚽',";
      changed = true;
    }
    // Fix Travel Partner
    if (lines[i].contains("'Travel Partner") && lines[i].contains("âœˆ")) {
      lines[i] = "    'Travel Partner ✈️',";
      changed = true;
    }
  }
  
  if (changed) {
    file.writeAsStringSync(lines.join('\r\n'));
    print('Fixed edit_profile_screen.dart');
  } else {
    print('No changes made to edit_profile_screen.dart');
  }
}
