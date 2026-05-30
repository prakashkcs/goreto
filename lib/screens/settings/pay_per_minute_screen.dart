import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:love_vibe_pro/services/chat_package_service.dart';
import 'package:love_vibe_pro/services/api_service.dart';
import 'package:love_vibe_pro/widgets/neon_toast.dart';
import 'package:love_vibe_pro/widgets/coin_icon.dart';
import 'package:love_vibe_pro/services/settings_store.dart';

// Kept for backward-compat navigation — now routes to ChatPackagesScreen.
class PayPerMinuteScreen extends StatelessWidget {
  const PayPerMinuteScreen({super.key});

  @override
  Widget build(BuildContext context) =>
      const ChatPackagesScreen();
}

/// Chat time-package manager — creators create packages (5 min / 10 min /
/// 20 min etc.) with a coin price. Buyers buy them from the chat composer.
class ChatPackagesScreen extends StatefulWidget {
  const ChatPackagesScreen({super.key});

  @override
  State<ChatPackagesScreen> createState() => _ChatPackagesScreenState();
}

class _ChatPackagesScreenState extends State<ChatPackagesScreen> {
  final ApiService _api = ApiService();
  bool _isLoading = true;
  bool _kycVerified = false;
  bool _chargeFriends = false;
  List<ChatPackage> _packages = [];

  // Form
  final _nameCtrl = TextEditingController();
  final _minutesCtrl = TextEditingController();
  final _coinsCtrl = TextEditingController();
  bool _creating = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _minutesCtrl.dispose();
    _coinsCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final store = await SettingsStore.getInstance();
    final kyc = await store.getKycVerified();

