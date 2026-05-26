import 'dart:io';

void main() {
  final dir = Directory('lib');
  
  // Mapping byte sequences to emoji Strings (UTF-8 encoded)
  final replacements = {
    // Each key is a list of bytes representing the broken sequence in Latin1/Windows-1252
    [0xF0, 0x9F, 0x92, 0x95]: '💕',
    [0xF0, 0x9F, 0x92, 0xAC]: '💬',
    [0xF0, 0x9F, 0x8E, 0x81]: '🎁',
    [0xF0, 0x9F, 0x92, 0x97]: '💗',
    [0xF0, 0x9F, 0x8E, 0xB5]: '🎵',
    [0xF0, 0x9F, 0x93, 0xB8]: '📷',
    [0xF0, 0x9F, 0x8D, 0xB3]: '🍳',
    [0xF0, 0x9F, 0x93, 0xB7]: '📸',
    [0xF0, 0x9F, 0x93, 0x9A]: '📚',
    [0xF0, 0x9F, 0x92, 0x83]: '💃',
    [0xF0, 0x9F, 0x8C, 0xBF]: '🌿',
    [0xF0, 0x9F, 0x92, 0xBB]: '💻',
    [0xF0, 0x9F, 0x91, 0x97]: '👗',
    [0xF0, 0x9F, 0xA7, 0x98]: '🧘',
    [0xF0, 0x9F, 0x92, 0x8D]: '💍',
    [0xF0, 0x9F, 0x8C, 0x99]: '🌙',
    [0xF0, 0x9F, 0xA4, 0x9D]: '🤝',
    [0xF0, 0x9F, 0xA7, 0xA0]: '🧠',
    [0xF0, 0x9F, 0x91, 0x8B]: '👋',
    [0xF0, 0x9F, 0x8F, 0x94, 0xEF, 0xB8, 0x8F]: '🏔️',
    [0xC3, 0xA2, 0xC2, 0xA4, 0xC3, 0xAF, 0xC2, 0xB8, 0xC2, 0x8F]: '❤️', // Complex broken heart
    [0xE2, 0x9D, 0xA4, 0xEF, 0xB8, 0x8F]: '❤️',
    [0xF0, 0x9F, 0x92, 0xBC]: '💼',
    [0xF0, 0x9F, 0x8E, 0xA8]: '🎨',
    [0xF0, 0x9F, 0x8E, 0xAE]: '🎮',
    [0xF0, 0x9F, 0x92, 0xAA]: '💪',
    [0xF0, 0x9F, 0x8E, 0xAC]: '🎬',
    [0xF0, 0x9F, 0x8D, 0x95]: '🍕',
    [0xF0, 0x9F, 0x92, 0x39]: '🌹', // Wait, 1F339 is Rose: F0 9F 8C B9
    [0xF0, 0x9F, 0x8C, 0xB9]: '🌹',
    [0xF0, 0x9F, 0x93, 0x8D]: '📍',
  };

  print('Starting byte-level emoji fix...');
  
  dir.listSync(recursive: true).forEach((file) {
    if (file is File && file.path.endsWith('.dart')) {
      bool changed = false;
      List<int> bytes = file.readAsBytesSync();
      
      for (var entry in replacements.entries) {
        final target = entry.key;
        final replacement = entry.value;
        final replacementBytes = replacement.codeUnits; // Note: this is UTF-16, we need UTF-8
        final utf8Replacement = File('tmp')..writeAsStringSync(replacement);
        final replacementUtf8Bytes = utf8Replacement.readAsBytesSync();
        
        int index = 0;
        while ((index = _findSequence(bytes, target, index)) != -1) {
          final newBytes = <int>[];
          newBytes.addAll(bytes.sublist(0, index));
          newBytes.addAll(replacementUtf8Bytes);
          newBytes.addAll(bytes.sublist(index + target.length));
          bytes = newBytes;
          changed = true;
          print('Fixed emoji in ${file.path}: mapping hex ${target.map((b) => b.toRadixString(16)).join()} to $replacement');
        }
      }
      
      if (changed) {
        file.writeAsBytesSync(bytes);
      }
    }
  });
  
  print('Done.');
}

int _findSequence(List<int> bytes, List<int> sequence, int start) {
  if (sequence.isEmpty) return -1;
  for (int i = start; i <= bytes.length - sequence.length; i++) {
    bool match = true;
    for (int j = 0; j < sequence.length; j++) {
      if (bytes[i + j] != sequence[j]) {
        match = false;
        break;
      }
    }
    if (match) return i;
  }
  return -1;
}
