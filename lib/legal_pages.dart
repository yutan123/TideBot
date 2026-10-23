import 'package:flutter/material.dart';
import 'native_selectable_text.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'main.dart';
import 'ota_update.dart';
import 'theme.dart';

const String tideBotLegalText = '''TideBot 用户协议与免责声明

【重要提示】
使用 TideBot 前，请仔细阅读并充分理解本协议全部内容。点击确认即表示您已年满 18 周岁，并已阅读、理解、同意接受本协议的全部条款。如您不同意本协议任何内容，请立即停止使用并卸载本应用。

一、关于本应用
TideBot 是一款基于人工智能技术的本地优先虚拟伴侣应用，提供多模态智能对话、情感陪伴、生活日程管理、记忆存储与检索等功能。本应用仅供年满 18 周岁的成年用户用于个人娱乐、情感陪伴及日常交流。本应用不构成、也不能替代任何形式的人际关系、医疗诊断、心理咨询、法律服务、金融投资建议、教育指导或紧急救援服务。

二、用户资格与年龄限制
1. 您必须年满 18 周岁方可使用本应用。未满 18 周岁的未成年人严禁使用本应用。
2. 若发现用户提供虚假年龄信息或存在违法违规行为，开发者保留立即终止服务并依法追究责任的权利。
3. 根据《中华人民共和国网络安全法》《生成式人工智能服务管理暂行办法》等法律法规，AI 生成内容服务提供者有义务落实用户实名制、内容安全管理和算法备案要求。

三、AI 内容生成与免责声明
1. 本应用所有 AI 生成的对话、文本、图片、语音等内容均由您自行配置的第三方 AI 大模型（包括但不限于 OpenAI、Anthropic、Google Gemini、Moonshot、阿里通义、百度文心等）自动生成。开发者不直接运营模型服务，不对 AI 生成内容的准确性、完整性、合法性、适当性、时效性作任何明示或默示的保证。
2. AI 的回复内容不代表开发者的观点、立场、价值判断或任何形式的建议。AI 输出可能包含错误、遗漏、偏见、过时信息或与事实不符的内容。您应独立判断 AI 回复的合理性，并自行承担依据 AI 回复作出任何决定或行为所产生的全部法律责任和实际后果。
3. 本应用已部署基础内容安全过滤机制，但由于 AI 技术本身的不确定性和局限性，无法保证 100% 拦截所有不当、违法或有害内容。如您在使用过程中发现任何违法违规、色情低俗、暴力恐怖、侵犯他人权益的内容，请立即停止使用并通过应用内反馈渠道联系开发者。
4. 涉及健康、心理危机、法律纠纷、财务决策、投资理财、未成年人安全、人身安全或紧急情况时，请立即联系相应专业机构或拨打紧急服务电话（如 120、110、119），切勿仅依赖 AI 输出作出决定。

四、用户行为规范
您在使用本应用时，应严格遵守以下行为规范：
1. 不得利用本应用从事任何违反《中华人民共和国刑法》《中华人民共和国治安管理处罚法》《中华人民共和国网络安全法》等法律法规的活动，包括但不限于：传播淫秽色情、暴力血腥、恐怖主义、极端主义、赌博、毒品、诈骗、传销、非法集资等违法信息；侵犯他人知识产权、隐私权、肖像权、名誉权、荣誉权等合法权益；干扰、破坏本应用或第三方服务的正常运行。
2. 不得诱导、操纵 AI 生成违反法律法规、公序良俗或社会主义核心价值观的内容；不得利用本应用制作、传播虚假信息、谣言或仇恨言论。
3. 不得将本应用用于任何商业目的，包括但不限于转售、出租、出借、代理或以其他方式牟利；不得将 AI 输出内容冒充真实事实、专业意见或真人表态用于误导他人。
4. 不得对本应用进行反向工程、反编译、反汇编、破解、修改或试图提取源代码；不得通过技术手段绕过任何安全措施或访问控制机制。
5. 上传或生成涉及他人肖像、声音、个人信息、作品、商标的内容前，您应确保已取得合法授权；未经授权不得使用。

五、隐私保护与数据安全
1. 本应用采用本地优先架构，您的聊天记录、通话摘要、日记、记忆、生活日程、世界书、图片、音频、机器人设置等数据均存储在您的设备本地数据库中。开发者无法访问、查看、获取、使用或分析您存储在本地的任何内容。
2. 您发送给 AI 的消息、图片、音频等内容会通过加密网络传输至您自行配置的第三方 AI 服务提供商（如 OpenAI、Google、Anthropic 等）进行处理。这些第三方服务商的数据处理方式、隐私政策、服务条款由其自行制定并负责。请在使用前仔细阅读相关第三方服务商的隐私政策和使用条款，切勿发送任何个人敏感信息（如身份证号、银行卡号、密码、家庭住址、详细行踪等）。
3. 本应用采集的设备标识符（Android ID）仅用于应用内部功能实现和违规行为追查，不会用于任何商业营销目的，也不会出售、出租或分享给任何第三方。
4. 本应用的自动版本检测功能仅通过 GitHub API 查询版本信息，不会上传您的任何个人数据、使用记录或设备信息。
5. 您可随时在应用内删除聊天记录、日记、记忆等数据。但请注意，卸载应用、设备损坏、系统清理、未及时备份或他人物理接触您的设备均可能导致数据永久丢失或泄露。请妥善保管设备、设置锁屏密码、保护 API Key 并定期备份重要数据。

六、第三方服务与局域网访问
1. 本应用支持您自行配置和接入第三方 AI 模型服务、语音识别（STT）服务、语音合成（TTS）服务、图片生成服务、网络搜索服务等。这些第三方服务的可用性、性能、收费标准、服务条款、数据处理方式和法律责任完全由服务提供方负责，与本应用开发者无关。
2. 本应用支持启用局域网 OpenAI 兼容 API 服务，允许同一网络中的其他设备通过 HTTP 接口访问您的 AI 服务。启用该功能前，您必须充分理解以下风险并自行承担全部后果：端口暴露可能导致未授权访问；API Key 泄露可能导致服务被滥用；同一网络中的恶意设备可能窃取数据或发起攻击；第三方调用产生的流量费用、API 配额消耗由您承担。请务必设置足够强的 API Key、限制可信网络访问、关闭不必要的端口转发，并定期检查访问日志。
3. 切勿将您的 API Key、私人对话记录、身份信息、他人隐私数据提交给不可信的第三方服务或分享给他人。

七、语音、图片与设备权限
1. 语音通话功能需要您授权麦克风权限。启用后，应用会在通话期间录制音频并发送至您配置的语音识别（STT）服务进行转写；AI 回复文本可能发送至语音合成（TTS）服务生成语音。录制的音频文件默认保存在设备本地，不会自动上传至开发者服务器。
2. 图片生成、图片识别、网络搜索等功能会将必要的文字、图片、音频或对话上下文发送至对应的第三方服务商。请在使用前确认您信任该服务商，并已阅读其隐私政策。
3. 设备信息获取、通知访问、位置服务、无障碍权限等系统能力仅在您主动启用相关功能并明确授权后使用。您可以随时在系统设置中撤回任何权限。
4. AI 生成的图片、语音转写结果、搜索来源内容可能存在错误、失真、过时或不完整，不应作为专业结论或事实依据。

八、服务可用性与技术限制
1. 本应用按「现状」和「可用」基础提供，不保证服务始终无中断、无错误、无延迟或完全满足您的需求。
2. 第三方 AI 服务提供商的服务中断、API 变更、政策调整、账号封禁、配额用尽或服务关停可能导致本应用部分或全部功能无法使用。开发者不对因第三方服务不可用造成的任何损失承担责任。
3. 本应用通过 GitHub 自动检测版本更新，但更新内容、更新频率和持续维护由开发者自主决定，不构成任何持续服务承诺。开发者保留随时暂停、终止或修改服务内容的权利，无需事先通知。
4. 由于 AI 技术本身的不确定性，生成内容可能出现逻辑错误、事实错误、重复、矛盾、不完整或不适当的表达。您应对 AI 输出保持审慎态度。

九、知识产权
1. 本应用（包括但不限于代码、界面设计、图标、Logo、文案、算法、数据库结构）的著作权及其他知识产权归开发者所有。未经开发者书面许可，任何个人或组织不得复制、修改、反编译、发布、出售、出租本应用或其任何部分。
2. 您通过本应用与 AI 交互产生的对话内容、生成的图片、合成的语音等，其知识产权归属和使用权限遵循您所使用的第三方 AI 服务商的使用条款和版权政策。请在使用前仔细阅读相关服务商的条款。
3. 您上传至本应用的文本、图片、音频等内容，其知识产权仍归您或原权利人所有。但您授予本应用在设备本地存储、处理、展示这些内容的必要权限，以实现应用功能。

十、责任限制
在适用法律允许的最大范围内：
1. 开发者不对因使用或无法使用本应用而产生的任何直接损失、间接损失、附带损失、特殊损失、惩罚性损失或后果性损失（包括但不限于数据丢失、精神损害、名誉损害、经济损失、利润损失、业务中断）承担赔偿责任，即使开发者已被告知此类损害的可能性。
2. 开发者不对第三方 AI 服务商、语音服务商、图片服务商、搜索服务商等外部服务提供方的服务质量、内容准确性、数据安全性、服务中断或终止承担任何责任。
3. 开发者不对因用户自身配置错误、API Key 泄露、设备丢失、操作系统故障、网络中断、恶意软件、黑客攻击或不可抗力（如地震、火灾、战争、政策变更等）导致的损失承担责任。
4. 若您因违反本协议或违反法律法规的行为导致开发者遭受损失或承担法律责任，您应全额赔偿开发者因此产生的全部损失和费用（包括但不限于律师费、诉讼费、调查费、公证费、差旅费）。
5. 若您不同意上述责任限制条款，请勿使用本应用。

十一、协议变更与终止
1. 开发者保留随时修改本协议的权利。修改后的协议将在应用更新时生效，并在应用内公布。继续使用本应用即视为您接受修改后的协议全部内容。如您不同意修改后的协议，请立即停止使用并卸载本应用。
2. 如您违反本协议任何条款或从事违法违规行为，开发者有权立即单方面终止您使用本应用的权利，并保留追究法律责任的权利。
3. 您可以随时通过卸载本应用来终止使用。终止后，本协议中关于隐私保护、知识产权、责任限制、争议解决等条款仍然有效。

十二、法律适用与争议解决
1. 本协议的订立、生效、解释、履行、修改、终止及争议解决均适用中华人民共和国大陆地区法律。法律另有强制性规定的除外。
2. 因本协议引起的或与本协议有关的任何争议，双方应首先通过友好协商解决。协商不成的，任何一方均有权向开发者所在地有管辖权的人民法院提起诉讼。

十三、特别声明
1. 本应用为个人开发者的学习、研究与技术分享项目，不构成商业运营。应用中所有虚拟角色的形象、性格、设定、对话内容均为虚构创作，仅供娱乐使用，与现实中的任何真实人物、事件、组织、品牌无任何关联。
2. 本应用不收集、不存储、不分析您的个人隐私数据。所有数据均存储在您的设备本地。但请注意，您配置的第三方服务商可能收集和使用您的数据，具体以其隐私政策为准。
3. 使用本应用即表示您已充分理解并明确同意：开发者对您使用本应用所产生的任何后果、风险、损失不承担任何法律责任或赔偿义务。
4. 如本协议任何条款被有管辖权的法院或仲裁机构认定为无效或不可执行，该条款的无效不影响本协议其他条款的效力。

【最终确认】
再次提醒：本应用仅供年满 18 周岁的成年人使用。AI 生成内容仅供参考，不构成任何专业建议。遇到健康、法律、财务、安全等问题时，请立即寻求专业帮助。使用本应用即表示您已完全阅读、理解并同意本协议全部内容。''';

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
                    child: NativeSelectableText(
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
