import 'dart:io';

void main() {
  final dir = Directory('lib');
  
  final replacements = {
    'â™‚': '♂️',
    'â™€': '♀️',
    'âœˆï¸ ': '✈️',
    'âš½': '⚽',
    'â˜•': '☕',
    'â ¤ï¸ ': '❤️',
    'ðŸ’•': '💕',
    'ðŸ’¬': '💬',
    'ðŸŽ ': '🎁',
    'ðŸ’—': '💗',
    'ðŸŽµ': '🎵',
    'ðŸ“¸': '📷',
    'ðŸ ³': '🍳',
    'ðŸ“·': '📸',
    'ðŸ“š': '📚',
    'ðŸ’ƒ': '💃',
    'ðŸŒ¿': '🌿',
    'ðŸ’»': '💻',
    'ðŸ‘—': '👗',
    'ðŸ§˜': '🧘',
    'ðŸ’ ': '💍',
    'ðŸŒ™': '🌙',
    'ðŸ¤ ': '🤝',
    'ðŸ§\u00A0': '🧠',
    'ðŸ‘‹': '👋',
    'ðŸ ”ï¸ ': '🏔️',
    'ðŸ’¼': '💼',
    'ðŸŽ¨': '🎨',
    'ðŸŽ®': '🎮',
    'ðŸ’ª': '💪',
    'ðŸŽ¬': '🎬',
    'ðŸŒ•': '🍕',
    'ðŸ’ ': '🌹',
    'ðŸŽ': '📽️',
    'ðŸ“ ': '📍',
  };

  print('Starting final exhaustive emoji fix...');
  
  dir.listSync(recursive: true).forEach((file) {
    if (file is File && file.path.endsWith('.dart')) {
      bool changed = false;
      List<int> bytes = file.readAsBytesSync();
      String content = String.fromCharCodes(bytes); // Treat bytes as Latin1 to match these exactly
      
      replacements.forEach((key, value) {
        if (content.contains(key)) {
          content = content.replaceAll(key, value);
          changed = true;
          print('Fixed in ${file.path}: $key -> $value');
        }
      });
      
      if (changed) {
        // Write as UTF-8
        file.writeAsStringSync(content);
      }
    }
  });
  
  print('Done.');
}
