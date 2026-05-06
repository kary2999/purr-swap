import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/exchange_record.dart' as em;
import '../theme/ios_theme.dart';
import '../widgets/ios_widgets.dart';

class GuidePage extends StatefulWidget {
  const GuidePage({super.key});
  @override
  State<GuidePage> createState() => _GuidePageState();
}

class _GuidePageState extends State<GuidePage> {
  int _activeTab = 0;

  @override
  Widget build(BuildContext c) {
    final g = _guides[_activeTab];
    return Scaffold(
      backgroundColor: IOS.grayBg,
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            IOSLargeTitle(
              title: '汇款指南',
              actions: [
                if (_channelMetaFor(g.name)?.downloadUrl != null)
                  IOSNavLink(
                    '↗ 下载 App',
                    onTap: () => _open(_channelMetaFor(g.name)!.downloadUrl!),
                  ),
              ],
            ),
            IOSSegmentedControl(
              items: _guides.map((g) => g.name).toList(),
              active: _activeTab,
              onChange: (i) => setState(() => _activeTab = i),
            ),
            _channelHeader(g),
            _feeSection(g),
            IOSSectionHeader('操作步骤 · ${g.steps.length} 步'),
            for (int i = 0; i < g.steps.length; i++)
              _stepCard(i + 1, g.steps[i]),
            if (g.footer != null) _footerCard(g.footer!),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _channelHeader(Guide g) {
    final meta = _channelMetaFor(g.name);
    return IOSSection(
      children: [
        IOSRow(
          leadingIcon: _iconFor(g.name),
          iconColors: _colorsFor(g.name),
          label: '${g.name} ${_channelDisplay(g.name)}',
          sub: g.tagline,
          trailing: meta != null
              ? IOSBadge(
                  risk: _riskTag(meta.risk),
                  text: '${_riskLabel(meta.risk)}风险',
                )
              : null,
        ),
      ],
    );
  }

  String _channelDisplay(String name) {
    if (name == '熊猫速汇') return '(MUFG ATM)';
    if (name == 'Wise') return '(PayPay 银行)';
    if (name == 'JRF') return '(ECO 预付卡)';
    if (name == '中行日本') return '(SWIFT 汇款)';
    return '';
  }

  IconData _iconFor(String name) {
    if (name.contains('熊猫')) return Icons.pets;
    if (name.contains('Wise')) return Icons.public;
    if (name.contains('JRF')) return Icons.credit_card;
    if (name.contains('中行')) return Icons.account_balance;
    return Icons.help_outline;
  }

  List<Color> _colorsFor(String name) {
    if (name.contains('熊猫')) return const [IOS.orange, Color(0xFFFF6B00)];
    if (name.contains('Wise')) return const [IOS.violet, IOS.indigo];
    if (name.contains('JRF')) return const [IOS.violet, IOS.indigo];
    if (name.contains('中行')) return const [IOS.red, Color(0xFFC93400)];
    return const [IOS.blue, IOS.blueDark];
  }

  Widget _feeSection(Guide g) {
    final m = _channelMetaFor(g.name);
    if (m == null) return const SizedBox.shrink();
    final rows = <Widget>[];
    if (m.platformFeeJpy > 0) {
      rows.add(IOSFormRow(
        label: '平台手续费',
        value: '¥${m.platformFeeJpy.toStringAsFixed(0)} JPY/笔',
        valueColor: IOS.gray,
      ));
    }
    if (m.markupPct > 0) {
      rows.add(IOSFormRow(
        label: '点差(vs mid)',
        value: '~${(m.markupPct * 100).toStringAsFixed(2)}%',
        valueColor: IOS.gray,
      ));
    }
    if (m.atmFeeJpy > 0) {
      rows.add(IOSFormRow(
        label: 'ATM 振込费',
        value: '+¥${m.atmFeeJpy.toStringAsFixed(0)} JPY (他行)',
        valueColor: IOS.gray,
      ));
    }
    if (m.fixedFeeCny > 0) {
      rows.add(IOSFormRow(
        label: '固定手续费',
        value: '¥${m.fixedFeeCny.toStringAsFixed(0)} CNY/笔',
        valueColor: IOS.gray,
      ));
    }
    if (rows.isEmpty) return const SizedBox.shrink();
    return IOSSection(header: '费用构成', children: rows);
  }

  Widget _stepCard(int n, GuideStep s) {
    return IOSStepCard(
      num: n,
      title: s.title,
      body: s.body,
      extras: [
        if (s.copyable != null)
          for (final e in s.copyable!.entries)
            IOSCopyRow(keyText: e.key, valueText: e.value),
        if (s.warning != null) IOSWarning(text: s.warning!, danger: true),
        if (s.tip != null)
          IOSWarning(text: '💡 ${s.tip!}', danger: false),
        if (s.image != null)
          GestureDetector(
            onTap: () => _showFullImage(s.image!),
            child: Container(
              margin: const EdgeInsets.only(top: 10, left: 32),
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: IOS.separator, width: 0.5),
              ),
              child: Image.asset(
                s.image!,
                height: 180,
                fit: BoxFit.cover,
                width: double.infinity,
              ),
            ),
          ),
      ],
    );
  }

