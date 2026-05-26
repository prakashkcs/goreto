import 'package:flutter/material.dart';

/// Draggable text overlay for story editor
/// Uses onScaleUpdate for both pan and scale to avoid gesture conflict
class DraggableText extends StatefulWidget {
  final String text;
  final Color color;
  final VoidCallback? onRemove;
  final VoidCallback? onTap; // For editing
  final ValueChanged<Offset>? onPositionChanged;
  final ValueChanged<double>? onScaleChanged;

  const DraggableText({
    super.key,
    required this.text,
    this.color = Colors.white,
    this.onRemove,
    this.onTap,
    this.onPositionChanged,
    this.onScaleChanged,
  });

  @override
  State<DraggableText> createState() => DraggableTextState();
}

class DraggableTextState extends State<DraggableText> {
  Offset _position = Offset.zero;
  double _scale = 1.0;
  double _baseScale = 1.0;
  double _rotation = 0.0;
  double _baseRotation = 0.0;
  Offset? _lastFocalPoint;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        final size = MediaQuery.of(context).size;
        setState(() {
          _position = Offset(size.width / 2 - 50, size.height / 2 - 20);
        });
      }
    });
  }

  /// Get current position for rendering
  Offset get position => _position;
  
  /// Get current scale for rendering
  double get scale => _scale;
  
  /// Get current rotation for rendering
  double get rotation => _rotation;

  void _handleScaleStart(ScaleStartDetails details) {
    _baseScale = _scale;
    _baseRotation = _rotation;
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
      
      // Update rotation
      _rotation = _baseRotation + details.rotation;
    });
    
    widget.onPositionChanged?.call(_position);
    widget.onScaleChanged?.call(_scale);
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
        onTap: widget.onTap,
        child: Transform.rotate(
          angle: _rotation,
          child: Transform.scale(
            scale: _scale,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                border: Border.all(
                  color: widget.color.withValues(alpha: 0.5),
                  width: 1,
                ),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                widget.text,
                style: TextStyle(
                  color: widget.color,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  shadows: [
                    Shadow(
                      color: Colors.black.withValues(alpha: 0.7),
                      blurRadius: 8,
                    ),
                  ],
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
