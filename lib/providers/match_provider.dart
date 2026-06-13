import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:love_vibe_pro/models/match_user.dart';
import 'package:love_vibe_pro/services/match_service.dart';
import 'package:love_vibe_pro/services/profile_service.dart';

enum NearbySortMode { closest, highestRated, newest }

class MatchProvider extends ChangeNotifier {
  final MatchService _service = MatchService();
  final ProfileService _profileService = ProfileService.instance;

  // â”€â”€ Match-swipe state â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  List<MatchUser> _matchQueue = [];
  int _currentIndex = 0;

  // â”€â”€ Nearby state â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  List<MatchUser> _nearbyAll = [];
  NearbySortMode _sortMode = NearbySortMode.closest;

  // â”€â”€ Common state â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  bool _isLoading = false;
  String? _error;
  bool _hasMatchProfile = true; // Assume true until checked

  // â”€â”€ Getters â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  bool get isLoading => _isLoading;
  String? get error => _error;
  int get currentIndex => _currentIndex;
  NearbySortMode get sortMode => _sortMode;
  bool get hasMatchProfile => _hasMatchProfile;

  MatchUser? get currentUser =>
      _matchQueue.isNotEmpty && _currentIndex < _matchQueue.length
          ? _matchQueue[_currentIndex]
          : null;

  MatchUser? get nextMatchUser =>
      _matchQueue.isNotEmpty && _currentIndex + 1 < _matchQueue.length
          ? _matchQueue[_currentIndex + 1]
          : null;

  List<MatchUser> get nearbyUsers {
    final list = List<MatchUser>.from(_nearbyAll);
    switch (_sortMode) {
      case NearbySortMode.closest:
        list.sort((a, b) {
          final da = double.tryParse(a.distanceKm ?? '9999') ?? 9999;
          final db = double.tryParse(b.distanceKm ?? '9999') ?? 9999;
          return da.compareTo(db);
        });
        break;
      case NearbySortMode.highestRated:
        list.sort((a, b) => b.rating.compareTo(a.rating));
        break;
      case NearbySortMode.newest:
        // "newest" = reverse of our natural order (id desc approximation)
        list.sort((a, b) => b.id.compareTo(a.id));
        break;
    }
    return list;
  }

  // Keep old property for backward compat
  List<MatchUser> get users => _nearbyAll;

  // â”€â”€ Load â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  Future<void> loadNearbyUsers() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      // Run userId fetch, gender fetch, and location in parallel
      final userId = await _profileService.getCurrentUserId();
      if (userId == null) throw Exception('User not logged in');

      // Kick off gender + location concurrently
      final results = await Future.wait([
        // Gender from match profile
        _service.api.getMyMatchProfile().then((r) async {
          final profileData = r['profile'];
          if (profileData is Map<String, dynamic>) {
            final g = (profileData['gender'] ?? '').toString().toLowerCase();
            if (g == 'male' || g == 'female') {
              // Persist own gender so FCM nearby filter can read it in any isolate.
              final prefs = await SharedPreferences.getInstance();
              await prefs.setString('user_gender', g);
              return g == 'male' ? 'female' : 'male';
            }
          }
          return null;
        }).catchError((_) => null),
        // Location (with short timeout so it doesn't block)
        _getLocationQuick(),
      ]);

      final String? targetGender = results[0] as String?;
      final Position? position = results[1] as Position?;

      // Update our location on the server BEFORE querying nearby, so that
      // other users' queries can find us at our current position.
      if (position != null) {
        try {
          await _service.api.updateLocation(
            userId: userId,
            lat: position.latitude,
            lng: position.longitude,
          );
        } catch (_) {}
      }

      final fetched = await _service.getNearbyUsers(
        userId: userId,
        myLat: position?.latitude,
        myLng: position?.longitude,
        sort: _sortMode == NearbySortMode.closest
            ? 'nearby'
            : (_sortMode == NearbySortMode.highestRated ? 'rating' : 'newest'),
        gender: targetGender,
      );


      // Always strip own profile from results (safety net in case server slips)
      var filtered = fetched.where((u) => u.id != userId).toList();

      // Always apply gender filter client-side when we know the target gender.
      // Even 1-2 nearby users of the wrong gender should be filtered out.
      if (targetGender != null && filtered.isNotEmpty) {
        final genderFiltered = filtered
            .where((u) => u.gender.isEmpty || u.gender.toLowerCase() == targetGender)
            .toList();
        if (genderFiltered.isNotEmpty) {
          filtered = genderFiltered;
        }
      }

      // Separate data: match queue = full list; nearby = full list
      _matchQueue = List<MatchUser>.from(filtered);
      _nearbyAll = List<MatchUser>.from(filtered);
      _currentIndex = 0;

      // Assume if we got results, profile is somewhat ready.
      // In real app, we'd check a specific flag.
      _hasMatchProfile = true;
    } catch (e) {
      _error = e.toString();
      _matchQueue = [];
      _nearbyAll = [];
      _currentIndex = 0;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Fast location fetch — medium accuracy, 8s timeout, falls back to last known
  Future<Position?> _getLocationQuick() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return null;
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return null;
      }
      try {
        return await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.medium,
        ).timeout(const Duration(seconds: 8));
      } catch (_) {
        // GPS timed out or failed — use last known position so the query
        // still works rather than sending null coordinates.
        return await Geolocator.getLastKnownPosition();
      }
    } catch (_) {
      return null;
    }
  }

  void setHasMatchProfile(bool value) {
    _hasMatchProfile = value;
    notifyListeners();
  }

  // â”€â”€ Undo history â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  final List<({MatchUser user, bool wasProposal})> _history = [];

  bool get canUndo => _history.isNotEmpty;
  ({MatchUser user, bool wasProposal})? get lastAction =>
      _history.isNotEmpty ? _history.last : null;

  // â”€â”€ Swipe actions â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  void nextUser({bool wasProposal = false}) {
    if (_currentIndex < _matchQueue.length) {
      _history.add((
        user: _matchQueue[_currentIndex],
        wasProposal: wasProposal,
      ));
      _currentIndex++;
      notifyListeners();
    }
  }

  void undoLast() {
    if (_history.isEmpty) return;
    _history.removeLast();
    if (_currentIndex > 0) {
      _currentIndex--;
    }
    notifyListeners();
  }

  void reset() {
    _currentIndex = 0;
    _history.clear();
    loadNearbyUsers();
  }

  /// Clears all cached match/nearby data on logout without triggering a reload.
  void clearForLogout() {
    _matchQueue = [];
    _nearbyAll = [];
    _currentIndex = 0;
    _history.clear();
    _error = null;
    notifyListeners();
  }

  // â”€â”€ Nearby sort â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  void setSortMode(NearbySortMode mode) {
    if (_sortMode == mode) return;
    _sortMode = mode;
    loadNearbyUsers(); // Fetch newly sorted list from API
    notifyListeners();
  }
}
