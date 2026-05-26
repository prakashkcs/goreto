import 'dart:io';

void main() {
  final file = File('lib/screens/home_screen.dart');
  final lines = file.readAsLinesSync();
  
  // Line 982 (0-indexed 981)
  if (lines.length > 981 && (lines[981].contains('Live Location') || lines[981].contains('ðŸ“'))) {
    lines[981] = "              '📍 Live Location: \${position.latitude.toStringAsFixed(5)}, \${position.longitude.toStringAsFixed(5)}',";
    print('Fixed line 982');
  }
  
  file.writeAsStringSync(lines.join('\r\n'));
}
