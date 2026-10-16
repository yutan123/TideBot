# 第三方声明

TideBot 使用开源依赖，并在开发中参考过以下项目。完整参考工程、演示资源和 APK 不随本仓库保留；对应许可与原始声明保存在 `third_party/licenses/`。以下清单用于保留这些参考来源的归属，不替代其他依赖自身的许可证。

| 项目 | 使用或参考方式 | 许可证与声明 |
| --- | --- | --- |
| [liquid_glass_widgets](https://github.com/sdegenaar/liquid_glass_widgets) | 液态玻璃 Flutter 依赖，通过 `pubspec.yaml` / `pubspec.lock` 获取；开发时也参考过其源码 | [MIT License](third_party/licenses/liquid_glass_widgets-LICENSE.txt)，Copyright (c) 2024–2026 Sebastian Degenaar |
| Liquid Glass (Backdrop)，原参考目录名 AndroidLiquidGlass-kmp | 液态玻璃效果开发参考；不是 TideBot 的本地构建依赖。[项目文档](https://kyant.gitbook.io/backdrop) | [Apache License 2.0](third_party/licenses/AndroidLiquidGlass-kmp-LICENSE.txt) |
| [Jev 聊天助手](https://github.com/jev-chat/jev-chat-jarvis) | 开发参考来源；保留原始版权和出处声明 | [MIT License](third_party/licenses/jev-chat-jarvis-LICENSE.txt)、[原始 NOTICE](third_party/licenses/jev-chat-jarvis-NOTICE.txt)，Copyright (c) 2026 Finderchangchang and the jev-chat contributors |

Jev 聊天助手为本项目的开发参考来源。上述项目及作者不因被列入本声明而为 TideBot 背书。

Flutter / Dart 包的完整依赖及锁定版本见 `pubspec.yaml` 和 `pubspec.lock`；各依赖的许可证仍按其自身条款适用。
