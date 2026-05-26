import 'package:permission_handler/permission_handler.dart';

class PermissionService {
  static final PermissionService instance = PermissionService._();
  PermissionService._();


  /// Check if the essential permissions for the app are granted.
  /// (Location, Notifications, Camera, Microphone)
  Future<bool> hasEssentialPermissions() async {
    final status = await Future.wait([
      Permission.location.status,
      Permission.notification.status,
      Permission.camera.status,
      Permission.microphone.status,
      Permission.nearbyWifiDevices.status,
      Permission.bluetoothScan.status,
      Permission.bluetoothConnect.status,
    ]);

    return status.every((s) => s.isGranted);
  }

  /// Request essential permissions.
  /// Returns map of permission to its final status.
  Future<Map<Permission, PermissionStatus>>
  requestEssentialPermissions() async {
    try {
      Map<Permission, PermissionStatus> status = await [
        Permission.location,
        Permission.notification,
        Permission.camera,
        Permission.microphone,
        Permission.nearbyWifiDevices,
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
      ].request();

      // On Android 11+, we must request locationAlways separately after whileInUse is granted
      if (status[Permission.location]?.isGranted == true) {
        final alwaysStatus = await Permission.locationAlways.request();
        status[Permission.locationAlways] = alwaysStatus;
      }

      return status;
    } catch (e) {
      return {};
    }
  }

  /// Check specific permission status
  Future<PermissionStatus> getStatus(Permission permission) async {
    return await permission.status;
  }

  /// Open app settings
  Future<bool> openSettings() async {
    return await openAppSettings();
  }

  /// Essential for nearby notifications: Location and Notifications
  Future<bool> hasNearbyPermissions() async {
    final loc = await Permission.location.status;
    final notif = await Permission.notification.status;
    return loc.isGranted && notif.isGranted;
  }
}
