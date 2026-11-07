# 第三方声明

TideBot 使用第三方开源组件。以下声明保留实际依赖组件的版权和许可信息；仅作为设计参考或灵感来源、未使用其代码或资源的项目不列入此清单。

| 组件 | 用途 | 许可证 |
| --- | --- | --- |
| [BGE small zh v1.5](https://huggingface.co/BAAI/bge-small-zh-v1.5) / [Xenova ONNX weights](https://huggingface.co/Xenova/bge-small-zh-v1.5) | 内置中文记忆语义检索模型和词表；固定 ONNX 修订版 `75c43b069aac4d136ba6bc1122f995fedcfd2781`，本地离线计算 | [MIT License](../android/app/src/main/assets/memory_embedding/LICENSE)，上游 FlagEmbedding 版权声明随附 |
| [LXGW Marker Gothic / 霞鹜漫黑](https://github.com/lxgw/LxgwMarkerGothic) | 应用主字体 `LXGWMarkerGothic-Regular.ttf`；Flutter 字体族别名继续使用 `TideFont`，字体内容未修改 | [SIL Open Font License 1.1](../assets/fonts/LXGWMarkerGothic-OFL.txt)，[原始版权及重命名说明](../assets/fonts/LXGWMarkerGothic-NOTICE.txt) |
| [EmojiTwo](https://github.com/EmojiTwo/emojitwo/) / [EmojiOne 2.2](https://www.emojione.com)（原作者 Ranks.com，后由 EmojiTwo 社区贡献） | 聊天表情面板；2,023 张 PNG 及 `emoji.json` 均与上游固定快照一致，未修改内容 | 图像为 [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/legalcode)，JSON 索引为 MIT；[上游许可](../assets/emojitwo/LICENSE.md)、[署名及来源](../assets/emojitwo/NOTICE.md) |
| Droid Sans Mono | 日志英文、数字和代码的内置等宽字体（`LogMono.ttf`），与 Android `monospace` 的字体族对齐 | [Apache License 2.0](../assets/fonts/LogMono-LICENSE.txt)，Digitized data copyright © 2007, Google Corporation. |
| Noto Sans CJK SC | 日志中文的内置无衬线字体（`LogSansSC.otf`） | [SIL Open Font License 1.1](../assets/fonts/LogSansSC-OFL.txt)，版权声明见随附许可 |
| [liquid_glass_widgets](https://github.com/sdegenaar/liquid_glass_widgets) | 通过 Flutter 包依赖提供液态玻璃界面效果 | [MIT License](../third_party/licenses/liquid_glass_widgets-LICENSE.txt)，Copyright (c) 2024–2026 Sebastian Degenaar |
| [ffmpeg_kit_flutter_new](https://github.com/sk3llo/ffmpeg_kit_flutter)（4.6.7） | 视频抽帧、音频提取与 H.264 压缩；Android 原生依赖为 `com.antonkarpenko:ffmpeg-kit-full-gpl:2.2.3` | Flutter 插件采用 [LGPL-3.0](../third_party/licenses/ffmpeg_kit_flutter_new-LICENSE.txt)；Full GPL 原生版本包含 x264 等 GPL 组件，适用 [GPL-3.0](../third_party/licenses/GPL-3.0.txt) 及各组件随附许可 |

FFmpegKit Android 原生代码、构建脚本及各编解码器来源见 [ffmpeg_kit_flutter_android（Full GPL）](https://github.com/sk3llo/ffmpeg_kit_flutter_android/tree/full-gpl)。该版本支持视频压缩使用的 `libx264`；其 GPL 组件保留 GPL-3.0 许可，与项目 AGPL-3.0 代码的组合按相应许可证要求分发。

锁定 Flutter/Dart 包、传递依赖、SDK、原生依赖声明及附加许可见后续逐项清单。每项许可保留原版权人及全文；本项目版权人为 yutan123，不改变任何第三方的权利。


## 原生库、SDK 和附加版权说明

- **Flutter / Dart / Flutter Engine**：应用界面与运行时。除 Flutter 和 Dart 的 BSD 条款外，Engine 包含 Skia、ICU、HarfBuzz、FreeType、BoringSSL、zlib 等上游组件；完整原始版权和多项许可保存在后续 `sky_engine` 条目的综合 LICENSE 中，不能只用一个 BSD 标签代替。Material 图标及 Cupertino 图标许可分别随 Engine/Flutter 和 `cupertino_icons` 保留。
- **Rive 及其 C/C++ 组件**：Rive 动画；`rive_common` 的 Android CMake 实际编译 `ios/` 目录下的 rive-cpp、HarfBuzz、SheenBidi、Yoga，并启用 miniaudio。原始 MIT、Apache 及其他许可/版权声明已按包目录保留。`image` 的移植算法等附加声明见其 `LICENSE-other.md`，不能只保留主 MIT 许可。
- **ONNX Runtime Android 1.20.0**：`com.microsoft.onnxruntime:onnxruntime-android:1.20.0`，本地模型推理。项目采用 MIT；原始版权和依赖声明以 [该版本 LICENSE](https://github.com/microsoft/onnxruntime/blob/v1.20.0/LICENSE) 和 [ThirdPartyNotices.txt](https://github.com/microsoft/onnxruntime/blob/v1.20.0/ThirdPartyNotices.txt) 为准。它与 BGE 模型是不同组件。
- **AndroidX**：WorkManager、Core、CameraX、Media3、WebKit、Security Crypto、DataStore、Preference、Lifecycle 等，由应用和 Flutter 插件引入，通常为 Apache-2.0；具体模块按各 POM 和随附 NOTICE 保留。
- **Kotlin / kotlinx.coroutines、Guava、OkHttp / Okio、Gson、Tink、desugar_jdk_libs**：分别用于 Kotlin 运行时、协程、并发集合、HTTP、序列化、加密及 Java API 回移。具体版本以声明及最终解析结果为准；各自的 Apache/BSD 等原始许可不能被项目 AGPL 覆盖。
- **Google ML Kit 中文文字识别**：`com.google.mlkit:text-recognition-chinese:16.0.1`，用于 OCR。它是受 [ML Kit 服务条款](https://developers.google.com/ml-kit/terms) 约束的第三方 SDK，不能整体标成 Apache-2.0 或本项目开源代码。关联 Google Play services 模块按 [Android SDK License](https://developer.android.com/studio/terms.html) 及其附带声明处理；这些 SDK 内的开源组件仍保留自身许可。
- **FFmpegKit Full GPL**：插件及本项目指定的 Full GPL 原生制品用于音视频处理，包含 FFmpeg 与 x264 等组件。插件上游 README 的包矩阵也已保存；它说明可用的包组合，不能当成最终发布制品中全部编解码器的精确版本清单。GPL/LGPL 义务包括适用情况下提供对应源码和构建/重新链接材料，仅附上一份许可证不替代这些义务。

本清单区分本地包含的代码/资源、源码开发依赖及第三方非开源 SDK。用户自行配置的模型 API、搜索服务和网页平台适用各自服务条款，不因被调用就成为本应用再分发的开源组件。只作为设计灵感、未使用代码或资源的项目不虚构列入。
