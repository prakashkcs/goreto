import 'dart:io';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import 'package:love_vibe_pro/models/user_profile.dart';
import 'package:love_vibe_pro/models/user_post.dart';
import 'package:love_vibe_pro/screens/profile/widgets/profile_header.dart';
import 'package:love_vibe_pro/screens/profile/follow_list_screen.dart';
import 'package:love_vibe_pro/models/collection.dart';
import 'package:love_vibe_pro/screens/profile/widgets/collections_strip.dart';
import 'package:love_vibe_pro/screens/profile/collection_detail_screen.dart';
import 'package:love_vibe_pro/screens/profile/create_collection_screen.dart';
import 'package:love_vibe_pro/screens/profile/widgets/posts_tabs.dart';
import 'package:love_vibe_pro/providers/auth_provider.dart';
import 'package:love_vibe_pro/services/sound_service.dart';
import 'package:love_vibe_pro/services/profile_service.dart';
import 'package:love_vibe_pro/services/thumbnail_cache.dart';
import 'package:love_vibe_pro/services/api_service.dart';
import 'package:love_vibe_pro/screens/chat/chat_screen.dart';
import 'package:love_vibe_pro/screens/start_screen.dart';
import 'package:love_vibe_pro/widgets/neon_toast.dart';
import 'package:love_vibe_pro/config/app_env.dart';
import 'package:love_vibe_pro/screens/profile/user_reels_feed_screen.dart';
import 'package:love_vibe_pro/screens/profile/edit_profile_screen.dart';
import 'package:love_vibe_pro/screens/profile/widgets/profile_plans_sheet.dart';
import 'package:love_vibe_pro/widgets/manage_user_sheet.dart';
import 'package:love_vibe_pro/screens/live/live_room_screen.dart';

/// Production-ready Profile Screen with real data, local persistence, and no UI overflow
class ProfileScreen extends StatefulWidget {
  final String? userId;

  const ProfileScreen({super.key, this.userId});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final ScrollController _scrollController = ScrollController();
  final ProfileService _profileService = ProfileService.instance;
  final ApiService _apiService = ApiService();
  late Future<UserProfile> _profileFuture;

  // Data
  UserProfile? _profile;
  List<Map<String, dynamic>> _posts = [];
  List<Map<String, dynamic>> _profileGifts = [];
  List<Collection> _collections = [];

  // State
  String? _errorMessage;
  bool _isFollowLoading = false;
  final bool _isSubscribeLoading = false;
  bool _isOwnProfileView = true;
  String _targetUserId = '';
  bool _isTargetUserLive = false;
  Map<String, dynamic>? _liveData;
  bool _loggingOut = false;

  void _shareProfile() {
    final profile = _profile;
    if (profile == null) return;
    final username = profile.username?.trim() ?? '';
    final url = username.isNotEmpty
        ? 'https://goreto.org/$username'
        : 'https://goreto.org/profile.php?id=${profile.id}';
    final name = username.isNotEmpty ? '@$username' : profile.name;
    SharePlus.instance.share(
      ShareParams(
        text: 'Check out $name on Goreto! $url',
        subject: '$name on Goreto',
      ),
    );
  }

