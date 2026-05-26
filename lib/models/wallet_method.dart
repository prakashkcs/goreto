class WalletMethod {
  final int id;
  final String name;
  final String? accountName;
  final String? accountNumber;
  final String? qrImage;

  const WalletMethod({
    required this.id,
    required this.name,
    this.accountName,
    this.accountNumber,
    this.qrImage,
  });

  factory WalletMethod.fromJson(Map<String, dynamic> json) {
    String? cleanNullable(dynamic value) {
      if (value == null) return null;
      final text = value.toString().trim();
      if (text.isEmpty || text.toLowerCase() == 'null') return null;
      return text;
    }

    return WalletMethod(
      id: int.tryParse((json['id'] ?? 0).toString()) ?? 0,
      name: (json['name'] ?? '').toString(),
      accountName: cleanNullable(json['account_name']),
      accountNumber: cleanNullable(json['account_number']),
      qrImage: cleanNullable(json['qr_image']),
    );
  }
}
