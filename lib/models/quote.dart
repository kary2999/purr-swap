class Quote {
  final String source;       // 渠道名: Binance-蓝钻 / OKX / Wise / Visa
  final String pair;         // USDT/CNY or USD/CNY
  final double mid;          // 中间价(参考)
  final double? bestBid;     // 最优价 (卖U时是最高价)
  // ===== 含 fee 的"用户实际拿到"汇率（仅 Wise comparisons 等支持的源） =====
  final double? effectiveRate;  // = receivedAmount / sendAmount
  final double? fee;            // 抽样金额下的实际 fee（source 货币单位）
  final double? feePctApprox;   // fee / sendAmount 比例（用于按比例外推到其他金额）
  final double? sampleAmount;   // 抽样金额
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
    this.isMeasured = false,
    this.sampleSize = 0,
    DateTime? sampledAt,
    this.note = '',
  }) : sampledAt = sampledAt ?? DateTime.now();

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
