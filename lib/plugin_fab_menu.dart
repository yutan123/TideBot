import 'package:flutter/material.dart';

import 'global_notice.dart';
import 'plugin_ecosystem_page.dart';
import 'theme.dart';

class PluginFabMenu extends StatefulWidget {
  const PluginFabMenu({super.key, required this.theme});
  final TideTheme theme;

  @override
  State<PluginFabMenu> createState() => _PluginFabMenuState();
}

class _PluginFabMenuState extends State<PluginFabMenu> {
  bool _expanded = false;

  Future<void> _importPlugin() async {
    try {
      await PluginRegistry.importManifest();
      if (mounted) GlobalNotice.show('插件已导入');
    } on FormatException catch (error) {
      if (mounted) {
        GlobalNotice.show(error.message, color: const Color(0xFFE74C3C));
      }
    } catch (error) {
      if (mounted) {
        GlobalNotice.show('导入失败：$error', color: const Color(0xFFE74C3C));
      }
    }
  }

  Widget _action(IconData icon, String tooltip, VoidCallback onPressed) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: FloatingActionButton.small(
          heroTag: tooltip,
          tooltip: tooltip,
          backgroundColor: widget.theme.surface,
          foregroundColor: widget.theme.primary,
          onPressed: onPressed,
          child: Icon(icon),
        ),
      );

  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (_expanded) ...[
            _action(
              Icons.extension_rounded,
              '插件',
              () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const PluginCenterPage())),
            ),
            _action(Icons.file_upload_rounded, '本地导入插件', _importPlugin),
            _action(
              Icons.code_rounded,
              '开发插件',
              () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const PluginDeveloperPage())),
            ),
          ],
          FloatingActionButton(
            heroTag: 'plugin_menu',
            tooltip: '插件菜单',
            backgroundColor: widget.theme.primary,
            foregroundColor: Colors.white,
            onPressed: () => setState(() => _expanded = !_expanded),
            child:
                Icon(_expanded ? Icons.close_rounded : Icons.extension_rounded),
          ),
        ],
      );
}
