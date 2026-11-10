import 'package:flutter/material.dart';

import 'android_selection_menu.dart';
import 'theme.dart';
import 'ui_components.dart';

// Consent is deliberately page-local: every visit requires fresh acceptance.
const supportAgreementSections = <({String title, String body})>[
  (
    title: '一、主体界定与参与资格',
    body:
        '甲方（赠予人）为自愿使用本人合法资金支持 TideBot 的自然人；乙方（受赠方）为 TideBot 开发维护方，由本页面展示的收款账户持有人实际接收支持款项。本协议不将微信、支付宝或其他支付机构列为受赠方或履约担保方。支付前请核对支付平台显示的收款主体；如对开发维护方与收款主体的关系存在疑问，请先通过应用内“反馈与建议”咨询，未确认前不要付款。\n\n甲方必须已年满十八周岁，并具有实施本次赠予所需的完全民事行为能力。未成年人禁止参与，即使获得监护人口头许可，也不得使用本入口赠予；不得冒用成年人身份、借用他人账户规避限制。年龄勾选属于本人声明，并非实名认证或年龄核验。甲方不得代未成年人或不具备相应行为能力的人作出赠予决定。',
  ),
  (
    title: '二、合同性质与自愿原则',
    body:
        '本次支持属于双方基于真实意思表示达成的无偿赠予，不属于购买软件、会员、订阅、预付款、定金、投资、借款、众筹回报或商业服务订单，不产生收益分配、股权、利息或保本承诺。该赠予也不是面向社会的公益募捐，不提供公益捐赠票据或税前扣除承诺。\n\n是否支持、何时支持以及金额多少均由甲方独立决定，本页面不设置最低支持金额。乙方不得以停止既有合法使用权、制造紧迫感或虚构回报迫使甲方付款。甲方可以不勾选、不付款或随时在付款前退出，单纯阅读、勾选或点击确认不构成付款义务，也不授权应用自动扣款。请量力而行，优先保障生活、学习、医疗和家庭必要支出，不借贷支持，不冲动转账。',
  ),
  (
    title: '三、权利界定与无对价说明',
    body:
        '赠予不换取任何特定功能、额度、模型使用权、更新频率、优先处理权、专属服务或特殊待遇，不使甲方取得对研发路线、上线时间、技术选型、人员安排、运营方式的决定权。甲方可以提出建议，但乙方无义务采纳，也不因赠予产生强制修复、适配或交付特定功能的义务。\n\n应用原有功能、开源许可证以及依法取得的权利，仍按其各自约定和法律规定处理。本协议不限制开源许可证已授予的权利，不因赠予增加或剥夺用户既有权利。第三方模型、API、云服务及网络等费用仍由使用者依相应服务规则自行承担，支持款不抵扣该类费用。',
  ),
  (
    title: '四、资金来源、支付与完成时点',
    body:
        '甲方应使用本人有权处分的合法资金，核对收款人、金额、付款备注与支付平台提示后，自行完成支付。不得使用盗刷、诈骗、挪用款项、无权处分的共有资金或其他违法所得。未经合法授权不得使用他人账户、他人支付凭证或公司资金。\n\n款项实际到达乙方收款账户时，该笔款项的交付完成；仅展示二维码、保存截图、发起支付或显示处理中不等于款项已到账。手续费、支付限额、风控、到账延迟与账单规则由相应支付平台决定。应用不保存银行卡信息、支付密码，不自动扣款，也不会自动核实到账或出具付款成功证明；请保留支付平台的真实账单，勿仅凭截图判断到账。',
  ),
  (
    title: '五、撤销权、退款与返还【重点条款】',
    body:
        '在法律允许的范围内，赠予资金交付完成后，甲方承诺不任意撤销，不要求退款，不主张返还，不以体验不佳、功能未实现、更新放缓、项目停更、个人喜好变化、误估使用效果或单纯后悔等理由反悔。乙方不设置基于上述原因的普通退款、试用退款或无理由退款服务。赠予前请充分考虑自身经济状况与不获回报的后果。\n\n但本条不得解释为排除法定撤销权、依法解除或请求返还的权利，也不保证“任何情形一律不退”具有法律效力。赠予交付前依法享有的任意撤销权、交付后的法定撤销事由、重大误解、欺诈、胁迫、行为能力欠缺、无权处分、不当得利以及其他依法应处理的情形，均依法律认定。未成年人付款、盗刷、真实误转、支付平台重复扣款等，请及时通过应用内反馈及支付平台依法核实处理；不得以本协议掩盖违法行为或阻碍合法救济。\n\n申请核实应提供必要的真实交易记录及相关事实，是否退款、返还及金额应依据核实结果和适用法律确定，不以乙方单方判断作为最终依据。请勿公开支付密码、完整证件号码、密钥等敏感信息。因维权而提交真实异议不构成违约，伪造账单、恶意冒领或欺诈行为依法处理。',
  ),
  (
    title: '六、资金用途与管理边界',
    body:
        '支持款用于 TideBot 的开发、测试、维护及相关优化，包括但不限于开发工具、测试设备、模型或接口测试、服务与存储、兼容适配、安全修复、文档完善，以及与项目开发维护直接相关的合理劳务和时间成本。乙方可根据项目实际需求统筹安排支出、使用节奏和技术方案。\n\n本次赠予不设个人专属预算或一对一交付计划，不承诺逐笔对应某项成果，也不承诺在固定时间内全部花费。除法律另有规定或双方另有有效约定外，乙方不承担向每名赠予人逐笔公示账目、流水或使用明细的合同义务。自主安排不代表可以虚构用途、侵占依法应返还的款项或免除适用法律规定的财务、税务责任。',
  ),
  (
    title: '七、软件状态与风险承担【重点条款】',
    body:
        '甲方理解软件可能持续处于开发和迭代状态，存在缺陷、闪退、卡顿、兼容问题、数据丢失、功能变更、服务中断以及第三方服务不可用等风险。模型回复和工具执行可能有误，平台规则、设备系统、外部 API 与网络环境变化也可能影响使用；未来维护、功能持续可用与项目持续运营不作保证。请自行备份重要数据，并在重要操作前核对结果。\n\n甲方自愿承担在知悉上述情况后仍作出无偿支持的经济决定及一般预期落空风险。法律允许范围内，乙方不因接受赠予承担特定的可用性保证、盈利保证或对不可合理控制风险的补偿义务。但因故意、重大过失造成的财产损失、人身损害，以及依法不得免除或限制的其他责任，不因本协议而被免除。对违法行为和法定责任的追究不受本条限制。',
  ),
  (
    title: '八、真实意思表示与条款提示',
    body:
        '甲方确认已获得完整阅读本协议的机会，重点阅读年龄限制、无对价、不任意退款、风险与责任边界等条款；如对任一条款含义、受赠主体或款项用途有疑问，应先暂停并通过反馈入口咨询。乙方不得将甲方的沉默、未操作或继续使用应用视为同意赠予。\n\n勾选并点击确认，表示甲方就本次查看收款码作出已成年、具备行为能力及同意协议的声明；实际赠予仍须甲方另行主动付款。甲方应基于真实、自由且独立的意愿决定，不受诱导、胁迫或对回报的误导。阅读完成标记仅辅助本地界面交互，不证明身份已核验、款项已支付，也不替代司法机关对真实意思表示的认定。',
  ),
  (
    title: '九、隐私、凭证与账户安全',
    body:
        '应用不持久保存本入口的年龄勾选和协议同意状态，每次打开都需重新阅读确认。支付在微信、支付宝等第三方平台完成，支付平台将按自身规则处理交易及身份信息；乙方可能通过收款账单看到平台展示的必要交易信息，不应将这些信息用于无关用途或擅自公开赠予人身份。\n\n请只使用本页面展示的收款码并核对平台实际收款信息，不轻信私信更换账户、索取验证码或保证回报的要求。二维码展示不代表支付平台为软件、协议或开发维护方背书。因支付争议需要联系时，仅提交核实所需的信息；甲方应妥善保留支付凭证及付款时适用的协议内容，避免公开个人隐私。',
  ),
  (
    title: '十、效力、变更与争议解决',
    body:
        '本协议适用中华人民共和国大陆地区法律。对依法须特别提示说明的格式条款，应结合页面提示、实际说明情况及法律规定认定其效力；不得以勾选确认代替依法应当履行的提示和说明义务。条款存在歧义时，按适用法律解释；部分条款无效、被撤销或不能执行，不影响其余条款在法律允许范围内的效力。\n\n后续协议更新仅适用于更新后重新确认的行为，不单方追溯变更已经完成赠予的约定。因本协议或赠予发生争议，双方可先通过应用内“反馈与建议”和支付平台协商；协商不成的，任何一方均可向依法具有管辖权的人民法院寻求解决。本协议不限制投诉、举报、诉讼或依法行使其他救济权利。\n\n请再次确认：支持完全自愿，不获得额外权益；未成年人禁止参与；在法律允许范围内，交付后不任意撤销、不退款、不主张返还、不因后悔反悔。不能接受全部条款时，请直接返回，不要付款。',
  ),
];

