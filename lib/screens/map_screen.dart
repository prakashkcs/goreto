import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:love_vibe_pro/core/theme.dart';
import 'package:love_vibe_pro/services/api_service.dart';
import 'package:love_vibe_pro/services/profile_service.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:love_vibe_pro/widgets/neon_toast.dart';
import 'package:love_vibe_pro/utils/privacy_utils.dart'; // Import privacy utils

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  LatLng? _currentPosition;
  List<dynamic> _nearbyUsers = [];
  Timer? _timer;
  final ApiService _apiService = ApiService();
  final MapController _mapController = MapController();

  @override
  void initState() {
    super.initState();
    _initLocation();
    // Update location every 5 minutes
    _timer = Timer.periodic(const Duration(minutes: 5), (timer) async {
      if (_currentPosition != null) {
        final userId = await ProfileService.instance.getCurrentUserId();
        if (userId != null) {
          _apiService.updateLocation(
            userId: userId,
            lat: _currentPosition!.latitude,
            lng: _currentPosition!.longitude,
          );
        }
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _initLocation() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return;
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      return;
    }

    final position = await Geolocator.getCurrentPosition();
    setState(() {
      _currentPosition = LatLng(position.latitude, position.longitude);
    });

    // Initial update
    final userId = await ProfileService.instance.getCurrentUserId();
    if (userId != null) {
      await _apiService.updateLocation(
        userId: userId,
        lat: position.latitude,
        lng: position.longitude,
      );
    }
    _fetchNearbyUsers();
  }

  Future<void> _fetchNearbyUsers() async {
    if (_currentPosition == null) return;
    final userId = await ProfileService.instance.getCurrentUserId();
    if (userId == null) return;
    try {
      final users = await _apiService.getNearbyMatchProfiles(
        userId: userId,
        lat: _currentPosition!.latitude,
        lng: _currentPosition!.longitude,
      );
      if (mounted) {
        setState(() {
          _nearbyUsers = users;
        });
      }
    } catch (e) {
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_currentPosition == null) {
      return const Center(
        child: CircularProgressIndicator(color: GalacticTheme.laserPink),
      );
    }

    final myFuzzedRaw = PrivacyUtils.fuzzLocation(_currentPosition!.latitude, _currentPosition!.longitude);
    final myFuzzedPos = LatLng(myFuzzedRaw['lat']!, myFuzzedRaw['lng']!);

    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(initialCenter: myFuzzedPos, initialZoom: 14.0),
      children: [
        TileLayer(
          // Use OpenStreetMap free tiles
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.example.love_vibe_pro',
        ),
        MarkerLayer(
          markers: [
            // Current User Marker (Fuzzed)
            Marker(
              point: myFuzzedPos,
              width: 80,
              height: 80,
              child: Container(
                decoration: BoxDecoration(
                  color: GalacticTheme.cyberBlue.withValues(alpha: 0.3),
                  shape: BoxShape.circle,
                  border: Border.all(color: GalacticTheme.cyberBlue, width: 2),
                ),
                child: const Icon(
                  Icons.my_location,
                  color: GalacticTheme.cyberBlue,
                  size: 40,
                ),
              ),
            ),
            // Nearby Users
            ..._nearbyUsers.map((user) {
              final theirFuzzedRaw = PrivacyUtils.fuzzLocation(user['lat'], user['lng']);
              final theirFuzzedPos = LatLng(theirFuzzedRaw['lat']!, theirFuzzedRaw['lng']!);
              return Marker(
                point: theirFuzzedPos,
                width: 60,
                height: 60,
                child: GestureDetector(
                  onTap: () {
                    // Show user details
                    NeonToast.info(context, user['name'] ?? 'User');
                  },
                  child: Container(
                    decoration: BoxDecoration(
                      color: GalacticTheme.laserPink.withValues(alpha: 0.3),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: GalacticTheme.laserPink,
                        width: 2,
                      ),
                    ),
                    child: CircleAvatar(
                      backgroundImage: CachedNetworkImageProvider(
                        user['avatar_url'] ?? '',
                      ),
                    ),
                  ),
                ),
              );
            }),
          ],
        ),
      ],
    );
  }
}
