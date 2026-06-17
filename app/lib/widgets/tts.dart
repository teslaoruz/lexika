import 'package:flutter_tts/flutter_tts.dart';

/// Device-native text-to-speech for word pronunciation (plan 5.8 — free, no
/// backend). ponytail: one shared engine, lazy-initialised, English voice.
/// Any failure is swallowed (e.g. Linux desktop has no TTS engine) so a tap
/// never throws. Upgrade path: play the dictionary `audio_url` mp3 when present
/// for a real human voice, fall back to this.
final FlutterTts _tts = FlutterTts();
bool _inited = false;

Future<void> ttsSpeak(String text) async {
  text = text.trim();
  if (text.isEmpty) return;
  try {
    if (!_inited) {
      await _tts.setLanguage('en-US');
      await _tts.setSpeechRate(0.45); // native default is too fast for learners
      _inited = true;
    }
    await _tts.stop(); // interrupt a previous word if still speaking
    await _tts.speak(text);
  } catch (_) {
    // no TTS engine on this platform — silent, button still wiggles
  }
}