  Future<void> _handleLogout() async {
    _loggingOut = true;
    try {
      final auth = Provider.of<AuthProvider>(context, listen: false);
      await _profileService.clearCachedProfile();
      await auth.logout();
    } catch (_) {}

    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const StartScreen()),
      (route) => false,
    );
  }

  @override
  void initState() {
    super.initState();
    final rawUserId = widget.userId;
    final isViewingOwnProfile =
        rawUserId == null || rawUserId.isEmpty || rawUserId == '0';
    if (isViewingOwnProfile) {
      _profileService.getCachedProfile().then((cached) {
        if (cached != null && mounted && _profile == null) {
          setState(() => _profile = cached);
        }
      });
    }
    _profileFuture = _loadProfileData();
    // Listen for cache clears (e.g. from ProposalsScreen) to trigger a refresh
    _profileService.currentProfileNotifier.addListener(_onProfileChanged);
  }

  void _onProfileChanged() {
    // Skip refresh if we're in the middle of logging out — the cache clear
    // during logout sets the notifier to null, which would otherwise trigger
    // a spurious reload that throws an "Unauthenticated" exception.
    if (_loggingOut) return;
    // If the notifier has been cleared (set to null), it means we need fresh data
    if (_profileService.currentProfileNotifier.value == null && mounted) {
      _refreshProfileData();
    }
  }

  @override
  void dispose() {
    _profileService.currentProfileNotifier.removeListener(_onProfileChanged);
    _scrollController.dispose();
    super.dispose();
  }

  /// Load profile + related resources once per explicit trigger.
  Future<UserProfile> _loadProfileData({bool forceRefresh = false}) async {
    final currentUserId = await _getCurrentUserId();

    // Treat null, empty, and "0" userId as "own profile"
    final rawUserId = widget.userId;
    final isUserIdValid =
        rawUserId != null && rawUserId.isNotEmpty && rawUserId != '0';

    final targetUserId = isUserIdValid ? rawUserId : currentUserId;
    final isOwnProfile = !isUserIdValid || rawUserId == currentUserId;

    _targetUserId = targetUserId;
    _isOwnProfileView = isOwnProfile;

    try {
      UserProfile profile;
      if (isOwnProfile) {
        // For own profile: if targetUserId is empty, getMyProfile will resolve from prefs
        profile = await _profileService.getMyProfile(
          forceRefresh: forceRefresh,
          userId: targetUserId.isNotEmpty ? targetUserId : null,
        );
      } else {
        // Always fetch fresh data when viewing another user's profile to avoid stale cache
        profile = await _profileService.getUserProfile(targetUserId,
            forceRefresh: true);
        // Track profile visit for other users
        _apiService.trackProfileVisit(targetUserId);
        _apiService.recordProfileView(targetUserId);
      }

      profile = profile.copyWith(isOwnProfile: isOwnProfile);

      // Fetch live stats, quality, posts, collections, base URL, live status in parallel
      final parallelResults = await Future.wait([
        _apiService
            .getProfileStats(targetUserId)
            .catchError((_) => null), // [0]
        _apiService
            .fetchUserQuality(targetUserId)
            .catchError((_) => <String, dynamic>{}), // [1]
        _profileService
            .getUserPosts(
              userId: targetUserId,
              viewerId: currentUserId.isNotEmpty ? currentUserId : null,
            )
            .catchError((_) => <Map<String, dynamic>>[]), // [2]
        _apiService
            .fetchReceivedGifts(targetUserId)
            .catchError((_) => <Map<String, dynamic>>[]), // [3]
        AppEnv.getBaseUrlAsync(), // [4]
        _profileService
            .getCollections(userId: targetUserId)
            .catchError((_) => <Collection>[]), // [5]
        _apiService
            .getMatchProfile(targetUserId)
            .catchError((_) => null), // [6]
        if (!isOwnProfile)
          _apiService
              .getLiveUsers()
              .catchError((_) => <dynamic>[]), // [7]
      ]);

      final liveProfileStats = parallelResults[0] as Map<String, dynamic>?;
      final liveQualityStats = parallelResults[1] as Map<String, dynamic>;
      final posts = parallelResults[2] as List<Map<String, dynamic>>;
      final gifts = parallelResults[3] as List<Map<String, dynamic>>;
      final baseUrl = parallelResults[4] as String;
      final collections = parallelResults[5] as List<Collection>;
      final matchProfileStats = parallelResults[6] as Map<String, dynamic>?;

      // Combine the standard stats with the new quality engine stats + match profile stats
      final combinedStats = {
        ...?liveProfileStats,
        ...liveQualityStats,
        ...?matchProfileStats,
      };

      profile = _mergeProfileStats(
        profile,
        combinedStats,
        mergeFollowState: true,
      );

      // Read social links using the combined stats
      profile = _mergeSocialLinks(profile, _extractSocialLinks(combinedStats));
      if (profile.cover.isNotEmpty && !profile.cover.startsWith('http')) {
        final fullCover = profile.cover.startsWith('/')
            ? '${baseUrl.replaceAll('/api/v1', '')}${profile.cover}'
            : '${baseUrl.replaceAll('/api/v1', '')}/${profile.cover}';
        profile = profile.copyWith(cover: fullCover, coverPicUrl: fullCover);
      }

      // Check if target user is currently live (result from parallel fetch)
      if (!isOwnProfile && parallelResults.length > 7) {
        final lives = parallelResults[7] as List<dynamic>? ?? [];
        Map<String, dynamic>? liveEntry;
        for (final l in lives) {
          if ((l['user_id'] ?? l['id'] ?? '').toString() == targetUserId) {
            liveEntry = Map<String, dynamic>.from(l as Map);
            break;
          }
        }
        if (mounted) {
          setState(() {
            _isTargetUserLive = liveEntry != null;
            _liveData = liveEntry;
          });
        }
      }

      if (mounted) {
        // Filter out reshared/reposted posts from profile display
        final originalPosts = posts.where((p) {
          final repostOf =
              int.tryParse((p['repost_of'] ?? '0').toString()) ?? 0;
          final isRepost = p['is_repost'] == 1 ||
              p['is_repost'] == true ||
              p['type'] == 'repost';
          return repostOf == 0 && !isRepost;
        }).toList();

        // Override postsCount with filtered (non-reposted) count
        profile = profile.copyWith(postsCount: originalPosts.length);

        // Preload thumbnails for video posts that don't have a stored thumbnail URL
        final reelUrlsToPreload = originalPosts
            .where((p) {
              final type = (p['type'] ?? '').toString().toLowerCase();
              return type == 'video' || type == 'reel';
            })
            .map((p) {
              final thumb = (p['thumbnail_url'] ?? '').toString().trim();
              if (thumb.isNotEmpty && thumb.startsWith('http')) return null;
              return (p['file_url'] ?? p['video_url'] ?? p['media_url'] ?? '')
                  .toString()
                  .trim();
            })
            .where((u) => u != null && u.isNotEmpty && u.startsWith('http'))
            .cast<String>()
            .toList();
        ThumbnailCache.instance.preload(reelUrlsToPreload);

        setState(() {
          _profile = profile;
          _posts = originalPosts;
          _profileGifts = gifts;
          _collections = collections;
          _errorMessage = null;
        });
      }

      return profile;
    } catch (e) {
      final msg = e.toString().replaceFirst('Exception: ', '');

      // Auth/suspension errors originate from OUR token, not the visited user's
      // account. When viewing another user's profile, swallow these silently so
      // the viewer isn't shown a "Your account has been suspended" dialog and
      // doesn't get logged out.
      final isAuthError = msg.toLowerCase().contains('suspend') ||
          msg.toLowerCase().contains('unauthenticated') ||
          msg.toLowerCase().contains('not logged in') ||
          msg.toLowerCase().contains('authentication token');
      if (!isOwnProfile && isAuthError) {
        if (mounted) setState(() => _errorMessage = 'Unable to load profile');
        return UserProfile(id: '', name: '');
      }

      if (mounted && !_loggingOut) {
        setState(() {
          _errorMessage = msg;
        });
        if (!msg.contains('User not found')) {
          _showErrorDialog(msg);
        }
      }
      // During logout the token is intentionally cleared; suppress the
      // expected "Not logged in" error so the user isn't shown a confusing
      // dialog while the app navigates away.
      if (_loggingOut &&
          (msg.contains('Not logged in') ||
              msg.contains('Authentication token not found'))) {
        return UserProfile(id: '', name: '');
      }
      rethrow;
    }
  }

  /// Show a non-crashing error dialog with the backend message.
  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text(
          'Profile Error',
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          message,
          style: TextStyle(color: Colors.white.withValues(alpha: 0.8)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('OK', style: TextStyle(color: Color(0xFFFF007F))),
          ),
        ],
      ),
    );
  }

  UserProfile _mergeProfileStats(
    UserProfile source,
    Map<String, dynamic>? stats, {
    required bool mergeFollowState,
  }) {
    if (stats == null || stats.isEmpty) return source;

    int? pickInt(List<String> keys) {
      for (final key in keys) {
        final value = stats[key];
        if (value == null) continue;
        if (value is int) return value;
        if (value is num) return value.toInt();
        final parsed = int.tryParse(value.toString());
        if (parsed != null) return parsed;
      }
      return null;
    }

    bool? pickBool(List<String> keys) {
      for (final key in keys) {
        final value = stats[key];
        if (value == null) continue;
        if (value is bool) return value;
        if (value is num) return value.toInt() == 1;
        final normalized = value.toString().trim().toLowerCase();
        if (normalized == '1' || normalized == 'true' || normalized == 'yes') {
          return true;
        }
        if (normalized == '0' || normalized == 'false' || normalized == 'no') {
          return false;
        }
      }
      return null;
    }

    double? pickDouble(List<String> keys) {
      for (final key in keys) {
        final value = stats[key];
        if (value == null) continue;
        if (value is double) return value;
        if (value is num) return value.toDouble();
        final parsed = double.tryParse(value.toString());
        if (parsed != null) return parsed;
      }
      return null;
    }

    final followers = pickInt(['followers_count', 'followers']);
    final following = pickInt(['following_count', 'following']);
    final posts = pickInt(['posts_count', 'total_posts']);
    final proposals = pickInt(['total_proposals', 'proposals_count']);
    final rating = pickDouble(['rating']);
    final isFollowing = pickBool(['is_following']);

    // Extract match profile traits if present in live stats
    final income = pickDouble(['income']);
    final incomeStatus = stats['income_status']?.toString();

    // Helper to safely parse string-arrays from JSON
    List<String>? extractList(String key) {
      if (stats.containsKey(key) && stats[key] is List) {
        return (stats[key] as List).map((e) => e.toString()).toList();
      }
      return null;
    }

    final interests = extractList('interests');
    final lookingFor = extractList('looking_for');
    final qualities = extractList('qualities');

    return source.copyWith(
      followersCount: followers ?? source.followersCount,
      followingCount: following ?? source.followingCount,
      postsCount: posts ?? source.postsCount,
      proposalsCount: proposals ?? source.proposalsCount,
      rating: rating ?? source.rating,
      income: income ?? source.income,
      incomeStatus: incomeStatus ?? source.incomeStatus,
      interests: interests ?? source.interests,
      lookingFor: lookingFor ?? source.lookingFor,
      qualities: qualities ?? source.qualities,
      isFollowing: mergeFollowState
          ? (isFollowing ?? source.isFollowing)
          : source.isFollowing,
    );
  }

  UserProfile _mergeSocialLinks(
    UserProfile source,
    Map<String, String>? socialLinks,
  ) {
    return source.copyWith(socialLinks: socialLinks ?? const {});
  }

  Map<String, String>? _extractSocialLinks(Map<String, dynamic>? stats) {
    if (stats == null) return null;
    final raw = stats['social_links'];
    if (raw is! Map) return null;

    final out = <String, String>{};
    for (final entry in raw.entries) {
      final key = entry.key.toString().trim().toLowerCase();
      final value = entry.value?.toString().trim() ?? '';
      if (key.isNotEmpty && value.isNotEmpty) {
        out[key] = value;
      }
    }
    return out;
  }

  Future<void> _refreshProfileStatsFromApi() async {
    if (_profile == null || _targetUserId.isEmpty) return;

    final liveStats = await _apiService.getProfileStats(_targetUserId);
    if (liveStats == null || liveStats.isEmpty) return;

    if (!mounted) return;
    setState(() {
      var next = _mergeProfileStats(
        _profile!,
        liveStats,
        mergeFollowState: true,
      );
      next = _mergeSocialLinks(next, _extractSocialLinks(liveStats));
      _profile = next;
    });
  }

  Future<void> _refreshProfileData() async {
    final future = _loadProfileData(forceRefresh: true);
    setState(() {
      _profileFuture = future;
    });
    await future;
  }

  Future<void> _reloadGifts() async {
    if (_targetUserId.isEmpty) return;
    try {
      final gifts = await _apiService.fetchReceivedGifts(_targetUserId);
      if (mounted) setState(() => _profileGifts = gifts);
    } catch (_) {}
  }

  Future<String> _getCurrentUserId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('user_id') ?? '';
  }

  // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
  // PROFILE EDITING (FULL SCREEN)
  // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•

  void _openEditScreen() async {
    if (_profile == null) return;

    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => EditProfileScreen(
          currentProfile: _profile!,
          onSave: (updatedProfile) {
            setState(() {
              _profile = updatedProfile;
            });
          },
        ),
      ),
    );
    // Reload only after successful save
    if (saved == true) {
      await _refreshProfileData();
    }
  }

  // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
  // ACTION BUTTONS
  // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•

  Future<void> _handleFollow() async {
    if (_profile == null || _isOwnProfileView) return;

    SoundService().playTap();
    setState(() => _isFollowLoading = true);

    final wasFollowing = _profile!.isFollowing;
    final response = wasFollowing
        ? await _apiService.unfollowUser(_profile!.id)
        : await _apiService.followUser(_profile!.id);

    if (!mounted) return;

    if (response != null) {
      // If the follow API returned is_following directly, use it immediately
      // (no second round-trip needed). Fall back to a stats refresh otherwise.
      final followRaw = response['is_following'] ?? response['following'];
      if (followRaw != null) {
        final nowFollowing =
            followRaw == true || followRaw == 1 || followRaw.toString() == '1';
        setState(() {
          _profile = _profile!.copyWith(isFollowing: nowFollowing);
          _isFollowLoading = false;
        });
      } else {
        await _refreshProfileStatsFromApi();
        if (mounted) setState(() => _isFollowLoading = false);
      }

      _showSnackBar(
        wasFollowing ? 'Unfollowed' : 'Following!',
        type: NeonToastType.success,
      );
    } else {
      // Rollback the optimistic update that was implicit in wasFollowing
      _showSnackBar(
        'Failed to update follow status',
        type: NeonToastType.error,
      );
      if (mounted) setState(() => _isFollowLoading = false);
    }
  }

  Future<void> _handleSubscribe() async {
    SoundService().playTap();
    if (_profile == null || _isOwnProfileView) return;

    final creatorId = int.tryParse(_profile!.id) ?? 0;
    if (creatorId <= 0) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF111118),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => ProfilePlansSheet(
        creatorId: creatorId,
        creatorName: _profile!.name,
        onSubscribed: () {
          Navigator.pop(ctx);
          _refreshProfileData();
        },
      ),
    );
  }

  void _handleInbox() {
    SoundService().playTap();
    if (_profile == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          userId: _profile!.id,
          userName: _profile!.name,
          userAvatar: _profile!.profilePicUrl,
        ),
      ),
    );
  }

  // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
  // PROFILE EDITING (QUICK ACTIONS)
  // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•

  Future<void> _handleUpdateAvatar() async {
    if (_profile == null || !_isOwnProfileView) return;

    final pickedFile = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 80,
    );

    if (pickedFile == null || !mounted) return;

    final file = File(pickedFile.path);

    // Show loading toast
    NeonToast.show(
      context,
      'Uploading profile picture...',
      type: NeonToastType.info,
    );

    try {
      final url = await ProfileService.instance.uploadAvatar(file);

      if (url != null && url.isNotEmpty) {
        // Optimistic UI update
        setState(() {
          _profile = _profile!.copyWith(avatar: url, profilePicUrl: url);
        });

        // Cache the updated profile
        final cached = await ProfileService.instance.getCachedProfile();
        if (cached != null) {
          await ProfileService.instance.cacheProfile(
            cached.copyWith(avatar: url, profilePicUrl: url),
          );
        }

        // Auto-post the update
        try {
          await ApiService().uploadPost(
            file,
            '📷 Updated profile picture',
            'image',
          );
        } catch (_) {}

        if (mounted) NeonToast.success(context, 'Profile picture updated!');
      } else {
        throw Exception('Upload failed');
      }
    } catch (e) {
      if (mounted) {
        NeonToast.error(context, 'Failed to update profile picture: $e');
      }
    }
  }

  Future<void> _handleUpdateCover() async {
    if (_profile == null || !_isOwnProfileView) return;

    final pickedFile = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 90,
    );
    if (pickedFile == null || !mounted) return;

    final croppedFile = await ImageCropper().cropImage(
      sourcePath: pickedFile.path,
      aspectRatio: const CropAspectRatio(ratioX: 16, ratioY: 9),
      compressQuality: 85,
      uiSettings: [
        AndroidUiSettings(
          toolbarTitle: 'Crop Cover Photo',
          lockAspectRatio: true,
          toolbarColor: const Color(0xFF111118),
          toolbarWidgetColor: Colors.white,
          activeControlsWidgetColor: const Color(0xFFFF007F),
        ),
        IOSUiSettings(
          title: 'Crop Cover Photo',
          aspectRatioLockEnabled: true,
        ),
      ],
    );
    if (croppedFile == null || !mounted) return;

    NeonToast.show(context, 'Uploading cover...', type: NeonToastType.info);

    try {
      final url = await ProfileService.instance.uploadCover(File(croppedFile.path));
      if (url != null && url.isNotEmpty) {
        setState(() {
          _profile = _profile!.copyWith(cover: url, coverPicUrl: url);
        });
        if (mounted) NeonToast.success(context, 'Cover updated!');
      } else {
        throw Exception('Upload failed');
      }
    } catch (e) {
      if (mounted) NeonToast.error(context, 'Failed to update cover: $e');
    }
  }

  //â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
  // POST TRACKING
  // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•

  Future<void> _openCreateCollection() async {
    final created = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const CreateCollectionScreen()),
    );
    if (created == true) await _refreshProfileData();
  }

  Future<void> _refreshCollections() async {
    final updated = await _profileService
        .getCollections(userId: _targetUserId.isNotEmpty ? _targetUserId : null)
        .catchError((_) => _collections);
    if (mounted) setState(() => _collections = updated);
  }

  Future<void> _confirmDeleteCollection(Collection collection) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1525),
        title: const Text('Delete Collection',
            style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700)),
        content: Text(
          'Delete "${collection.title}"? This cannot be undone.',
          style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: TextStyle(color: Colors.white.withValues(alpha: 0.5))),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: Color(0xFFFF007F), fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final ok = await _profileService.deleteCollection(collection.id);
    if (!mounted) return;
    if (ok) {
      setState(() => _collections.removeWhere((c) => c.id == collection.id));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to delete collection')),
      );
    }
  }

  Future<void> _trackPostView(Map<String, dynamic> post) async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getString('user_id') ?? 'anonymous';
    final viewedKey = 'viewed_post_ids_$userId';
    final viewedSet = prefs.getStringList(viewedKey)?.toSet() ?? {};

    final postId = (post['id'] ?? post['post_id'])?.toString() ?? '';
    if (!viewedSet.contains(postId)) {
      viewedSet.add(postId);
      await prefs.setStringList(viewedKey, viewedSet.toList());
    }
  }

  void _openPost(Map<String, dynamic> post) {
    final postId = (post['id'] ?? post['post_id'])?.toString() ?? '';
    if (postId.isEmpty) {
      _showSnackBar('Post unavailable');
      return;
    }

    _trackPostView(post);
    final tapIndex = _posts.indexWhere(
      (p) =>
          p == post ||
          (p['id']?.toString() == postId) ||
          (p['post_id']?.toString() == postId),
    );

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => UserReelsFeedScreen(
          posts: _posts,
          initialIndex: tapIndex >= 0 ? tapIndex : 0,
          userName: _profile?.username ?? _profile?.name ?? 'User',
        ),
      ),
    );
  }

  // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
  // UTILS
  // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•

  void _showSnackBar(
    String message, {
    NeonToastType type = NeonToastType.info,
  }) {
    NeonToast.show(context, message, type: type);
  }


  // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
  // BUILD
  // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•

  @override
  Widget build(BuildContext context) {
    final canPop = Navigator.of(context).canPop();
    return Scaffold(
      backgroundColor: Colors.black, // Darken background to match the blobs
      extendBody: true,
      extendBodyBehindAppBar: true,
      appBar: canPop
          ? AppBar(
              backgroundColor: Colors.transparent,
              elevation: 0,
              leading: IconButton(
                icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white),
                onPressed: () => Navigator.of(context).maybePop(),
              ),
              actions: [
                if (_profile != null)
                  IconButton(
                    tooltip: 'Share Profile',
                    icon: const Icon(Icons.share_rounded, color: Colors.white),
                    onPressed: _shareProfile,
                  ),
                if (_profile?.isOwnProfile == true)
                  IconButton(
                    tooltip: 'Logout',
                    icon: const Icon(Icons.logout_rounded, color: Colors.white),
                    onPressed: _handleLogout,
                  ),
                if (_profile != null && !_isOwnProfileView)
                  IconButton(
                    tooltip: 'Manage User',
                    icon: const Icon(Icons.more_vert, color: Colors.white),
                    onPressed: () => ManageUserSheet.show(
                      context,
                      userId: _profile!.id,
                      userName: _profile!.name,
                      userAvatar: _profile!.profilePicUrl,
                      onActionTaken: () {
                        _refreshProfileData();
                      },
                    ),
                  ),
              ],
            )
          : null,
      body: Padding(
        padding: EdgeInsets.zero,
        child: Stack(
          children: [
            // Background Blob matching the match tab
            Positioned(
              top: -100,
              right: -100,
              child: Container(
                width: 300,
                height: 300,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFFFF007F).withValues(alpha: 0.15),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFFF007F).withValues(alpha: 0.4),
                      blurRadius: 100,
                      spreadRadius: 20,
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              bottom: -50,
              left: -100,
              child: Container(
                width: 250,
                height: 250,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF00E5FF).withValues(alpha: 0.1),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF00E5FF).withValues(alpha: 0.3),
                      blurRadius: 100,
                      spreadRadius: 20,
                    ),
                  ],
                ),
              ),
            ),
            // Main Content
            Positioned.fill(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  void _joinLive() {
    if (_liveData == null) return;
    final name = _profile?.name ?? 'User';
    final avatar = _profile?.profilePicUrl ?? _profile?.avatar ?? '';
    final viewers = int.tryParse((_liveData!['viewers'] ?? 0).toString()) ?? 0;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => LiveRoomScreen(
          userId: _targetUserId,
          userName: name,
          userAvatar: avatar.isNotEmpty ? avatar : null,
          viewerCount: viewers,
        ),
      ),
    );
  }

  Widget _buildLiveBanner() {
    final name = _profile?.name ?? 'This user';
    final viewers = int.tryParse((_liveData?['viewers'] ?? 0).toString()) ?? 0;
    return GestureDetector(
      onTap: _joinLive,
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFFFF007F), Color(0xFFD946EF)],
          ),
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFFF007F).withValues(alpha: 0.45),
              blurRadius: 20,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Row(
          children: [
            const Icon(Icons.wifi_tethering_rounded,
                color: Colors.white, size: 28),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    '\u25cf LIVE NOW',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 11,
                      letterSpacing: 1.5,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$name is streaming live',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                  if (viewers > 0)
                    Text(
                      '$viewers watching',
                      style: const TextStyle(
                        color: Color(0xCCFFFFFF),
                        fontSize: 12,
                      ),
                    ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Text(
                'Join',
                style: TextStyle(
                  color: Color(0xFFFF007F),
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    return FutureBuilder<UserProfile>(
      future: _profileFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            _profile == null) {
          return const Center(
            child: CircularProgressIndicator(color: Color(0xFFFF007F)),
          );
        }

        final profile = _profile ?? snapshot.data;

        if (profile == null) {
          final isNotFound = _errorMessage?.contains('User not found') ?? false;

          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  isNotFound ? Icons.person_off_rounded : Icons.error_outline,
                  color: isNotFound
                      ? Colors.grey
                      : Colors.red.withValues(alpha: 0.7),
                  size: 64,
                ),
                const SizedBox(height: 16),
                Text(
                  isNotFound
                      ? 'This account is unavailable.'
                      : (_errorMessage ?? 'Failed to load profile'),
                  style: TextStyle(
                    color: Colors.white.withValues(
                      alpha: isNotFound ? 0.5 : 0.7,
                    ),
                  ),
                  textAlign: TextAlign.center,
                ),
                if (!isNotFound) ...[
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: _refreshProfileData,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFF007F),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text('Retry'),
                  ),
                ],
              ],
            ),
          );
        }

        return RefreshIndicator(
          color: const Color(0xFFFF007F),
          onRefresh: _refreshProfileData,
          child: MediaQuery.removePadding(
            context: context,
            removeTop: true,
            child: CustomScrollView(
              controller: _scrollController,
              physics: const BouncingScrollPhysics(),
              slivers: [
                // Live banner — shown at top when this user is currently live
                if (_isTargetUserLive && !_isOwnProfileView)
                  SliverToBoxAdapter(child: _buildLiveBanner()),

                SliverToBoxAdapter(
                  child: ProfileHeader(
                    profile: profile,
                    onEditCover: _handleUpdateCover,
                    onEditAvatar: _handleUpdateAvatar,
                    onEditBio: _openEditScreen,
                    onFollow: _handleFollow,
                    onSubscribe: _handleSubscribe,
                    onInbox: _handleInbox,
                    onLogout: _handleLogout,
                    isFollowLoading: _isFollowLoading,
                    isSubscribeLoading: _isSubscribeLoading,
                    onFollowersTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => FollowListScreen(
                          userId: profile.id,
                          type: 'followers',
                          displayName: profile.name,
                        ),
                      ),
                    ),
                    onFollowingTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => FollowListScreen(
                          userId: profile.id,
                          type: 'following',
                          displayName: profile.name,
                        ),
                      ),
                    ),
                  ),
                ),

                // Collections strip — hidden when empty on other users' profiles
                if (_collections.isNotEmpty || profile.isOwnProfile) ...[
                  const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                      child: Divider(color: Colors.white12, height: 1),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: CollectionsStrip(
                      collections: _collections,
                      canAddCollection: profile.isOwnProfile,
                      onAddCollection: _openCreateCollection,
                      onCollectionTap: (col) => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => CollectionDetailScreen(
                            collection: col,
                            canAddPosts: profile.isOwnProfile,
                          ),
                        ),
                      ).then((_) => _refreshCollections()),
                      onCollectionLongPress: profile.isOwnProfile
                          ? (col) => _confirmDeleteCollection(col)
                          : null,
                    ),
                  ),
                  const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                      child: Divider(color: Colors.white12, height: 1),
                    ),
                  ),
                ],

                SliverToBoxAdapter(child: _buildPostsSection()),
                const SliverToBoxAdapter(child: SizedBox(height: 120)),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildPostsSection() {
    if (_posts.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          children: [
            const Icon(
              Icons.photo_library_outlined,
              color: Colors.white24,
              size: 64,
            ),
            const SizedBox(height: 16),
            Text(
              'No posts yet',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.5),
                fontSize: 16,
              ),
            ),
          ],
        ),
      );
    }

    final rawPostsById = <String, Map<String, dynamic>>{};
    final userPosts = _posts.map((p) {
      final raw = Map<String, dynamic>.from(p);
      final id = (raw['id'] ?? raw['post_id'])?.toString() ?? '';
      if (id.isNotEmpty) rawPostsById[id] = raw;

      return UserPost(
        id: id,
        type: _mapPostType(
          raw['type']?.toString(),
          duration: raw['duration'] as int?,
        ),
        caption: raw['caption']?.toString() ?? '',
        mediaUrl: raw['media_url']?.toString() ??
            raw['file_url']?.toString() ??
            raw['video_url']?.toString() ??
            '',
        thumbnailUrl: () {
          final t = (raw['thumbnail_url'] ?? raw['image_url'] ?? '')
              .toString()
              .trim();
          return t.isNotEmpty ? t : null;
        }(),
        createdAt: DateTime.tryParse(raw['created_at']?.toString() ?? '') ??
            DateTime.now(),
        viewsUnique: raw['views_unique'] ?? raw['views'] ?? 0,
        viewsTotal:
            raw['views_total'] ?? raw['view_count'] ?? raw['views'] ?? 0,
        likesCount: raw['likes_count'] ?? raw['likes'] ?? 0,
        commentsCount: raw['comments_count'] ?? raw['comments'] ?? 0,
        isLiked: raw['is_liked'] == true || raw['is_liked'] == 1,
        duration: raw['duration'] as int?,
        isRepost:
            (int.tryParse((raw['repost_of'] ?? '0').toString()) ?? 0) > 0 ||
                raw['is_repost'] == 1 ||
                raw['is_repost'] == true,
      );
    }).toList();

    return PostsTabs(
      posts: userPosts,
      gifts: _profileGifts,
      isOwnProfile: _isOwnProfileView,
      onGiftSold: _isOwnProfileView ? _reloadGifts : null,
      onPostTap: (post) {
        final rawPost = rawPostsById[post.id] ??
            {
              'id': post.id,
              'post_id': post.id,
              'caption': post.caption,
              'type': post.type.value,
              'file_url': post.mediaUrl,
              'media_url': post.mediaUrl,
              'image_url': post.thumbnailUrl ?? post.mediaUrl,
              'thumbnail_url': post.thumbnailUrl ?? post.mediaUrl,
              'created_at': post.createdAt.toIso8601String(),
              'likes_count': post.likesCount,
              'comments_count': post.commentsCount,
              'views_count': post.viewsUnique,
              'is_liked': post.isLiked,
            };
        _openPost(Map<String, dynamic>.from(rawPost));
      },
    );
  }

  PostType _mapPostType(String? type, {int? duration}) {
    // Added duration parameter
    switch (type) {
      case 'image':
      case 'photo':
        return PostType.photo;
      case 'video':
        if (duration != null && duration <= 60) {
          return PostType.reel;
        }
        return PostType.video;
      case 'reel': // Keep existing reel type if API already sends it
        return PostType.reel;
      default:
        return PostType.content;
    }
  }
}
