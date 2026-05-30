import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:love_vibe_pro/services/api_service.dart';
import 'package:gradient_borders/gradient_borders.dart';
import 'package:love_vibe_pro/core/theme.dart';
import 'package:love_vibe_pro/services/settings_store.dart';
import 'package:love_vibe_pro/services/kyc_status_controller.dart';
import 'package:love_vibe_pro/services/profile_service.dart';
import 'package:love_vibe_pro/screens/profile_screen.dart';
import 'package:love_vibe_pro/screens/settings/kyc_screen.dart';
import 'package:love_vibe_pro/screens/settings/wallet_screen.dart';
import 'package:love_vibe_pro/screens/settings/pay_per_minute_screen.dart';
import 'package:love_vibe_pro/screens/settings/manage_plans_screen.dart';
import 'package:love_vibe_pro/screens/settings/active_subscribers_screen.dart';

import 'package:love_vibe_pro/screens/settings/account_security_screen.dart';
import 'package:love_vibe_pro/screens/settings/username_screen.dart';
import 'package:love_vibe_pro/screens/settings/privacy_controls_screen.dart';
import 'package:love_vibe_pro/screens/settings/blocked_users_screen.dart';
import 'package:love_vibe_pro/screens/settings/nearby_blocked_screen.dart';
import 'package:love_vibe_pro/widgets/neon_toast.dart';
import 'package:love_vibe_pro/screens/settings/delete_account_screen.dart';
import 'package:love_vibe_pro/screens/settings/legal_screen.dart';
import 'package:love_vibe_pro/widgets/coin_icon.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  SettingsStore? _settingsStore;
  bool _isLoading = true;

  // Settings values
  String _subscriptionStatus = 'inactive';
  bool _kycVerified = false;
  String _kycStatus = 'not_submitted';
  double _walletBalance = 0.0;
  String _referralCode = '';


  void _onKycStatusChanged() async {
    if (_settingsStore == null) return;
    final kycStatus = await _settingsStore!.getKycStatus();
    final kycVerified = await _settingsStore!.getKycVerified();
    final subscriptionStatus = await _settingsStore!.getSubscriptionStatus();

    if (mounted &&
        (_kycStatus != kycStatus ||
            _kycVerified != kycVerified ||
            _subscriptionStatus != subscriptionStatus)) {
      setState(() {
        _kycStatus = kycStatus;
        _kycVerified = kycVerified;
        _subscriptionStatus = subscriptionStatus;
      });
    }
  }

  @override
  void initState() {
    super.initState();
    KycStatusController.instance.addListener(_onKycStatusChanged);
    _loadSettings();
  }

  @override
  void dispose() {
    KycStatusController.instance.removeListener(_onKycStatusChanged);
    super.dispose();
  }

  Future<void> _loadSettings() async {
    _settingsStore = await SettingsStore.getInstance();

    // Show screen immediately using locally-stored values — no network needed.
    final local = await Future.wait([
      _settingsStore!.getSubscriptionStatus(),
      _settingsStore!.getKycStatus(),
      _settingsStore!.getKycVerified(),
      _settingsStore!.getWalletBalance(),
      _settingsStore!.getReferralCode(),
    ]);
    if (mounted) {
      setState(() {
        _subscriptionStatus = local[0] as String;
        _kycStatus          = local[1] as String;
        _kycVerified        = local[2] as bool;
        _walletBalance      = local[3] as double;
        _referralCode       = local[4] as String;
        _isLoading = false;
      });
    }

    // Refresh from network in background — updates UI when done.
    _refreshSettingsFromNetwork();
  }

  Future<void> _refreshSettingsFromNetwork() async {
    try {
      await Future.wait([
        KycStatusController.instance.init(refresh: true),
        ProfileService().getMyProfile(forceRefresh: true),
      ]);
    } catch (_) {}
    if (_settingsStore == null || !mounted) return;

    // Fetch live wallet balance from the API and persist it so every screen
    // that reads from SettingsStore sees the latest value without having to
    // open the wallet page first.
    try {
      final walletInfo = await ApiService().getWalletBalanceRemote();
      final liveBalance = walletInfo.coins.toDouble();
      await _settingsStore!.setWalletBalance(liveBalance);
      if (mounted) setState(() => _walletBalance = liveBalance);
    } catch (_) {}

    try {
      final fresh = await Future.wait([
        _settingsStore!.getSubscriptionStatus(),
        _settingsStore!.getKycStatus(),
        _settingsStore!.getKycVerified(),
        _settingsStore!.getReferralCode(),
      ]);
      if (mounted) {
        setState(() {
          _subscriptionStatus = fresh[0] as String;
          _kycStatus          = fresh[1] as String;
          _kycVerified        = fresh[2] as bool;
          _referralCode       = fresh[3] as String;
        });
      }
    } catch (_) {}
  }

  void _showComingSoon(String feature) {
    NeonToast.info(context, '$feature coming soon!');
  }

  void _hapticFeedback() {
    HapticFeedback.mediumImpact();
  }

  void _showStatusInactiveDialog(String feature) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFFFF0055), width: 1.2),
        ),
        title: const Text(
          'Monetization Locked',
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          _subscriptionStatus == 'disabled'
              ? 'Your monetization features have been disabled by admin.'
              : 'Your subscription status is inactive. Please contact admin to activate monetization.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK', style: TextStyle(color: Color(0xFFFF0055))),
          ),
        ],
      ),
    );
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
              child: CustomScrollView(
                physics: const BouncingScrollPhysics(),
                slivers: [
                  // â”€â”€ Header â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
                  SliverToBoxAdapter(child: _buildHeader()),

                  // â”€â”€ Account Section â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
                  SliverToBoxAdapter(
                    child: _buildSection(
                      title: 'Account',
                      icon: Icons.person_outline,
                      children: [
                        _buildNavigationTile(
                          icon: Icons.person,
                          label: 'Profile Settings',
                          subtitle: 'Edit your profile information',
                          color: const Color(0xFFD946EF),
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const ProfileScreen(),
                            ),
                          ),
                        ),
                        _buildNavigationTile(
                          icon: Icons.alternate_email,
                          label: 'Username',
                          subtitle: 'Set your unique @username',
                          color: const Color(0xFFD946EF),
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const UsernameScreen(),
                            ),
                          ),
                        ),
                        _buildNavigationTile(
                          icon: Icons.security,
                          label: 'Account Security',
                          subtitle: 'Change email, password & sessions',
                          color: const Color(0xFF06B6D4),
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const AccountSecurityScreen(),
                            ),
                          ),
                        ),
                        _buildNavigationTile(
                          icon: Icons.lock_outline,
                          label: 'Privacy Controls',
                          subtitle: 'Manage your privacy settings',
                          color: const Color(0xFFF97316),
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const PrivacyControlsScreen(),
                            ),
                          ),
                        ),
                        _buildNavigationTile(
                          icon: Icons.block,
                          label: 'Blocked Users',
                          subtitle: 'Manage blocked accounts',
                          color: const Color(0xFFEF4444),
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const BlockedUsersScreen(),
                            ),
                          ),
                        ),
                        _buildNavigationTile(
                          icon: Icons.location_off_rounded,
                          label: 'Blocked Nearby Users',
                          subtitle: 'Manage nearby alert blocks',
                          color: const Color(0xFFFF6B35),
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const NearbyBlockedScreen(),
                            ),
                          ),
                        ),
                        _buildNavigationTile(
                          icon: Icons.delete_forever,
                          label: 'Delete Account',
                          subtitle: 'Permanently delete your account',
                          color: const Color(0xFFFF0055),
                          isDestructive: true,
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const DeleteAccountScreen(),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // â”€â”€ Subscription & Monetization Section â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
                  SliverToBoxAdapter(
                    child: _buildSection(
                      title: 'Subscription & Monetization',
                      icon: Icons.diamond_outlined,
                      children: [
                        // Subscription status card
                        _buildStatusCard(
                          title: 'Subscription Status',
                          status: _subscriptionStatus == 'active' && !_kycVerified
                              ? 'KYC Required'
                              : _subscriptionStatus == 'active'
                                  ? 'Active'
                                  : _subscriptionStatus == 'disabled'
                                      ? 'Disabled'
                                      : 'Inactive',
                          isActive: _subscriptionStatus == 'active' && _kycVerified,
                          isWarning: _subscriptionStatus == 'active' && !_kycVerified,
                          icon: Icons.workspace_premium,
                        ),
                        _buildNavigationTile(
                          icon: Icons.manage_accounts,
                          label: 'Manage Subscription Plans',
                          subtitle: _kycVerified
                              ? 'Create plans for subscriber-only content'
                              : 'KYC verification required',
                          color: const Color(0xFFD946EF),
                          isLocked:
                              !_kycVerified || _subscriptionStatus != 'active',
                          onTap: () {
                            if (!_kycVerified) {
                              _showKycRequiredDialog();
                            } else if (_subscriptionStatus != 'active') {
                              _showStatusInactiveDialog('Subscription Plans');
                            } else {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const ManagePlansScreen(),
                                ),
                              );
                            }
                          },
                        ),
                        _buildNavigationTile(
                          icon: Icons.star,
                          label: 'Active Subscriber',
                          subtitle: _kycVerified
                              ? 'View your current subscribers'
                              : 'KYC verification required',
                          color: const Color(0xFFFFD700),
                          isLocked:
                              !_kycVerified || _subscriptionStatus != 'active',
                          onTap: () {
                            if (!_kycVerified) {
                              _showKycRequiredDialog();
                            } else if (_subscriptionStatus != 'active') {
                              _showStatusInactiveDialog('Active Subscriber');
                            } else {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) =>
                                      const ActiveSubscribersScreen(),
                                ),
                              );
                            }
                          },
                        ),
                        _buildNavigationTile(
                          icon:
                              null, // Signals _buildNavigationTile to use CoinIcon or similar
                          label: 'Pay-per-minute Chat',
                          subtitle: _kycVerified
                              ? 'Set your chat rate'
                              : 'KYC verification required',
                          color: const Color(0xFF22C55E),
                          isLocked:
                              !_kycVerified || _subscriptionStatus != 'active',
                          onTap: () async {
                            if (!_kycVerified) {
                              _showKycRequiredDialog();
                            } else if (_subscriptionStatus != 'active') {
                              _showStatusInactiveDialog('Pay-per-minute Chat');
                            } else {
                              await Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const PayPerMinuteScreen(),
                                ),
                              );
                              _loadSettings();
                            }
                          },
                        ),
                      ],
                    ),
                  ),

                  // â”€â”€ KYC Verification Section â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
                  SliverToBoxAdapter(
                    child: _buildSection(
                      title: 'KYC Verification',
                      icon: Icons.verified_user_outlined,
                      children: [
                        _buildKycStatusCard(),
                        _buildNavigationTile(
                          icon: Icons.upload_file,
                          label: 'Complete KYC',
                          subtitle: _getKycSubtitle(),
                          color: _getKycColor(),
                          onTap: () async {
                            await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const KycScreen(),
                              ),
                            );
                            _loadSettings();
                          },
                        ),
                      ],
                    ),
                  ),

                  // â”€â”€ Wallet Section â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
                  SliverToBoxAdapter(
                    child: _buildSection(
                      title: 'Wallet',
                      icon: Icons.account_balance_wallet_outlined,
                      children: [
                        _buildWalletBalanceCard(),
                        _buildNavigationTile(
                          icon: Icons.account_balance_wallet,
                          label: 'Wallet',
                          subtitle: 'Manage your funds',
                          color: const Color(0xFF22C55E),
                          onTap: () async {
                            await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const WalletScreen(),
                              ),
                            );
                            _loadSettings();
                          },
                        ),
                      ],
                    ),
                  ),

                  // â”€â”€ App Section â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
                  SliverToBoxAdapter(
                    child: _buildSection(
                      title: 'App',
                      icon: Icons.settings_outlined,
                      children: [
                        _buildNavigationTile(
                          icon: Icons.info_outline,
                          label: 'About',
                          subtitle: 'App version and info',
                          color: const Color(0xFF06B6D4),
                          onTap: () => _showAboutDialog(),
                        ),
                        _buildNavigationTile(
                          icon: Icons.description_outlined,
                          label: 'Terms of Service',
                          subtitle: 'Read our terms',
                          color: const Color(0xFFF97316),
                          onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) =>
                                      const LegalScreen(type: 'terms'))),
                        ),
                        _buildNavigationTile(
                          icon: Icons.privacy_tip_outlined,
                          label: 'Privacy Policy',
                          subtitle: 'Read our privacy policy',
                          color: const Color(0xFF22C55E),
                          onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) =>
                                      const LegalScreen(type: 'privacy'))),
                        ),
                        _buildNavigationTile(
                          icon: Icons.flag_outlined,
                          label: 'Report a Problem',
                          subtitle: 'Report bugs, abuse or concerns',
                          color: const Color(0xFFFF007F),
                          onTap: () => _showSystemReportSheet(),
                        ),
                      ],
                    ),
                  ),

                  // Bottom padding
                  const SliverToBoxAdapter(child: SizedBox(height: 40)),
                ],
              ),
            ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A1A),
                shape: BoxShape.circle,
                border: Border.all(
                  color: GalacticTheme.laserPink.withValues(alpha: 0.5),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: GalacticTheme.laserPink.withValues(alpha: 0.2),
                    blurRadius: 8,
                  ),
                ],
              ),
              child: const Icon(
                Icons.arrow_back,
                color: Colors.white,
                size: 22,
              ),
            ),
          ),
          const SizedBox(width: 16),
          const Text(
            'Settings',
            style: TextStyle(
              color: Colors.white,
              fontSize: 26,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSection({
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      decoration: BoxDecoration(
        color: const Color(0xFF121212),
        borderRadius: BorderRadius.circular(20),
        border: const GradientBoxBorder(
          gradient: LinearGradient(
            colors: [Color(0xFFD946EF), Color(0xFF06B6D4)],
          ),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFD946EF).withValues(alpha: 0.1),
            blurRadius: 20,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section Header
          Container(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: GalacticTheme.laserPink.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: GalacticTheme.laserPink.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Icon(icon, color: GalacticTheme.laserPink, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          // Divider
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 20),
            height: 1,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.transparent,
                  Color(0xFFD946EF),
                  Colors.transparent,
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          // Children
          ...children,
        ],
      ),
    );
  }

  Widget _buildNavigationTile({
    required IconData? icon,
    required String label,
    required String subtitle,
    required Color color,
    bool isDestructive = false,
    bool isLocked = false,
    required VoidCallback onTap,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: isLocked
            ? Colors.grey.withValues(alpha: 0.05)
            : (isDestructive
                ? Colors.red.withValues(alpha: 0.05)
                : color.withValues(alpha: 0.05)),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isLocked
              ? Colors.white10
              : (isDestructive
                  ? Colors.red.withValues(alpha: 0.3)
                  : color.withValues(alpha: 0.15)),
        ),
      ),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: isLocked
                ? Colors.grey.withValues(alpha: 0.1)
                : (isDestructive
                    ? Colors.red.withValues(alpha: 0.15)
                    : color.withValues(alpha: 0.15)),
            shape: BoxShape.circle,
            border: Border.all(
              color: isLocked
                  ? Colors.white12
                  : (isDestructive
                      ? Colors.red.withValues(alpha: 0.3)
                      : color.withValues(alpha: 0.3)),
            ),
          ),
          child: isLocked
              ? const Icon(Icons.lock, color: Colors.grey, size: 20)
              : (icon == null
                  ? CoinIcon(
                      size: 20, color: isDestructive ? Colors.red : color)
                  : Icon(icon,
                      color: isDestructive ? Colors.red : color, size: 20)),
        ),
        title: Text(
          label,
          style: TextStyle(
            color: isLocked
                ? Colors.grey
                : (isDestructive ? Colors.red : Colors.white),
            fontWeight: FontWeight.w500,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          isLocked ? 'KYC required' : subtitle,
          style: TextStyle(
            color:
                isLocked ? Colors.grey.withValues(alpha: 0.5) : Colors.white54,
            fontSize: 12,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Icon(
          Icons.chevron_right,
          color: isLocked ? Colors.grey.withValues(alpha: 0.3) : Colors.white30,
          size: 20,
        ),
        onTap: () {
          _hapticFeedback();
          onTap();
        },
      ),
    );
  }

  Widget _buildStatusCard({
    required String title,
    required String status,
    required bool isActive,
    required IconData icon,
    bool isWarning = false,
  }) {
    final color = isActive
        ? const Color(0xFF22C55E)
        : isWarning
            ? const Color(0xFFF59E0B)
            : const Color(0xFFFF007F);
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.22), width: 1),
      ),
      child: Row(
        children: [
          Icon(icon, color: color.withValues(alpha: 0.8), size: 16),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(color: Colors.white60, fontSize: 13),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: color.withValues(alpha: 0.35)),
            ),
            child: Text(
              status,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildKycStatusCard() {
    String statusText;
    Color statusColor;
    IconData statusIcon;

    switch (_kycStatus) {
      case 'verified':
      case 'approved':
        statusText = 'Verified';
        statusColor = const Color(0xFF22C55E);
        statusIcon = Icons.verified;
        break;
      case 'pending':
        statusText = 'Pending Review';
        statusColor = const Color(0xFFF97316);
        statusIcon = Icons.hourglass_top;
        break;
      case 'rejected':
        statusText = 'Rejected';
        statusColor = const Color(0xFFEF4444);
        statusIcon = Icons.cancel_outlined;
        break;
      default:
        statusText = 'Not Submitted';
        statusColor = const Color(0xFFFF007F);
        statusIcon = Icons.error_outline;
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            statusColor.withValues(alpha: 0.15),
            statusColor.withValues(alpha: 0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: statusColor.withValues(alpha: 0.3)),
        boxShadow: [
          BoxShadow(color: statusColor.withValues(alpha: 0.1), blurRadius: 12),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.2),
              shape: BoxShape.circle,
              border: Border.all(color: statusColor.withValues(alpha: 0.5)),
            ),
            child: Icon(statusIcon, color: statusColor, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'KYC Status',
                  style: TextStyle(color: Colors.white70, fontSize: 13),
                ),
                const SizedBox(height: 4),
                Text(
                  statusText,
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWalletBalanceCard() {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF22C55E), Color(0xFF06B6D4)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF22C55E).withValues(alpha: 0.3),
            blurRadius: 12,
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.account_balance_wallet,
              color: Colors.white,
              size: 24,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Wallet Balance',
                  style: TextStyle(color: Colors.white70, fontSize: 13),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const CoinIcon(
                      color: Colors.amber,
                      size: 26,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _walletBalance.toStringAsFixed(2),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right, color: Colors.white54),
        ],
      ),
    );
  }

  String _getKycSubtitle() {
    switch (_kycStatus) {
      case 'verified':
        return 'Your identity is verified';
      case 'pending':
        return 'Under review...';
      case 'rejected':
        return 'Rejected. Please try again.';
      default:
        return 'Required for subscription';
    }
  }

  Color _getKycColor() {
    switch (_kycStatus) {
      case 'verified':
        return const Color(0xFF22C55E);
      case 'pending':
        return const Color(0xFFF97316);
      case 'rejected':
        return const Color(0xFFEF4444);
      default:
        return const Color(0xFFFF007F);
    }
  }

  void _showKycRequiredDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: Color(0xFFFFD700), width: 1.5),
        ),
        title: const Row(
          children: [
            Icon(Icons.warning_amber, color: Color(0xFFFFD700)),
            SizedBox(width: 8),
            Text('KYC Required', style: TextStyle(color: Colors.white)),
          ],
        ),
        content: const Text(
          'You need to complete KYC verification before subscribing.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Colors.white54),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const KycScreen()),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFFD700),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text(
              'Verify Now',
              style: TextStyle(color: Colors.black),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showSystemReportSheet() async {
    final reasonCtrl = TextEditingController();
    final detailsCtrl = TextEditingController();
    String selectedReason = 'Bug / App crash';
    File? attachedImage;
    bool submitting = false;
    bool submitted = false;

    final reasons = [
      'Bug / App crash',
      'Inappropriate content',
      'Spam or scam',
      'Harassment or bullying',
      'Other',
    ];

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) {
          final kb = MediaQuery.of(ctx).viewInsets.bottom;
          final nb = MediaQuery.of(ctx).padding.bottom;
          return Container(
            padding: EdgeInsets.fromLTRB(20, 24, 20, kb + nb + 24),
            decoration: const BoxDecoration(
              color: Color(0xFF111118),
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: submitted
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Icon(Icons.check_circle_rounded, color: Color(0xFF34D399), size: 56),
                      SizedBox(height: 14),
                      Text('Report submitted', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                      SizedBox(height: 8),
                      Text('Our team will review it shortly. Thank you!', style: TextStyle(color: Colors.white54, fontSize: 13), textAlign: TextAlign.center),
                      SizedBox(height: 24),
                    ],
                  )
                : SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(children: [
                          const Icon(Icons.flag_rounded, color: Color(0xFFFF007F), size: 22),
                          const SizedBox(width: 10),
                          const Text('Report a Problem', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
                          const Spacer(),
                          GestureDetector(onTap: () => Navigator.pop(ctx), child: const Icon(Icons.close, color: Colors.white54)),
                        ]),
                        const SizedBox(height: 18),
                        // Reason chips
                        Wrap(spacing: 8, runSpacing: 8, children: reasons.map((r) {
                          final sel = r == selectedReason;
                          return GestureDetector(
                            onTap: () => setState(() => selectedReason = r),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                              decoration: BoxDecoration(
                                color: sel ? const Color(0xFFFF007F).withValues(alpha: 0.2) : Colors.white.withValues(alpha: 0.06),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: sel ? const Color(0xFFFF007F) : Colors.white24),
                              ),
                              child: Text(r, style: TextStyle(color: sel ? const Color(0xFFFF007F) : Colors.white70, fontSize: 13, fontWeight: sel ? FontWeight.w600 : FontWeight.normal)),
                            ),
                          );
                        }).toList()),
                        const SizedBox(height: 16),
                        // Details field
                        TextField(
                          controller: detailsCtrl,
                          maxLines: 4,
                          maxLength: 500,
                          style: const TextStyle(color: Colors.white, fontSize: 14),
                          decoration: InputDecoration(
                            hintText: 'Describe the problem in detail...',
                            hintStyle: const TextStyle(color: Colors.white38),
                            filled: true,
                            fillColor: Colors.white.withValues(alpha: 0.05),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                            counterStyle: const TextStyle(color: Colors.white38, fontSize: 11),
                            contentPadding: const EdgeInsets.all(14),
                          ),
                        ),
                        const SizedBox(height: 8),
                        // Attach screenshot
                        GestureDetector(
                          onTap: () async {
                            final picker = ImagePicker();
                            final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 70);
                            if (picked != null) setState(() => attachedImage = File(picked.path));
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.05),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: attachedImage != null ? const Color(0xFFFF007F) : Colors.white24),
                            ),
                            child: Row(children: [
                              Icon(attachedImage != null ? Icons.image_rounded : Icons.attach_file_rounded,
                                  color: attachedImage != null ? const Color(0xFFFF007F) : Colors.white54, size: 18),
                              const SizedBox(width: 10),
                              Expanded(child: Text(
                                attachedImage != null ? attachedImage!.path.split('/').last : 'Attach screenshot (optional)',
                                style: TextStyle(color: attachedImage != null ? const Color(0xFFFF007F) : Colors.white54, fontSize: 13),
                                overflow: TextOverflow.ellipsis,
                              )),
                              if (attachedImage != null)
                                GestureDetector(onTap: () => setState(() => attachedImage = null), child: const Icon(Icons.close, color: Colors.white38, size: 16)),
                            ]),
                          ),
                        ),
                        const SizedBox(height: 20),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFFF007F),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 15),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            ),
                            onPressed: submitting ? null : () async {
                              if (detailsCtrl.text.trim().isEmpty) {
                                if (ctx.mounted) ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Please describe the problem')));
                                return;
                              }
                              setState(() => submitting = true);
                              try {
                                await ApiService().reportSystem(
                                  reason: selectedReason,
                                  details: detailsCtrl.text.trim(),
                                  imagePath: attachedImage?.path,
                                );
                                if (!ctx.mounted) return;
                                setState(() { submitted = true; submitting = false; });
                                await Future.delayed(const Duration(seconds: 2));
                                if (ctx.mounted) Navigator.pop(ctx);
                              } catch (e) {
                                if (!ctx.mounted) return;
                                setState(() => submitting = false);
                                ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('Failed: $e')));
                              }
                            },
                            child: submitting
                                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                : const Text('Submit Report', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                          ),
                        ),
                      ],
                    ),
                  ),
          );
        },
      ),
    );

    reasonCtrl.dispose();
    detailsCtrl.dispose();
  }

  void _showAboutDialog() {
    showAboutDialog(
      context: context,
      applicationName: 'Goreto',
      applicationVersion: '1.0.0',
      applicationIcon: Container(
        width: 60,
        height: 60,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFFD946EF), Color(0xFF06B6D4)],
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Icon(Icons.favorite, color: Colors.white, size: 32),
      ),
      children: [
        const Text(
          'A social media app for connecting people.',
          style: TextStyle(color: Colors.white70),
        ),
      ],
    );
  }

  String _getLanguageName(String code) {
    switch (code) {
      case 'en':
        return 'English';
      case 'es':
        return 'EspaÃ±ol';
      case 'fr':
        return 'FranÃ§ais';
      case 'de':
        return 'Deutsch';
      case 'zh':
        return 'ä¸­æ–‡';
      case 'ja':
        return 'æ—¥æœ¬èªž';
      default:
        return 'English';
    }
  }
}
