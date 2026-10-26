import 'android_selection_menu.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'main.dart';
import 'ota_update.dart';
import 'theme.dart';

const String tideBotLegalText = '''TideBot 用户协议与免责声明

请在使用前阅读本协议，尤其是数据传输、工具权限与责任限制条款。首次使用时，请明确勾选同意并确认已满 18 周岁；不同意时可退出应用。

一、应用定位与使用资格
TideBot 是本地优先的 AI 伴侣与智能交互工具，提供角色对话、记忆、日程、语音、图片、视频和可扩展工具等功能。当前面向年满 18 周岁的用户。虚拟角色与 AI 回复不是真人的承诺，也不能替代现实中的人际支持或专业服务。

二、模型与第三方服务
聊天、语音识别、语音合成、生图、搜索等能力依赖您配置或启用的服务。您需要自行取得合法的服务访问权限，核对服务地址、费用、配额、使用条款和隐私政策。相关调用可能产生费用，能力与可用性会受提供方、网络及设备限制影响。
请妥善保管 API Key，不要将密钥、私人对话或敏感资料交给不可信的服务、技能包或 MCP 服务。

三、AI 输出与重要决定
AI 生成的文字、图片、语音、视频理解结果、转写和摘要可能包含错误、偏见、遗漏或虚构内容，不代表开发者观点。角色记忆、提醒及工具执行也可能出现延迟、失败或误判，请核实重要信息和执行结果。
涉及医疗、心理、法律、财务或人身安全的决定时，请咨询合格专业人员；遇到紧急情况，请联系当地紧急救助服务，不要依赖本应用处理危机。

四、本地数据与对外传输
聊天记录、角色设置、记忆和媒体等应用数据主要保存在设备上，本地优先不代表所有处理均离线进行。调用模型或其他远程服务时，相关消息、上下文、媒体、提示词或工具参数会按功能需要发送至相应服务。第三方可能记录请求，其处理规则以相应政策为准。
分享网页或抖音、小红书、哔哩哔哩等链接时，应用可能访问目标平台、解析和下载媒体，并将抽帧图片、音频转写等内容交给所配置的模型处理。平台及网络服务可能接收到 IP 地址等连接信息。
更新检查会访问发布服务，下载更新时会访问相应下载地址。请勿将网络请求理解为绝不产生服务端访问记录。自行配置 HTTP 地址时，传输内容可能未加密，建议使用可信的 HTTPS 服务。

五、设备权限、技能与外部访问
麦克风、相机、通知等权限用于对应功能，您可以在系统设置中管理。录音、图片和其他资料可能按所启用功能发送至配置的服务，请确保具有必要的授权。
技能包、MCP 及其他工具可能访问外部服务或执行操作。启用前请确认来源、权限与作用范围；AI 对指令的理解可能出错，涉及发送信息、修改资料或费用支出的操作应谨慎核对。
局域网 OpenAI 兼容 API 是可选功能。开启后，请设置访问密钥并限制在可信网络中使用，不要随意将端口暴露到公网；调用可能消耗您配置的服务额度或传输相关数据。

六、数据保存、删除与备份
请定期导出备份并妥善保管。卸载、清理存储、设备损坏或操作失误可能导致数据丢失；缓存和历史视频可能因自动清理而无法再次查看。平台视频能否重新获取取决于原内容是否仍可访问及平台限制。
您可通过应用提供的数据管理功能删除相应本地资料。删除本地资料不会自动删除已导出的备份，或已发送给第三方并由其保存的内容；这些副本需分别处理。反馈问题时请先移除密钥和私人内容。

七、合法使用与内容权利
请遵守适用法律及所用第三方服务的规则，不得侵犯他人的隐私、肖像、声音、著作权等权益，不得用于诈骗、非法访问或其他违法活动。上传、解析、下载或分享他人的内容前，请确认具有合法依据；可访问链接不代表已获得复制或传播授权。
您提供的内容仍归原权利人所有。AI 输出的权利归属及使用范围受适用法律与相关服务条款约束，应用不保证输出具有独占性或不侵犯第三方权利。对外发布可能引起误解的生成内容时，请作必要说明。

八、版权与开源许可证
Copyright (C) 2025-2026 TideBot contributors.
TideBot 的原创源代码、应用界面、文档及项目自有资源，除另有说明外，采用 GNU Affero General Public License v3.0（AGPL-3.0-only）授权。项目版权声明和完整许可证随源码中的 COPYRIGHT、LICENSE 文件提供。第三方组件保留各自的版权和许可证。
使用、修改和分发时，请按许可证要求保留 TideBot 的版权与许可声明。本应用按许可证以“现状”提供，不作任何担保，具体以许可证全文及适用法律为准。
您可按许可证使用、研究、修改和分发代码，包括商业使用；分发及修改后通过网络与用户交互等情形下，应履行许可证规定的对应源代码提供等义务。本使用协议不增加对开源许可证所授予权利的限制；涉及代码许可的事项以相应开源许可证为准。

九、可用性与责任边界
本应用按现状提供，不承诺始终无中断、无错误或持续维护。第三方接口、平台规则、系统后台限制及网络变化可能使部分功能失效。请对重要数据保留备份，对重要提醒设置其他保障。
在适用法律允许的范围内，开发者不对不可合理控制的第三方故障、用户配置错误或不可抗力造成的损失承担责任。法律规定不得免除或限制的责任，不因本协议被免除或限制；本协议不排除您依法享有的权利。

十、协议更新与反馈
协议内容会随功能与实际数据处理方式调整，更新内容在应用内公布。涉及需要重新取得同意的重大变更时，应再次征求同意，不以静默更新替代必要授权。您可随时停止使用，并按需要备份或删除本地资料；停止使用不影响您依开源许可证已取得的权利。
问题与建议可通过应用内的“反馈与建议”入口提交。请勿在公开反馈中上传私人数据或服务密钥。争议依适用法律处理，由依法具有管辖权的机构解决；个别条款无效不影响其他条款依法适用。''';

