import 'package:flutter/material.dart';

import 'theme.dart';

const String tideBotPluginGuide = '''TideBot Plugin Standard v2

A TideBot plugin is one installable package. A plugin may add assistant rules, remote tools, and a form page. These are capabilities of the same plugin, not separate products.

1. Start with a JSON object. Set format to tidebot.plugin/v2, use a lowercase id, and give the plugin a name, version, and description.
2. Declare only permissions the plugin needs. network permits connections to public HTTP or HTTPS tool services. TideBot does not run Dart, JavaScript, shell commands, APKs, native libraries, or arbitrary local-file operations from a plugin.
3. Put capabilities in capabilities. assistant_rules adds instructions to selected bots. tools connects a public JSON-RPC service with tools/list and tools/call. views adds a simple form whose actions invoke a declared tool.
4. Keep secrets out of a plugin file. Configure service credentials in a trusted endpoint or use revocable limited tokens. Do not put passwords, device addresses, localhost, LAN addresses, or private network URLs in a plugin.
5. Import the JSON file. TideBot statically checks it, then requires the user to grant permissions and run a connection check before enabling it.

Example:
{
  "format":"tidebot.plugin/v2",
  "id":"weather-helper",
  "name":"天气助手",
  "description":"查询公开天气服务",
  "version":"1.0.0",
  "permissions":["network"],
  "capabilities":{
    "assistant_rules":[{"name":"天气回答规则","instructions":"查询结果要标明地点和时间。","bot_ids":[]}],
    "tools":[{"name":"天气服务","url":"https://example.com/mcp","headers":{}}],
    "views":[{"title":"天气查询","fields":[{"id":"city","label":"城市"}],"actions":[{"label":"查询","tool_service":0,"tool":"weather"}]}]
  }
}

Compatibility: v1 files using skills, mcp_servers and ui can still be imported. TideBot converts them locally to this v2 structure. Remote tools use the interoperable MCP JSON-RPC tools/list and tools/call transport, while the plugin container itself is the TideBot v2 standard because no industry format covers local Flutter forms, prompt rules, permissions, and safe mobile execution together.

Security boundary: a passed scan only verifies manifest structure, blocked dangerous fields, and URL constraints. It does not certify a remote service as trustworthy. Review the plugin author and every permission before enabling.''';

class PluginDevelopmentGuidePage extends StatelessWidget {
  const PluginDevelopmentGuidePage({super.key});
  @override
  Widget build(BuildContext context) {
    final theme = TideTheme.of(context);
    return Scaffold(
      backgroundColor: theme.bgColor,
      appBar:
          AppBar(title: const Text('插件开发文档'), backgroundColor: theme.bgColor),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: SelectableText(tideBotPluginGuide,
            style: TextStyle(
                fontFamily: 'monospace',
                height: 1.55,
                color: theme.textStrong)),
      ),
    );
  }
}
