import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:geolocator/geolocator.dart';
import 'package:love_vibe_pro/services/api_service.dart';
import 'package:love_vibe_pro/managers/privacy_manager.dart';

class SyncManager {
  static final SyncManager instance = SyncManager._internal();
  SyncManager._internal();

  Database? _db;
  StreamSubscription? _connectivitySubscription;

  Future<void> init() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'offline_sync.db');

    _db = await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE encounter_logs (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            detected_ephemeral_id TEXT,
            timestamp TEXT
          )
        ''');
        await db.execute('''
          CREATE TABLE location_cache (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            lat REAL,
            lng REAL,
            timestamp TEXT
          )
        ''');
      },
    );

    _listenForNetworkRecovery();
  }

  void _listenForNetworkRecovery() {
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((List<ConnectivityResult> results) {
      if (results.contains(ConnectivityResult.mobile) || results.contains(ConnectivityResult.wifi)) {
        _syncOfflineData();
      }
    });
  }

  /// Caches location using Balanced Power Accuracy when offline
  Future<void> cacheLastKnownLocation() async {
    if (PrivacyManager.instance.isInvisibleMode) {
      // Data Minimization: Do not record absolute GPS if invisible
      return; 
    }

    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium, // Balanced Power Accuracy
      );

      await _db?.insert('location_cache', {
        'lat': position.latitude,
        'lng': position.longitude,
        'timestamp': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      // Geolocator permissions might be denied
    }
  }

  Future<void> logOfflineEncounter(String ephemeralId) async {
    await _db?.insert('encounter_logs', {
      'detected_ephemeral_id': ephemeralId,
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  Future<void> _syncOfflineData() async {
    if (_db == null) return;

    // 1. Fetch cached encounters and locations
    final encounters = await _db!.query('encounter_logs');
    final locations = await _db!.query('location_cache');

    if (encounters.isEmpty && locations.isEmpty) return;

    // Use the most recent location ping
    Map<String, dynamic>? finalPing;
    if (locations.isNotEmpty) {
      finalPing = {
        'lat': locations.last['lat'],
        'lng': locations.last['lng'],
        'timestamp': locations.last['timestamp'],
      };
    }

    // 2. Batch upload to backend
    try {
      await ApiService().syncOfflineData(encounters, finalPing);

      // 3. Clear SQLite on successful sync
      await _db!.execute('DELETE FROM encounter_logs');
      await _db!.execute('DELETE FROM location_cache');
    } catch (e) {
      // Remain in cache to retry next time internet is regained
    }
  }

  void dispose() {
    _connectivitySubscription?.cancel();
    _db?.close();
  }
}
