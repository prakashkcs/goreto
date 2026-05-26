/// Data model for user posts in profile
library;
import 'package:love_vibe_pro/utils/date_util.dart';

class UserPost {
  final String id;
  final PostType type;
  final String caption;
  final String mediaUrl;
  final String? thumbnailUrl;
  final DateTime createdAt;
  final int viewsUnique; // Unique viewer count
  final int viewsTotal; // Total view count (including repeat views)
  final int likesCount;
  final int commentsCount;
  final bool isLiked;
  final int? duration;
  final bool isRepost; // True if this post is a reshare

  UserPost({
    required this.id,
    required this.type,
    this.caption = "",
    this.mediaUrl = "",
    this.thumbnailUrl,
    required this.createdAt,
    this.viewsUnique = 0,
    this.viewsTotal = 0,
    this.likesCount = 0,
    this.commentsCount = 0,
    this.isLiked = false,
    this.duration,
    this.isRepost = false,
  });

  factory UserPost.fromJson(Map<String, dynamic> json) {
    // Detect reshare: is_repost flag or non-zero repost_of
    final repostOf = int.tryParse((json['repost_of'] ?? '0').toString()) ?? 0;
    final isRepost =
        json['is_repost'] == 1 ||
        json['is_repost'] == true ||
        json['type'] == 'repost' ||
        repostOf > 0;

    return UserPost(
      id: json["id"]?.toString() ?? "",
      type: PostType.fromString(json["type"]?.toString() ?? "content"),
      caption: json["caption"]?.toString() ?? "",
      mediaUrl: json["media_url"] ?? json["file_url"] ?? "",
      thumbnailUrl: json["thumbnail_url"] ?? json["image_url"],
      createdAt: json["created_at"] != null
          ? DateUtil.parseServerTime(json["created_at"]?.toString())
          : DateTime.now(),
      viewsUnique:
          int.tryParse(
            (json["views_unique"] ?? json["unique_views"] ?? json["views"] ?? 0)
                .toString(),
          ) ??
          0,
      viewsTotal:
          int.tryParse(
            (json["views_total"] ?? json["view_count"] ?? json["views"] ?? 0)
                .toString(),
          ) ??
          0,
      likesCount:
          int.tryParse(
            (json["likes_count"] ?? json["likes"] ?? 0).toString(),
          ) ??
          0,
      commentsCount:
          int.tryParse(
            (json["comments_count"] ?? json["comments"] ?? 0).toString(),
          ) ??
          0,
      isLiked: json["is_liked"] == true || json["is_liked"] == 1,
      duration: json["duration"] is int
          ? json["duration"]
          : int.tryParse(json["duration"]?.toString() ?? ''),
      isRepost: isRepost,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      "id": id,
      "type": type.value,
      "caption": caption,
      "media_url": mediaUrl,
      "thumbnail_url": thumbnailUrl,
      "created_at": createdAt.toIso8601String(),
      "views_unique": viewsUnique,
      "views_total": viewsTotal,
      "likes_count": likesCount,
      "comments_count": commentsCount,
      "is_liked": isLiked,
      "duration": duration,
      "is_repost": isRepost,
    };
  }

  UserPost copyWith({
    String? id,
    PostType? type,
    String? caption,
    String? mediaUrl,
    String? thumbnailUrl,
    DateTime? createdAt,
    int? viewsUnique,
    int? viewsTotal,
    int? likesCount,
    int? commentsCount,
    bool? isLiked,
    int? duration,
    bool? isRepost,
  }) {
    return UserPost(
      id: id ?? this.id,
      type: type ?? this.type,
      caption: caption ?? this.caption,
      mediaUrl: mediaUrl ?? this.mediaUrl,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      createdAt: createdAt ?? this.createdAt,
      viewsUnique: viewsUnique ?? this.viewsUnique,
      viewsTotal: viewsTotal ?? this.viewsTotal,
      likesCount: likesCount ?? this.likesCount,
      commentsCount: commentsCount ?? this.commentsCount,
      isLiked: isLiked ?? this.isLiked,
      duration: duration ?? this.duration,
      isRepost: isRepost ?? this.isRepost,
    );
  }