class SupportUsPage extends StatefulWidget {
  const SupportUsPage({super.key});

  @override
  State<SupportUsPage> createState() => _SupportUsPageState();
}

class _SupportUsPageState extends State<SupportUsPage> {
  final _scroll = ScrollController();
  bool _readToEnd = false;
  bool _agreed = false;
  bool _showingCodes = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_checkEnd);
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkEnd());
  }

  void _checkEnd() {
    if (mounted &&
        !_readToEnd &&
        _scroll.hasClients &&
        _scroll.position.extentAfter <= 2) {
      setState(() => _readToEnd = true);
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    if (!_readToEnd || !_agreed || _showingCodes) return;
    setState(() => _showingCodes = true);
    final done = await TideDialogs.show<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _SupportPaymentDialog(),
    );
    if (!mounted) return;
    if (done == true) {
      Navigator.of(context).pop();
    } else {
      setState(() {
        _showingCodes = false;
        _agreed = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = TideTheme.of(context);
    final enabled = _readToEnd && _agreed && !_showingCodes;
    return TideBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text('支持我们'),
          backgroundColor: Colors.transparent,
        ),
        body: SafeArea(
          top: false,
          child: Scrollbar(
            controller: _scroll,
            child: SingleChildScrollView(
              controller: _scroll,
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(Icons.favorite_rounded, color: theme.primary, size: 36),
                  const SizedBox(height: 14),
                  Text('让喜欢的事，继续生长',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontFamily: 'TideFont',
                          fontSize: 23,
                          fontWeight: FontWeight.w700,
                          color: theme.textStrong)),
                  const SizedBox(height: 10),
                  Text('感谢你对 TideBot 的支持。请量力而行，阅读完整协议后再决定。',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontFamily: 'TideFont',
                          height: 1.6,
                          color: theme.textWeak)),
                  const SizedBox(height: 24),
                  FrostCard(
                    padding: const EdgeInsets.all(18),
                    child: Text(
                        '自愿赠予与免责协议\n\n仅限年满 18 周岁且具有相应完全民事行为能力的本人参与。\n无偿支持不换取功能或服务；一般不退款，法定权利与责任除外。',
                        style: TextStyle(
                            fontFamily: 'TideFont',
                            fontSize: 15,
                            height: 1.7,
                            fontWeight: FontWeight.w600,
                            color: theme.textStrong)),
                  ),
                  const SizedBox(height: 22),
                  SelectionArea(
                    contextMenuBuilder: androidSelectionContextMenu,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final section in supportAgreementSections) ...[
                          Text(section.title,
                              style: TextStyle(
                                  fontFamily: 'TideFont',
                                  fontSize: 17,
                                  height: 1.6,
                                  fontWeight: FontWeight.w700,
                                  color: theme.textStrong)),
                          const SizedBox(height: 10),
                          Text(section.body,
                              style: TextStyle(
                                  fontFamily: 'TideFont',
                                  fontSize: 15,
                                  height: 1.85,
                                  color: theme.textStrong)),
                          const SizedBox(height: 26),
                        ],
                      ],
                    ),
                  ),
                  Divider(color: theme.border),
                  const SizedBox(height: 8),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    activeColor: theme.primary,
                    checkColor: Colors.white,
                    value: _agreed,
                    onChanged: _readToEnd && !_showingCodes
                        ? (value) => setState(() => _agreed = value ?? false)
                        : null,
                    title: Text('我已年满18周岁，同意以上全部条款',
                        style: TextStyle(
                            fontFamily: 'TideFont',
                            fontSize: 14,
                            height: 1.6,
                            color: theme.textStrong)),
                  ),
                  const SizedBox(height: 8),
                  Text(
                      _readToEnd
                          ? '点击确定后展示收款码，是否付款仍由你自行决定。'
                          : '请滑动到底部，阅读完成后方可勾选。',
                      style: TextStyle(
                          fontFamily: 'TideFont',
                          fontSize: 12,
                          height: 1.6,
                          color: theme.textWeak)),
                  const SizedBox(height: 16),
                  Semantics(
                    button: true,
                    enabled: enabled,
                    child: IgnorePointer(
                      ignoring: !enabled,
                      child: Opacity(
                        opacity: enabled ? 1 : 0.4,
                        child: TideDialogs.glassButton('确定', onTap: _confirm),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SupportPaymentDialog extends StatefulWidget {
  const _SupportPaymentDialog();

  @override
  State<_SupportPaymentDialog> createState() => _SupportPaymentDialogState();
}

class _SupportPaymentDialogState extends State<_SupportPaymentDialog> {
  int _method = 0;
  final _zoom = TransformationController();

  @override
  void dispose() {
    _zoom.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = TideTheme.of(context);
    final availableHeight = MediaQuery.sizeOf(context).height -
        MediaQuery.paddingOf(context).vertical -
        48;
    return TideDialogSurface(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 460, maxHeight: availableHeight),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: theme.surface,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: theme.border, width: 0.5),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withValues(alpha: 0.16),
                  blurRadius: 28,
                  offset: const Offset(0, 12))
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('感谢你的自愿支持',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontFamily: 'TideFont',
                      fontSize: 19,
                      fontWeight: FontWeight.w700,
                      color: theme.textStrong)),
              const SizedBox(height: 14),
              Row(children: [
                for (var index = 0; index < 2; index++) ...[
                  if (index > 0) const SizedBox(width: 10),
                  Expanded(
                    child: Semantics(
                      selected: _method == index,
                      button: true,
                      child: TideDialogs.glassButton(
                        index == 0 ? '微信支付' : '支付宝',
                        color: _method == index
                            ? theme.primary
                            : theme.primary.withValues(alpha: 0.1),
                        textColor:
                            _method == index ? Colors.white : theme.textStrong,
                        onTap: () {
                          _zoom.value = Matrix4.identity();
                          setState(() => _method = index);
                        },
                      ),
                    ),
                  ),
                ],
              ]),
              const SizedBox(height: 14),
              Flexible(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: ColoredBox(
                    color: Colors.white,
                    child: InteractiveViewer(
                      transformationController: _zoom,
                      minScale: 1,
                      maxScale: 4,
                      child: Image.asset(
                        _method == 0
                            ? 'assets/images/support_wechat.png'
                            : 'assets/images/support_alipay.jpg',
                        fit: BoxFit.contain,
                        semanticLabel:
                            _method == 0 ? '微信自愿支持收款码' : '支付宝自愿支持收款码',
                        errorBuilder: (_, error, stack) => const Padding(
                          padding: EdgeInsets.all(24),
                          child: Text('收款码暂时无法显示，请退出后重试。',
                              style: TextStyle(color: Colors.black87)),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text('可切换支付方式。付款前请核对收款人及金额，无需付款也可退出。',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontFamily: 'TideFont',
                      fontSize: 12,
                      height: 1.6,
                      color: theme.textWeak)),
              const SizedBox(height: 14),
              TideDialogs.glassButton('确定',
                  onTap: () => Navigator.of(context).pop(true)),
            ],
          ),
        ),
      ),
    );
  }
}
