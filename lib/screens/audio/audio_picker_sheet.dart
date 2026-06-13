import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:love_vibe_pro/services/api_service.dart';
import 'package:love_vibe_pro/widgets/neon_toast.dart';

/// Trending-first audio picker. Lists user-uploaded sounds ranked by the
/// server's virality score, lets the user search or upload their own clip
/// (auto-trimmed to 60s server-side), and returns the chosen sound map.
///
/// Returned map keys: id, title, audio_url, duration, use_count, author_username.
class AudioPickerSheet extends StatefulWidget {
  const AudioPickerSheet({super.key});

  /// Shows the sheet and resolves to the selected sound (or null if cancelled).
  static Future<Map<String, dynamic>?> show(BuildContext context) {
    return showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      backgroundColor: const Color(0xFF12121E),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (_) => const AudioPickerSheet(),
    );
  }

  @override
  State<AudioPickerSheet> createState() => _AudioPickerSheetState();
}

class _AudioPickerSheetState extends State<AudioPickerSheet> {
  final ApiService _api = ApiService();
  final AudioPlayer _player = AudioPlayer();
  final TextEditingController _searchCtrl = TextEditingController();

  List<Map<String, dynamic>> _sounds = [];
  bool _loading = true;
  bool _uploading = false;
  int? _playingId; // sound id currently previewing
  String _query = '';

  static const _pink = Color(0xFFFF007F);

  @override
  void initState() {
    super.initState();
    _load();
    _player.onPlayerComplete.listen((_) {
      if (mounted) setState(() => _playingId = null);
    });
  }

  @override
  void dispose() {
    _player.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final list = _query.trim().isEmpty
        ? await _api.getSounds(action: 'trending', limit: 50)
        : await _api.getSounds(action: 'search', query: _query.trim(), limit: 50);
    if (mounted) {
      setState(() {
        _sounds = list;
        _loading = false;
      });
    }
  }

  Future<void> _togglePreview(Map<String, dynamic> s) async {
    final id = (s['id'] as num?)?.toInt() ?? 0;
    final url = (s['audio_url'] ?? '').toString();
    if (url.isEmpty) return;
    if (_playingId == id) {
      await _player.stop();
      if (mounted) setState(() => _playingId = null);
      return;
    }
    await _player.stop();
    try {
      await _player.play(UrlSource(url));
      if (mounted) setState(() => _playingId = id);
    } catch (_) {
      if (mounted) setState(() => _playingId = null);
    }
  }

  Future<void> _uploadOwn() async {
    try {
      final result = await FilePicker.platform.pickFiles(type: FileType.audio);
      final path = result?.files.single.path;
      if (path == null) return;
      if (!mounted) return;
      setState(() => _uploading = true);
      final name = path.split(Platform.pathSeparator).last;
      final title = name.contains('.')
          ? name.substring(0, name.lastIndexOf('.'))
          : name;
      final sound = await _api.uploadCustomSound(File(path), title: title);
      if (!mounted) return;
      setState(() => _uploading = false);
      if (sound != null) {
        NeonToast.success(context, 'Uploaded · trimmed to 60s');
        // Select it immediately.
        Navigator.of(context).pop(sound);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _uploading = false);
        NeonToast.error(context, e.toString().replaceAll('Exception: ', ''));
      }
    }
  }

  String _fmtDuration(num d) {
    final s = d.round();
    final m = s ~/ 60;
    final r = s % 60;
    return '$m:${r.toString().padLeft(2, '0')}';
  }

  String _fmtUses(num n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return '$n';
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                children: [
                  const Icon(Icons.graphic_eq_rounded, color: _pink, size: 22),
                  const SizedBox(width: 8),
                  const Text('Add music',
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 17)),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: _uploading ? null : _uploadOwn,
                    icon: _uploading
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: _pink))
                        : const Icon(Icons.upload_rounded,
                            color: _pink, size: 18),
                    label: Text(_uploading ? 'Uploading…' : 'Upload',
                        style: const TextStyle(
                            color: _pink, fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
            ),
            // Search
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _searchCtrl,
                style: const TextStyle(color: Colors.white, fontSize: 14),
                textInputAction: TextInputAction.search,
                onSubmitted: (v) {
                  _query = v;
                  _load();
                },
                onChanged: (v) => _query = v,
                decoration: InputDecoration(
                  hintText: 'Search audio',
                  hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.35)),
                  prefixIcon:
                      const Icon(Icons.search, color: Colors.white38, size: 20),
                  isDense: true,
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.05),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 10, 18, 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  _query.trim().isEmpty ? '🔥 Trending audio' : 'Results',
                  style: const TextStyle(
                      color: Colors.white60,
                      fontSize: 12,
                      fontWeight: FontWeight.w600),
                ),
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(color: _pink))
                  : _sounds.isEmpty
                      ? _emptyState()
                      : ListView.builder(
                          controller: scrollController,
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          itemCount: _sounds.length,
                          itemBuilder: (_, i) => _soundRow(_sounds[i], i),
                        ),
            ),
          ],
        );
      },
    );
  }

  Widget _emptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.library_music_outlined,
                color: Colors.white24, size: 48),
            const SizedBox(height: 12),
            Text(
              _query.trim().isEmpty
                  ? 'No trending audio yet.\nBe the first — upload your own clip!'
                  : 'No audio found for "${_query.trim()}"',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white54, height: 1.5),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _uploading ? null : _uploadOwn,
              style: ElevatedButton.styleFrom(
                backgroundColor: _pink,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              icon: const Icon(Icons.upload_rounded, size: 18),
              label: const Text('Upload your own'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _soundRow(Map<String, dynamic> s, int index) {
    final id = (s['id'] as num?)?.toInt() ?? 0;
    final title = (s['title'] ?? 'Sound').toString();
    final author = (s['author_username'] ?? '').toString();
    final duration = (s['duration'] as num?) ?? 0;
    final uses = (s['use_count'] as num?) ?? 0;
    final cover = (s['cover_url'] ?? '').toString();
    final isPlaying = _playingId == id;
    final trendingTop = _query.trim().isEmpty && index < 3;

    return GestureDetector(
      onTap: () => Navigator.of(context).pop(s),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
        ),
        child: Row(
          children: [
            // Cover / play toggle
            GestureDetector(
              onTap: () => _togglePreview(s),
              child: Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  gradient: const LinearGradient(
                    colors: [Color(0xFFFF007F), Color(0xFF7C3AED)],
                  ),
                  image: cover.isNotEmpty && cover.startsWith('http')
                      ? DecorationImage(
                          image: CachedNetworkImageProvider(cover),
                          fit: BoxFit.cover,
                        )
                      : null,
                ),
                child: Icon(
                  isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  color: Colors.white,
                  size: 26,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (trendingTop) ...[
                        const Text('🔥', style: TextStyle(fontSize: 12)),
                        const SizedBox(width: 4),
                      ],
                      Expanded(
                        child: Text(title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 14)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${author.isNotEmpty ? '@$author · ' : ''}${_fmtDuration(duration)} · ${_fmtUses(uses)} uses',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white38, fontSize: 11),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.check_circle_outline,
                color: Color(0xFFFF007F), size: 22),
          ],
        ),
      ),
    );
  }
}
