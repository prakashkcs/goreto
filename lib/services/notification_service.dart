import '../models/app_notification.dart';
import 'api_service.dart';

class NotificationService {
  NotificationService._();
  static final NotificationService _instance = NotificationService._();
  factory NotificationService() => _instance;

  final ApiService _apiService = ApiService();

  Future<List<AppNotification>> getNotifications() async {
    try {
      final dio = await _apiService.getDioClient();
      final response = await dio.get('api_notifications.php?action=list');

      if (response.data != null &&
          (response.data['status'] == 'success' ||
              response.data['status'] == true)) {
        final List<dynamic> data = response.data['data'] ?? [];
        return data.map((e) => AppNotification.fromJson(e)).toList();
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  Future<int> getUnreadCount() async {
    try {
      final dio = await _apiService.getDioClient();
      final response = await dio.get(
        'api_notifications.php?action=unread_count',
      );

      if (response.data != null &&
          (response.data['status'] == 'success' ||
              response.data['status'] == true)) {
        return response.data['count'] is int
            ? response.data['count']
            : int.tryParse(response.data['count'].toString()) ?? 0;
      }
      return 0;
    } catch (e) {
      return 0;
    }
  }

  Future<bool> markAsRead({int? notificationId}) async {
    try {
      final dio = await _apiService.getDioClient();
      final data = <String, dynamic>{'action': 'mark_read'};
      if (notificationId != null) {
        data['notification_id'] = notificationId;
      }

      final response = await dio.post('api_notifications.php', data: data);

      return response.data != null &&
          (response.data['status'] == 'success' ||
              response.data['status'] == true);
    } catch (e) {
      return false;
    }
  }
}
