import 'package:audioplayers/audioplayers.dart';

class SoundService {
  static final SoundService _instance = SoundService._internal();
  factory SoundService() => _instance;
  SoundService._internal();

  final AudioPlayer _fxPlayer = AudioPlayer();
  final AudioPlayer _fxPlayer2 = AudioPlayer();
  final AudioPlayer _callRingPlayer = AudioPlayer();

  Future<void> preloadSounds() async {
    try {
      await _fxPlayer.setSource(AssetSource('notify.mp3'));
    } catch (_) {}
  }

  Future<void> playTap() async {}

  /// Tier-based gift sound. tier 0=regular, 1=premium, 2=vip, 3=legendary.
  Future<void> playGiftSound(int coins) async {
    if (coins >= 50000) {
      // Legendary: dramatic double chime
      await _playFx('call-send.mp3', volume: 1.0);
      Future.delayed(const Duration(milliseconds: 380),
          () => _fxPlayer2.play(AssetSource('notify.mp3'), volume: 0.9));
    } else if (coins >= 20000) {
      await _playFx('call-send.mp3', volume: 0.85);
    } else if (coins >= 8000) {
      await _playFx('msg-notify.mp3', volume: 0.85);
    } else {
      await _playFx('notify.mp3', volume: 0.75);
    }
  }

  // Global / general notification sound
  Future<void> playNotification() async {
    await _playFx('notify.mp3', volume: 0.9);
  }

  // Incoming message notification (same tone as global)
  Future<void> playMessageNotification() async {
    await _playFx('notify.mp3', volume: 0.9);
  }

  // Nearby alert — shown in NearbyAlertScreen and nearby tray notifications
  Future<void> playNearbySound() async {
    await _playFx('nearby.mp3', volume: 0.9);
  }

  Future<void> playReact() async {}

  Future<void> playProposed() async {
    await playOutgoingCallRingOnce();
  }

  Future<void> playReject() async {}

  // Outgoing call: plays once (e.g. when initiating from chat)
  Future<void> playOutgoingCallRingOnce() async {
    await _playFx('call-send.mp3', volume: 0.9);
  }

  // Outgoing call: loops while waiting for answer
  Future<void> startOutgoingCallRingLoop() async {
    try {
      await _callRingPlayer.stop();
      await _callRingPlayer.setVolume(1.0);
      await _callRingPlayer.setReleaseMode(ReleaseMode.loop);
      await _callRingPlayer.play(AssetSource('call-send.mp3'), volume: 1.0);
    } catch (_) {}
  }

  // Incoming call: loops ringtone while showing ringing screen
  Future<void> startIncomingCallRingLoop() async {
    try {
      await _callRingPlayer.stop();
      await _callRingPlayer.setVolume(1.0);
      await _callRingPlayer.setReleaseMode(ReleaseMode.loop);
      await _callRingPlayer.play(AssetSource('ringtone.mp3'), volume: 1.0);
    } catch (_) {}
  }

  Future<void> stopOutgoingCallRing() async {
    try {
      await _callRingPlayer.stop();
    } catch (_) {}
  }

  // Alias — stop incoming ring (same player)
  Future<void> stopIncomingCallRing() async {
    try {
      await _callRingPlayer.stop();
    } catch (_) {}
  }

  Future<void> _playFx(String asset, {double volume = 1.0}) async {
    try {
      await _fxPlayer.stop();
      await _fxPlayer.setReleaseMode(ReleaseMode.stop);
      await _fxPlayer.play(AssetSource(asset), volume: volume);
    } catch (_) {}
  }
}
