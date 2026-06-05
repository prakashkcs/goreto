class Collection {
  final String id;
  final String title;
  final int itemCount;
  final String? coverThumb;
  final DateTime createdAt;

  Collection({
    required this.id,
    required this.title,
    this.itemCount = 0,
    this.coverThumb,
    required this.createdAt,
  });

  factory Collection.fromJson(Map<String, dynamic> json) {
    final rawCount = json['item_count'] ?? json['count'] ?? 0;
    return Collection(
      id: (json['id'] ?? json['collection_id'])?.toString() ?? '',
      title: (json['title'] ?? json['name'])?.toString() ?? 'Untitled',
      itemCount: rawCount is String ? int.tryParse(rawCount) ?? 0 : (rawCount as int? ?? 0),
      coverThumb: (json['cover_thumb'] ?? json['cover_url'] ?? json['cover'])?.toString(),
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '') ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'item_count': itemCount,
      'cover_thumb': coverThumb,
      'created_at': createdAt.toIso8601String(),
    };
  }

  Collection copyWith({
    String? id,
    String? title,
    int? itemCount,
    String? coverThumb,
    DateTime? createdAt,
  }) {
    return Collection(
      id: id ?? this.id,
      title: title ?? this.title,
      itemCount: itemCount ?? this.itemCount,
      coverThumb: coverThumb ?? this.coverThumb,
      createdAt: createdAt ?? this.createdAt,
    );
  }

}