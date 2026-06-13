import 'dart:async';
import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

class ConnectivityService extends ChangeNotifier {
  static final ConnectivityService instance = ConnectivityService._();
  ConnectivityService._();

  bool _isOnline = true;
  bool _isInitialized = false;
  StreamSubscription<List<ConnectivityResult>>? _sub;

  bool get isOnline => _isOnline;
  bool get isInitialized => _isInitialized;

  Future<void> init() async {
    _isOnline = await _checkInternet();
    _isInitialized = true;
    notifyListeners();

    _sub = Connectivity().onConnectivityChanged.listen((results) async {
      if (results.every((r) => r == ConnectivityResult.none)) {
        _update(false);
      } else {
        _update(await _checkInternet());
      }
    });
  }

  Future<bool> recheck() async {
    final online = await _checkInternet();
    _update(online);
    return online;
  }

  void _update(bool online) {
    if (_isOnline == online) return;
    _isOnline = online;
    notifyListeners();
  }

  static Future<bool> _checkInternet() async {
    try {
      final result = await InternetAddress.lookup('google.com')
          .timeout(const Duration(seconds: 5));
      return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
