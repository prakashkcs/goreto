/// Data model for user profile
class UserProfile {
  final String id;
  final String name;
  final String? username;
  final String bio;
  final String location;
  final String avatar;
  final String cover;
  final String profilePicUrl;
  final String coverPicUrl;
  final Map<String, String> socialLinks;
  final int followersCount;
  final int followingCount;
  final int postsCount;
  final bool isFollowing;
  final bool isSubscribed;
  final bool isOwnProfile;
  final String gender;
  final int age; // Added age field
  final List<String> galleryPhotos; // Added galleryPhotos field
  final double rating;
  final int proposalsCount;

  // Added match fields
  final double income;
  final String incomeStatus;
  final String kycStatus; // Added kycStatus field
  final String subscriptionStatus;
  final List<String> interests;
  final List<String> lookingFor;
  final List<String> qualities;
  final Map<String, dynamic>? publicPartner; // Added for public connections
  final int gifterLevel;       // 0–6 badge level (computed from totalCoinsSent)
  final int totalCoinsSent;    // lifetime coins spent on gifts

  UserProfile({
    required this.id,
    required this.name,
    this.username,
    this.bio = '',
    this.location = '',
    this.avatar = '',
    this.cover = '',
    this.profilePicUrl = '',
    this.coverPicUrl = '',
    this.socialLinks = const {},
    this.followersCount = 0,
    this.followingCount = 0,
    this.postsCount = 0,
    this.isFollowing = false,
    this.isSubscribed = false,
    this.isOwnProfile = true,
    this.gender = 'male', // Default for filtering logic if missing
    this.age = 25, // Default age
    this.galleryPhotos = const [],
    this.rating = 0.0,
    this.proposalsCount = 0,
    this.income = 0.0,
    this.incomeStatus = 'none',
    this.kycStatus = 'none',
    this.subscriptionStatus = 'inactive',
    this.interests = const [],
    this.lookingFor = const [],
    this.qualities = const [],
    this.publicPartner,
    this.gifterLevel = 0,
    this.totalCoinsSent = 0,
  });

  static int _computeGifterLevel(int coins) {
    if (coins >= 5000000) return 6;
    if (coins >= 1500000) return 5;
    if (coins >= 500000)  return 4;
    if (coins >= 200000)  return 3;
    if (coins >= 50000)   return 2;
    if (coins >= 10000)   return 1;
    return 0;
  }

  /// Safe bool parser — handles bool, int (0/1), String ("1"/"true"/"yes"/"on").
  static bool _asBool(dynamic v, {bool fallback = false}) {
    if (v == null) return fallback;
    if (v is bool) return v;
    if (v is int) return v == 1;
    if (v is String) {
      final s = v.trim().toLowerCase();
      return s == '1' || s == 'true' || s == 'yes' || s == 'on';
    }
    return fallback;
  }

