class ReelSound {
  final int id;
  final int postId;
  final int userId;
  final String title;
  final String audioUrl;
  final double duration;
  final int useCount;
  final String coverUrl;
  final String authorUsername;
  final String authorAvatar;
  final String createdAt;

  const ReelSound({
    required this.id,
    required this.postId,
    required this.userId,
    required this.title,
    required this.audioUrl,
    required this.duration,
    required this.useCount,
    required this.coverUrl,
    required this.authorUsername,
    required this.authorAvatar,
    required this.createdAt,
  });

  factory ReelSound.fromJson(Map<String, dynamic> j) => ReelSound(
        id: j['id'] as int? ?? 0,
        postId: j['post_id'] as int? ?? 0,
        userId: j['user_id'] as int? ?? 0,
        title: j['title'] as String? ?? 'Original Sound',
        audioUrl: j['audio_url'] as String? ?? '',
        duration: (j['duration'] as num?)?.toDouble() ?? 0.0,
        useCount: j['use_count'] as int? ?? 0,
        coverUrl: j['cover_url'] as String? ?? '',
        authorUsername: j['author_username'] as String? ?? '',
        authorAvatar: j['author_avatar'] as String? ?? '',
        createdAt: j['created_at'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'post_id': postId,
        'user_id': userId,
        'title': title,
        'audio_url': audioUrl,
        'duration': duration,
        'use_count': useCount,
        'cover_url': coverUrl,
        'author_username': authorUsername,
        'author_avatar': authorAvatar,
        'created_at': createdAt,
      };

  /// Human-readable duration e.g. "0:32"
  String get durationLabel {
    final secs = duration.toInt();
    final m = secs ~/ 60;
    final s = secs % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }
}
