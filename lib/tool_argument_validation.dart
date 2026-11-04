import 'dart:convert';

/// Validate common JSON Schema constraints before dispatch. Unknown extension
/// keywords remain the executor's responsibility; no values are coerced.
String? validateToolArguments(dynamic schema, dynamic value) {
  String? visit(dynamic node, dynamic data, String path, int depth) {
    if (depth > 64) return '$path：参数或 Schema 嵌套过深';
    if (node == false) return '$path：不允许此参数';
    if (node is! Map) return null;
    final ref = node[r'$ref'];
    if (ref is String && ref.startsWith('#/')) {
      dynamic target = schema;
      for (final key in ref.substring(2).split('/')) {
        target = target is Map
            ? target[key.replaceAll('~1', '/').replaceAll('~0', '~')]
            : null;
      }
      if (target == null) return '$path：参数定义引用不存在 $ref';
      final error = visit(target, data, path, depth + 1);
      if (error != null) return error;
    }
    bool equal(dynamic a, dynamic b) {
      if (a is num && b is num) return a == b;
      if (a is Map && b is Map)
        return a.length == b.length &&
            a.keys.every((k) => b.containsKey(k) && equal(a[k], b[k]));
      if (a is List && b is List)
        return a.length == b.length &&
            List.generate(a.length, (i) => i).every((i) => equal(a[i], b[i]));
      return a == b;
    }

    if (node.containsKey('const') && !equal(node['const'], data))
      return '$path：必须为 ${jsonEncode(node['const'])}';
    if (node['enum'] is List &&
        !(node['enum'] as List).any((v) => equal(v, data)))
      return '$path：必须为 ${jsonEncode(node['enum'])} 中的值';
    for (final key in ['allOf', 'anyOf', 'oneOf']) {
      if (node[key] is! List) continue;
      final choices = node[key] as List;
      final passed =
          choices.where((s) => visit(s, data, path, depth + 1) == null).length;
      if ((key == 'allOf' && passed != choices.length) ||
          (key == 'anyOf' && passed == 0) ||
          (key == 'oneOf' && passed != 1))
        return '$path：不符合 $key 参数结构，请按工具定义填写';
    }
    if (node.containsKey('not') &&
        visit(node['not'], data, path, depth + 1) == null)
      return '$path：符合禁止的参数结构';
    if (node.containsKey('if')) {
      final branch =
          visit(node['if'], data, path, depth + 1) == null ? 'then' : 'else';
      final error = visit(node[branch], data, path, depth + 1);
      if (error != null) return error;
    }
    bool matches(dynamic type) => switch (type) {
          'object' => data is Map,
          'array' => data is List,
          'string' => data is String,
          'boolean' => data is bool,
          'null' => data == null,
          'number' => data is num && data.isFinite,
          'integer' =>
            data is num && data.isFinite && data == data.roundToDouble(),
          _ => true,
        };
    final type = node['type'];
    if (type != null && !(type is List ? type.any(matches) : matches(type)))
      return '$path：需要 $type 类型';
    if (data is Map) {
      for (final key
          in node['required'] is List ? node['required'] as List : const []) {
        if (!data.containsKey(key)) return '$path.$key：缺少必填参数';
      }
      final properties =
          node['properties'] is Map ? node['properties'] as Map : const {};
      final patterns = node['patternProperties'] is Map
          ? node['patternProperties'] as Map
          : const {};
      for (final key in data.keys) {
        bool known = properties.containsKey(key);
        if (known) {
          final error =
              visit(properties[key], data[key], '$path.$key', depth + 1);
          if (error != null) return error;
        }
        for (final pattern in patterns.keys) {
          if (RegExp(pattern.toString()).hasMatch(key.toString())) {
            known = true;
            final error =
                visit(patterns[pattern], data[key], '$path.$key', depth + 1);
            if (error != null) return error;
          }
        }
        if (!known) {
          final error = visit(
              node['additionalProperties'], data[key], '$path.$key', depth + 1);
          if (error != null) return error;
        }
      }
      if (node['minProperties'] is num && data.length < node['minProperties'])
        return '$path：属性数量过少';
      if (node['maxProperties'] is num && data.length > node['maxProperties'])
        return '$path：属性数量过多';
    }
    if (data is List) {
      if (node['minItems'] is num && data.length < node['minItems'])
        return '$path：数组元素过少';
      if (node['maxItems'] is num && data.length > node['maxItems'])
        return '$path：数组元素过多';
      for (var i = 0; i < data.length; i++) {
        final prefix = node['prefixItems'] ??
            (node['items'] is List ? node['items'] : null);
        final item = prefix is List && i < prefix.length
            ? prefix[i]
            : node['items'] is List
                ? node['additionalItems']
                : node['items'];
        final error = visit(item, data[i], '$path[$i]', depth + 1);
        if (error != null) return error;
        if (node['uniqueItems'] == true &&
            data.take(i).any((v) => equal(v, data[i])))
          return '$path[$i]：数组元素不能重复';
      }
    }
    if (data is String) {
      final length = data.runes.length;
      if (node['minLength'] is num && length < node['minLength'])
        return '$path：文本过短';
      if (node['maxLength'] is num && length > node['maxLength'])
        return '$path：文本过长';
      if (node['pattern'] is String && !RegExp(node['pattern']).hasMatch(data))
        return '$path：文本不符合 ${node['pattern']}';
    }
    if (data is num) {
      if (node['minimum'] is num && data < node['minimum'])
        return '$path：不能小于 ${node['minimum']}';
      if (node['maximum'] is num && data > node['maximum'])
        return '$path：不能大于 ${node['maximum']}';
      if (node['exclusiveMinimum'] is num && data <= node['exclusiveMinimum'])
        return '$path：必须大于 ${node['exclusiveMinimum']}';
      if (node['exclusiveMaximum'] is num && data >= node['exclusiveMaximum'])
        return '$path：必须小于 ${node['exclusiveMaximum']}';
      final multiple = node['multipleOf'];
      if (multiple is num &&
          multiple > 0 &&
          ((data / multiple) - (data / multiple).round()).abs() > 1e-9)
        return '$path：必须为 $multiple 的倍数';
    }
    return null;
  }

  return visit(schema, value, 'arguments', 0);
}
