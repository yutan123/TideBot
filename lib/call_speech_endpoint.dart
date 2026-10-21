import 'dart:math';

/// Energy-based endpoint detection. This does not perform speech recognition.
class CallSpeechEndpoint {
  final List<double> _levels = [];
  int? lastSampleMs;
  int? _candidateMs;
  int? _lastVoiceMs;
  double? _peak;
  bool speechDetected = false;
  double noiseFloor = -65;
  double gate = -52;

  void reset() {
    _levels.clear();
    lastSampleMs = _candidateMs = _lastVoiceMs = null;
    _peak = null;
    speechDetected = false;
    noiseFloor = -65;
    gate = -52;
  }

  bool add(double level, int elapsedMs) {
    if (!level.isFinite) return false;
    level = level.clamp(-80, 0);
    lastSampleMs = elapsedMs;
    if (!speechDetected || level < gate) {
      _levels.add(level);
      if (_levels.length > 30) _levels.removeAt(0);
    }
    final sorted = [..._levels]..sort();
    // Low-energy samples track the room without following every spoken peak.
    noiseFloor = _levels.length < 5
        ? -65
        : sorted[(sorted.length * .2).floor()].clamp(-75, -35);
    final startGate = max(-55.0, min(-38.0, noiseFloor + 9));
    gate = speechDetected
        ? max(startGate - 3, (_peak ?? startGate) - 12)
        : startGate;
    final voice = level >= gate;
    if (voice) {
      _candidateMs ??= elapsedMs;
      // One transient does not extend the turn; require sustained energy.
      if (elapsedMs - _candidateMs! >= 180) {
        speechDetected = true;
        _lastVoiceMs = elapsedMs;
        _peak = _peak == null ? level : max(level, _peak! - .4);
      }
    } else {
      _candidateMs = null;
    }
    return voice;
  }

  String? stopReason(int elapsedMs) {
    if (elapsedMs >= 120000) return 'maximum_duration';
    final last = lastSampleMs;
    if (elapsedMs >= 5000 && (last == null || elapsedMs - last >= 3000)) {
      return 'amplitude_unavailable';
    }
    if (speechDetected &&
        _lastVoiceMs != null &&
        elapsedMs - _lastVoiceMs! >= 1000) {
      return 'speech_ended';
    }
    // No periodic empty STT requests when the caller has not spoken.
    return null;
  }
}
