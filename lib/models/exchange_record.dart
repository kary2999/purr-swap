/// 一笔换汇记录。
///
/// 两种链路:
///   ① 直接路径  USDT → CNY        (Binance/OKX/线下/Visa)
///      → jpyAmount 留空,referenceRate = Wise USD/CNY
///   ② 两段路径  USDT → JPY → CNY (熊猫/Wise/JRF/中行 - 在日本)
///      → jpyAmount 必填,两个参考率都存
class ExchangeRecord {
  final String id;
  final DateTime at;
  final String channel;
  final double usdtAmount;
  final double? jpyAmount;        // 中转日元(USDT→JPY 段的产出)
  final double cnyReceived;
  final double referenceRate;     // USDT→CNY 或 USDT→JPY (直接/中转段 1)
  final double? jpyCnyReference;  // JPY→CNY Wise (仅两段路径)
  final String recipient;         // 本人 / 配偶 / 父 / 母 / 其他
  final String note;

  ExchangeRecord({
    required this.id,
    required this.at,
    required this.channel,
    required this.usdtAmount,
    this.jpyAmount,
    required this.cnyReceived,
    required this.referenceRate,
    this.jpyCnyReference,
    this.recipient = '本人',
    this.note = '',
  });

  bool get isTwoHop => jpyAmount != null;

  /// 直接路径的成交汇率
  double get effectiveRate => cnyReceived / usdtAmount;

  /// 相对 Wise 全链路预期的相对偏差%
  /// 单段: (eff - ref)/ref * 100
  /// 两段: eff vs (ref1 * ref2)
  double get pctVsReference {
    final expected = expectedCny;
    if (expected == 0) return 0;
    return (cnyReceived - expected) / expected * 100;
  }

  /// 按 Wise 基准的"理论到手 CNY"
  double get expectedCny {
    if (isTwoHop && jpyCnyReference != null) {
      // USDT→JPY 段用 referenceRate(USD/JPY),JPY→CNY 段用 jpyCnyReference
      return usdtAmount * referenceRate * jpyCnyReference!;
    }
    return usdtAmount * referenceRate;
  }

  /// 总汇损(正值 = 亏了,负值 = 溢价)
  double get costVsReference => expectedCny - cnyReceived;

  /// 第一段实际汇率(USDT→JPY), 仅两段路径
  double? get leg1EffectiveRate =>
      isTwoHop ? jpyAmount! / usdtAmount : null;

  /// 第二段实际汇率(JPY→CNY), 仅两段路径
  double? get leg2EffectiveRate =>
      isTwoHop ? cnyReceived / jpyAmount! : null;

  /// 第一段相对 Wise 偏差%
  double? get leg1PctVsRef {
    if (!isTwoHop) return null;
    return (leg1EffectiveRate! - referenceRate) / referenceRate * 100;
  }

  /// 第二段相对 Wise 偏差%
  double? get leg2PctVsRef {
    if (!isTwoHop || jpyCnyReference == null) return null;
    return (leg2EffectiveRate! - jpyCnyReference!) / jpyCnyReference! * 100;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'at': at.toIso8601String(),
        'channel': channel,
        'usdtAmount': usdtAmount,
        'jpyAmount': jpyAmount,
        'cnyReceived': cnyReceived,
        'referenceRate': referenceRate,
        'jpyCnyReference': jpyCnyReference,
        'recipient': recipient,
        'note': note,
      };

  factory ExchangeRecord.fromJson(Map<String, dynamic> j) => ExchangeRecord(
        id: j['id'] as String,
        at: DateTime.parse(j['at'] as String),
        channel: j['channel'] as String,
        usdtAmount: (j['usdtAmount'] as num).toDouble(),
        jpyAmount: (j['jpyAmount'] as num?)?.toDouble(),
        cnyReceived: (j['cnyReceived'] as num).toDouble(),
        referenceRate: (j['referenceRate'] as num).toDouble(),
        jpyCnyReference: (j['jpyCnyReference'] as num?)?.toDouble(),
        recipient: (j['recipient'] as String?) ?? '本人',
        note: (j['note'] as String?) ?? '',
      );
}

/// 风险等级
enum RiskLevel { veryLow, low, medium, high }

extension RiskLevelX on RiskLevel {
  String get label => switch (this) {
        RiskLevel.veryLow => '极低',
        RiskLevel.low => '低',
        RiskLevel.medium => '中',
        RiskLevel.high => '高',
      };
}