    // Load creator's own packages
    final dio = await _api.getDioClient();
    try {
      final res = await dio.get('chat_packages.php',
          queryParameters: {'action': 'list'});
      final body = _map(res.data);
      final pkgs = (body['packages'] as List? ?? [])
          .map((e) => ChatPackage.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();

      // Load charge-friends pref from profile
      bool cf = false;
      try {
        final prRes = await dio.get('profile_v19.php');
        final pr = _map(prRes.data);
        final u = (pr['user'] is Map ? pr['user'] : pr) as Map;
        cf = u['ppm_charge_friends'] == 1 || u['ppm_charge_friends'] == true;
      } catch (_) {}

      if (mounted) {
        setState(() {
          _packages = pkgs;
          _kycVerified = kyc;
          _chargeFriends = cf;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _createPackage() async {
    final name = _nameCtrl.text.trim();
    final mins = int.tryParse(_minutesCtrl.text.trim()) ?? 0;
    final coins = int.tryParse(_coinsCtrl.text.trim()) ?? 0;
    if (name.isEmpty || mins <= 0) {
      NeonToast.error(context, 'Enter a name and valid minutes');
      return;
    }
    setState(() => _creating = true);
    try {
      final dio = await _api.getDioClient();
      final res = await dio.post(
        'chat_packages.php?action=create',
        data: {'name': name, 'minutes': mins, 'price_coins': coins, 'is_free': 0},
      );
      final body = _map(res.data);
      if (body['status'] == 'success') {
        _nameCtrl.clear();
        _minutesCtrl.clear();
        _coinsCtrl.clear();
        NeonToast.success(context, 'Package created!');
        await _load();
      } else {
        NeonToast.error(context, body['message']?.toString() ?? 'Failed');
      }
    } catch (e) {
      NeonToast.error(context, e.toString().replaceAll('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  Future<void> _deletePackage(int pkgId) async {
    try {
      final dio = await _api.getDioClient();
      await dio.post('chat_packages.php?action=delete',
          data: {'id': pkgId});
      if (mounted) {
        setState(() => _packages.removeWhere((p) => p.id == pkgId));
        NeonToast.info(context, 'Package removed');
      }
    } catch (_) {}
  }

  Future<void> _toggleChargeFriends(bool v) async {
    setState(() => _chargeFriends = v);
    try {
      final dio = await _api.getDioClient();
      await dio.post('update_profile.php',
          data: {'ppm_charge_friends': v ? 1 : 0});
    } catch (_) {
      if (mounted) setState(() => _chargeFriends = !v);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A14),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Chat Time Packages',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFFFF007F)))
          : _buildBody(),
    );
  }

  Widget _buildBody() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Info card
        Container(
          padding: const EdgeInsets.all(16),
          margin: const EdgeInsets.only(bottom: 20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [
              Color(0xFF1A1A28),
              Color(0xFF12121E),
            ]),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
                color: const Color(0xFFFF007F).withValues(alpha: 0.25)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(children: [
                Icon(Icons.timer_rounded, color: Color(0xFFFF007F), size: 20),
                SizedBox(width: 8),
                Text('How it works',
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 15)),
              ]),
              const SizedBox(height: 10),
              _bullet('Everyone gets 5 min free per creator'),
              _bullet('Buy a time package to get more minutes'),
              _bullet('Timer counts down live inside the chat'),
              _bullet('Chat is blocked when time runs out'),
            ],
          ),
        ),

        // Charge friends toggle
        _sectionHeader('Settings'),
        _toggleTile(
          icon: Icons.people_rounded,
          label: 'Charge friends too',
          subtitle: 'When ON, mutual friends also need a package to message you',
          value: _chargeFriends,
          onChanged: _toggleChargeFriends,
        ),
        const SizedBox(height: 24),

        // Existing packages
        _sectionHeader('Your Packages (${_packages.length})'),
        if (_packages.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              'No packages yet. Create one below.',
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.4), fontSize: 13),
            ),
          ),
        ..._packages.map(_buildPackageCard),
        const SizedBox(height: 24),

        // Create form
        _sectionHeader('Create Package'),
        if (!_kycVerified)
          Container(
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: Colors.amber.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
            ),
            child: const Row(children: [
              Icon(Icons.warning_amber_rounded, color: Colors.amber, size: 18),
              SizedBox(width: 8),
              Expanded(
                  child: Text('KYC verification required to create packages',
                      style: TextStyle(color: Colors.amber, fontSize: 13))),
            ]),
          ),
        _inputField('Package name (e.g. "10 Min Chat")', _nameCtrl,
            keyboard: TextInputType.text),
        const SizedBox(height: 10),
        _inputField('Minutes', _minutesCtrl,
            keyboard: TextInputType.number),
        const SizedBox(height: 10),
        _inputField('Price (coins, 0 = free)', _coinsCtrl,
            keyboard: TextInputType.number),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton(
            onPressed: (_creating || !_kycVerified) ? null : _createPackage,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF007F),
              disabledBackgroundColor: Colors.grey.shade800,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
            child: _creating
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2.5))
                : const Text('Create Package',
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 15)),
          ),
        ),
        const SizedBox(height: 40),
      ],
    );
  }

  Widget _buildPackageCard(ChatPackage p) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A28),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: const Color(0xFFFF007F).withValues(alpha: 0.25)),
      ),
      child: Row(children: [
        const Icon(Icons.timer_rounded, color: Color(0xFFFF007F), size: 22),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(p.name,
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 14)),
              Text('${p.minutes} min • ${p.priceCoins == 0 ? "Free" : "${p.priceCoins} coins"}',
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.5),
                      fontSize: 12)),
            ],
          ),
        ),
        if (p.priceCoins > 0)
          Row(children: [
            const CoinIcon(size: 16, color: Colors.amber),
            const SizedBox(width: 4),
            Text('${p.priceCoins}',
                style: const TextStyle(
                    color: Colors.amber, fontWeight: FontWeight.w700)),
            const SizedBox(width: 10),
          ]),
        IconButton(
          icon: const Icon(Icons.delete_outline_rounded,
              color: Colors.red, size: 20),
          onPressed: () => _deletePackage(p.id),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
        ),
      ]),
    );
  }

  Widget _bullet(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 5),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('• ',
                style: TextStyle(color: Color(0xFFFF007F), fontSize: 14)),
            Expanded(
                child: Text(text,
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.7),
                        fontSize: 13))),
          ],
        ),
      );

  Widget _sectionHeader(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(text,
            style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 14,
                letterSpacing: 0.5)),
      );

  Widget _toggleTile({
    required IconData icon,
    required String label,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A28),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
      ),
      child: Row(children: [
        Icon(icon, color: const Color(0xFFFF007F), size: 22),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w600)),
              Text(subtitle,
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.45),
                      fontSize: 12)),
            ],
          ),
        ),
        Switch(
          value: value,
          onChanged: onChanged,
          activeColor: const Color(0xFFFF007F),
        ),
      ]),
    );
  }

  Widget _inputField(String hint, TextEditingController ctrl,
      {TextInputType keyboard = TextInputType.text}) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A28),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: TextField(
        controller: ctrl,
        keyboardType: keyboard,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle:
              TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 14),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          border: InputBorder.none,
        ),
      ),
    );
  }

  static Map<String, dynamic> _map(dynamic raw) {
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) return Map<String, dynamic>.from(raw);
    if (raw is String) {
      try {
        final v = jsonDecode(raw);
        if (v is Map) return Map<String, dynamic>.from(v);
      } catch (_) {}
    }
    return {};
  }
}