  /// Safe int parser — handles int, String, num.
  static int _asInt(dynamic v, {int fallback = 0}) {
    if (v == null) return fallback;
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v.trim()) ?? fallback;
    return fallback;
  }

  /// Safe double parser
  static double _asDouble(dynamic v, {double fallback = 0.0}) {
    if (v == null) return fallback;
    if (v is double) return v;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v.trim()) ?? fallback;
    return fallback;
  }

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    final avatar =
        (json['avatar'] ??
                json['profile_pic_url'] ??
                json['avatar_url'] ??
                json['profile_pic'] ??
                '')
            .toString();
    final cover =
        (json['cover'] ?? json['cover_pic_url'] ?? json['cover_url'] ?? '')
            .toString();

    return UserProfile(
      id: json["id"]?.toString() ?? '',
      name: (json["name"]?.toString() ?? '').trim().isEmpty ? 'User' : json["name"].toString(),
      username: json["username"]?.toString(),
      bio: json["bio"]?.toString() ?? '',
      location: json["location"]?.toString() ?? '',
      avatar: avatar,
      cover: cover,
      profilePicUrl: avatar,
      coverPicUrl: cover,
      socialLinks: _parseSocialLinks(json["social_links"]),
      followersCount: _asInt(json["followers_count"] ?? json["followers"]),
      followingCount: _asInt(json["following_count"] ?? json["following"]),
      postsCount: _asInt(json["posts_count"] ?? json["posts"]),
      isFollowing: _asBool(json["is_following"]),
      isSubscribed: _asBool(json["is_subscribed"]),
      isOwnProfile: _asBool(json["is_own_profile"], fallback: true),
      gender: json["gender"]?.toString() ?? 'male',
      age: _asInt(json["age"], fallback: 25),
      galleryPhotos: List<String>.from(json["gallery_photos"] ?? []),
      rating: _asDouble(json["rating"]),
      proposalsCount: _asInt(
        json["total_proposals"] ?? json["proposals_count"],
      ),
      income: _asDouble(json["income"]),
      incomeStatus: json["income_status"]?.toString() ?? 'none',
      kycStatus: json["kyc_status"]?.toString() ?? 'none',
      subscriptionStatus: json["subscription_status"]?.toString() ?? 'inactive',
      interests: List<String>.from(json["interests"] ?? []),
      lookingFor: List<String>.from(json["looking_for"] ?? []),
      qualities: List<String>.from(json["qualities"] ?? []),
      publicPartner: (json["public_partner"] is Map)
          ? Map<String, dynamic>.from(json["public_partner"] as Map)
          : null,
      totalCoinsSent: _asInt(json["total_coins_sent"]),
      gifterLevel: json["gifter_level"] != null
          ? _asInt(json["gifter_level"])
          : _computeGifterLevel(_asInt(json["total_coins_sent"])),
    );
  }

  static Map<String, String> _parseSocialLinks(dynamic raw) {
    if (raw is! Map) {
      return <String, String>{};
    }

    final map = <String, String>{};
    raw.forEach((key, value) {
      if (value == null) return;
      final asString = value.toString().trim();
      if (asString.isEmpty) return;
      map[key.toString()] = asString;
    });
    return map;
  }

  Map<String, dynamic> toJson() {
    return {
      "id": id,
      "name": name,
      "username": username,
      "bio": bio,
      "location": location,
      "avatar": avatar,
      "cover": cover,
      "profile_pic_url": profilePicUrl,
      "cover_pic_url": coverPicUrl,
      "social_links": socialLinks,
      "followers_count": followersCount,
      "following_count": followingCount,
      "posts_count": postsCount,
      "is_following": isFollowing,
      "is_subscribed": isSubscribed,
      "is_own_profile": isOwnProfile,
      "gender": gender,
      "age": age,
      "gallery_photos": galleryPhotos,
      "rating": rating,
      "total_proposals": proposalsCount,
      "income": income,
      "income_status": incomeStatus,
      "kyc_status": kycStatus,
      "subscription_status": subscriptionStatus,
      "interests": interests,
      "looking_for": lookingFor,
      "qualities": qualities,
      if (publicPartner != null) "public_partner": publicPartner,
      "total_coins_sent": totalCoinsSent,
      "gifter_level": gifterLevel,
    };
  }

  UserProfile copyWith({
    String? id,
    String? name,
    String? username,
    String? bio,
    String? location,
    String? avatar,
    String? cover,
    String? profilePicUrl,
    String? coverPicUrl,
    Map<String, String>? socialLinks,
    int? followersCount,
    int? followingCount,
    int? postsCount,
    bool? isFollowing,
    bool? isSubscribed,
    bool? isOwnProfile,
    String? gender,
    int? age,
    List<String>? galleryPhotos,
    double? rating,
    int? proposalsCount,
    double? income,
    String? incomeStatus,
    String? kycStatus,
    String? subscriptionStatus,
    List<String>? interests,
    List<String>? lookingFor,
    List<String>? qualities,
    Map<String, dynamic>? publicPartner,
  }) {
    return UserProfile(
      id: id ?? this.id,
      name: name ?? this.name,
      username: username ?? this.username,
      bio: bio ?? this.bio,
      location: location ?? this.location,
      avatar: avatar ?? profilePicUrl ?? this.avatar,
      cover: cover ?? coverPicUrl ?? this.cover,
      profilePicUrl: profilePicUrl ?? avatar ?? this.profilePicUrl,
      coverPicUrl: coverPicUrl ?? cover ?? this.coverPicUrl,
      socialLinks: socialLinks ?? this.socialLinks,
      followersCount: followersCount ?? this.followersCount,
      followingCount: followingCount ?? this.followingCount,
      postsCount: postsCount ?? this.postsCount,
      isFollowing: isFollowing ?? this.isFollowing,
      isSubscribed: isSubscribed ?? this.isSubscribed,
      isOwnProfile: isOwnProfile ?? this.isOwnProfile,
      gender: gender ?? this.gender,
      age: age ?? this.age,
      galleryPhotos: galleryPhotos ?? this.galleryPhotos,
      rating: rating ?? this.rating,
      proposalsCount: proposalsCount ?? this.proposalsCount,
      income: income ?? this.income,
      incomeStatus: incomeStatus ?? this.incomeStatus,
      kycStatus: kycStatus ?? this.kycStatus,
      subscriptionStatus: subscriptionStatus ?? this.subscriptionStatus,
      interests: interests ?? this.interests,
      lookingFor: lookingFor ?? this.lookingFor,
      qualities: qualities ?? this.qualities,
      publicPartner: publicPartner ?? this.publicPartner,
    );
  }

  /// Generate mock profile for testing
  static UserProfile mock() {
    return UserProfile(
      id: '1',
      name: 'Alex Rivera',
      username: '@alexr',
      bio:
          'Digital creator & photographer 📸\nLiving life one adventure at a time ✨\nLove music, art & good vibes 🎵',
      location: 'Los Angeles, CA',
      avatar: 'https://i.pravatar.cc/400?img=12',
      cover: 'https://picsum.photos/seed/cover/800/400',
      profilePicUrl: 'https://i.pravatar.cc/400?img=12',
      coverPicUrl: 'https://picsum.photos/seed/cover/800/400',
      socialLinks: {
        'facebook': 'https://facebook.com/alexr',
        'instagram': 'https://instagram.com/alexr',
        'youtube': 'https://youtube.com/@alexr',
        'x': 'https://x.com/alexr',
      },
      followersCount: 12500,
      followingCount: 890,
      postsCount: 156,
      isFollowing: false,
      isSubscribed: false,
      isOwnProfile: true,
      gender: 'male',
      age: 28,
      galleryPhotos: [
        'https://picsum.photos/seed/gallery1/400/600',
        'https://picsum.photos/seed/gallery2/400/600',
        'https://picsum.photos/seed/gallery3/400/600',
      ],
      income: 75000,
      incomeStatus: 'verified',
      kycStatus: 'verified',
      interests: ['Photography', 'Music', 'Travel', 'Art'],
      lookingFor: ['Long-term relationship', 'Friendship'],
      qualities: ['Creative', 'Adventurous', 'Loyal'],
    );
  }
}