  /// Generate mock posts for testing
  static List<UserPost> mockList({PostType? filterType}) {
    final posts = [
      UserPost(
        id: "1",
        type: PostType.content,
        caption:
            "Just finished an amazing photoshoot in the mountains! 🏔️ The views were absolutely breathtaking.",
        mediaUrl: "",
        createdAt: DateTime.now().subtract(const Duration(hours: 2)),
        viewsUnique: 1250,
        likesCount: 89,
        commentsCount: 12,
      ),
      UserPost(
        id: "2",
        type: PostType.photo,
        caption: "Golden hour magic ✨",
        mediaUrl: "https://picsum.photos/seed/p1/400/400",
        createdAt: DateTime.now().subtract(const Duration(hours: 5)),
        viewsUnique: 3420,
        likesCount: 256,
        commentsCount: 34,
      ),
      UserPost(
        id: "3",
        type: PostType.reel,
        caption: "Quick tutorial: How I edit my photos 📸",
        mediaUrl: "https://example.com/video1.mp4",
        thumbnailUrl: "https://picsum.photos/seed/r1/400/600",
        createdAt: DateTime.now().subtract(const Duration(days: 1)),
        viewsUnique: 15600,
        likesCount: 890,
        commentsCount: 67,
        duration: 45, // Added for reel
      ),
      UserPost(
        id: "4",
        type: PostType.photo,
        caption: "Street photography vibes 🌃",
        mediaUrl: "https://picsum.photos/seed/p2/400/400",
        createdAt: DateTime.now().subtract(const Duration(days: 1, hours: 5)),
        viewsUnique: 2100,
        likesCount: 145,
        commentsCount: 23,
      ),
      UserPost(
        id: "5",
        type: PostType.video,
        caption: "Behind the scenes of my latest project 🎬",
        mediaUrl: "https://example.com/video2.mp4",
        thumbnailUrl: "https://picsum.photos/seed/v1/400/300",
        createdAt: DateTime.now().subtract(const Duration(days: 2)),
        viewsUnique: 8900,
        likesCount: 445,
        commentsCount: 56,
        duration: 90, // Added for video
      ),
      UserPost(
        id: "6",
        type: PostType.photo,
        caption: "Minimalist aesthetic 🖤",
        mediaUrl: "https://picsum.photos/seed/p3/400/400",
        createdAt: DateTime.now().subtract(const Duration(days: 3)),
        viewsUnique: 4500,
        likesCount: 312,
        commentsCount: 45,
      ),
      UserPost(
        id: "7",
        type: PostType.reel,
        caption: "Travel diaries: Paris edition 🗼",
        mediaUrl: "https://example.com/video3.mp4",
        thumbnailUrl: "https://picsum.photos/seed/r2/400/600",
        createdAt: DateTime.now().subtract(const Duration(days: 4)),
        viewsUnique: 22100,
        likesCount: 1560,
        commentsCount: 89,
        duration: 30, // Added for reel
      ),
      UserPost(
        id: "8",
        type: PostType.content,
        caption: "New music dropping soon! Stay tuned 🎵🔥",
        mediaUrl: "",
        createdAt: DateTime.now().subtract(const Duration(days: 5)),
        viewsUnique: 5600,
        likesCount: 678,
        commentsCount: 92,
      ),
      UserPost(
        id: "9",
        type: PostType.photo,
        caption: "Ocean therapy 🌊",
        mediaUrl: "https://picsum.photos/seed/p4/400/400",
        createdAt: DateTime.now().subtract(const Duration(days: 6)),
        viewsUnique: 7800,
        likesCount: 534,
        commentsCount: 67,
      ),
      UserPost(
        id: "10",
        type: PostType.video,
        caption: "My morning routine for productivity ☀️",
        mediaUrl: "https://example.com/video4.mp4",
        thumbnailUrl: "https://picsum.photos/seed/v2/400/300",
        createdAt: DateTime.now().subtract(const Duration(days: 7)),
        viewsUnique: 18500,
        likesCount: 1102,
        commentsCount: 134,
        duration: 120, // Added for video
      ),
    ];

    if (filterType != null) {
      return posts.where((p) => p.type == filterType).toList();
    }
    return posts;
  }
}

enum PostType {
  content,
  photo,
  reel,
  video;

  String get value {
    switch (this) {
      case PostType.content:
        return "content";
      case PostType.photo:
        return "photo";
      case PostType.reel:
        return "reel";
      case PostType.video:
        return "video";
    }
  }

  static PostType fromString(String value) {
    switch (value.toLowerCase()) {
      case "content":
      case "text":
        return PostType.content;
      case "photo":
      case "image":
        return PostType.photo;
      case "reel":
        return PostType.reel;
      case "video":
        return PostType.video;
      default:
        return PostType.content;
    }
  }
}
