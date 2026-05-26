import 'package:flutter/material.dart';

/// Draggable @username tag sticker for story editor
/// Uses onScaleUpdate for both pan and scale to avoid gesture conflict
class DraggableTag extends StatefulWidget {
  final String username;
  final VoidCallback? onRemove;
  final ValueChanged<Offset>? onPositionChanged;

  const DraggableTag({
    super.key,
    required this.username,
    this.onRemove,
    this.onPositionChanged,
  });

  @override
  State<DraggableTag> createState() => DraggableTagState();
}

class DraggableTagState extends State<DraggableTag> {
  Offset _position = Offset.zero;
  double _scale = 1.0;
  double _baseScale = 1.0;
  Offset? _lastFocalPoint;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        final size = MediaQuery.of(context).size;
        setState(() {
          _position = Offset(size.width / 2 - 50, size.height / 2);
        });
      }
    });
  }

  /// Get current position for rendering
  Offset get position => _position;
  
  /// Get current scale for rendering
  double get scale => _scale;

  void _handleScaleStart(ScaleStartDetails details) {
    _baseScale = _scale;
    _lastFocalPoint = details.localFocalPoint;
  }

  void _handleScaleUpdate(ScaleUpdateDetails details) {
    setState(() {
      // Calculate position delta from focal point movement
      if (_lastFocalPoint != null) {
        final delta = details.localFocalPoint - _lastFocalPoint!;
        _position += delta;
      }
      _lastFocalPoint = details.localFocalPoint;
      
      // Update scale (clamped)
      _scale = (_baseScale * details.scale).clamp(0.5, 3.0);
    });
    
    widget.onPositionChanged?.call(_position);
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: _position.dx,
      top: _position.dy,
      child: GestureDetector(
        onScaleStart: _handleScaleStart,
        onScaleUpdate: _handleScaleUpdate,
        onLongPress: widget.onRemove,
        child: Transform.scale(
          scale: _scale,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF00E5FF), Color(0xFFD946EF)],
              ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF00E5FF).withValues(alpha: 0.5),
                  blurRadius: 12,
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.alternate_email,
                  color: Colors.white,
                  size: 18,
                ),
                const SizedBox(width: 4),
                Text(
                  widget.username,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
