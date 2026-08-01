import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';

/// 生态插件与外部模型挂载层 (plug.dart)
/// 负责无服务器状态下的外部扩展、本地轻量模型下载管理、以及远程配置拉取
class PlugManager {
  /// 从官方仓库拉取预设和生态插件信息
  static const String _pluginRegistryUrl = "https://raw.githubusercontent.com/YourRepo/TideBot-Plugins/main/registry.json";

  /// 1. 初始化检查：应用冷启动时对比版本号，判断是否有新插件
  static Future<void> checkForUpdates() async {
    try {
      final response = await http.get(Uri.parse(_pluginRegistryUrl)).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final prefs = await SharedPreferences.getInstance();
        final localVersion = prefs.getString('plugin_version') ?? '0.0.0';
        
        if (data['version'] != localVersion) {
          await prefs.setString('plugin_version', data['version']);
          // 更新本地 SQLite 词库等逻辑...
        }
      }
    } catch (e) {
      // 纯本地应用，如果 GitHub 连不上直接忽略
      print("Plugin registry fetch bypassed: $e");
    }
  }

  /// 2. 本地化轻量模型引擎下载器（供 API设置 - 本地模型板块 使用）
  /// 参数: modelId(模型标识), downloadUrl(直连链接), onProgress(下载进度回调)
  static Future<bool> downloadLocalModel(
      String modelId, 
      String downloadUrl, 
      Function(double) onProgress) async {
    try {
      final request = http.Request('GET', Uri.parse(downloadUrl));
      final response = await http.Client().send(request).timeout(const Duration(seconds: 30));
      final contentLength = response.contentLength ?? 0;
      
      int bytesDownloaded = 0;
      List<int> bytes = [];

      // 监听数据流，用于在 UI 显示下载进度条
      await for (var newBytes in response.stream) {
        bytes.addAll(newBytes);
        bytesDownloaded += newBytes.length;
        if (contentLength > 0) {
          onProgress(bytesDownloaded / contentLength);
        }
      }

      // 写入设备沙盒目录
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/$modelId.bin');
      await file.writeAsBytes(bytes);

      return true;
    } catch (e) {
      print("Local model download failed: $e");
      return false;
    }
  }

  /// 3. 从云端/内置生态拉取官方维护的最新预设配置字典（真实接口请求）
  /// 用于获取由社区和开发者共同维护的最优 System Prompt 和人物设定
  static Future<List<Map<String, dynamic>>> fetchPromptMarket() async {
    try {
      // 真实请求官方维护的预设库 JSON 文件
      final response = await http.get(
        Uri.parse("https://raw.githubusercontent.com/YourRepo/TideBot-Plugins/main/prompts_market.json")
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        // 如果成功拉取，则返回真实的在线数据
        final List<dynamic> data = jsonDecode(response.body);
        return data.map((e) => e as Map<String, dynamic>).toList();
      } else {
        throw Exception("Status code: ${response.statusCode}");
      }
    } catch (e) {
      // 如果断网或无法访问，返回硬编码的保底空数组，严格禁止使用任何虚假模拟数据！
      // 正式环境遇到错误应返回空，由 UI 层提示用户检查网络
      print("Failed to fetch prompt market: $e");
      return [];
    }
  }
}
