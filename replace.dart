import 'dart:io';

void main() async {
  final file = File('lib/screens/home_screen.dart');
  final content = await file.readAsString();

  const startStr = '  Future<void> _openNotifications() async {';
  const endStr = '  void _showCreatePostOptions() {';

  final startIndex = content.indexOf(startStr);
  final endIndex = content.indexOf(endStr);

  if (startIndex != -1 && endIndex != -1) {
    final before = content.substring(0, startIndex);
    final after = content.substring(endIndex);

    const newCode = '''  Future<void> _openNotifications() async {
    await SoundService().playNotification();
    if (!mounted) return;
    
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const NotificationsScreen()),
    ).then((_) {
      if (mounted) setState(() {});
    });
  }

''';

    await file.writeAsString(before + newCode + after);
    print('Replaced successfully!');
  } else {
    print('Failed to find markers.');
  }
}
