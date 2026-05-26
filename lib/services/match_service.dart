import 'package:love_vibe_pro/models/match_user.dart';
import 'package:love_vibe_pro/services/api_service.dart';

class MatchService {
  final ApiService _api = ApiService();
  ApiService get api => _api;

  Future<List<MatchUser>> getNearbyUsers({
    required String userId,
    double? myLat,
    double? myLng,
    String? sort,
    String? gender,
  }) async {
    try {
      final users = await _api.getNearbyMatchProfiles(
        userId: userId,
        lat: myLat,
        lng: myLng,
        sort: sort,
        gender: gender,
      );
      
      if (users.isNotEmpty) {
        return users.map((u) => MatchUser.fromJson(u)).toList();
      }
    } catch (_) {
      // API failed — return empty list, no dummy data
    }

    return [];
  }
}
