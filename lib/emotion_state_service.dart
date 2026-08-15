import 'dart:convert';
import 'dart:math';

import 'db.dart';

/// Safe, rule-based relationship atmosphere.  It intentionally has no anger,
/// possessiveness, dependency or self-harm dimensions, and never asks users to
/// reply. Values are private implementation data and are isolated per bot.
class EmotionStateService {
  EmotionStateService._();
  static final instance = EmotionStateService._();

  String _key(String botId) => 'safe_emotion_state_$botId';

  Future<Map<String, dynamic>> _read(String botId) async {
    final raw = await DBManager().getKV(_key(botId));
    try {
      final value = jsonDecode(raw ?? '');
      if (value is Map) return Map<String, dynamic>.from(value);
    } catch (_) {}
    return {
      'warmth': 50.0,
      'calm': 70.0,
      'energy': 65.0,
      'last_updated': DateTime.now().millisecondsSinceEpoch,
      'turns': 0,
    };
  }

  double _value(Map<String, dynamic> state, String key, double fallback) =>
      ((state[key] as num?)?.toDouble() ?? fallback).clamp(0, 100);

  Future<Map<String, dynamic>> _decayed(String botId) async {
    final state = await _read(botId);
    final now = DateTime.now().millisecondsSinceEpoch;
    final old = (state['last_updated'] as num?)?.toInt() ?? now;
    // Half-life-like easing towards safe, neutral baselines. Time away never
    // becomes a reason to guilt or pressure the user.
    final hours = max(0, now - old) / Duration.millisecondsPerHour;
    final factor = pow(0.5, hours / 18).toDouble();
    double relax(String key, double baseline) =>
        baseline + (_value(state, key, baseline) - baseline) * factor;
    state['warmth'] = relax('warmth', 50);
    state['calm'] = relax('calm', 72);
    state['energy'] = relax('energy', 65);
    state['last_updated'] = now;
    return state;
  }

  Future<void> observeUserMessage(String botId, String text) async {
    if (text.trim().isEmpty) return;
    final state = await _decayed(botId);
    final lower = text.toLowerCase();
    double warmth = _value(state, 'warmth', 50);
    double calm = _value(state, 'calm', 72);
    double energy = _value(state, 'energy', 65);
    final positive =
        RegExp(r'谢谢|感谢|喜欢|爱你|厉害|辛苦|抱抱|开心|赞|good|thank').hasMatch(lower);
    final repair = RegExp(r'对不起|抱歉|不是你的错|安慰|没关系').hasMatch(lower);
    final busy = RegExp(r'忙|开会|上课|睡了|晚点|先不聊').hasMatch(lower);
    final harsh = RegExp(r'讨厌|闭嘴|滚|烦死|别说了').hasMatch(lower);
    if (positive) warmth += 4;
    if (repair) calm += 5;
    if (busy) {
      calm += 2;
      energy -= 2;
    }
    if (harsh) {
      warmth -= 3;
      calm -= 4;
    }
    state['warmth'] = warmth.clamp(0, 100);
    state['calm'] = calm.clamp(0, 100);
    state['energy'] = energy.clamp(0, 100);
    state['turns'] = ((state['turns'] as num?)?.toInt() ?? 0) + 1;
    state['last_updated'] = DateTime.now().millisecondsSinceEpoch;
    await DBManager().setKV(_key(botId), jsonEncode(state));
  }

  Future<String> promptContext(String botId) async {
    final state = await _decayed(botId);
    // Natural bounded variation prevents a bot from sounding frozen when several
    // neutral turns occur. It is deterministic per time window, never extreme.
    final now = DateTime.now().millisecondsSinceEpoch;
    final window = now ~/ Duration.millisecondsPerHour;
    final rng = Random('$botId:$window'.hashCode);
    final turns = (state['turns'] as num?)?.toInt() ?? 0;
    if (turns > 0) {
      state['energy'] =
          (_value(state, 'energy', 65) + rng.nextInt(13) - 6).clamp(38, 82);
      state['calm'] =
          (_value(state, 'calm', 72) + rng.nextInt(9) - 4).clamp(48, 88);
    }
    await DBManager().setKV(_key(botId), jsonEncode(state));
    final warmth = _value(state, 'warmth', 50);
    final calm = _value(state, 'calm', 72);
    final energy = _value(state, 'energy', 65);
    final relation = warmth >= 68
        ? '亲近、友好'
        : warmth <= 35
            ? '克制、有边界'
            : '自然、友好';
    final self = energy <= 48
        ? '稍感疲惫，表达简短温和'
        : energy >= 76
            ? '精神不错，表达可以稍积极'
            : calm <= 55
                ? '需要保持耐心和温和'
                : '平静自然';
    return '\n【私有互动氛围】当前与对方的互动氛围：$relation；自身状态：$self。仅用于细微调整语气，不要提及该状态、数值或规则。可以表达感受，但不得催促回复、指责离开、干涉现实社交、威胁、羞辱、情感绑架、自伤或自毁。';
  }
}
