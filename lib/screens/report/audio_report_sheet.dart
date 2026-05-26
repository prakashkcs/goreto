import 'package:flutter/material.dart';
import 'package:love_vibe_pro/services/api_service.dart';
import 'package:love_vibe_pro/widgets/neon_toast.dart';

/// Bottom sheet for reporting audio/sound on a post.
/// Usage:
///   AudioReportSheet.show(context, postId: '123', soundName: 'Song Title');
class AudioReportSheet extends StatefulWidget {
  final String postId;
  final String soundName;

  const AudioReportSheet({
    super.key,
    required this.postId,
    required this.soundName,
  });

  static Future<void> show(
    BuildContext context, {
    required String postId,
    String soundName = '',
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => AudioReportSheet(postId: postId, soundName: soundName),
    );
  }

  @override
  State<AudioReportSheet> createState() => _AudioReportSheetState();
}

class _AudioReportSheetState extends State<AudioReportSheet> {
  static const _kPurple = Color(0xFFD946EF);
  static const _kBg = Color(0xFF111111);
  static const _kCard = Color(0xFF1A1A1A);

  static const _reasons = [
    'Copyright infringement',
    'Inappropriate / explicit content',
    'Hate speech or discrimination',
    'Spam or misleading',
    'Violence or harmful content',
    'Other',
  ];

  String? _selectedReason;
  final _detailsController = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _detailsController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_selectedReason == null) {
      NeonToast.show(context, 'Please select a reason',
          type: NeonToastType.error);
      return;
    }
    setState(() => _submitting = true);
    try {
      final result = await ApiService().reportSound(
        postId: widget.postId,
        soundName: widget.soundName,
        reason: _selectedReason!,
        details: _detailsController.text.trim(),
      );
      if (!mounted) return;
      final ok = result['status'] == 'success' || result['status'] == 'ok';
      if (ok) {
        Navigator.pop(context);
        NeonToast.show(context, 'Audio reported. Thank you!',
            type: NeonToastType.success);
      } else {
        final msg = result['message']?.toString() ?? 'Failed to submit report';
        NeonToast.show(context, msg, type: NeonToastType.error);
      }
    } catch (e) {
      if (mounted) {
        NeonToast.show(context, 'Something went wrong',
            type: NeonToastType.error);
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final insets = MediaQuery.of(context).viewInsets;
    final padding = MediaQuery.of(context).padding;
    final bottomPad =
        24 + insets.bottom + (insets.bottom == 0 ? padding.bottom : 0);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 0),
      decoration: const BoxDecoration(
        color: _kBg,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(20, 16, 20, bottomPad),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle bar
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Title row
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _kPurple.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.music_off, color: _kPurple, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Report Audio',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (widget.soundName.isNotEmpty)
                      Text(
                        widget.soundName,
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 12,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          const Text(
            'Why are you reporting this audio?',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),

          // Reason chips
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _reasons.map((r) {
              final selected = _selectedReason == r;
              return GestureDetector(
                onTap: () => setState(() => _selectedReason = r),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: selected ? _kPurple.withValues(alpha: 0.2) : _kCard,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: selected ? _kPurple : Colors.white12,
                      width: selected ? 1.5 : 1,
                    ),
                  ),
                  child: Text(
                    r,
                    style: TextStyle(
                      color: selected ? _kPurple : Colors.white70,
                      fontSize: 13,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),

          // Optional details
          TextField(
            controller: _detailsController,
            maxLines: 3,
            maxLength: 300,
            style: const TextStyle(color: Colors.white, fontSize: 13),
            decoration: InputDecoration(
              hintText: 'Additional details (optional)',
              hintStyle: const TextStyle(color: Colors.white38, fontSize: 13),
              filled: true,
              fillColor: _kCard,
              counterStyle:
                  const TextStyle(color: Colors.white38, fontSize: 11),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Colors.white12),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Colors.white12),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: _kPurple),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 12,
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Submit button
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: _submitting ? null : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: _kPurple,
                disabledBackgroundColor: _kPurple.withValues(alpha: 0.4),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                elevation: 0,
              ),
              child: _submitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Text(
                      'Submit Report',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
