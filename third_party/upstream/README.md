# 上游证据来源

此目录只保存声明、许可证和 Maven 元数据，不包含下载的 AAR 二进制，也不执行其中的代码。

- `maven/<group>/<artifact>/<version>/download/*.pom`：按坐标从 Maven Central 或 Google Maven 下载的原始 POM。URL 由坐标还原，并记录在生成清单的组件来源中。父 POM 和 BOM 用于继承许可及解析声明版本；这不等于 Gradle 的最终版本选择。
- `onnxruntime-1.20.0/LICENSE`、`ThirdPartyNotices.txt`：分别来自 `https://raw.githubusercontent.com/microsoft/onnxruntime/v1.20.0/LICENSE` 和同目录的 `ThirdPartyNotices.txt`，保留微软及各第三方原始声明。
- `Apache-2.0.txt`：`https://www.apache.org/licenses/LICENSE-2.0.txt`，只关联到 POM、父 POM 或原始源码明确采用 Apache-2.0 的组件。
- `javax.inject-1/Inject.java`：从 `https://repo.maven.apache.org/maven2/javax/inject/javax.inject/1/javax.inject-1-sources.jar` 提取的原始文件，保留 `Copyright (C) 2009 The JSR-330 Expert Group` 和 Apache-2.0 声明。
- `ffmpeg-kit-full-gpl-2.2.3/LICENSE`、`README.md`、`android/README.md`、`android/build.gradle.kts`：来源为 `https://github.com/sk3llo/ffmpeg_kit_flutter_android/tree/bbdc89a142fa40b548e5049dddecffd0c1419417`。该固定提交用于保留取证时的上游声明，不据此断言该提交就是 Maven 制品的完整构建源码。
- `ffmpeg-kit-full-gpl-2.2.3/AAR-CONTENTS.json`：从 `https://repo.maven.apache.org/maven2/com/antonkarpenko/ffmpeg-kit-full-gpl/2.2.3/ffmpeg-kit-full-gpl-2.2.3.aar` 的 ZIP 目录读取文件名、大小及 CRC32；目录中没有独立的 LICENSE/NOTICE。CRC32 仅为归档元数据，不替代 SHA-256 完整性校验。
- `ffmpeg-kit-full-gpl-2.2.3/ARM64-CONFIGURATION.txt`：从上述 AAR 的 `jni/arm64-v8a/libavutil.so` 只读提取配置及版本字符串，没有运行二进制。启用项证明该 ABI 的编译配置，不能证明所有 ABI、所有传递库的完整版本和版权信息。制品还包含 `libc++_shared.so`；它的对应 NDK/LLVM 版本及完整随附声明同样需要构建方提供。
- `ffmpeg-kit-full-gpl-2.2.3/FFmpeg-n8.1.2/`：来自 `https://raw.githubusercontent.com/FFmpeg/FFmpeg/n8.1.2/` 下的 `LICENSE.md`、`COPYING.GPLv3`、`COPYING.LGPLv3`。该版本名与制品 POM 和 ARM64 字符串一致，不代表已经取得 fork 的全部修改和对应源码。

生成文件的逐文件 SHA-256 见 `../notices_manifest.json`。`update_notices.py` 离线读取这些材料及本地 SDK/依赖缓存；`fetch_upstream_notices.py` 可补取清单中缺少的 POM，下载后需重新生成，直到没有缺失的父 POM、BOM 或普通 POM。工具均不调用构建，也不上传任何内容。
