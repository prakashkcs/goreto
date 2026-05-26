import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:love_vibe_pro/core/theme.dart';
import 'package:love_vibe_pro/models/wallet_models.dart';
import 'package:love_vibe_pro/screens/wallet/deposit_flow_screen.dart';
import 'package:love_vibe_pro/screens/wallet/subscription_screen.dart';
import 'package:love_vibe_pro/screens/wallet/wallet_history_screen.dart';
import 'package:love_vibe_pro/screens/wallet/withdraw_screen.dart';
import 'package:love_vibe_pro/services/settings_store.dart';
import 'package:love_vibe_pro/widgets/neon_toast.dart';
import 'package:love_vibe_pro/services/wallet_service.dart';
import 'package:love_vibe_pro/services/api_service.dart';
import 'package:love_vibe_pro/screens/wallet/wallet_gifts_tab.dart';
import 'package:love_vibe_pro/widgets/coin_icon.dart';
import 'package:share_plus/share_plus.dart';

class WalletScreen extends StatefulWidget {
  const WalletScreen({super.key});

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen> {
  final WalletService _walletService = WalletService();

  SettingsStore? _settingsStore;
  bool _isLoading = true;

  int _walletCoins = 0;
  String _referralCode = '';
  int _referralEditCount = 0;

  // Referral program settings
  int _referralCoinsReward = 100;
  String _playstoreUrl = '';
  String _appstoreUrl = '';

  // Redeem code state
  final TextEditingController _redeemController = TextEditingController();
  bool _isRedeeming = false;

  final int _maxReferralEdits = 1;
  List<WalletTransaction> _recentTransactions = <WalletTransaction>[];
  int _selectedTabIndex = 0; // 0 = Overview, 1 = My Gifts

  @override
  void initState() {
    super.initState();
    _loadWalletData();
    _loadReferralSettings();
  }

  @override
  void dispose() {
    _redeemController.dispose();
    super.dispose();
  }

  Future<void> _loadWalletData() async {
    _settingsStore ??= await SettingsStore.getInstance();
    if (mounted) setState(() => _isLoading = true);

    try {
      final results = await Future.wait<dynamic>([
        _walletService.getWalletBalance().then<dynamic>((v) => v).catchError((_) => null), // [0]
        ApiService().getUserProfile().catchError((_) => <String, dynamic>{}), // [1]
        _walletService.getReferralCode().catchError((_) => ''),               // [2]
        _walletService.applyPendingInstallReferralIfAny().catchError((_) => null), // [3]
        _walletService.getMergedTransactions(limit: 30).catchError((_) => <WalletTransaction>[]), // [4]
      ]);

      // [0] Wallet balance
      if (results[0] != null) {
        final info = results[0] as WalletInfo;
        _walletCoins = info.coins;
        await _settingsStore?.setWalletBalance(info.coins.toDouble());
      } else {
        _walletCoins = ((await _settingsStore?.getWalletBalance()) ?? 0).round();
      }

      // [1] Profile → referral code + edit count
      // Only write to SettingsStore when the profile returns a non-empty value —
      // never wipe a previously saved user-edited code with an empty string.
      final user = (results[1] as Map<String, dynamic>)['user'] ?? results[1];
      if (user is Map) {
        final profileCode = (user['referral_code'] ?? '').toString().trim();
        final profileEdited =
            int.tryParse((user['referral_code_edited'] ?? '0').toString()) ?? 0;
        if (profileCode.isNotEmpty) {
          _referralCode = profileCode;
          await _settingsStore?.setReferralCode(profileCode);
        }
        _referralEditCount = profileEdited;
        await _settingsStore?.setReferralEditCount(profileEdited);
      }

      // [2] Wallet service referral code overrides if non-empty
      final backendCode = (results[2] as String?) ?? '';
      if (backendCode.isNotEmpty) {
        _referralCode = backendCode;
        await _settingsStore?.setReferralCode(backendCode);
      }

      // Final fallback: SettingsStore cache (covers offline or API-failure case)
      if (_referralCode.isEmpty) {
        _referralCode = await _settingsStore?.getReferralCode() ?? '';
      }
      _referralEditCount =
          await _settingsStore?.getReferralEditCount() ?? _referralEditCount;

      // [4] Transactions
      final txList = results[4] as List<WalletTransaction>;
      if (mounted) setState(() => _recentTransactions = txList);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _refreshAll() async {
    await _loadWalletData();
  }

  Future<void> _loadReferralSettings() async {
    try {
      final dio = await ApiService().getDioClient();
      final response = await dio.get('/api_referral.php', queryParameters: {'action': 'settings'});
      final data = response.data is String
          ? (jsonDecode(response.data) as Map<String, dynamic>)
          : (response.data as Map<String, dynamic>);
      if (data['status'] == 'success' && mounted) {
        setState(() {
          _referralCoinsReward = (data['coins_reward'] as num?)?.toInt() ?? 100;
          _playstoreUrl = (data['playstore_url'] as String?) ?? '';
          _appstoreUrl  = (data['appstore_url']  as String?) ?? '';
        });
      }
    } catch (_) {}
  }

  Future<void> _redeemReferralCode() async {
    final code = _redeemController.text.trim().toUpperCase();
    if (code.isEmpty) {
      _showSnack('Enter a referral code first');
      return;
    }
    setState(() => _isRedeeming = true);
    try {
      final result = await _walletService.applyReferralCode(referralCode: code, source: 'manual');
      if (!mounted) return;
      if (result.success) {
        _redeemController.clear();
        NeonToast.success(context, result.message);
        await _loadWalletData();
      } else {
        NeonToast.error(context, result.message);
      }
    } finally {
      if (mounted) setState(() => _isRedeeming = false);
    }
  }

  void _showSnack(String message) {
    if (!mounted) return;
    NeonToast.info(context, message);
  }

  void _hapticFeedback() {
    HapticFeedback.mediumImpact();
  }

  Future<void> _openDeposit() async {
    _hapticFeedback();
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const DepositFlowScreen()),
    );
    await _refreshAll();
  }

  Future<void> _openHistory() async {
    _hapticFeedback();
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const WalletHistoryScreen()),
    );
    await _refreshAll();
  }

  Future<void> _openWithdraw() async {
    _hapticFeedback();
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => WithdrawScreen(maxCoins: _walletCoins)),
    );
    await _refreshAll();
  }

  Future<void> _openSubscription() async {
    _hapticFeedback();
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const SubscriptionScreen()),
    );
    await _refreshAll();
  }

  Future<void> _shareReferralCode() async {
    _hapticFeedback();

    final code = _referralCode.trim();
    if (code.isEmpty) {
      _showSnack('Referral code not available');
      return;
    }

    final encodedCode = Uri.encodeComponent(code);

    // Use stored Play Store URL if available, otherwise fallback
    final basePlay = _playstoreUrl.isNotEmpty
        ? _playstoreUrl
        : 'https://play.google.com/store/apps/details?id=com.nex.ekloapp';
    final playSep = basePlay.contains('?') ? '&' : '?';
    final playLink = '$basePlay${playSep}referrer=ref_$encodedCode';

    String message = 'Join GORETO using my referral code: $code\n$playLink';

    if (_appstoreUrl.isNotEmpty) {
      final iosSep = _appstoreUrl.contains('?') ? '&' : '?';
      final iosLink = '$_appstoreUrl${iosSep}referral=$encodedCode';
      message += '\n\niOS: $iosLink';
    }

    await SharePlus.instance.share(ShareParams(text: message, subject: 'GORETO Referral'));
  }

  Future<void> _editReferralCode() async {
    final remaining = _maxReferralEdits - _referralEditCount;
    if (remaining <= 0) {
      _showSnack('Referral code change limit reached');
      return;
    }

    final controller = TextEditingController(text: _referralCode);
    final formKey = GlobalKey<FormState>();

    final newCode = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text(
          'Edit Referral Code',
          style: TextStyle(color: Colors.white),
        ),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: controller,
            style: const TextStyle(color: Colors.white),
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(
              hintText: 'Enter new code',
              hintStyle: TextStyle(color: Colors.white54),
            ),
            validator: (value) {
              final v = (value ?? '').trim();
              if (v.length < 4) return 'Minimum 4 characters';
              final ok = RegExp(r'^[A-Za-z0-9]+$').hasMatch(v);
              if (!ok) return 'Use letters and numbers only';
              return null;
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              if (!(formKey.currentState?.validate() ?? false)) return;
              Navigator.pop(context, controller.text.trim().toUpperCase());
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (newCode == null || newCode.isEmpty) return;

    if (mounted) setState(() => _isLoading = true);

    final dio = await ApiService().getDioClient();
    try {
      final response = await dio.post(
        '/profile.php',
        queryParameters: {'action': 'update_referral_code'},
        data: {'referral_code': newCode},
      );
      final payload =
          response.data is String ? jsonDecode(response.data) : response.data;

      if (payload['status'] == 'success') {
        await _settingsStore?.setReferralCode(newCode);
        await _settingsStore?.setReferralEditCount(1);
        if (mounted) {
          setState(() {
            _referralCode = newCode;
            _referralEditCount = 1;
            _isLoading = false;
          });
        }
        _showSnack('Referral code updated successfully');
        return;
      } else {
        _showSnack(payload['message'] ?? 'Failed to update referral code');
      }
    } catch (e) {
      _showSnack('Error updating referral code: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: GalacticTheme.laserPink),
            )
          : SafeArea(
              child: RefreshIndicator(
                onRefresh: _refreshAll,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                  children: [
                    _buildHeader(),
                    _buildTabBar(),
                    if (_selectedTabIndex == 0) ...[
                      const SizedBox(height: 12),
                      _buildBalanceCard(),
                      const SizedBox(height: 14),
                      _buildQuickActions(),
                      const SizedBox(height: 14),
                      _buildReferralSection(),
                      const SizedBox(height: 14),
                      _buildRecentTransactions(),
                    ] else ...[
                      const SizedBox(height: 12),
                      WalletGiftsTab(
                        onBalanceUpdated: () {
                          _loadWalletData();
                        },
                      ),
                    ],
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        GestureDetector(
          onTap: () => Navigator.pop(context),
          child: Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A1A),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white24),
            ),
            child: const Icon(Icons.arrow_back, color: Colors.white),
          ),
        ),
        const SizedBox(width: 12),
        const Text(
          'Wallet',
          style: TextStyle(
            color: Colors.white,
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildTabBar() {
    return Container(
      margin: const EdgeInsets.only(top: 16, bottom: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF141414),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () {
                _hapticFeedback();
                setState(() => _selectedTabIndex = 0);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: _selectedTabIndex == 0
                      ? const Color(0xFF06B6D4).withValues(alpha: 0.2)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(13),
                  border: Border.all(
                    color: _selectedTabIndex == 0
                        ? const Color(0xFF06B6D4).withValues(alpha: 0.5)
                        : Colors.transparent,
                  ),
                ),
                alignment: Alignment.center,
                child: Text(
                  'Overview',
                  style: TextStyle(
                    color: _selectedTabIndex == 0
                        ? const Color(0xFF06B6D4)
                        : Colors.white60,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: GestureDetector(
              onTap: () {
                _hapticFeedback();
                setState(() => _selectedTabIndex = 1);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: _selectedTabIndex == 1
                      ? const Color(0xFFF97316).withValues(alpha: 0.2)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(13),
                  border: Border.all(
                    color: _selectedTabIndex == 1
                        ? const Color(0xFFF97316).withValues(alpha: 0.5)
                        : Colors.transparent,
                  ),
                ),
                alignment: Alignment.center,
                child: Text(
                  'My Gifts',
                  style: TextStyle(
                    color: _selectedTabIndex == 1
                        ? const Color(0xFFF97316)
                        : Colors.white60,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBalanceCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          colors: [Color(0xFF22C55E), Color(0xFF06B6D4)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Current Balance',
            style: TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Text(
                '$_walletCoins',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 34,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 8),
              const CoinIcon(size: 30, color: Colors.white),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _openDeposit,
              icon: const Icon(Icons.add_circle_outline),
              label: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Deposit'),
                  SizedBox(width: 4),
                  CoinIcon(size: 16, color: Colors.black),
                ],
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: const Color(0xFF0C1220),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActions() {
    return Row(
      children: [
        Expanded(
          child: _actionCard(
            icon: Icons.arrow_upward_rounded,
            label: 'Withdraw',
            color: const Color(0xFFFF9800),
            onTap: _openWithdraw,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _actionCard(
            icon: Icons.history,
            label: 'History',
            color: const Color(0xFFD946EF),
            onTap: _openHistory,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _actionCard(
            icon: Icons.workspace_premium_outlined,
            label: 'Subscription',
            color: const Color(0xFF22C55E),
            onTap: _openSubscription,
          ),
        ),
      ],
    );
  }

  Widget _actionCard({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Ink(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFF141414),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color),
            const SizedBox(height: 6),
            Text(
              label,
              style: const TextStyle(color: Colors.white, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReferralSection() {
    final remaining = (_maxReferralEdits - _referralEditCount).clamp(
      0,
      _maxReferralEdits,
    );

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF141414),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFFD946EF).withValues(alpha: 0.35),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Referral Program',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFD946EF).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFFD946EF).withValues(alpha: 0.4)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CoinIcon(size: 14, color: Color(0xFFD946EF)),
                    const SizedBox(width: 4),
                    Text(
                      '+$_referralCoinsReward each',
                      style: const TextStyle(color: Color(0xFFD946EF), fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'Invite friends — both of you earn coins.',
            style: TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF1D1D1D),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white12),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Your referral code',
                        style: TextStyle(color: Colors.white54),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _referralCode.isEmpty ? '—' : _referralCode,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: _referralCode.isEmpty
                      ? null
                      : () {
                          Clipboard.setData(ClipboardData(text: _referralCode));
                          _showSnack('Referral code copied');
                        },
                  icon: const Icon(Icons.copy, color: Colors.white70),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _shareReferralCode,
                  icon: const Icon(Icons.share, size: 18),
                  label: const Text('Share Link'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFD946EF),
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: remaining > 0 ? _editReferralCode : null,
                  icon: const Icon(Icons.edit, size: 18),
                  label: Text(
                    remaining > 0
                        ? 'Edit ($remaining left)'
                        : 'Edit unavailable',
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: BorderSide(
                      color: Colors.white.withValues(alpha: 0.25),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // Redeem a friend's code
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF0D1A0D),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF22C55E).withValues(alpha: 0.35)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Redeem a Friend\'s Code',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                  'Enter a referral code to claim $_referralCoinsReward coins',
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _redeemController,
                        style: const TextStyle(color: Colors.white, letterSpacing: 1.1),
                        textCapitalization: TextCapitalization.characters,
                        decoration: InputDecoration(
                          hintText: 'Enter code',
                          hintStyle: const TextStyle(color: Colors.white38),
                          filled: true,
                          fillColor: const Color(0xFF1A1A1A),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    SizedBox(
                      height: 46,
                      child: ElevatedButton(
                        onPressed: _isRedeeming ? null : _redeemReferralCode,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF22C55E),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        child: _isRedeeming
                            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Text('Redeem', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecentTransactions() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF141414),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Recent Transactions',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              TextButton(onPressed: _openHistory, child: const Text('See All')),
            ],
          ),
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_recentTransactions.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'No transactions yet',
                style: TextStyle(color: Colors.white60),
              ),
            )
          else
            ..._recentTransactions.take(5).map(_transactionTile),
        ],
      ),
    );
  }

  Widget _transactionTile(WalletTransaction tx) {
    final color = _statusColor(tx.status);
    final amountWidget = _formatAmount(tx, color);
    final timeText = tx.createdAt == null
        ? 'Unknown time'
        : DateFormat('MMM d, yyyy â€¢ h:mm a').format(tx.createdAt!.toLocal());

    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(_typeIcon(tx.type), color: color, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _titleFromType(tx.type),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  timeText,
                  style: const TextStyle(color: Colors.white60, fontSize: 12),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              amountWidget,
              if ((tx.rejectReason ?? '').isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    tx.rejectReason!,
                    style: const TextStyle(
                      color: Colors.redAccent,
                      fontSize: 10,
                    ),
                  ),
                ),
              const SizedBox(height: 2),
              _statusBadge(tx.status),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statusBadge(String status) {
    final color = _statusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        status.toUpperCase(),
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Color _statusColor(String statusRaw) {
    final status = statusRaw.toLowerCase();
    if (status.contains('approved') || status.contains('completed')) {
      return const Color(0xFF22C55E);
    }
    if (status.contains('review') || status.contains('pending')) {
      return const Color(0xFFF59E0B);
    }
    if (status.contains('reject') || status.contains('failed')) {
      return const Color(0xFFEF4444);
    }
    return const Color(0xFF06B6D4);
  }

  IconData _typeIcon(String typeRaw) {
    final type = typeRaw.toLowerCase();
    if (type.contains('deposit')) return Icons.south_west;
    if (type.contains('withdraw')) return Icons.north_east;
    if (type.contains('referral')) return Icons.people_alt_outlined;
    if (type.contains('gift')) return Icons.card_giftcard;
    return Icons.receipt_long_outlined;
  }

  String _titleFromType(String typeRaw) {
    final type = typeRaw.toLowerCase();
    if (type.contains('deposit')) return 'Deposit';
    if (type.contains('withdraw')) return 'Withdraw';
    if (type.contains('referral')) return 'Referral Bonus';
    if (type.contains('gift')) return 'Gift';
    return toBeginningOfSentenceCase(typeRaw.replaceAll('_', ' ')) ??
        'Transaction';
  }

  Widget _formatAmount(WalletTransaction tx, Color color) {
    final type = tx.type.toLowerCase();
    final debit =
        tx.direction.toLowerCase() == 'debit' || type.contains('withdraw');
    final sign = debit ? '-' : '+';

    if (tx.currencyAmount != null) {
      return Text(
        '$sign${tx.currencyAmount!.abs().toStringAsFixed(2)} ${tx.currencyCode}',
        style: TextStyle(color: color, fontWeight: FontWeight.bold),
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$sign${tx.coins.abs()}',
          style: TextStyle(color: color, fontWeight: FontWeight.bold),
        ),
        const SizedBox(width: 4),
        CoinIcon(size: 14, color: color),
      ],
    );
  }
}