/// 外部参考链接
class RiskReference {
  final String title;
  final String url;
  const RiskReference(this.title, this.url);
}

/// 渠道能力 + 费率 + 风险元数据。
class ChannelMeta {
  final String name;
  final bool twoHop;
  final bool jpyQuotaControlled;
  final double platformFeeJpy;
  final double atmFeeJpy;
  final double markupPct;
  final double fixedFeeCny;
  final String? jpyCnyRateSource;
  final String? downloadUrl;
  final String tagline;
  // 风险模型
  final RiskLevel risk;
  final String riskNote;
  final List<RiskReference> riskRefs;

  const ChannelMeta(
    this.name, {
    this.twoHop = false,
    this.jpyQuotaControlled = false,
    this.platformFeeJpy = 0,
    this.atmFeeJpy = 0,
    this.markupPct = 0,
    this.fixedFeeCny = 0,
    this.jpyCnyRateSource,
    this.downloadUrl,
    this.tagline = '',
    this.risk = RiskLevel.medium,
    this.riskNote = '',
    this.riskRefs = const [],
  });
}

const kChannels = <ChannelMeta>[
  // ========== 合规渠道 ==========
  ChannelMeta(
    '中国银行汇款',
    twoHop: true,
    jpyQuotaControlled: true,
    platformFeeJpy: 6000,
    atmFeeJpy: 440,
    jpyCnyRateSource: '中行(日本)',
    downloadUrl:
        'https://www.boc.cn/jp/custserv/cs1/201301/t20130111_2167389.html',
    tagline: '¥6000/笔 · 大额才划算',
    risk: RiskLevel.veryLow,
    riskNote: '完全合规合法。需亲自去日本中行柜台操作(或网银),'
        '需国内本人/直系亲属有中行账户作为收款方。'
        '资金走银行间 SWIFT,完全受两国金融监管。',
    riskRefs: [
      RiskReference('中行日本 · 汇出汇款 FAQ',
          'https://www.boc.cn/jp/custserv/cs4/201303/t20130327_2208608.html'),
    ],
  ),
  ChannelMeta(
    '熊猫速汇(JPY)',
    twoHop: true,
    jpyQuotaControlled: true,
    platformFeeJpy: 800,
    atmFeeJpy: 440,
    jpyCnyRateSource: '熊猫速汇',
    downloadUrl: 'https://www.pandaremit.com/download',
    tagline: '800 JPY/笔 · 10-30min 到账 · 国内团队',
    risk: RiskLevel.low,
    riskNote: '持有日本金融厅(関東財務局)登录番号 · 正规合规平台。'
        '大额/长期使用可能被要求提供收入证明(源泉徴収票/工资单)。'
        '收款方 **仅推荐微信/支付宝**,国内银行卡有被临时冻结的概率。',
    riskRefs: [
      RiskReference('熊猫速汇合规说明',
          'https://www.pandaremit.com/en/jpn/send-money-to-china'),
    ],
  ),
  ChannelMeta(
    '7Bank(JPY)',
    twoHop: true,
    jpyQuotaControlled: true,
    platformFeeJpy: 2000,
    atmFeeJpy: 440,
    jpyCnyRateSource: 'Seven Bank',
    downloadUrl: 'https://www.sevenbank.co.jp/personal/oversea/',
    tagline: '2000 JPY/笔 · 便利店 ATM 直发',
    risk: RiskLevel.low,
    riskNote: '由 Seven Bank(日本上市行,JFSA 持牌)运营。'
        '便利店 ATM 直发,操作便利但单笔费用高于熊猫(2000 vs 800)。'
        '小额不划算,大额体验最便捷。收款方建议微信/支付宝。',
    riskRefs: [],
  ),
  ChannelMeta(
    'Wise(JPY)',
    twoHop: true,
    jpyQuotaControlled: true,
    // Wise 实际: 固定 ¥350 + 0.44% 浮动 (JPY→CNY)。我们用等价固定 + 点差近似
    platformFeeJpy: 350,
    markupPct: 0.0044,
    atmFeeJpy: 440,
    downloadUrl: 'https://wise.com/download',
    tagline: '非国内团队 · 风控退款慢',
    risk: RiskLevel.low,
    riskNote: '英国/欧盟金融牌照,合规。**风控严格**,大额/高频'
        '易触发审核,退款周期 1-4 周。'
        '收款同样推荐微信/支付宝,银行卡慎用。',
    riskRefs: [
      RiskReference('Wise 国际汇款合规说明',
          'https://wise.com/help/articles/2977951'),
    ],
  ),
  ChannelMeta(
    'JRF Wallet',
    twoHop: true,
    jpyQuotaControlled: true,
    // JRF 实际: ¥1000/笔 + 约 0.3% 点差 vs mid
    platformFeeJpy: 1000,
    atmFeeJpy: 440,
    markupPct: 0.003,
    downloadUrl: 'https://www.jrf.co.jp/app/',
    tagline: 'ECO 预付卡 · 可多笔小额',
    risk: RiskLevel.low,
    riskNote: '日本金融厅登录番号平台,正规合规。'
        '大额同样需要资金来源证明。收款建议微信/支付宝。',
    riskRefs: [],
  ),

  // ========== 中风险 ==========
  ChannelMeta(
    'Visa 卡取现',
    markupPct: 0.006,
    fixedFeeCny: 15,
    tagline: '国内 ATM 取现 千6+¥15',
    risk: RiskLevel.medium,
    riskNote: '发卡方多为离岸机构(圣文森特/开曼),监管灰区。'
        '资金走 Visa 国际清算,**无法提供中国境内合法收入证明**。'
        '国内已有多起 U 卡 ATM 取现被定性为"非法经营/洗钱"案例。'
        '高频/大额使用可能触发银行风控或立案。',
    riskRefs: [
      RiskReference('Web3律师:USDT 银行卡法律问题',
          'https://news.qq.com/rain/a/20240809A09D8300'),
      RiskReference('U卡境内运营合规风险',
          'https://news.qq.com/rain/a/20240802A06G6V00'),
      RiskReference('U卡热度飙升 存在哪些风险(新浪财经)',
          'https://finance.sina.com.cn/blockchain/roll/2025-02-10/doc-ineiyprh3696633.shtml'),
    ],
  ),
  ChannelMeta(
    '线下人民币',
    tagline: '朋友/同事直接人民币',
    risk: RiskLevel.medium,
    riskNote: '无法核实对方资金来源,对方若为币商/黑灰产,'
        '收到款后仍有被冻卡风险。熟人小额相对安全。',
    riskRefs: [
      RiskReference('普通用户如何规避冻卡(新浪)',
          'https://finance.sina.cn/blockchain/2023-11-01/detail-imztasyu9096454.d.html'),
    ],
  ),

  // ========== 高风险 ==========
  ChannelMeta(
    'Binance OTC',
    tagline: 'P2P 蓝钻 / 大宗',
    risk: RiskLevel.high,
    riskNote: '国内司法解释已明确: **与黑 U 交易即使不知情,'
        '个人银行卡仍会被冻结 3 天 - 6 个月**。冻卡后虽然资金'
        '最终会解冻(走刑事流程),但期间银行卡全面停用。'
        '2024 年同比冻卡案例 +300%,高峰期国内 60% U 商卡被封。',
    riskRefs: [
      RiskReference('2026 最新防冻卡全攻略',
          'https://zhuanlan.zhihu.com/p/1911098655341023325'),
      RiskReference('买U卖U的刑事法律风险(律师解读)',
          'https://www.houqilawyer.com/thickpointofview/info.aspx?itemid=2493'),
      RiskReference('真实案例: U 商面临的刑事风险',
          'https://web3caff.com/archives/115546'),
    ],
  ),
  ChannelMeta(
    'OKX OTC',
    tagline: 'C2C 订单簿',
    risk: RiskLevel.high,
    riskNote: '同 Binance OTC。C2C 订单簿流动性更杂,'
        '对手方不可控风险更高。冻卡风险与币安同量级。',
    riskRefs: [
      RiskReference('黑灰产利用 USDT 的六大犯罪路径(腾讯)',
          'https://news.qq.com/rain/a/20250928A04JSE00'),
      RiskReference('亲历三次暴雷后,2025 出 U 最安全三种姿势',
          'https://zhuanlan.zhihu.com/p/31081779415'),
    ],
  ),
];

ChannelMeta metaFor(String name) =>
    kChannels.firstWhere((c) => c.name == name,
        orElse: () => const ChannelMeta(''));

const kRecipients = ['本人', '配偶', '父', '母', '子女', '兄弟姐妹', '其他'];
