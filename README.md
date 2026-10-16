<div align="center">

<img src="assets/images/logo.png" width="104" alt="TideBot 图标" />

# TideBot

**在自己的手机上，建立有记忆、有日常的 AI 陪伴。**

面向 Android 的多角色 AI 伴侣应用，集成文字对话、语音交流、多模态交互与可扩展工具。

![Android](https://img.shields.io/badge/Android-8.0%2B-3DDC84?logo=android&logoColor=white)
![Flutter](https://img.shields.io/badge/Built_with-Flutter-02569B?logo=flutter&logoColor=white)
![Dart](https://img.shields.io/badge/Dart-3.0%2B-0175C2?logo=dart&logoColor=white)
![Local First](https://img.shields.io/badge/Data-Local_First-547AA5)

[功能概览](#功能概览) · [模型与服务](#模型与服务) · [开始使用](#开始使用) · [常见问题](#常见问题) · [问题反馈](https://github.com/yutan123/TideBot/issues)

</div>

## 关于 TideBot

TideBot 希望让 AI 陪伴成为一段可以持续的日常：角色拥有自己的设定，对话中的重要信息可以留下来，聊天之外也有日记、生活日程与空间动态。你可以创建不同的角色，为它们配置模型、声音、记忆和工具，逐步建立属于自己的互动方式。

应用采用本地优先的设计，聊天记录、角色配置、记忆与媒体文件保存在设备上。模型、语音和图片服务由你选择并配置，无需自行部署 TideBot 服务端。调用远程 AI 服务时，完成请求所需的内容仍会发送至对应服务商。

## 功能概览

| 能力 | 可以做什么 |
| --- | --- |
| 多角色对话 | 创建和管理角色，配置人设与模型，保留独立聊天记录，使用流式回复和表情贴纸 |
| 记忆与世界书 | 管理角色记忆、背景设定与世界书条目，让相关信息参与后续对话，支持记忆检索与更新 |
| 角色日常 | 结合日记、生活日程、状态变化和空间动态，延续聊天之外的互动 |
| 语音交流 | 通过语音识别与语音合成进行交流，配置不同声音，并查看通话记录与摘要 |
| 多模态输入 | 发送图片、音频、视频和文件；结合图片识别、视频预处理、本机 OCR 与文档正文提取处理内容 |
| 图片生成与编辑 | 为角色设置参考图，按需生成图片；选择本轮或历史用户图片进行临时图改 |
| 工具与扩展 | 使用网络工具，导入技能包，连接远程 MCP 服务，按角色需要启用工具 |
| 提醒与设备协作 | 结合定时任务、通知与获授权的设备能力，让对话连接日常事务 |
| 个性化界面 | 日夜间主题、全局背景、聊天背景与液态玻璃效果；设置全局背景并开启玻璃选项后启用对应效果 |
| 数据管理 | 管理本地存储，导出和恢复完整备份，保留自己的角色与对话资料 |

多模态理解、工具调用、生图和语音能力取决于所选模型及接口支持；配置一个聊天模型不会自动获得全部能力。Android 后台行为也受系统权限、电池策略及厂商限制影响。

## 模型与服务

### 聊天模型

TideBot 通过 OpenAI 兼容的 Chat Completions 接口连接聊天模型，支持自定义服务地址、API Key 和模型名称。当前提供以下内置预设：

| 提供商 | 预设服务地址 | 预设模型示例 |
| --- | --- | --- |
| [DeepSeek](https://www.deepseek.com/) | `https://api.deepseek.com/v1` | `deepseek-chat` |
| [SiliconFlow（硅基流动）](https://siliconflow.cn/) | `https://api.siliconflow.cn/v1` | `Qwen/Qwen2.5-7B-Instruct` |
| [阿里云百炼](https://bailian.console.aliyun.com/) | `https://dashscope.aliyuncs.com/compatible-mode/v1` | `qwen-plus` |
| 小米 MiMo | `https://api.xiaomimimo.com/v1` | `mimo-v2-flash` |
| [Kimi / Moonshot](https://platform.moonshot.cn/) | `https://api.moonshot.cn/v1` | `moonshot-v1-8k` |
| [Gitee AI](https://ai.gitee.com/) | `https://ai.gitee.com/v1` | `Qwen2.5-7B-Instruct` |

预设用于简化填写，不代表服务商始终提供表中的模型。请以自己的账户权限与服务商最新模型列表为准。其他符合相同接口约定的服务也可手动配置，具体兼容性以连接测试和实际请求为准。

### 语音与图片

| 能力 | 当前接入方式 |
| --- | --- |
| 语音识别（STT） | SiliconFlow / OpenAI 兼容的音频转写接口，以及 MiMo 语音识别适配 |
| 语音合成（TTS） | SiliconFlow / OpenAI 兼容的语音接口，以及 MiMo、MiniMax 的独立协议适配 |
| 图片生成 | 配置支持 OpenAI 兼容 `/images/generations` 的服务与模型 |
| 用户原图编辑 | 配置支持 `/images/edits` 的服务与模型，按明确指令编辑选中的用户图片 |

聊天、语音、图片服务可以分别配置。图片编辑使用的用户图片仅作为当次编辑参考，不会替换角色的长期参考图；编辑请求失败时会返回失败信息。

### 如何选择

- **日常陪伴**：优先比较角色表达、上下文长度、回复延迟与长期使用费用。先用熟悉的提供商完成基础对话，再逐项增加能力。
- **语音交流**：分别考虑识别准确率、合成音色和响应速度，选择适合自己语言与交流习惯的 STT / TTS 组合。
- **图片与工具**：确认模型实际支持图片输入、图像编辑或工具调用，再为角色启用对应功能。
- **多服务组合**：需要在同一平台选择多种模型时，可考虑聚合服务；已有某家服务商账户时，也可以直接使用其兼容接口。

TideBot 保留提供商选择权，是为了让角色体验、预算和能力配置可以独立调整。项目没有将某个服务商设为所有场景的唯一选择。

## 开始使用

1. 从 [TideBot 更新发布页](https://github.com/yutan123/TideBot-OTA/releases) 获取适合设备的 APK 并安装。当前最低系统版本为 **Android 8.0（API 26）**。
2. 在应用的 **API 设置**中添加提供商，填写服务地址、API Key 和模型名称，并测试连接。
3. 创建角色，设置名称、人设与使用的模型，开始文字对话。
4. 按需要配置 STT、TTS 和图片服务，再启用语音、图片与工具能力。
5. 在使用过程中整理记忆与世界书，并定期导出完整备份。

麦克风、相机、通知及其他设备权限按所用功能授权；可随时在系统设置中管理。

## 扩展能力

### 技能包

可导入以 `SKILL.md` 或 `manifest.json` 为入口的技能，也支持 `.zip`、`.skill`、`.tideskill` 等包格式。技能可以携带说明与附属文件，并按配置参与角色的上下文和工具使用。

### MCP

可配置远程 MCP 服务地址与请求头，发现并管理服务提供的工具、资源和提示词。启用后，角色可以在模型支持工具调用的前提下使用对应工具。

### 外部访问

提供可选的局域网 OpenAI 兼容 API，便于其他客户端调用已配置的能力。需要使用时，在应用内配置访问密钥并限制为可信网络。

## 为什么采用这些设计

- **本地优先**：角色、记录与记忆跟随自己的设备，方便管理、删除和备份。远程推理由自行选择的服务完成。
- **Flutter + Android 原生能力**：使用 Flutter 构建统一的交互界面，通过 Kotlin 接入 Android 的后台调度、通知和设备功能。
- **兼容接口与独立适配并用**：聊天使用通用接口降低切换成本，语音等能力按服务商实际协议适配。
- **记忆与工具可配置**：将人设、世界书、记忆和外部工具组合起来，让不同角色拥有适合自己的能力范围。

## 隐私与数据

TideBot 将应用数据保存在设备上，但本地存储不等于所有 AI 处理都离线进行。调用模型、语音、图片、搜索或外部工具时，相关文字、媒体或上下文会按功能需要发送给所配置的服务。

请妥善保管 API Key 和备份文件，并在更换设备、卸载或清理应用前完成备份。模型服务的费用、可用性与数据处理规则由对应提供商决定。

## 常见问题

### 可以完全离线聊天吗？

当前项目不内置在手机上离线运行的大模型。聊天需要能访问所配置的模型服务；使用本地或局域网服务时，也需要该服务提供兼容接口。

### 为什么文字聊天正常，语音或生图却不可用？

这些能力需要分别配置。请确认对应服务的地址、密钥、模型、协议和账户权限，并检查所选模型是否支持目标功能。

### 为什么角色没有按预期使用工具或记忆？

工具调用与记忆判断会受模型能力、角色配置和当前上下文影响。请先确认相应功能已经启用、工具连接正常，再检查模型返回和应用日志。

### 是否支持 iOS 或桌面端？

当前以 Android 为目标平台，部分能力依赖 Android 原生实现。Flutter 技术栈不代表本仓库已提供其他平台的完整支持。

## 开发与反馈

项目使用 Flutter、Dart 和 Kotlin，依赖见 [pubspec.yaml](pubspec.yaml)。准备可用的 Flutter 与 Android 开发环境后：

```bash
git clone https://github.com/yutan123/TideBot.git
cd TideBot
flutter pub get
flutter run
```

欢迎通过 [Issues](https://github.com/yutan123/TideBot/issues) 反馈问题或建议。报告问题时，请附上应用版本、Android 版本、复现步骤与已隐去密钥和私人内容的日志。

## 第三方许可

实际使用的第三方组件声明见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。其中 `liquid_glass_widgets` 使用 MIT License。当前仓库尚未提供项目整体的 `LICENSE` 文件，第三方组件的许可证不代表 TideBot 整体采用相同许可。
