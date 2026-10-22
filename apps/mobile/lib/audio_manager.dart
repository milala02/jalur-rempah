import 'dart:io' show Platform;
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

/// Singleton pengelola musik latar (BGM) dan efek suara (SFX) Jalur Rempah.
class AudioManager extends ChangeNotifier {
  static final AudioManager _instance = AudioManager._internal();

  factory AudioManager() => _instance;

  AudioManager._internal();

  static const String defaultBgmUrl =
      'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-1.mp3';

  static const Map<String, String> sfxUrls = <String, String>{
    'coin': 'https://actions.google.com/sounds/v1/cartoon/coins.ogg',
    'click': 'https://actions.google.com/sounds/v1/ui/click.ogg',
    'success':
        'https://actions.google.com/sounds/v1/cartoon/clang_and_wobble.ogg',
    'cannon':
        'https://actions.google.com/sounds/v1/weapons/big_explosion_cut_off.ogg',
  };

  AudioPlayer? _bgmPlayer;
  AudioPlayer? _sfxPlayer;

  bool _isMuted = false;
  bool _isBgmPlaying = false;
  String? _lastPlayedSfx;

  bool get isMuted => _isMuted;
  bool get isBgmPlaying => _isBgmPlaying;
  String? get lastPlayedSfx => _lastPlayedSfx;

  static bool get _isTestEnvironment {
    try {
      return const bool.fromEnvironment('FLUTTER_TEST') ||
          Platform.environment.containsKey('FLUTTER_TEST');
    } catch (_) {
      return false;
    }
  }

  AudioPlayer _ensureBgmPlayer() {
    return _bgmPlayer ??= AudioPlayer();
  }

  AudioPlayer _ensureSfxPlayer() {
    return _sfxPlayer ??= AudioPlayer();
  }

  /// Memutar musik latar belakang maritim secara berulang (loop).
  Future<void> playBgm({String url = defaultBgmUrl}) async {
    _isBgmPlaying = true;
    if (_isMuted || _isTestEnvironment) {
      return;
    }
    try {
      final player = _ensureBgmPlayer();
      await player.setReleaseMode(ReleaseMode.loop);
      await player.setVolume(_isMuted ? 0.0 : 0.45);
      await player.play(UrlSource(url));
    } catch (_) {
      // Abaikan kegagalan pemutaran audio jika perangkat sedang offline atau tanpa plugin
    }
  }

  /// Menghentikan musik latar belakang.
  Future<void> stopBgm() async {
    _isBgmPlaying = false;
    if (_isTestEnvironment) {
      return;
    }
    try {
      await _bgmPlayer?.stop();
    } catch (_) {}
  }

  /// Memutar efek suara berdasarkan nama aksi: 'coin', 'click', 'success', atau 'cannon'.
  Future<void> playSfx(String sound) async {
    final key = sound.trim().toLowerCase();
    _lastPlayedSfx = key;
    if (_isMuted || _isTestEnvironment) {
      return;
    }
    final targetUrl = sfxUrls[key] ??
        (sound.startsWith('http') ? sound : sfxUrls['click']!);
    try {
      final player = _ensureSfxPlayer();
      await player.setReleaseMode(ReleaseMode.stop);
      await player.setVolume(0.85);
      await player.play(UrlSource(targetUrl));
    } catch (_) {
      // Abaikan kegagalan pemutaran SFX bila perangkat offline
    }
  }

  /// Mengaktifkan atau mematikan seluruh suara (Mute / Unmute).
  Future<void> toggleMute() async {
    await setMuted(!_isMuted);
  }

  Future<void> setMuted(bool muted) async {
    _isMuted = muted;
    notifyListeners();
    if (_isTestEnvironment) {
      return;
    }
    try {
      if (_isMuted) {
        await _bgmPlayer?.setVolume(0.0);
        await _sfxPlayer?.stop();
      } else {
        await _bgmPlayer?.setVolume(0.45);
        if (_isBgmPlaying) {
          await playBgm();
        }
      }
    } catch (_) {}
  }
}