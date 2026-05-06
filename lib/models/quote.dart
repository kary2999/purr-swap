class Quote {
  final String source;     // 渠道名: Binance-蓝钻 / OKX / Wise / Visa
  final String pair;       // USDT/CNY or USD/CNY
  final double mid;        // 代表价
  final double? bestBid;   // 最优价 (卖U时是最高价)
  final int sampleSize;
  final DateTime sampledAt;
  final String note;

  Quote({
    required this.source,
    required this.pair,
    required this.mid,
    this.bestBid,
    this.sampleSize = 0,
    DateTime? sampledAt,
    this.note = '',
  }) : sampledAt = sampledAt ?? DateTime.now();

  Map<String, dynamic> toMap() => {
        'source': source,
        'pair': pair,
        'mid': mid,
        'bestBid': bestBid,
        'sampleSize': sampleSize,
        'sampledAt': sampledAt.toIso8601String(),
        'note': note,
      };
}
