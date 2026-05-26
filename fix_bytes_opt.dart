import 'dart:io';
import 'dart:convert';

void main() {
  final dir = Directory('lib');
  
  // Mapping byte sequences to emoji Strings
  final replacements = {
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
    [0xE2, 0x9D, 0xA4, 0xEF, 0xB8, 0x8F]: '❤️',
    [0xF0, 0x9F, 0x92, 0xBC]: '💼',
    [0xF0, 0x9F, 0x8E, 0xA8]: '🎨',
    [0xF0, 0x9F, 0x8E, 0xAE]: '🎮',
    [0xF0, 0x9F, 0x92, 0xAA]: '💪',
    [0xF0, 0x9F, 0x8E, 0xAC]: '🎬',
    [0xF0, 0x9F, 0x8D, 0x95]: '🍕',
    [0xF0, 0x9F, 0x8C, 0xB9]: '🌹',
    [0xF0, 0x9F, 0x93, 0x8D]: '📍',
    // Catch single trailing bytes if they appear
    [0xF0, 0x9F, 0x92]: '🌹',
  };

  print('Starting optimized byte-level emoji fix...');
  
  // Pre-calculate UTF-8 bytes for replacements
  final replacementMap = <List<int>, List<int>>{};
  replacements.forEach((key, value) {
    replacementMap[key] = utf8.encode(value);
  });

  dir.listSync(recursive: true).forEach((file) {
    if (file is File && file.path.endsWith('.dart')) {
      bool changed = false;
      List<int> bytes = file.readAsBytesSync();
      
      for (var entry in replacementMap.entries) {
        final target = entry.key;
        final replacementUtf8Bytes = entry.value;
        
        int index = 0;
        while ((index = _findSequence(bytes, target, index)) != -1) {
          final newBytes = <int>[];
          newBytes.addAll(bytes.sublist(0, index));
          newBytes.addAll(replacementUtf8Bytes);
          newBytes.addAll(bytes.sublist(index + target.length));
          bytes = newBytes;
          changed = true;
          // No print in loop to save time
        }
      }
      
      if (changed) {
        file.writeAsBytesSync(bytes);
        print('Fixed file: ${file.path}');
      }
    }
  });
  
  print('Done.');
}

int _findSequence(List<int> bytes, List<int> sequence, int start) {
  if (sequence.isEmpty) return -1;
  if (start > bytes.length - sequence.length) return -1;
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
