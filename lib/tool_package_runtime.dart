import 'tool_argument_validation.dart';
import 'tool_package_catalog.dart';

typedef PackageToolExecutor = Future<Map<String, dynamic>> Function(
    String source,
    String id,
    String toolName,
    Map<String, dynamic> arguments,
    bool referenceReader);

/// A fresh catalog is supplied for every operation so discovery never grants
/// lasting permission to tools that the user subsequently disables.
Future<Map<String, dynamic>> executeToolPackage({
  required ToolPackageCatalog catalog,
  required String name,
  required Map<String, dynamic> args,
  required PackageToolExecutor execute,
}) async {
  try {
    final packageId = args['package_id'];
    final package = packageId is String ? catalog.get(packageId) : null;
    if (package == null) throw const FormatException('工具包不存在或已停用，请重新查看可用工具包');
    if (name == 'get_tool_package')
      return {
        'result': {'ok': true, ...package}
      };
    if (name != 'call_package_tool') throw const FormatException('未知工具包操作');
    final toolName = args['tool_name'];
    final arguments = args['arguments'];
    if (toolName is! String || arguments is! Map<String, dynamic>) {
      throw const FormatException('tool_name 必须为文本，arguments 必须为 JSON 对象');
    }
    final tool = (package['tools'] as List)
        .cast<Map<String, dynamic>>()
        .where((t) => t['name'] == toolName)
        .firstOrNull;
    if (tool == null) throw const FormatException('包内工具不存在、已停用或尚未授权');
    final error = validateToolArguments(tool['parameters'], arguments);
    if (error != null)
      return {
        'result': {
          'ok': false,
          'error': error,
          'package_id': packageId,
          'tool_name': toolName,
          'parameters': tool['parameters']
        }
      };
    final id =
        packageId.toString().substring(packageId.toString().indexOf(':') + 1);
    return await execute(package['source'] as String, id, toolName, arguments,
        tool['reference_reader'] == true);
  } catch (error) {
    return {
      'result': {'ok': false, 'error': '工具包调用失败：$error'}
    };
  }
}
