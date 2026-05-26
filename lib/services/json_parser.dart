import 'dart:convert';
import 'package:flutter/foundation.dart';

Future<Map<String, dynamic>> parseJsonToMap(String encodedJson) {
  return compute(_decodeJsonToMap, encodedJson);
}

Map<String, dynamic> _decodeJsonToMap(String encodedJson) {
  return jsonDecode(encodedJson) as Map<String, dynamic>;
}

Future<List<dynamic>> parseJsonToList(String encodedJson) {
  return compute(_decodeJsonToList, encodedJson);
}

List<dynamic> _decodeJsonToList(String encodedJson) {
  return jsonDecode(encodedJson) as List<dynamic>;
}
