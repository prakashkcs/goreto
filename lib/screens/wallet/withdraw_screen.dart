import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:love_vibe_pro/core/theme.dart';
import 'package:love_vibe_pro/services/api_service.dart';
import 'package:love_vibe_pro/widgets/neon_toast.dart';
import 'package:love_vibe_pro/widgets/coin_icon.dart';

class WithdrawScreen extends StatefulWidget {
  final int maxCoins;
  const WithdrawScreen({super.key, required this.maxCoins});

  @override
  State<WithdrawScreen> createState() => _WithdrawScreenState();
}

class _WithdrawScreenState extends State<WithdrawScreen> {
  final _amountController = TextEditingController();
  final _detailsController = TextEditingController();
  final ApiService _api = ApiService();

  // Dynamically loaded from admin
  List<Map<String, dynamic>> _methods = [];
  Map<String, dynamic>? _selectedMethod;
  bool _isLoadingMethods = true;
  bool _withdrawalEnabled = true;
  int _minCoins = 100;

  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _loadMethods();
  }

  @override
  void dispose() {
    _amountController.dispose();
    _detailsController.dispose();
    super.dispose();
  }

  Future<void> _loadMethods() async {
    try {
      final data = await _api.fetchWithdrawMethods();
      final rawMethods =
          (data['methods'] as List?)
              ?.whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList() ??
          [];
      final settingsMap = data['settings'] as Map? ?? {};

      setState(() {
        _methods = rawMethods.isNotEmpty
            ? rawMethods
            : [
                {
                  'name': 'PayPal',
                  'account_hint': 'Enter your PayPal email address',
                },
                {
                  'name': 'Bank Transfer',
                  'account_hint': 'Enter bank IBAN / account number',
                },
                {
                  'name': 'Crypto Wallet',
                  'account_hint': 'Enter your crypto wallet address',
                },
              ];
        _selectedMethod = _methods.isNotEmpty ? _methods.first : null;
        _withdrawalEnabled = settingsMap['withdrawal_enabled'] != false;
        _minCoins =
            int.tryParse(settingsMap['min_coins']?.toString() ?? '100') ?? 100;
        _isLoadingMethods = false;
      });
    } catch (_) {
      setState(() {
        _methods = [
          {'name': 'PayPal', 'account_hint': 'Enter your PayPal email address'},
          {
            'name': 'Bank Transfer',
            'account_hint': 'Enter bank IBAN / account details',
          },
          {
            'name': 'Crypto Wallet',
            'account_hint': 'Enter crypto wallet address',
          },
        ];
        _selectedMethod = _methods.first;
        _isLoadingMethods = false;
      });
    }
  }

  String get _currentHint =>
      _selectedMethod?['account_hint']?.toString() ??
      'Enter your payment account details';

  String get _currentMethodName =>
      _selectedMethod?['name']?.toString() ?? 'Unknown';

  void _submitWithdrawal() async {
    if (!_withdrawalEnabled) {
      NeonToast.error(context, 'Withdrawals are temporarily disabled');
      return;
    }

    final amountText = _amountController.text.trim();
    final details = _detailsController.text.trim();

    if (amountText.isEmpty) {
      NeonToast.error(context, 'Enter an amount to withdraw');
      return;
    }

    final coins = int.tryParse(amountText) ?? 0;
    if (coins < _minCoins) {
      NeonToast.error(context, 'Minimum withdrawal is $_minCoins coins');
      return;
    }
    if (coins > widget.maxCoins) {
      NeonToast.error(context, 'Insufficient coin balance');
      return;
    }
    if (details.isEmpty) {
      NeonToast.error(context, 'Enter your payment details');
      return;
    }

    setState(() => _isSubmitting = true);

    final res = await _api.requestWithdrawal(
      coins: coins,
      paymentMethod: _currentMethodName,
      paymentDetails: details,
    );

    setState(() => _isSubmitting = false);

    if (res['status'] == true) {
      NeonToast.success(context, 'Withdrawal request submitted!');
      if (mounted) Navigator.pop(context, true);
    } else {
      NeonToast.error(context, res['message'] ?? 'Failed to submit request');
    }
  }

  void _setMax() {
    setState(() => _amountController.text = widget.maxCoins.toString());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Withdraw',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
            SizedBox(width: 8),
            CoinIcon(size: 20, color: Colors.white),
          ],
        ),
      ),
      body: _isLoadingMethods
          ? const Center(
              child: CircularProgressIndicator(color: GalacticTheme.laserPink),
            )
          : !_withdrawalEnabled
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'Withdrawals are temporarily disabled by the admin.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70, fontSize: 16),
                ),
              ),
            )
          : SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Balance Info
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: GalacticTheme.laserPink.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: GalacticTheme.laserPink.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Available Balance',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 16,
                            ),
                          ),
                          Row(
                            children: [
                              Text(
                                '${widget.maxCoins}',
                                style: const TextStyle(
                                  color: GalacticTheme.laserPink,
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(width: 6),
                              const CoinIcon(size: 18, color: GalacticTheme.laserPink),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 32),

                    // Amount Input
                    const Text(
                      'Withdrawal Amount',
                      style: TextStyle(color: Colors.white, fontSize: 16),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF141414),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _amountController,
                              keyboardType: TextInputType.number,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 24,
                              ),
                              decoration: const InputDecoration(
                                hintText: '0',
                                hintStyle: TextStyle(color: Colors.white24),
                                border: InputBorder.none,
                                contentPadding: EdgeInsets.symmetric(
                                  horizontal: 20,
                                ),
                              ),
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                              ],
                            ),
                          ),
                          TextButton(
                            onPressed: _setMax,
                            child: const Text(
                              'MAX',
                              style: TextStyle(
                                color: Color(0xFF06B6D4),
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 8, left: 4),
                      child: Row(
                        children: [
                          Text(
                            'Minimum $_minCoins',
                            style: const TextStyle(
                              color: Colors.white38,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(width: 4),
                          const CoinIcon(size: 12, color: Colors.white38),
                        ],
                      ),
                    ),
                    const SizedBox(height: 32),

                    // Payment Method â€” dynamically from admin
                    const Text(
                      'Payment Method',
                      style: TextStyle(color: Colors.white, fontSize: 16),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        color: const Color(0xFF141414),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<Map<String, dynamic>>(
                          value: _selectedMethod,
                          isExpanded: true,
                          dropdownColor: const Color(0xFF141414),
                          icon: const Icon(
                            Icons.keyboard_arrow_down,
                            color: Colors.white54,
                          ),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                          ),
                          items: _methods.map((method) {
                            return DropdownMenuItem<Map<String, dynamic>>(
                              value: method,
                              child: Text(
                                method['name']?.toString() ?? 'Unknown',
                              ),
                            );
                          }).toList(),
                          onChanged: (val) {
                            if (val != null) {
                              setState(() {
                                _selectedMethod = val;
                                _detailsController.clear();
                              });
                            }
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 32),

                    // Payment Details
                    Text(
                      '$_currentMethodName Details',
                      style: const TextStyle(color: Colors.white, fontSize: 16),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF141414),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: TextField(
                        controller: _detailsController,
                        maxLines: 3,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          hintText: _currentHint,
                          hintStyle: const TextStyle(
                            color: Colors.white24,
                            fontSize: 14,
                          ),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.all(16),
                        ),
                      ),
                    ),
                    const SizedBox(height: 48),

                    // Submit Button
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton(
                        onPressed: _isSubmitting ? null : _submitWithdrawal,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: GalacticTheme.laserPink,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(28),
                          ),
                          elevation: 5,
                          shadowColor: GalacticTheme.laserPink,
                        ),
                        child: _isSubmitting
                            ? const SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 3,
                                ),
                              )
                            : const Text(
                                'Submit Request',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1.2,
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
