import 'dart:async';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:love_vibe_pro/models/wallet_method.dart';
import 'package:love_vibe_pro/services/wallet_service.dart';
import 'package:love_vibe_pro/widgets/neon_toast.dart';
import 'package:love_vibe_pro/widgets/coin_icon.dart';

class DepositQrScreen extends StatefulWidget {
  final WalletMethod method;
  final int depositId;
  final String qrImage;
  final int coins;
  final double amount;
  final String currencyCode;

  const DepositQrScreen({
    super.key,
    required this.method,
    required this.depositId,
    required this.qrImage,
    required this.coins,
    required this.amount,
    this.currencyCode = 'NPR',
  });

  @override
  State<DepositQrScreen> createState() => _DepositQrScreenState();
}

class _DepositQrScreenState extends State<DepositQrScreen> {
  final WalletService _walletService = WalletService();

  bool _isChecking = false;
  bool _inCooldown = false;
  bool _isReviewing = false;
  int _cooldownLeft = 0;
  Timer? _cooldownTimer;

  String _statusText = 'Tap "Check Payment" after sending payment.';

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    super.dispose();
  }

  Future<void> _checkPayment() async {
    if (_isChecking || _inCooldown) return;

    setState(() => _isChecking = true);

    try {
      final result = await _walletService.checkPayment(
        depositId: widget.depositId,
      );
      final status = result.status.toLowerCase();
      final message = result.message.toLowerCase();

      if (status == 'error' && message.contains('payment not received')) {
        if (!mounted) return;
        setState(() {
          _statusText = 'Payment not received. Try again.';
          _isReviewing = false;
        });
        NeonToast.error(context, 'Payment not received. Try again.');
      } else if (status == 'reviewing') {
        if (!mounted) return;
        await _walletService.addLocalPendingDeposit(
          depositId: widget.depositId,
          coins: widget.coins,
          amount: widget.amount,
          currencyCode: widget.currencyCode,
          methodName: widget.method.name,
        );

        setState(() {
          _statusText = 'Payment under review. Wait some time.';
          _isReviewing = true;
        });
        NeonToast.info(context, 'Payment under review. Wait some time.');
        _startCooldown();
      } else {
        if (!mounted) return;
        setState(() {
          _statusText = result.message.isNotEmpty
              ? result.message
              : 'Payment status: ${result.status}';
          _isReviewing = false;
        });
        NeonToast.info(
          context,
          result.message.isNotEmpty ? result.message : 'Payment status updated',
        );
      }
    } catch (_) {
      if (!mounted) return;
      NeonToast.error(context, 'Wallet API error');
    } finally {
      if (mounted) setState(() => _isChecking = false);
    }
  }

  Future<void> _uploadScreenshot() async {
    if (_isChecking || _inCooldown) return;

    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery);

    if (image == null) return;

    setState(() => _isChecking = true);

    try {
      final result = await _walletService.uploadDepositProof(
        depositId: widget.depositId,
        imagePath: image.path,
      );

      final status = result.status.toLowerCase();

      if (status == 'reviewing' || status == 'success') {
        if (!mounted) return;
        await _walletService.addLocalPendingDeposit(
          depositId: widget.depositId,
          coins: widget.coins,
          amount: widget.amount,
          currencyCode: widget.currencyCode,
          methodName: widget.method.name,
        );

        setState(() {
          _statusText =
              'Screenshot uploaded successfully. Payment under review.';
          _isReviewing = true;
        });
        NeonToast.info(context, 'Payment under review. Wait some time.');
      } else {
        if (!mounted) return;
        NeonToast.error(
          context,
          result.message.isNotEmpty ? result.message : 'Upload failed',
        );
      }
    } catch (_) {
      if (!mounted) return;
      NeonToast.error(context, 'Upload failed');
    } finally {
      if (mounted) setState(() => _isChecking = false);
    }
  }

  void _startCooldown() {
    _cooldownTimer?.cancel();
    setState(() {
      _inCooldown = true;
      _cooldownLeft = 10;
    });

    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      if (_cooldownLeft <= 1) {
        timer.cancel();
        setState(() {
          _cooldownLeft = 0;
          _inCooldown = false;
        });
      } else {
        setState(() => _cooldownLeft -= 1);
      }
    });
  }

  void _backToWallet() {
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final qr = widget.qrImage.trim();

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        title: const Text('Deposit QR'),
        backgroundColor: const Color(0xFF0A0A0A),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _info('Method', widget.method.name),
              _info('Coins', widget.coins.toString(), showIcon: true),
              _info(
                'Amount',
                '${widget.currencyCode} ${widget.amount.toStringAsFixed(2)}',
              ),
              _info('Deposit ID', widget.depositId.toString()),
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF151515),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white12),
                ),
                child: qr.isEmpty
                    ? const Column(
                        children: [
                          Icon(Icons.qr_code_2,
                              size: 110, color: Colors.white38),
                          SizedBox(height: 8),
                          Text(
                            'QR image not available',
                            style: TextStyle(color: Colors.white70),
                          ),
                        ],
                      )
                    : Image.network(
                        qr,
                        height: 240,
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => const Column(
                          children: [
                            Icon(
                              Icons.broken_image,
                              size: 90,
                              color: Colors.white38,
                            ),
                            SizedBox(height: 8),
                            Text(
                              'Unable to load QR image',
                              style: TextStyle(color: Colors.white70),
                            ),
                          ],
                        ),
                      ),
              ),
              const SizedBox(height: 14),
              if (!_isReviewing) ...[
                const Text(
                  'Please make the payment using the details above, then take a screenshot of your successful transaction and upload it here.',
                  style: TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 14),
              ],
              if (_isReviewing) _reviewBanner(),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF151515),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white12),
                ),
                child: Text(
                  _statusText,
                  style: const TextStyle(color: Colors.white70),
                ),
              ),
              const SizedBox(height: 14),
              if (!_isReviewing) ...[
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed:
                        (_isChecking || _inCooldown) ? null : _uploadScreenshot,
                    icon: const Icon(Icons.upload_file),
                    label: _isChecking
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('Upload Payment Screenshot'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF06B6D4),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed:
                        (_isChecking || _inCooldown) ? null : _checkPayment,
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      side: const BorderSide(color: Color(0xFF22C55E)),
                      foregroundColor: const Color(0xFF22C55E),
                    ),
                    child: Text(
                      _inCooldown
                          ? 'Check Payment Status ($_cooldownLeft s)'
                          : 'I have already paid (Check without screenshot)',
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _reviewBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: LinearGradient(
          colors: [
            const Color(0xFF06B6D4).withValues(alpha: 0.2),
            const Color(0xFF22C55E).withValues(alpha: 0.15),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(
          color: const Color(0xFF06B6D4).withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(
                Icons.hourglass_top_rounded,
                color: Color(0xFF06B6D4),
                size: 22,
              ),
              SizedBox(width: 8),
              Text(
                'Payment Submitted',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Your payment is under review. It may take a few minutes.',
            style: TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _backToWallet,
              icon: const Icon(Icons.account_balance_wallet_outlined),
              label: const Text('Back to Wallet'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF06B6D4),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _info(String label, String value, {bool showIcon = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF151515),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white12),
        ),
        child: Row(
          children: [
            Text(
              '$label: ',
              style: const TextStyle(
                color: Colors.white70,
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
            if (showIcon) ...[
              const CoinIcon(size: 14, color: Colors.white),
              const SizedBox(width: 4),
            ],
            Text(
              value,
              style: const TextStyle(color: Colors.white, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }
}
