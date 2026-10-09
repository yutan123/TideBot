/// Reassembles OpenAI tool-call deltas without losing earlier fragments.
class ToolCallAccumulator {
  final _calls = <int, Map<String, dynamic>>{};

  void add(List<dynamic> fragments, {bool snapshot = false}) {
    for (var position = 0; position < fragments.length; position++) {
      final fragment = fragments[position];
      if (fragment is! Map) continue;
      final index = (fragment['index'] as num?)?.toInt() ?? position;
      final call = _calls.putIfAbsent(
          index,
          () => {
                'id': '',
                'type': 'function',
                'function': <String, dynamic>{'name': '', 'arguments': ''},
              });
      if (fragment['id'] != null) call['id'] = fragment['id'].toString();
      if (fragment['type'] != null) call['type'] = fragment['type'];
      final function = fragment['function'];
      if (function is! Map) continue;
      final target = call['function'] as Map<String, dynamic>;
      for (final key in ['name', 'arguments']) {
        if (function[key] == null) continue;
        final value = function[key].toString();
        target[key] = snapshot ? value : '${target[key]}$value';
      }
    }
  }

  List<Map<String, dynamic>> get calls {
    final indexes = _calls.keys.toList()..sort();
    return indexes
        .map((index) => {
              ..._calls[index]!,
              'function':
                  Map<String, dynamic>.from(_calls[index]!['function'] as Map),
            })
        .toList();
  }
}
