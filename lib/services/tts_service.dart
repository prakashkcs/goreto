import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

/// Lightweight text-to-speech used for the nearby-alert voice announcement.
///
/// Speaks the nearby user's name followed by the Nepali phrase
/// "तपाईंको नजिक हुनुहुन्छ" ("… is near you"). The Nepali part is in
/// Devanagari so a Nepali (ne-NP) TTS voice pronounces it correctly; if the
/// device has no Nepali voice it falls back gracefully (silent / default voice).
class TtsService {
  TtsService._();
  static final TtsService instance = TtsService._();

  FlutterTts? _tts;

  Future<FlutterTts> _engine() async {
    if (_tts != null) return _tts!;
    final tts = FlutterTts();
    try {
      await tts.setVolume(1.0);
      await tts.setSpeechRate(0.45);
      await tts.setPitch(1.0);
    } catch (_) {}
    _tts = tts;
    return tts;
  }

  /// Announces "<name> तपाईंको नजिक हुनुहुन्छ" in Nepali.
  Future<void> announceNearby(String name) async {
    try {
      final tts = await _engine();
      try {
        await tts.setLanguage('ne-NP');
      } catch (_) {
        // Nepali voice not installed — keep the default voice.
      }
      final n = name.trim().isEmpty ? 'कोही' : name.trim();
      await tts.speak('$n तपाईंको नजिक हुनुहुन्छ');
    } catch (e) {
      if (kDebugMode) print('TTS announceNearby error: $e');
    }
  }

  Future<void> stop() async {
    try {
      await _tts?.stop();
    } catch (_) {}
  }
}
