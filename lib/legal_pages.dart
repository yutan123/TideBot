import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'main.dart';
import 'ota_update.dart';
import 'theme.dart';

const String tideBotLegalText = '''用户协议与免责声明

生效提示
使用 TideBot 前，请完整阅读并理解本协议。点击确认表示您已阅读、理解并同意本协议全部内容。本应用提供的是本地运行的 AI 交互工具，不构成医疗、心理治疗、法律、金融、投资、教育、紧急救援或其他专业意见。

一、服务说明
TideBot 可在您的设备上保存聊天记录、设置和本地数据，并可按您的配置调用第三方模型或网络服务。第三方服务的可用性、内容、收费、数据处理和服务条款由其提供方负责。请勿在未理解第三方规则前提交个人信息、密钥或敏感数据。

二、用户行为
您应遵守中华人民共和国法律法规，不得利用本应用制作、复制、发布、传播违法、有害、侵犯他人权益或危害网络安全的内容。您对通过自己设备、账号、API Key 和网络连接进行的操作负责。

三、AI 内容与风险
AI 输出可能存在错误、遗漏、偏见、过时信息或不符合实际情况的内容。涉及健康、心理危机、法律、财务、投资、未成年人安全、人身安全或紧急情况时，请联系相应专业机构或紧急服务，不得仅依赖 AI 输出作出决定。

四、隐私、本地数据与记忆
TideBot 会在您的设备上保存您主动输入或启用后产生的聊天记录、通话摘要、日记、记忆、机器人生活日程、图片、音频、设置及模型配置。这些内容用于提供连续对话、本地检索、日程展示和您选择的功能。您可在应用内删除相应内容；卸载、设备损坏、系统清理、未备份或他人取得设备访问权均可能造成数据不可恢复或泄露。请妥善保管设备、锁屏、API Key 和备份文件。

五、语音、图片、联网与设备能力
语音通话会在您授权麦克风后录制音频并发送给您配置的语音识别服务；机器人回复可能发送给语音合成服务。联网搜索、图片生成以及您配置的模型服务会将为完成请求所必要的文字、图片、音频或上下文发送至对应第三方。设备信息、通知、使用情况、定位或无障碍等能力仅在您主动启用并授权后使用；请自行判断是否授予，并随时可在系统设置中撤回。AI 生成内容、搜索来源与转写结果可能错误、过时、失真或不完整，不应作为专业结论。

六、外部服务与局域网访问
外部模型、语音、图片、搜索和局域网 OpenAI 兼容 API 均由您自行配置和启用。局域网服务可能被同一网络中的其他设备访问；您必须设置足够强的 API Key、限制可信网络并自行承担端口暴露、密钥泄露、未经授权调用、流量费用和第三方服务条款风险。请勿将密钥、私人通话、身份信息或他人数据提交给不可信服务。

七、用户行为、内容与权利
您应遵守中华人民共和国法律法规，不得利用本应用制作、复制、发布、传播违法、有害、侵犯他人权益或危害网络安全的内容。您对通过自己设备、账号、API Key 和网络连接进行的操作负责。上传或生成涉及他人肖像、声音、隐私、作品、商标或个人信息的内容前，您应确保已取得合法授权；不得将 AI 输出冒充真实事实、专业意见或真人表态。

八、未成年人、紧急情况与免责声明
本应用仅面向年满 18 周岁的成年人。AI 陪伴、聊天和生活状态功能不构成医疗、心理治疗、法律、金融、投资、教育、紧急救援或其他专业意见。涉及健康、心理危机、法律、财务、投资、未成年人安全、人身安全或紧急情况时，请联系相应专业机构或紧急服务，不得仅依赖 AI 输出作出决定。在法律允许范围内，TideBot 按现状提供，不保证服务不中断、无错误、适配所有设备或满足任何特定目的。对因网络、设备、系统、模型、第三方服务、用户配置或不当使用造成的损失，运营者在法律允许范围内不承担责任；法律另有强制规定的除外。

九、知识产权、协议变更与争议解决
应用及其内容受法律保护。您不得侵犯他人知识产权。运营者可因法律、技术或服务变化更新本协议，并在应用内公布；继续使用更新后的服务即表示接受更新内容。本协议适用中华人民共和国法律。发生争议时，双方应先友好协商；协商不成的，按有管辖权的人民法院处理。有效联系信息、协议版本和更新说明以应用内公布内容为准。正式商业发布前，应由中国执业律师结合实际运营主体、业务模式、隐私政策、数据流向与第三方 SDK 审阅本协议。''';

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
                    child: SelectableText(
                      tideBotLegalText,
                      style: TextStyle(
                        fontFamily: 'TideFont',
                        height: 1.65,
                        color: theme.textStrong,
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
          child: Padding(
            padding: const EdgeInsets.all(24),
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
                  style:
                      TextStyle(fontFamily: 'TideFont', color: theme.textWeak),
                ),
                const SizedBox(height: 28),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '功能特性',
                    style: TextStyle(
                      fontFamily: 'TideFont',
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: theme.textStrong,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  '多角色聊天与本地记录\n图片、语音、文件等多模态交互\n网络工具和外部访问服务\n设备端设置、记忆与日程管理',
                  style: TextStyle(fontFamily: 'TideFont', height: 1.8),
                ),
                const Spacer(),
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
                        builder: (_) =>
                            const LegalAgreementPage(requiredAcceptance: false),
                      ),
                    ),
                    child: const Text('查看用户协议与免责声明'),
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
