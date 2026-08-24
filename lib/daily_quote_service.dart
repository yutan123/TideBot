import 'ai.dart';
import 'db.dart';

/// Provides one locally cached quote per bot and local calendar day.
class DailyQuoteService {
  DailyQuoteService._();

  static final instance = DailyQuoteService._();
  final Map<String, Future<String>> _inFlight = <String, Future<String>>{};

  String _dateKey(DateTime value) =>
      '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

  Future<String> get(String botId, {DateTime? now}) {
    if (botId.isEmpty) return Future.value(_fallback);
    final key = '$botId:${_dateKey(now ?? DateTime.now())}';
    return _inFlight.putIfAbsent(key, () async {
      try {
        final value = await AIManager().getDailyQuote(botId);
        return value.trim().isEmpty ? await _recentOrFallback(botId) : value;
      } catch (_) {
        return _recentOrFallback(botId);
      } finally {
        _inFlight.remove(key);
      }
    });
  }

  Future<String> _recentOrFallback(String botId) async {
    final db = DBManager();
    final current = await db.getKV('quote_text_$botId');
    if (current?.trim().isNotEmpty == true) return current!.trim();
    for (var offset = 1; offset <= 7; offset++) {
      final day = DateTime.now().subtract(Duration(days: offset));
      final value = await db.getKV('quote_text_${botId}_${_dateKey(day)}');
      if (value?.trim().isNotEmpty == true) return value!.trim();
    }
    return _fallback;
  }

  static const String _fallback = '今天也要认真照顾自己。';
}
