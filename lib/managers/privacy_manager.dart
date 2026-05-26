import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:love_vibe_pro/services/api_service.dart';

class PrivacyManager {
  static final PrivacyManager instance = PrivacyManager._internal();
  PrivacyManager._internal();
  
  bool isInvisibleMode = false;

  /// Loads simple local settings
  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    isInvisibleMode = prefs.getBool('invisible_mode') ?? false;
  }

  /// Toggles invisible mode (No precise GPS sent to backend if true)
  Future<void> toggleInvisibleMode(bool val) async {
    isInvisibleMode = val;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('invisible_mode', val);
  }

  /// Prominent In-App Disclosure (GDPR/CCPA compliant) for Location/BLE
  static Future<bool> requestConsent(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('ble_consent') == true) return true;

    if (!context.mounted) return false;
    
    final granted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2C),
        title: const Text("Safety & Offline Discovery", style: TextStyle(color: Colors.white)),
        content: const Text(
          "To notify you of potential matches when you have no internet access, "
          "this app briefly collects location data and uses Bluetooth to detect others securely in the background.\n\n"
          "Your precise location is NEVER shared with other users. An approximated radius is used instead.\n\n"
          "Do you consent to enable background discovery?",
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Decline", style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF007F)),
            onPressed: () => Navigator.pop(context, true),
            child: const Text("I Consent"),
          ),
        ],
      ),
    ) ?? false;

    if (granted) {
      await prefs.setBool('ble_consent', true);
    }
    return granted;
  }

  /// Right to be Forgotten: Clears the server trail
  Future<void> wipeLocationHistory() async {
    try {
      await ApiService().forgetMe();
    } catch (e) {
    }
  }
}