  void _showFullImage(String path) {
    Navigator.of(context).push(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          iconTheme: const IconThemeData(color: Colors.white),
        ),
        body: Center(
          child: InteractiveViewer(
            minScale: 0.5,
            maxScale: 4,
            child: Image.asset(path),
          ),
        ),
      ),
    ));
  }

  Widget _footerCard(String text) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: IOS.blue.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(IOS.radCard),
      ),
      child: Text(text,
          style: const TextStyle(fontSize: 12, color: IOS.textSecondary, height: 1.5)),
    );
  }

  Future<void> _open(String url) async {
    final uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('无法打开,已复制链接'),
            duration: Duration(seconds: 1)));
        await Clipboard.setData(ClipboardData(text: url));
      }
    }
  }

  em.ChannelMeta? _channelMetaFor(String guideName) {
    final map = {
      '熊猫速汇': '熊猫速汇(JPY)',
      'Wise': 'Wise(JPY)',
      'JRF': 'JRF Wallet',
      '中行日本': '中国银行汇款',
    };
    final cn = map[guideName];
    if (cn == null) return null;
    return em.kChannels.where((c) => c.name == cn).firstOrNull;
  }

  RiskTag _riskTag(em.RiskLevel l) => switch (l) {
        em.RiskLevel.veryLow => RiskTag.veryLow,
        em.RiskLevel.low => RiskTag.low,
        em.RiskLevel.medium => RiskTag.medium,
        em.RiskLevel.high => RiskTag.high,
      };

  String _riskLabel(em.RiskLevel l) => switch (l) {
        em.RiskLevel.veryLow => '极低',
        em.RiskLevel.low => '低',
        em.RiskLevel.medium => '中',
        em.RiskLevel.high => '高',
      };
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

class Guide {
  final String name;
  final String tagline;
  final List<String> tags;
  final List<GuideStep> steps;
  final String? footer;
  const Guide({
    required this.name,
    required this.tagline,
    required this.tags,
    required this.steps,
    this.footer,
  });
}

class GuideStep {
  final String title;
  final String body;
  final String? warning;
  final String? tip;
  final Map<String, String>? copyable;
  /// 可选: 配图资源路径,点击后全屏查看
  final String? image;
  const GuideStep({
    required this.title,
    required this.body,
    this.warning,
    this.tip,
    this.copyable,
    this.image,
  });
}

