import 'dart:io';

void main() async {
  final file = File('test_push_income.php');
  if (!file.existsSync()) {
    print('File not found');
    return;
  }

  String content = await file.readAsString();
  print(content);
}
