class Quote {
  final String source;       // 渠道名: Binance-蓝钻 / OKX / Wise / Visa
  final String pair;         // USDT/CNY or USD/CNY
  final double mid;          // 中间价(参考)
  final double? bestBid;     // 最优价 (卖U时是最高价)
  // ===== 含 fee 的"用户实际拿到"汇率（仅 Wise comparisons 等支持的源） =====
  final double? effectiveRate;  // = receivedAmount / sendAmount (基于 sampleAmount)
  final double? fee;            // 抽样金额下的实际 fee（source 货币单位）
  final double? feePctApprox;   // fee / sampleAmount 比例（粗略）
  final double? sampleAmount;   // 抽样金额
  // —— 线性 fee 模型（基于两个 sample 拟合）: fee = feeIntercept + feeSlope × amount
  //    Wise 实测拟合度极好(≥3 个数据点 R² ≈ 1.000)，可放心外推到任意金额
  final double? feeIntercept;   // a in fee = a + b × amount (source 币种单位)
  final double? feeSlope;       // b in fee = a + b × amount (无单位比例, 0.01244 = 1.244%)
  final bool isMeasured;        // true=实测有 fee；false=只有中间价（需估算）
  // ===== /含 fee =====
  final int sampleSize;
  final DateTime sampledAt;
  final String note;

  Quote({
    required this.source,
    required this.pair,
    required this.mid,
    this.bestBid,
    this.effectiveRate,
    this.fee,
    this.feePctApprox,
    this.sampleAmount,
    this.feeIntercept,
    this.feeSlope,
    this.isMeasured = false,
    this.sampleSize = 0,
    DateTime? sampledAt,
    this.note = '',
  }) : sampledAt = sampledAt ?? DateTime.now();

  /// 用线性模型估算任意金额下的 fee。
  /// 若无模型则用 feePctApprox 兜底，再无则返回 null。
  double? feeFor(double sourceAmount) {
    if (feeIntercept != null && feeSlope != null) {
      return feeIntercept! + feeSlope! * sourceAmount;
    }
    if (feePctApprox != null) return feePctApprox! * sourceAmount;
    return null;
  }

  Map<String, dynamic> toMap() => {
        'source': source,
        'pair': pair,
        'mid': mid,
        'bestBid': bestBid,
        'effectiveRate': effectiveRate,
        'fee': fee,
        'feePctApprox': feePctApprox,
        'sampleAmount': sampleAmount,
        'isMeasured': isMeasured,
        'sampleSize': sampleSize,
        'sampledAt': sampledAt.toIso8601String(),
        'note': note,
      };
}