const _guides = <Guide>[
  // --------- 1. 熊猫速汇 ---------
  Guide(
    name: '熊猫速汇',
    tagline: '费率最优 · 国内团队 · 到账最快',
    tags: ['限额 300w/月', '600w/年', 'ATM 自助', '微信/支付宝'],
    steps: [
      GuideStep(
        title: '注册 · 绑定收款方',
        body: 'App 内用在留卡 + (半年内住民票 或 My Number)完成实名。'
            '收款方支持微信/支付宝/银行卡,推荐微信支付宝到账最快。'
            '非本人收款需上传亲属证明(结婚证/户口本)。',
      ),
      GuideStep(
        title: 'App 发起订单',
        body: '输入要汇的日元金额 → 选择收款人 → 选择"ATM 自助转账" → '
            'App 会给出一个本次专用的 MUFG(三菱 UFJ) 收款账号、户名和金额,'
            '通常账户名是假名(エムビリング 等),户名和金额每次不同。',
        warning: '金额必须和 App 显示完全一致,差 1 日元都会触发风控。',
      ),
      GuideStep(
        title: '前往 MUFG 或 JP Bank ATM',
        body: 'MUFG ATM 最稳,JP Bank 郵便局 也支持。'
            '选择"振込(振り込み)" → 输入 App 给的银行、支店、账号、金额。',
        tip: '熊猫指定的是 MUFG 收款,不同批次支店不同,按 App 当次显示为准。',
        image: 'assets/guide/raw/page-01.png',
      ),
      GuideStep(
        title: '拍照凭证上传',
        body: '转账完成后 ATM 会吐出一张振込凭证,拍照上传到 App 对应订单。',
        warning: '不上传凭证 → 到账会延迟,甚至被风控要求你补提'
            '"收入证明"(源泉徴収票 或 工资条)。',
      ),
      GuideStep(
        title: '等待到账',
        body: '常规 10–30 分钟到账国内收款方。超时可先联系客服,不要反复重发订单。',
      ),
    ],
    footer: '📎 官方教程: 熊猫速汇 App 底部 → 帮助中心 → "日本汇款中国相关教程"',
  ),

  // --------- 2. Wise ---------
  Guide(
    name: 'Wise',
    tagline: '费率次优 · 非国内团队 · 风控退款较慢',
    tags: ['限额 300w/月', '和熊猫不共享', 'PayPay 银行', 'ツツジ支店'],
    steps: [
      GuideStep(
        title: 'Wise App 创建汇款',
        body: '金额 → 收款方 → 付款方式选"银行转账" → Wise 会给出一个'
            ' PayPay 银行(ペイペイ銀行)的收款账号,支行固定是 ツツジ支店,'
            '但收款人名字/账号每笔不同。',
        copyable: {
          '收款银行': 'PayPay 銀行 (PayPay Bank)',
          '支店名': 'ツツジ支店',
          '支店首字': 'ツ',
        },
        warning: '支行必须选 ツツジ支店,首字 ツ,别按到 ツジ。',
        image: 'assets/guide/raw/page-02.png',
      ),
      GuideStep(
        title: '去 JP Bank / Seven Bank ATM',
        body: '插卡或刷折 → 振込 → "他の金融機関へ" → '
            '金融機関選択里 PayPay 不在常用列表,翻到 **"その他"**(最后一页)。',
        tip: '"その他"就是"其他银行",翻到最下面点它。',
        image: 'assets/guide/raw/page-03.png',
      ),
      GuideStep(
        title: '片假名键盘选首字 ツ',
        body: '进入金融機関名選択键盘 → 按 "ツ"。翻页时注意看屏幕标题。',
        image: 'assets/guide/raw/page-04.png',
      ),
      GuideStep(
        title: '确认 PayPay 銀行',
        body: '列表里点 PayPay 銀行,进入下一步支店名選択。',
        image: 'assets/guide/raw/page-05.png',
      ),
      GuideStep(
        title: '支店名 → ツ → 选 ツツジ支店',
        body: '再次片假名键盘选 "ツ",列表里会出 ツツジ支店,点它。',
        warning: '屏幕标题是"支店名の選択",不是"金融機関名の選択"。',
        image: 'assets/guide/raw/page-06.png',
      ),
      GuideStep(
        title: '口座种类 普通預金',
        body: '選擇 普通預金,然后输入 App 给的 7 位账号(如 0168607)和金额,'
            '确认收款人名与 App 显示一致 → 按確認 → 放入现金或从账户扣款。',
        image: 'assets/guide/raw/page-08.png',
      ),
      GuideStep(
        title: 'ご確認 → 确认一切无误',
        body: '最终 ATM 会显示金融機関、支店、口座、金額、收款人。'
            '比对 Wise App 显示的内容,一致再按 確認。',
        warning: '看到 "+220円" 这种是 ATM 手续费,不要以为金额错了。',
        image: 'assets/guide/raw/page-09.png',
      ),
      GuideStep(
        title: 'Wise App 标记"已完成银行转账"',
        body: '转账完成后回到 App 点"我已完成银行转账",Wise 收到到款后开始结算。',
        tip: '单笔 50w 日元,Wise 比熊猫约少 ¥100 CNY。累计多笔差距更大。',
      ),
    ],
    footer: '⚠️ 如被 Wise 风控,退款周期较长(非国内团队)。大额优先走熊猫。',
  ),

  // --------- 3. JRF Wallet ---------
  Guide(
    name: 'JRF',
    tagline: '需先办卡充值 · 再 App 内汇款 · 单笔 200w 日元',
    tags: ['JRF ECO 预付卡', '日本金融牌照', '限额 300w/月'],
    steps: [
      GuideStep(
        title: '申请 JRF ECO 卡',
        body: '官网 / App 提交在留卡 + My Number(或住民票)。'
            '审核通过后邮寄 JRF ECO 预付卡到你的日本住址。',
        tip: '卡本身不是借记卡,是"预付充值载体",收到激活才能用。',
      ),
      GuideStep(
        title: '往卡里充值日元',
        body: '有两种方式:\n'
            '  ① ATM: 用 JRF ECO 卡在合作 ATM(含 Seven Bank / JP Bank)直接存现金\n'
            '  ② 银行转账: 从你的日本银行账户转账到 JRF 指定的专属虚拟账户\n'
            '单笔上限 200w 日元。',
        warning: '钱进到的是你在 JRF 的 Wallet 余额,不是直接汇出。',
      ),
      GuideStep(
        title: 'App 发起汇款',
        body: 'JRF Wallet App 选收款人 → 输入 CNY 金额 → 选择支付宝/微信/银行卡 → '
            '确认费率和到手 → 提交。',
      ),
      GuideStep(
        title: '等待到账',
        body: '常规 10–30 分钟,部分银行/风控时段 1 天内。',
        tip: 'JRF 费率略高于熊猫速汇,但好处: 钱留在 Wallet 里可以多笔小额发,不用每次跑 ATM。',
      ),
    ],
    footer: '📎 日本金融厅登录番号可在 App 底部查询,用于核验正规性。',
  ),

  // --------- 4. 中国银行(日本) ---------
  Guide(
    name: '中行日本',
    tagline: '开户麻烦 · 单次费率一般 · 大额稳妥',
    tags: ['东京/大阪/横滨/名古屋/福冈', '日元/USD/CNY', '1-5 工作日'],
    steps: [
      GuideStep(
        title: '预约开户',
        body: '去中行日本分行(东京/大阪/横滨/名古屋/福冈任一)柜台预约开户。\n'
            '也可以在国内先申请"赴日代理开户见证服务",到日本后半年内到柜台'
            '完成本人确认和领取存折。',
        warning: '半年内没去柜台激活 → 账户会被销户。',
      ),
      GuideStep(
        title: '开户所需材料',
        body: '带齐:\n'
            '  • 在留卡(原件)\n'
            '  • My Number 通知卡 或个人番号卡\n'
            '  • 住址证明(住民票 或 公共事业账单)\n'
            '  • 印章(银行印,可现场刻)\n'
            '  • 护照(部分网点需要)',
      ),
      GuideStep(
        title: '网银或柜台发起汇款',
        body: '开通个人网银后,登录选"汇出汇款" → 选币种(可日元、美元、CNY 预结汇)'
            ' → 填收款人信息(本人或国内亲属的中行账号、英文户名)→ 提交。',
        copyable: {
          '可选币种': '日元 / 美元 / CNY(预结汇) / HKD / EUR / GBP',
        },
        tip: '预结汇: 在日本把日元直接换成 CNY 汇出,国内账户收到就是 CNY,省一步。',
      ),
      GuideStep(
        title: '填写汇款申请(如走柜台)',
        body: '携带存折、印章、在留卡,填《汇款申请书》。\n'
            '金额较大时银行可能要求:\n'
            '  • 资金来源证明(工资单 / 源泉徴収票 / 税票)\n'
            '  • 非本人收款 → 亲属关系证明',
      ),
      GuideStep(
        title: '等待到账',
        body: '常规 1–5 个工作日。收款方是中行国内账户最快(同行当日/次日),他行需中转手续费。',
        warning: '国内收款人年度个人外汇上限 5w USD。超额需提前用亲属额度。',
      ),
    ],
    footer: '📞 东京分行客服: 0120-66-1090(日本境内免费)',
  ),
];
