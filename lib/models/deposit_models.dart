class CreateDepositResult {
  final int depositId;
  final String qrImage;

  const CreateDepositResult({
    required this.depositId,
    required this.qrImage,
  });

  factory CreateDepositResult.fromJson(Map<String, dynamic> json) {
    return CreateDepositResult(
      depositId: int.tryParse((json['deposit_id'] ?? 0).toString()) ?? 0,
      qrImage: (json['qr_image'] ?? '').toString(),
    );
  }
}

class CheckPaymentResult {
  final String status;
  final String message;

  const CheckPaymentResult({
    required this.status,
    required this.message,
  });

  factory CheckPaymentResult.fromJson(Map<String, dynamic> json) {
    return CheckPaymentResult(
      status: (json['status'] ?? '').toString(),
      message: (json['message'] ?? '').toString(),
    );
  }
}
