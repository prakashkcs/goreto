import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:flutter/widgets.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

/// Detects deliberate eye blinks via the front camera and ML Kit.
///
/// Blink state machine:
///   OPEN → eyes drop below [closedThreshold] → CLOSED (held ≥ [minHoldMs])
///   → eyes rise above [openThreshold] → fire trigger
///
/// Two triggers within [doubleWindowMs] → [onDoubleBlink] (e.g. go back).
/// One trigger alone → [onSingleBlink] (e.g. next reel).
class EyeBlinkService {
  EyeBlinkService._();
  static final EyeBlinkService instance = EyeBlinkService._();

  // ── Config (set before calling start) ────────────────────────────────────
  double closedThreshold = 0.35;
  double openThreshold   = 0.65;
  int    cooldownMs      = 800;
  int    doubleWindowMs  = 1000;
  int    minHoldMs       = 80; // eyes must stay closed ≥ this to count

  // ── Callbacks ─────────────────────────────────────────────────────────────
  VoidCallback? onSingleBlink;
  VoidCallback? onDoubleBlink;

  // ── Internal ──────────────────────────────────────────────────────────────
  CameraController?  _camera;
  CameraDescription? _cameraDesc;
  FaceDetector?      _detector;

  bool _isRunning  = false;
  bool _processing = false;
  int  _frameCount = 0;

  // Only process one in every N frames – ~4 fps is enough for blink detection.
  static const int _kSkip = 8;

  bool      _eyeWasClosed      = false;
  DateTime? _closeStartTime;
  DateTime? _lastTriggerTime;
  DateTime? _lastSingleBlinkAt;

  bool get isRunning => _isRunning;

  // ── Public API ────────────────────────────────────────────────────────────

  /// Starts the front camera and ML Kit detector.
  /// Returns true on success, false if camera/permission not available.
  Future<bool> start({
    required VoidCallback onSingleBlink,
    VoidCallback? onDoubleBlink,
  }) async {
    if (_isRunning) return true;
    this.onSingleBlink = onSingleBlink;
    this.onDoubleBlink = onDoubleBlink;

    try {
      _detector = FaceDetector(
        options: FaceDetectorOptions(
          enableClassification: true, // gives leftEyeOpenProbability etc.
          performanceMode: FaceDetectorMode.fast,
          minFaceSize: 0.25,
        ),
      );

      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        _detector?.close();
        _detector = null;
        return false;
      }
      _cameraDesc = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );

      _camera = CameraController(
        _cameraDesc!,
        ResolutionPreset.low, // 240 p — enough for face detection
        enableAudio: false,
        imageFormatGroup: Platform.isAndroid
            ? ImageFormatGroup.nv21
            : ImageFormatGroup.bgra8888,
      );

      await _camera!.initialize();
      _resetState();
      _isRunning = true;
      await _camera!.startImageStream(_onFrame);
      return true;
    } catch (_) {
      _cleanup();
      return false;
    }
  }

  void stop() {
    if (!_isRunning) return;
    _isRunning = false;
    _cleanup();
  }

  // ── Frame pipeline ────────────────────────────────────────────────────────

  void _onFrame(CameraImage image) {
    _frameCount++;
    if (_frameCount % _kSkip != 0) return; // throttle
    if (_processing || !_isRunning) return;
    _processing = true;
    _detectBlink(image).whenComplete(() => _processing = false);
  }

  Future<void> _detectBlink(CameraImage image) async {
    try {
      final inputImage = _toInputImage(image);
      if (inputImage == null) return;

      final faces = await _detector!.processImage(inputImage);
      if (faces.isEmpty) {
        // Face disappeared — reset so we don't get a phantom trigger
        _eyeWasClosed = false;
        _closeStartTime = null;
        return;
      }

      final face = faces.first;
      final leftOpen  = face.leftEyeOpenProbability  ?? 1.0;
      final rightOpen = face.rightEyeOpenProbability ?? 1.0;
      // Average probability: both eyes must move together for a deliberate blink.
      final avg = (leftOpen + rightOpen) / 2.0;

      final now = DateTime.now();

      if (!_eyeWasClosed) {
        if (avg < closedThreshold) {
          _eyeWasClosed  = true;
          _closeStartTime = now;
        }
      } else {
        if (avg > openThreshold) {
          final heldMs = _closeStartTime != null
              ? now.difference(_closeStartTime!).inMilliseconds
              : 0;
          _eyeWasClosed  = false;
          _closeStartTime = null;

          if (heldMs >= minHoldMs) {
            _fireTrigger(now);
          }
          // If heldMs < minHoldMs it was a natural blink — ignored.
        }
      }
    } catch (_) {}
  }

  void _fireTrigger(DateTime now) {
    // Global cooldown between any triggers
    if (_lastTriggerTime != null &&
        now.difference(_lastTriggerTime!).inMilliseconds < cooldownMs) {
      return;
    }
    _lastTriggerTime = now;

    if (onDoubleBlink != null &&
        _lastSingleBlinkAt != null &&
        now.difference(_lastSingleBlinkAt!).inMilliseconds < doubleWindowMs) {
      // Second blink within the window → double blink
      _lastSingleBlinkAt = null;
      onDoubleBlink!();
    } else {
      // Potential single blink — wait half the window before firing
      // so a quick second blink can still be caught as double.
      _lastSingleBlinkAt = now;
      final captured = now;
      Future.delayed(Duration(milliseconds: doubleWindowMs ~/ 2), () {
        if (_lastSingleBlinkAt == captured) {
          _lastSingleBlinkAt = null;
          onSingleBlink?.call();
        }
      });
    }
  }

  // ── CameraImage → InputImage ──────────────────────────────────────────────

  InputImage? _toInputImage(CameraImage image) {
    if (_cameraDesc == null) return null;

    final format = InputImageFormatValue.fromRawValue(image.format.raw);
    if (format == null) return null;

    return InputImage.fromBytes(
      bytes: _concatPlanes(image.planes),
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: _rotation(),
        format: format,
        bytesPerRow: image.planes.first.bytesPerRow,
      ),
    );
  }

  InputImageRotation _rotation() {
    switch (_cameraDesc?.sensorOrientation ?? 0) {
      case 90:  return InputImageRotation.rotation90deg;
      case 180: return InputImageRotation.rotation180deg;
      case 270: return InputImageRotation.rotation270deg;
      default:  return InputImageRotation.rotation0deg;
    }
  }

  Uint8List _concatPlanes(List<Plane> planes) {
    final size = planes.fold<int>(0, (s, p) => s + p.bytes.length);
    final out  = Uint8List(size);
    int offset = 0;
    for (final p in planes) {
      out.setRange(offset, offset + p.bytes.length, p.bytes);
      offset += p.bytes.length;
    }
    return out;
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  void _resetState() {
    _eyeWasClosed     = false;
    _closeStartTime   = null;
    _lastTriggerTime  = null;
    _lastSingleBlinkAt = null;
    _frameCount       = 0;
  }

  void _cleanup() {
    _camera?.stopImageStream().then((_) {
      _camera?.dispose();
      _camera = null;
    }).catchError((_) {
      _camera?.dispose();
      _camera = null;
    });
    _detector?.close();
    _detector  = null;
    _cameraDesc = null;
    _resetState();
  }
}
