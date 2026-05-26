class WalletGiftItem {
  final String giftId;
  final String name;
  final String emoji;
  final String senderName;
  final int qty;
  final int coinPrice;
  final int sellPrice;
  final int totalValue;
  final String thumbImage;
  final String gifUrl;
  final String glbUrl;
  final String updatedAt;

  WalletGiftItem({
    required this.giftId,
    required this.name,
    this.emoji = '🎁',
    this.senderName = '',
    required this.qty,
    required this.coinPrice,
    required this.sellPrice,
    required this.totalValue,
    required this.thumbImage,
    required this.gifUrl,
    required this.glbUrl,
    required this.updatedAt,
  });

  factory WalletGiftItem.fromJson(Map<String, dynamic> json) {
    int parseInt(dynamic value, {int fallback = 0}) {
      if (value == null) return fallback;
      if (value is int) return value;
      if (value is double) return value.toInt();
      return int.tryParse(value.toString()) ?? fallback;
    }

    String parseString(dynamic value) {
      if (value == null) return '';
      return value.toString().trim();
    }

    return WalletGiftItem(
      giftId: parseString(json['gift_id']),
      name: parseString(json['name']),
      emoji: parseString(json['emoji']).isNotEmpty ? parseString(json['emoji']) : '🎁',
      senderName: parseString(
        json['sender_name'] ?? json['sent_by'] ?? json['sender'] ?? '',
      ),
      qty: parseInt(json['qty']),
      coinPrice: parseInt(json['coin_price']),
      sellPrice: parseInt(json['sell_price']),
      totalValue: parseInt(json['total_value']),
      thumbImage: parseString(json['thumb_image']),
      gifUrl: parseString(json['gif_url']),
      glbUrl: parseString(json['glb_url']),
      updatedAt: parseString(json['updated_at']),
    );
  }
}
