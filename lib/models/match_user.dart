class MatchUser {
  final String id;
  final String name;
  final int age;
  final double rating;
  final String city;
  final String country;
  final double lat;
  final double lng;
  final String? distanceKm;
  final String photoUrl;
  final String? coverPicUrl;
  final List<String> interests;
  final int matchPercent;
  final bool isOnline;
  final String gender; // 'male', 'female'
  final double? income;
  final String incomeStatus; // 'none', 'pending', 'approved', 'rejected'
  final List<String> lookingFor; // up to 3 qualities
  final List<String> qualities; // up to 3 qualities
  final Map<String, String> socialLinks;

  MatchUser({
    required this.id,
    required this.name,
    required this.age,
    required this.rating,
    required this.city,
    required this.country,
    required this.lat,
    required this.lng,
    this.distanceKm,
    required this.photoUrl,
    this.coverPicUrl,
    required this.interests,
    this.matchPercent = 75,
    this.isOnline = false,
    this.gender = 'female',
    this.income,
    this.incomeStatus = 'none',
    this.lookingFor = const [],
    this.qualities = const [],
    this.socialLinks = const {},
  });

  factory MatchUser.fromJson(Map<String, dynamic> json) {
    return MatchUser(
      id: (json['id'] ?? json['user_id']).toString(),
      name: json['name'] ?? json['username'] ?? 'User',
      age: int.tryParse(json['age'].toString()) ?? 18,
      rating: double.tryParse(json['rating'].toString()) ?? 0.0,
      city:
          json['city'] ??
          json['location']?.toString().split(',').first ??
          'Unknown',
      country: json['country'] ?? 'World',
      lat: double.tryParse(json['lat'].toString()) ?? 0.0,
      lng: double.tryParse(json['lng'].toString()) ?? 0.0,
      distanceKm: json['distance_km']?.toString(),
      photoUrl:
          (json['profile_pic'] != null && json['profile_pic'].toString().isNotEmpty)
              ? json['profile_pic']
              : 'https://picsum.photos/seed/${json['id'] ?? '1'}/400/600',
      coverPicUrl: json['cover_pic'],
      interests: List<String>.from(json['interests'] ?? []),
      matchPercent: int.tryParse(json['match_percent']?.toString() ?? '') ?? 75,
      isOnline: json['is_online'] == true || json['online'] == 1,
      gender: json['gender'] ?? 'female',
      income: double.tryParse(json['income']?.toString() ?? ''),
      incomeStatus: json['income_status'] ?? 'none',
      lookingFor: List<String>.from(json['looking_for'] ?? []),
      qualities: List<String>.from(json['qualities'] ?? []),
      socialLinks: _parseSocialLinks(json['social_links']),
    );
  }

  static Map<String, String> _parseSocialLinks(dynamic data) {
    if (data == null) return {};
    if (data is Map) {
      return data.map((key, value) => MapEntry(key.toString(), value.toString()));
    }
    return {};
  }

  MatchUser copyWith({
    String? id,
    String? name,
    int? age,
    double? rating,
    String? city,
    String? country,
    double? lat,
    double? lng,
    String? distanceKm,
    String? photoUrl,
    String? coverPicUrl,
    List<String>? interests,
    int? matchPercent,
    bool? isOnline,
    String? gender,
    double? income,
    String? incomeStatus,
    List<String>? lookingFor,
    List<String>? qualities,
    Map<String, String>? socialLinks,
  }) {
    return MatchUser(
      id: id ?? this.id,
      name: name ?? this.name,
      age: age ?? this.age,
      rating: rating ?? this.rating,
      city: city ?? this.city,
      country: country ?? this.country,
      lat: lat ?? this.lat,
      lng: lng ?? this.lng,
      distanceKm: distanceKm ?? this.distanceKm,
      photoUrl: photoUrl ?? this.photoUrl,
      coverPicUrl: coverPicUrl ?? this.coverPicUrl,
      interests: interests ?? this.interests,
      matchPercent: matchPercent ?? this.matchPercent,
      isOnline: isOnline ?? this.isOnline,
      gender: gender ?? this.gender,
      income: income ?? this.income,
      incomeStatus: incomeStatus ?? this.incomeStatus,
      lookingFor: lookingFor ?? this.lookingFor,
      qualities: qualities ?? this.qualities,
      socialLinks: socialLinks ?? this.socialLinks,
    );
  }
}
