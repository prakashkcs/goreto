import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'package:love_vibe_pro/services/api_service.dart';
import 'package:love_vibe_pro/widgets/neon_toast.dart';

class ActiveSubscribersScreen extends StatefulWidget {
  const ActiveSubscribersScreen({super.key});

  @override
  State<ActiveSubscribersScreen> createState() =>
      _ActiveSubscribersScreenState();
}

class _ActiveSubscribersScreenState extends State<ActiveSubscribersScreen> {
  bool _isLoading = true;
  List<dynamic> _subscribers = [];
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _fetchSubscribers();
  }

  Future<void> _fetchSubscribers() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getString('user_id');

      if (userId == null) {
        setState(() {
          _errorMessage = 'User not logged in';
          _isLoading = false;
        });
        return;
      }

      final dio = Dio();
      final response = await dio.get(
        'https://goreto.org/ekloadmin/api/v1/api_subscriptions.php',
        queryParameters: {
          'action': 'my_subscribers',
          'user_id': userId,
        },
      );

      if (response.data is Map && response.data['status'] == 'success') {
        setState(() {
          _subscribers = response.data['subscribers'] ?? [];
          _isLoading = false;
          _errorMessage = null;
        });
      } else {
        setState(() {
          _errorMessage =
              response.data['message'] ?? 'Failed to load subscribers';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Network error occurred';
        _isLoading = false;
      });
    }
  }

  String _formatDate(String dateString) {
    try {
      final date = DateTime.parse(dateString);
      return DateFormat('MMM d, yyyy - h:mm a').format(date);
    } catch (e) {
      return dateString;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        title: const Text(
          'Active Subscribers',
          style: TextStyle(fontFamily: 'Outfit', fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(child: _buildBody()),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return Center(
          child:
              CircularProgressIndicator(color: Theme.of(context).primaryColor));
    }

    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, color: Colors.redAccent, size: 60),
            const SizedBox(height: 16),
            Text(
              _errorMessage!,
              style: const TextStyle(color: Colors.white70, fontSize: 16),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).primaryColor,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
              onPressed: () {
                setState(() {
                  _isLoading = true;
                  _errorMessage = null;
                });
                _fetchSubscribers();
              },
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_subscribers.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.people_outline,
                color: Colors.white.withValues(alpha: 0.5), size: 80),
            const SizedBox(height: 16),
            Text(
              'No active subscribers yet',
              style:
                  TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 18),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _subscribers.length,
      itemBuilder: (context, index) {
        final sub = _subscribers[index];
        return _buildSubscriberCard(sub);
      },
    );
  }

  Future<void> _confirmTerminate(Map<String, dynamic> sub) async {
    final name = (sub['name'] ?? 'this subscriber').toString();
    final subscriptionId =
        int.tryParse((sub['subscription_id'] ?? '').toString()) ?? 0;
    if (subscriptionId <= 0) {
      NeonToast.error(context, 'Cannot terminate: subscription id missing');
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A28),
        title: const Text('Terminate subscriber?',
            style: TextStyle(color: Colors.white)),
        content: Text(
          'Cancel the active subscription for $name? They will lose access to your subscriber-only content immediately. This cannot be undone.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Terminate',
                style: TextStyle(color: Color(0xFFFF007F))),
          ),
        ],
      ),
    );
    if (ok != true) return;

    try {
      final result = await ApiService().terminateSubscriber(subscriptionId);
      if (!mounted) return;
      if (result['status'] == 'success') {
        NeonToast.success(context, 'Subscriber terminated');
        // Optimistically drop the card; refresh in background to be safe.
        setState(() {
          _subscribers.removeWhere(
              (s) => (s['subscription_id']?.toString() ?? '') ==
                  subscriptionId.toString());
        });
        _fetchSubscribers();
      } else {
        NeonToast.error(
            context, result['message']?.toString() ?? 'Failed to terminate');
      }
    } catch (e) {
      if (mounted) NeonToast.error(context, 'Network error: $e');
    }
  }

  Widget _buildSubscriberCard(Map<String, dynamic> sub) {
    final avatar = sub['avatar'] ?? '';
    final name = sub['name'] ?? 'Unknown User';
    final username = sub['username'] ?? '';
    final subscribeTime = sub['subscribe_time'] ?? '';
    final renewals = sub['total_renewals']?.toString() ?? '0';

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 30,
            backgroundImage: avatar.isNotEmpty ? NetworkImage(avatar) : null,
            backgroundColor: Colors.white.withValues(alpha: 0.1),
            child: avatar.isEmpty
                ? const Icon(Icons.person, color: Colors.white)
                : null,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (username.isNotEmpty)
                  Text(
                    '@$username',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.6),
                      fontSize: 14,
                    ),
                  ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Icon(Icons.schedule, color: Colors.amber, size: 14),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        'Subscribed: ${_formatDate(subscribeTime)}',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.8),
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(Icons.autorenew,
                        color: Colors.greenAccent, size: 14),
                    const SizedBox(width: 4),
                    Text(
                      'Total Renewals: $renewals',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.8),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: () => _confirmTerminate(sub),
                    icon: const Icon(Icons.cancel_outlined,
                        color: Color(0xFFFF007F), size: 18),
                    label: const Text(
                      'Terminate',
                      style: TextStyle(
                        color: Color(0xFFFF007F),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      backgroundColor:
                          const Color(0xFFFF007F).withValues(alpha: 0.08),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