class LegalAgreementPage extends StatefulWidget {
  const LegalAgreementPage({super.key, required this.requiredAcceptance});
  final bool requiredAcceptance;
  @override
  State<LegalAgreementPage> createState() => _LegalAgreementPageState();
}

class _LegalAgreementPageState extends State<LegalAgreementPage> {
  bool _agreed = false;
  bool _adult = false;
  Future<void> _confirm() async {
    if (!_agreed || !_adult) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('legal_agreement_accepted', true);
    await prefs.setBool('legal_age_confirmed', true);
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const TideMainScaffold()),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = TideTheme.of(context);
    return TideBackground(
      child: PopScope(
        canPop: !widget.requiredAcceptance,
        child: Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            automaticallyImplyLeading: !widget.requiredAcceptance,
            title: const Text('用户协议与免责声明'),
            backgroundColor: Colors.transparent,
          ),
          body: SafeArea(
            child: Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                    // Keep long legal content in Flutter's scroll layout.
                    // One tall Android platform view can exceed texture limits.
                    child: SelectionArea(
                      contextMenuBuilder: androidSelectionContextMenu,
                      child: Text(
                        tideBotLegalText,
                        style: TextStyle(
                          fontFamily: 'TideFont',
                          fontSize: 15,
                          height: 1.65,
                          color: theme.textStrong,
                        ),
                      ),
                    ),
                  ),
                ),
                if (widget.requiredAcceptance)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
                    child: Column(
                      children: [
                        CheckboxListTile(
                          value: _agreed,
                          onChanged: (v) =>
                              setState(() => _agreed = v ?? false),
                          title: const Text(
                            '我同意用户协议与免责声明',
                            style: TextStyle(fontFamily: 'TideFont'),
                          ),
                        ),
                        CheckboxListTile(
                          value: _adult,
                          onChanged: (v) => setState(() => _adult = v ?? false),
                          title: const Text(
                            '我确认我已满18周岁',
                            style: TextStyle(fontFamily: 'TideFont'),
                          ),
                        ),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            onPressed: _agreed && _adult ? _confirm : null,
                            child: const Text('确认并进入 TideBot'),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class TideBotAboutPage extends StatelessWidget {
  const TideBotAboutPage({super.key});
  @override
  Widget build(BuildContext context) {
    final theme = TideTheme.of(context);
    return TideBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text('关于 TideBot'),
          backgroundColor: Colors.transparent,
        ),
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 18),
                  child: Column(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(24),
                        child: Image.asset(
                          'assets/images/logo.png',
                          height: 112,
                          fit: BoxFit.cover,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'TideBot',
                        style: TextStyle(
                          fontFamily: 'TideFont',
                          fontWeight: FontWeight.w800,
                          fontSize: 28,
                          color: theme.textStrong,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        '面向个人的本地优先 AI 伴侣与智能交互工具。',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontFamily: 'TideFont', color: theme.textWeak),
                      ),
                      const SizedBox(height: 32),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          '功能特性',
                          style: TextStyle(
                            fontFamily: 'TideFont',
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: theme.textStrong,
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      _aboutFeature(theme, '自然对话与专属角色'),
                      _aboutFeature(theme, '文字、语音与多媒体'),
                      _aboutFeature(theme, '本地优先的数据管理'),
                    ],
                  ),
                ),
              ),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 18),
                child: Column(
                  children: [
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: theme.primary,
                          side: BorderSide(color: theme.primary),
                        ),
                        onPressed: () => OtaUpdate.checkNow(context),
                        child: const Text('检测新版本'),
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: theme.primary,
                          foregroundColor: Colors.white,
                        ),
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const LegalAgreementPage(
                                requiredAcceptance: false),
                          ),
                        ),
                        child: const Text('查看用户协议与免责声明'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '潮起有时，陪伴无期',
                      style: TextStyle(
                        fontFamily: 'TideFont',
                        fontSize: 12,
                        color: theme.textWeak,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _aboutFeature(TideTheme theme, String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(
              color: theme.primary,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),
          Text(
            title,
            style: TextStyle(
              fontFamily: 'TideFont',
              fontSize: 14,
              color: theme.textStrong,
            ),
          ),
        ],
      ),
    );
  }
}
