import 'package:flutter/material.dart';
import 'package:love_vibe_pro/models/wallet_method.dart';
import 'package:love_vibe_pro/models/wallet_models.dart';
import 'package:love_vibe_pro/screens/wallet/deposit_qr_screen.dart';
import 'package:love_vibe_pro/services/wallet_service.dart';
import 'package:love_vibe_pro/widgets/neon_toast.dart';
import 'package:love_vibe_pro/widgets/coin_icon.dart';

class DepositFlowScreen extends StatefulWidget {
  const DepositFlowScreen({super.key});

  @override
  State<DepositFlowScreen> createState() => _DepositFlowScreenState();
}

class _DepositInitData {
  final List<WalletMethod> methods;
  final WalletSettingsModel settings;

  const _DepositInitData({required this.methods, required this.settings});
}

class _DepositFlowScreenState extends State<DepositFlowScreen> {
  final WalletService _walletService = WalletService();
  final TextEditingController _coinsController = TextEditingController();

  late Future<_DepositInitData> _initFuture;
  int? _selectedMethodId;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _initFuture = _loadInitData();
  }

  @override
  void dispose() {
    _coinsController.dispose();
    super.dispose();
  }

  Future<_DepositInitData> _loadInitData() async {
    final results = await Future.wait([
      _walletService.getDepositMethods(),
      _walletService.getSettings(),
    ]);
    return _DepositInitData(
      methods: results[0] as List<WalletMethod>,
      settings: results[1] as WalletSettingsModel,
    );
  }

  int get _coinsValue => int.tryParse(_coinsController.text.trim()) ?? 0;

  bool _canProceed(_DepositInitData data) {
    final coins = _coinsValue;
    final amount = coins /
        (data.settings.coinsPerCurrency > 0
            ? data.settings.coinsPerCurrency
            : 1);

    return _selectedMethodId != null &&
        coins > 0 &&
        amount > 0 &&
        coins >= data.settings.minDepositCoins &&
        !_isSubmitting;
  }

  Future<void> _handleProceed(_DepositInitData data) async {
    if (_isSubmitting) return;

    final coins = _coinsValue;
    final amount = coins /
        (data.settings.coinsPerCurrency > 0
            ? data.settings.coinsPerCurrency
            : 1);

    if (_selectedMethodId == null) {
      _showSnack('Please select a deposit method');
      return;
    }
    if (coins <= 0) {
      _showSnack('Please enter valid coins');
      return;
    }
    if (coins < data.settings.minDepositCoins) {
      _showSnack('Minimum deposit is ${data.settings.minDepositCoins} coins');
      return;
    }
    if (amount <= 0) {
      _showSnack('Please enter valid amount');
      return;
    }

    final selectedMethod = data.methods.cast<WalletMethod?>().firstWhere(
          (m) => m?.id == _selectedMethodId,
          orElse: () => null,
        );

    if (selectedMethod == null) {
      _showSnack('Wallet API error');
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      final result = await _walletService.createDeposit(
        methodId: selectedMethod.id,
        coins: coins,
        amount: amount,
      );

      if (!mounted) return;
      final backToWallet = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) => DepositQrScreen(
            method: selectedMethod,
            depositId: result.depositId,
            qrImage: result.qrImage.isNotEmpty
                ? result.qrImage
                : (selectedMethod.qrImage ?? ''),
            coins: coins,
            amount: amount,
            currencyCode: 'NPR',
          ),
        ),
      );

      if (backToWallet == true && mounted) {
        Navigator.pop(context, true);
      }
    } catch (_) {
      _showSnack('Wallet API error');
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  void _showSnack(String message) {
    if (!mounted) return;
    NeonToast.info(context, message);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Deposit'),
            SizedBox(width: 8),
            CoinIcon(size: 20, color: Colors.white),
          ],
        ),
        backgroundColor: const Color(0xFF0A0A0A),
      ),
      body: SafeArea(
        child: FutureBuilder<_DepositInitData>(
          future: _initFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            if (snapshot.hasError || !snapshot.hasData) {
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Wallet API error',
                      style: TextStyle(color: Colors.white70),
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton(
                      onPressed: () {
                        setState(() {
                          _initFuture = _loadInitData();
                        });
                      },
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              );
            }

            final data = snapshot.data!;
            final methods = data.methods;

            return SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Select Deposit Method',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (methods.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 12),
                      child: Text(
                        'No deposit methods available',
                        style: TextStyle(color: Colors.white70),
                      ),
                    ),
                  ...methods.map(
                    (method) => Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF151515),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: RadioListTile<int>(
                        value: method.id,
                        groupValue: _selectedMethodId,
                        activeColor: const Color(0xFF22C55E),
                        onChanged: (value) {
                          setState(() => _selectedMethodId = value);
                        },
                        title: Text(
                          method.name,
                          style: const TextStyle(color: Colors.white),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _coinsController,
                    keyboardType: TextInputType.number,
                    onChanged: (_) => setState(() {}),
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      label: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CoinIcon(size: 16, color: Colors.white70),
                          SizedBox(width: 4),
                          Text('Coins'),
                        ],
                      ),
                      labelStyle: const TextStyle(color: Colors.white70),
                      filled: true,
                      fillColor: const Color(0xFF151515),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 18,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF151515),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Amount (NPR)',
                          style: TextStyle(color: Colors.white70, fontSize: 16),
                        ),
                        Text(
                          'NPR ${(_coinsValue / (data.settings.coinsPerCurrency > 0 ? data.settings.coinsPerCurrency : 1)).toStringAsFixed(2)}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Exchange Rate: ${data.settings.coinsPerCurrency} = NPR 1.00',
                    style: const TextStyle(color: Colors.white60),
                  ),
                  const CoinIcon(size: 12, color: Colors.white60),
                  if (data.settings.minDepositCoins > 0) ...[
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Text(
                          'Minimum Deposit: ${data.settings.minDepositCoins}',
                          style: const TextStyle(
                            color: Colors.redAccent,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(width: 4),
                        const CoinIcon(size: 14, color: Colors.redAccent),
                      ],
                    ),
                  ],
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed:
                          _canProceed(data) ? () => _handleProceed(data) : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF22C55E),
                        disabledBackgroundColor: Colors.white24,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: _isSubmitting
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Proceed'),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
