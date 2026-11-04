# 第三方声明

TideBot 使用第三方开源组件。以下声明保留实际依赖组件的版权和许可信息；仅作为设计参考或灵感来源、未使用其代码或资源的项目不列入此清单。

| 组件 | 用途 | 许可证 |
| --- | --- | --- |
| [BGE small zh v1.5](https://huggingface.co/BAAI/bge-small-zh-v1.5) / [Xenova ONNX weights](https://huggingface.co/Xenova/bge-small-zh-v1.5) | 内置中文记忆语义检索模型和词表；固定 ONNX 修订版 `75c43b069aac4d136ba6bc1122f995fedcfd2781`，本地离线计算 | [MIT License](android/app/src/main/assets/memory_embedding/LICENSE)，上游 FlagEmbedding 版权声明随附 |
| [LXGW Marker Gothic / 霞鹜漫黑](https://github.com/lxgw/LxgwMarkerGothic) | 应用主字体 `LXGWMarkerGothic-Regular.ttf`；Flutter 字体族别名继续使用 `TideFont`，字体内容未修改 | [SIL Open Font License 1.1](assets/fonts/LXGWMarkerGothic-OFL.txt)，[原始版权及重命名说明](assets/fonts/LXGWMarkerGothic-NOTICE.txt) |
| [EmojiTwo](https://github.com/EmojiTwo/emojitwo/) / [EmojiOne 2.2](https://www.emojione.com)（原作者 Ranks.com，后由 EmojiTwo 社区贡献） | 聊天表情面板；2,023 张 PNG 及 `emoji.json` 均与上游固定快照一致，未修改内容 | 图像为 [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/legalcode)，JSON 索引为 MIT；[上游许可](assets/emojitwo/LICENSE.md)、[署名及来源](assets/emojitwo/NOTICE.md) |
| Droid Sans Mono | 日志英文、数字和代码的内置等宽字体（`LogMono.ttf`），与 Android `monospace` 的字体族对齐 | [Apache License 2.0](assets/fonts/LogMono-LICENSE.txt)，Digitized data copyright © 2007, Google Corporation. |
| Noto Sans CJK SC | 日志中文的内置无衬线字体（`LogSansSC.otf`） | [SIL Open Font License 1.1](assets/fonts/LogSansSC-OFL.txt)，版权声明见随附许可 |
| [liquid_glass_widgets](https://github.com/sdegenaar/liquid_glass_widgets) | 通过 Flutter 包依赖提供液态玻璃界面效果 | [MIT License](third_party/licenses/liquid_glass_widgets-LICENSE.txt)，Copyright (c) 2024–2026 Sebastian Degenaar |
| [ffmpeg_kit_flutter_new](https://github.com/sk3llo/ffmpeg_kit_flutter)（4.6.7） | 视频抽帧、音频提取与 H.264 压缩；Android 原生依赖为 `com.antonkarpenko:ffmpeg-kit-full-gpl:2.2.3` | Flutter 插件采用 [LGPL-3.0](third_party/licenses/ffmpeg_kit_flutter_new-LICENSE.txt)；Full GPL 原生版本包含 x264 等 GPL 组件，适用 [GPL-3.0](third_party/licenses/GPL-3.0.txt) 及各组件随附许可 |

FFmpegKit Android 原生代码、构建脚本及各编解码器来源见 [ffmpeg_kit_flutter_android（Full GPL）](https://github.com/sk3llo/ffmpeg_kit_flutter_android/tree/full-gpl)。该版本支持视频压缩使用的 `libx264`；其 GPL 组件保留 GPL-3.0 许可，与项目 AGPL-3.0 代码的组合按相应许可证要求分发。

此表不是全部传递依赖的许可证清单。完整 Flutter / Dart 依赖与锁定版本见 [pubspec.yaml](pubspec.yaml) 和 [pubspec.lock](pubspec.lock)；各组件的版权和许可证以其随附文件为准。
