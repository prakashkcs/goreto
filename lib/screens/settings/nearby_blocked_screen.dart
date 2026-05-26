import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:love_vibe_pro/services/nearby_block_service.dart';
import 'package:love_vibe_pro/widgets/neon_toast.dart';

class NearbyBlockedScreen extends StatefulWidget {
  const NearbyBlockedScreen({super.key});

  @override
  State<NearbyBlockedScreen> createState() => _NearbyBlockedScreenState();
}

class _NearbyBlockedScreenState extends State<NearbyBlockedScreen> {
  List<Map<String, String>> _blocked = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await NearbyBlockService.instance.getBlockedList();
    if (mounted) setState(() { _blocked = list; _loading = false; });
  }

  Future<void> _unblock(String userId, String name, int index) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: const Color(0xFF16162A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.location_on_rounded,
                  color: Color(0xFF22C55E), size: 40),
              const SizedBox(height: 12),
              Text(
                'Unblock $name from Nearby?',
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Text(
                '$name will be able to trigger nearby alerts again.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: Color(0xAAFFFFFF), fontSize: 13, height: 1.5),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: const BorderSide(color: Color(0xFF2A2A3E)),
                        ),
                      ),
                      child: const Text('Cancel',
                          style: TextStyle(color: Color(0xAAFFFFFF))),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        backgroundColor:
                            const Color(0xFF22C55E).withValues(alpha: 0.15),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: const BorderSide(color: Color(0xFF22C55E)),
                        ),
                      ),
                      child: const Text('Unblock',
                          style: TextStyle(
                              color: Color(0xFF22C55E),
                              fontWeight: FontWeight.w700)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    if (ok != true || !mounted) return;
    await NearbyBlockService.instance.unblock(userId);
    if (!mounted) return;
    setState(() => _blocked.removeAt(index));
    NeonToast.show(context, '$name unblocked from nearby',
        type: NeonToastType.success);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF060610),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D0D1A),
        foregroundColor: Colors.white,
        title: const Text(
          'Blocked Nearby Users',
          style: TextStyle(
              color: Colors.white, fontWeight: FontWeight.w700, fontSize: 17),
        ),
        centerTitle: true,
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: const Color(0xFF1C1C2E)),
        ),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFFFF007F)))
          : _blocked.isEmpty
              ? _buildEmpty()
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: _blocked.length,
                  separatorBuilder: (_, __) =>
                      const Divider(color: Color(0xFF1C1C2E), height: 1),
                  itemBuilder: (ctx, i) {
                    final user = _blocked[i];
                    final name = user['name'] ?? 'Unknown';
                    final avatar = user['avatar'] ?? '';
                    final id = user['id'] ?? '';
                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 4, vertical: 6),
                      leading: CircleAvatar(
                        radius: 26,
                        backgroundColor: const Color(0xFF1C1C2E),
                        backgroundImage: avatar.isNotEmpty
                            ? CachedNetworkImageProvider(avatar)
                            : null,
                        child: avatar.isEmpty
                            ? const Icon(Icons.person,
                                color: Colors.white54, size: 24)
                            : null,
                      ),
                      title: Text(
                        name,
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 15),
                      ),
                      subtitle: const Text(
                        'Blocked from nearby alerts',
                        style:
                            TextStyle(color: Color(0xFF8E8E93), fontSize: 12),
                      ),
                      trailing: TextButton(
                        onPressed: () => _unblock(id, name, i),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 8),
                          backgroundColor:
                              const Color(0xFF22C55E).withValues(alpha: 0.12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                            side: const BorderSide(
                                color: Color(0xFF22C55E), width: 0.8),
                          ),
                        ),
                        child: const Text(
                          'Unblock',
                          style: TextStyle(
                              color: Color(0xFF22C55E),
                              fontSize: 12,
                              fontWeight: FontWeight.w600),
                        ),
                      ),
                    );
                  },
                ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.location_on_rounded,
                size: 64,
                color: const Color(0xFF22C55E).withValues(alpha: 0.4)),
            const SizedBox(height: 16),
            const Text(
              'No blocked nearby users',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            const Text(
              'Users you block from nearby alerts will appear here.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: Color(0xFF8E8E93), fontSize: 13, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}
