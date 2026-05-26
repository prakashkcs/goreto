import 'dart:io';

void main() {
  final dir = Directory('lib');
  final replacements = {
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
    'â ¤ï¸ ': '❤️',
    'ðŸ’¼': '💼',
    'ðŸŽ¨': '🎨',
    'ðŸŽ®': '🎮',
    'ðŸ’ª': '💪',
    'ðŸŽ¬': '🎬',
    'ðŸŒ•': '🍕',
    'ðŸ’ ': '🌹',
    'ðŸŽ': '📽️',
    'ðŸ“ ': '📍', // Live location
  };

  print('Starting comprehensive emoji fix...');
  
  dir.listSync(recursive: true).forEach((file) {
    if (file is File && file.path.endsWith('.dart')) {
      bool changed = false;
      List<int> bytes = file.readAsBytesSync();
      // Use Latin1 decoding to treat bytes as characters for mapping
      String content = String.fromCharCodes(bytes); 
      
      replacements.forEach((key, value) {
        if (content.contains(key)) {
          content = content.replaceAll(key, value);
          changed = true;
          print('Fixed emoji in ${file.path}: mapping $key to $value');
        }
      });
      
      if (changed) {
        // Write back as UTF-8
        file.writeAsStringSync(content);
      }
    }
  });
  
  print('Done.');
}
