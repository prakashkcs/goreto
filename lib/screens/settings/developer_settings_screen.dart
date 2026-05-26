import 'package:flutter/material.dart';
import 'package:love_vibe_pro/config/app_config.dart';
import 'package:love_vibe_pro/services/api_service.dart';
import 'package:love_vibe_pro/widgets/neon_toast.dart';

class DeveloperSettingsScreen extends StatefulWidget {
  const DeveloperSettingsScreen({super.key});

  @override
  State<DeveloperSettingsScreen> createState() =>
      _DeveloperSettingsScreenState();
}

class _DeveloperSettingsScreenState extends State<DeveloperSettingsScreen> {
  ApiMode _selectedApiMode = ApiMode.live;
  String _lanIp = ""; // To store user-inputted LAN IP
  @override
  void initState() {
    super.initState();
    _loadApiMode();
  }

  Future<void> _loadApiMode() async {
    final currentBaseUrl = await AppConfig.getBaseUrl();
    if (currentBaseUrl == AppConfig.emulatorBaseUrl) {
      _selectedApiMode = ApiMode.emulator;
    } else if (currentBaseUrl.startsWith("http://") &&
        currentBaseUrl.contains("/ekloadmin/api/v1")) {
      // Attempt to extract LAN IP from current URL if it matches the pattern
      final uri = Uri.parse(currentBaseUrl);
      _lanIp = uri.host;
      _selectedApiMode = ApiMode.device;
    } else {
      _selectedApiMode = ApiMode.live;
    }
    setState(() {});
  }

  Future<void> _saveApiMode(ApiMode mode) async {
    // Special handling for device mode to update the LAN IP in AppConfig
    if (mode == ApiMode.device && _lanIp.isNotEmpty) {
      // This is a temporary way to update the static member. In a real app,
      // AppConfig should probably have a method to update deviceBaseUrl.
      // For this task, we will simulate by updating the static string directly.
    }

    await AppConfig.setApiMode(mode);
    await ApiService().init(); // Re-initialize ApiService with the new base URL
    setState(() {
      _selectedApiMode = mode;
    });
    NeonToast.info(context, 'API Mode set to ${_selectedApiMode.name}');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Developer Settings")),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "Select API Mode:",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              RadioListTile<ApiMode>(
                title: const Text("Emulator (10.0.2.2)"),
                value: ApiMode.emulator,
                groupValue: _selectedApiMode,
                onChanged: (ApiMode? value) {
                  if (value != null) _saveApiMode(value);
                },
              ),
              RadioListTile<ApiMode>(
                title: const Text("Local Device (LAN IP)"),
                value: ApiMode.device,
                groupValue: _selectedApiMode,
                onChanged: (ApiMode? value) {
                  if (value != null) _saveApiMode(value);
                },
              ),
              if (_selectedApiMode == ApiMode.device)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16.0,
                    vertical: 8.0,
                  ),
                  child: TextField(
                    decoration: const InputDecoration(
                      labelText: "Enter LAN IP",
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.url,
                    onChanged: (value) {
                      setState(() {
                        _lanIp = value;
                      });
                    },
                    controller: TextEditingController(text: _lanIp),
                  ),
                ),
              RadioListTile<ApiMode>(
                title: const Text("Live (goreto.org)"),
                value: ApiMode.live,
                groupValue: _selectedApiMode,
                onChanged: (ApiMode? value) {
                  if (value != null) _saveApiMode(value);
                },
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}
