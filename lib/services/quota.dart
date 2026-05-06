import '../models/exchange_record.dart';

/// 每个 JPY 渠道独立的额度(不共享)。
class QuotaUsage {
  final double monthUsed;
  final double yearUsed;
  final double monthLimit;
  final double yearLimit;
  const QuotaUsage({
    required this.monthUsed,
    required this.yearUsed,
    this.monthLimit = 3000000,
    this.yearLimit = 6000000,
  });

  double get monthRemaining => (monthLimit - monthUsed).clamp(0, monthLimit);
  double get yearRemaining => (yearLimit - yearUsed).clamp(0, yearLimit);

  double get monthPct => monthUsed / monthLimit;
  double get yearPct => yearUsed / yearLimit;

  /// 国内每人年度 5w USD 外汇上限(换算)
  /// 5w USD ≈ 5w × Wise USD/JPY rate JPY (可以换成 JPY 比)
  /// 这里只是工具,真实 5w 值由调用方按当前汇率换算后传入
}

class QuotaService {
  /// 按渠道统计本月 / 本年 JPY 投入。
  static QuotaUsage forChannel(
      List<ExchangeRecord> records, String channel, DateTime now) {
    double month = 0, year = 0;
    for (final r in records) {
      if (r.channel != channel) continue;
      final jpy = r.jpyAmount;
      if (jpy == null) continue;
      if (r.at.year == now.year) {
        year += jpy;
        if (r.at.month == now.month) month += jpy;
      }
    }
    return QuotaUsage(monthUsed: month, yearUsed: year);
  }

  /// 按收款人统计本年累计(折 USD) — 用于 5w USD/年 外汇管制追踪。
  /// 传入 usdJpyRate 用于把日元金额折算成 USD。
  static Map<String, double> yearlyUsdByRecipient(
      List<ExchangeRecord> records, DateTime now,
      {double? usdJpyRate}) {
    final out = <String, double>{};
    for (final r in records) {
      if (r.at.year != now.year) continue;
      // 按 USDT 量计(≈ USD)是最接近真实监管口径的
      out[r.recipient] = (out[r.recipient] ?? 0) + r.usdtAmount;
    }
    return out;
  }
}
