import 'dart:async';
import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';

/// The part of an audio file the user chose (seconds).
class AudioTrim {
  final double start;
  final double duration;
  const AudioTrim(this.start, this.duration);
}

/// Pick which part of a local audio file to use: a two-handle range over the
/// whole track (max [maxSeconds], min [minSeconds]), with a preview that plays
/// exactly the selected part. Returns null if cancelled.
class AudioTrimSheet extends StatefulWidget {
  final String path;
  final String title;
  final double maxSeconds;
  final double minSeconds;

  const AudioTrimSheet({
    super.key,
    required this.path,
    required this.title,
    this.maxSeconds = 60,
    this.minSeconds = 3,
  });

  static Future<AudioTrim?> show(BuildContext context,
      {required String path, required String title}) {
    return showModalBottomSheet<AudioTrim>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => AudioTrimSheet(path: path, title: title),
    );
  }

  @override
  State<AudioTrimSheet> createState() => _AudioTrimSheetState();
}

class _AudioTrimSheetState extends State<AudioTrimSheet> {
  static const _pink = Color(0xFFFF007F);
  static const _purple = Color(0xFFD946EF);
  static const _cyan = Color(0xFF06B6D4);

  final AudioPlayer _player = AudioPlayer();
  StreamSubscription<Duration>? _posSub;
  double _total = 0; // seconds
  RangeValues _range = const RangeValues(0, 0);
  double _pos = 0;
  bool _playing = false;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      await _player.setSource(DeviceFileSource(widget.path));
      final d = await _player.getDuration();
      final total = (d?.inMilliseconds ?? 0) / 1000.0;
      if (total <= 0) throw Exception('Could not read this audio file');
      setState(() {
        _total = total;
        _range = RangeValues(0, math.min(total, widget.maxSeconds));
        _loading = false;
      });
      _posSub = _player.onPositionChanged.listen((p) {
        final s = p.inMilliseconds / 1000.0;
        if (!mounted) return;
        setState(() => _pos = s);
        if (_playing && s >= _range.end) _stop();
      });
      _player.onPlayerComplete.listen((_) {
        if (mounted) setState(() => _playing = false);
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _error = e.toString().replaceAll('Exception: ', '');
      });
    }
  }

  Future<void> _togglePreview() async {
    if (_playing) return _stop();
    await _player.seek(Duration(milliseconds: (_range.start * 1000).round()));
    await _player.resume();
    setState(() => _playing = true);
  }

  Future<void> _stop() async {
    await _player.pause();
    if (mounted) setState(() => _playing = false);
  }

  void _onRange(RangeValues v) {
    var start = v.start, end = v.end;
    // Keep the selection between min and max length, moving the other handle.
    if (end - start > widget.maxSeconds) {
      if ((start - _range.start).abs() > 0.001) {
        end = start + widget.maxSeconds;
      } else {
        start = end - widget.maxSeconds;
      }
    }
    if (end - start < widget.minSeconds) {
      if ((start - _range.start).abs() > 0.001) {
        start = math.max(0, end - widget.minSeconds);
      } else {
        end = math.min(_total, start + widget.minSeconds);
      }
    }
    setState(() => _range = RangeValues(start, end));
    if (_playing) _stop();
  }

  String _fmt(double s) {
    final t = s.round();
    return '${t ~/ 60}:${(t % 60).toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _posSub?.cancel();
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final len = _range.end - _range.start;
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF12101C),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(top: BorderSide(color: Color(0x55D946EF))),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 14),
            const Row(children: [
              Icon(Icons.content_cut_rounded, color: _purple, size: 20),
              SizedBox(width: 8),
              Text('Choose the part to use',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w800)),
            ]),
            const SizedBox(height: 4),
            Text(widget.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white54, fontSize: 13)),
            const SizedBox(height: 18),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 30),
                child: Center(
                    child: CircularProgressIndicator(color: _pink, strokeWidth: 2)),
              )
            else if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Text(_error!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Color(0xFFFF6B6B))),
              )
            else ...[
              // Selected window over the full track, with playhead.
              SizedBox(
                height: 54,
                child: LayoutBuilder(builder: (context, c) {
                  final w = c.maxWidth;
                  double x(double s) => _total <= 0 ? 0 : (s / _total) * w;
                  return Stack(children: [
                    // Fake waveform bars (decorative) across the full track.
                    Positioned.fill(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: List.generate(48, (i) {
                          final h = 10 + 30 * (0.5 + 0.5 * math.sin(i * 1.7) * math.cos(i * 0.6)).abs();
                          final mid = (i + 0.5) / 48 * _total;
                          final inSel = mid >= _range.start && mid <= _range.end;
                          return Expanded(
                            child: Center(
                              child: Container(
                                width: 3,
                                height: h,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(2),
                                  color: inSel
                                      ? Color.lerp(_pink, _cyan, i / 48)
                                      : Colors.white.withValues(alpha: 0.15),
                                ),
                              ),
                            ),
                          );
                        }),
                      ),
                    ),
                    Positioned(
                      left: x(_range.start),
                      width: math.max(2, x(_range.end) - x(_range.start)),
                      top: 0,
                      bottom: 0,
                      child: IgnorePointer(
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: _purple, width: 1.5),
                            color: _purple.withValues(alpha: 0.10),
                          ),
                        ),
                      ),
                    ),
                    if (_playing)
                      Positioned(
                        left: x(_pos).clamp(0.0, w - 2),
                        top: 0,
                        bottom: 0,
                        child: Container(width: 2, color: Colors.white),
                      ),
                  ]);
                }),
              ),
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  activeTrackColor: _purple,
                  inactiveTrackColor: Colors.white12,
                  thumbColor: Colors.white,
                  overlayColor: _pink.withValues(alpha: 0.2),
                  rangeThumbShape:
                      const RoundRangeSliderThumbShape(enabledThumbRadius: 9),
                ),
                child: RangeSlider(
                  min: 0,
                  max: _total,
                  values: _range,
                  onChanged: _onRange,
                ),
              ),
              Row(children: [
                Text(_fmt(_range.start),
                    style: const TextStyle(color: Colors.white70, fontSize: 12)),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: _cyan.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _cyan.withValues(alpha: 0.6)),
                  ),
                  child: Text('${len.toStringAsFixed(1)} s selected',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w700)),
                ),
                const Spacer(),
                Text(_fmt(_range.end),
                    style: const TextStyle(color: Colors.white70, fontSize: 12)),
              ]),
              const SizedBox(height: 4),
              Text('Full track ${_fmt(_total)} · up to ${widget.maxSeconds.round()} s',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white38, fontSize: 11.5)),
              const SizedBox(height: 16),
              Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _togglePreview,
                    icon: Icon(_playing ? Icons.stop_rounded : Icons.play_arrow_rounded,
                        color: _cyan),
                    label: Text(_playing ? 'Stop' : 'Preview',
                        style: const TextStyle(color: Colors.white)),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: _cyan),
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(24)),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      _player.stop();
                      Navigator.pop(context, AudioTrim(_range.start, len));
                    },
                    child: Container(
                      height: 48,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(24),
                        gradient: const LinearGradient(colors: [_pink, _purple]),
                      ),
                      child: const Text('Use this part',
                          style: TextStyle(
                              color: Colors.white, fontWeight: FontWeight.w800)),
                    ),
                  ),
                ),
              ]),
            ],
          ],
        ),
      ),
    );
  }
}
