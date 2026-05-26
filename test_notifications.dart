import 'dart:convert';
import 'dart:io';

void main() async {
  final url = Uri.parse(
    'https://coinzop.com/ekloadmin/api/v1/gift_notifications.php?action=list',
  );
  final request = await HttpClient().getUrl(url);

  // Use a known user token or the debug bypass token to fetch data
  request.headers.add('Authorization', 'Bearer debug_bypass_sathi_2026');

  final response = await request.close();
  final responseBody = await response.transform(utf8.decoder).join();
  print('Real API Response: $responseBody');
}
