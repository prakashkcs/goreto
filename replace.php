<?php
$content = file_get_contents('lib/screens/home_screen.dart');
$startId = '  Future<void> _openNotifications() async {';
$endId = '  void _showCreatePostOptions() {';
$startPos = strpos($content, $startId);
$endPos = strpos($content, $endId);
if ($startPos !== false && $endPos !== false) {
    $newCode = "  Future<void> _openNotifications() async {
    await SoundService().playNotification();
    if (!mounted) return;
    Navigator.push(context, MaterialPageRoute(builder: (_) => const NotificationsScreen())).then((_) {
      if (mounted) setState(() {});
    });
  }

";
    $newContent = substr($content, 0, $startPos) . $newCode . substr($content, $endPos);
    file_put_contents('lib/screens/home_screen.dart', $newContent);
    echo "Replaced successfully\n";
}
else {
    echo "Strings not found $startPos, $endPos\n";
}
?>
