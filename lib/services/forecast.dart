import '../models/exchange_record.dart';
import '../models/quote.dart';

/// 一次预测结果。
class ForecastRow {
  final ChannelMeta channel;
  final double cnyNet;          // 预计到手 CNY
  final double? jpyIn;          // 中转 JPY (仅两段)
  final List<String> breakdown; // 费用明细
  final double? pctVsBest;      // 相对最优渠道差 %
  final bool isMeasured;        // 全链路是否都是实测（vs 内置估算）
  ForecastRow({
    required this.channel,
    required this.cnyNet,
    this.jpyIn,
    this.breakdown = const [],
    this.pctVsBest,
    this.isMeasured = true,
  });
}

class ForecastService {
  /// 输入 USDT 数量 + 当前所有报价,输出每条渠道预计到手 CNY。
  static List<ForecastRow> forecast({
    required double usdt,
    required List<Quote> quotes,
  }) {
    // 索引查价
    Quote? q(String source, String pair) =>
        quotes.where((x) => x.source == source && x.pair == pair).firstOrNull;

    final wiseUsdCnyQ = q('Wise', 'USD/CNY');
    final wiseUsdJpyQ = q('Wise', 'USD/JPY');
    final wiseJpyCnyQ = q('Wise', 'JPY/CNY');
    final wiseUsdCny = wiseUsdCnyQ?.mid;
    final wiseUsdJpy = wiseUsdJpyQ?.mid;
    final wiseJpyCny = wiseJpyCnyQ?.mid;
    // ↓ comparisons API 实测的"含 fee 实际汇率"（无则为 null，走估算回退）
    final wiseUsdJpyEff = wiseUsdJpyQ?.effectiveRate;
    final wiseJpyCnyEff = wiseJpyCnyQ?.effectiveRate;
    final visaUsdCny = q('Visa', 'USD/CNY')?.mid;
    final binanceBlueDiamond = q('Binance-蓝钻', 'USDT/CNY')?.mid;
    final binanceBlock = q('Binance-大宗', 'USDT/CNY')?.mid;
    final okx = q('OKX-C2C', 'USDT/CNY')?.mid;
    final pandaJpyCny = q('熊猫速汇', 'JPY/CNY')?.mid;
    final bocJpyCny = q('中行(日本)', 'JPY/CNY')?.mid;
    final sevenBankJpyCny = q('Seven Bank', 'JPY/CNY')?.mid;

    final rows = <ForecastRow>[];

    // --- 直连渠道 ---
    void addDirect(ChannelMeta c, double? rate,
        {String rateLabel = '', bool isMeasured = true}) {
      if (rate == null) return;
      final gross = usdt * rate;
      final afterMarkup = gross * (1 - c.markupPct);
      final net = afterMarkup - c.fixedFeeCny;
      final parts = <String>[
        '${rateLabel.isNotEmpty ? "$rateLabel · " : ""}'
            '${rate.toStringAsFixed(4)} × $usdt = ¥${gross.toStringAsFixed(2)}',
      ];
      if (c.markupPct > 0) {
        parts.add('扣 ${(c.markupPct * 100).toStringAsFixed(2)}% 点差 = ¥${afterMarkup.toStringAsFixed(2)}');
      }
      if (c.fixedFeeCny > 0) {
        parts.add('减 ¥${c.fixedFeeCny.toStringAsFixed(0)} ATM 手续费');
      }
      rows.add(ForecastRow(
          channel: c, cnyNet: net, breakdown: parts, isMeasured: isMeasured));
    }

    for (final c in kChannels.where((c) => !c.twoHop)) {
      switch (c.name) {
        case 'Binance OTC':
          // C2C 成交价 = 实测净价
          addDirect(c, binanceBlueDiamond ?? binanceBlock,
              rateLabel: 'Binance 蓝钻 OTC', isMeasured: true);
          break;
        case 'OKX OTC':
          addDirect(c, okx, rateLabel: 'OKX C2C', isMeasured: true);
          break;
        case '线下人民币':
          // Wise mid 当 P2P 成交价是乐观估算
          addDirect(c, wiseUsdCny,
              rateLabel: '按 Wise 中间价(乐观)', isMeasured: false);
          break;
        case 'Visa 卡取现':
          // Visa 官方汇率实测，但 markup/atmFee 内置估算
          addDirect(c, visaUsdCny,
              rateLabel: 'Visa 官方', isMeasured: false);
          break;
      }
    }

    // --- 两段渠道 USDT → JPY → CNY ---
    if (wiseUsdJpy != null) {
      // leg1 (USDT/USD → JPY): 优先用 Wise comparisons 实测，否则 fallback mid
      final leg1Rate = wiseUsdJpyEff ?? wiseUsdJpy;
      final leg1IsMeasured = wiseUsdJpyEff != null;
      final leg1Label = leg1IsMeasured ? 'Wise 实测' : 'Wise mid';

      for (final c in kChannels.where((c) => c.twoHop)) {
        double? leg2Rate;
        String leg2Label;
        bool leg2IsMeasured = false;
        // 当 leg2 走 comparisons 实测，platformFee 已经在 effectiveRate 里 → 置 0
        double effectivePlatformFee = c.platformFeeJpy;

        switch (c.jpyCnyRateSource) {
          case '熊猫速汇':
            leg2Rate = pandaJpyCny;
            leg2Label = '熊猫 实测牌价';
            leg2IsMeasured = true;
            break;
          case '中行(日本)':
            leg2Rate = bocJpyCny;
            leg2Label = '中行 实测牌价';
            leg2IsMeasured = true;
            break;
          case 'Seven Bank':
            leg2Rate = sevenBankJpyCny;
            leg2Label = '7Bank 实测牌价';
            leg2IsMeasured = true;
            break;
          default:
            // Wise(JPY) / JRF Wallet 没有自家牌价 API
            if (c.name == 'Wise(JPY)' && wiseJpyCnyEff != null) {
              // Wise comparisons 实测，含 fee
              leg2Rate = wiseJpyCnyEff;
              leg2Label = 'Wise comparisons 实测';
              leg2IsMeasured = true;
              effectivePlatformFee = 0; // fee 已在 effectiveRate
            } else {
              // JRF（无 API）/ Wise 回退（API 失败）→ mid - 内置估算 markup
              leg2Rate = wiseJpyCny != null
                  ? wiseJpyCny * (1 - c.markupPct)
                  : null;
              leg2Label =
                  'Wise mid − ${(c.markupPct * 100).toStringAsFixed(2)}% (估算)';
              leg2IsMeasured = false;
            }
        }
        if (leg2Rate == null) continue;

        final jpyGross = usdt * leg1Rate;
        final jpyAfterAtm = jpyGross - c.atmFeeJpy;
        final jpyAfterPlatform = jpyAfterAtm - effectivePlatformFee;
        final cnyNet = jpyAfterPlatform * leg2Rate;

        rows.add(ForecastRow(
          channel: c,
          cnyNet: cnyNet,
          jpyIn: jpyGross,
          isMeasured: leg1IsMeasured && leg2IsMeasured,
          breakdown: [
            '$usdt × ${leg1Rate.toStringAsFixed(2)} ($leg1Label) = ¥${jpyGross.toStringAsFixed(0)} JPY',
            if (c.atmFeeJpy > 0)
              '减 ¥${c.atmFeeJpy.toStringAsFixed(0)} ATM 振込费',
            if (effectivePlatformFee > 0)
              '减 ¥${effectivePlatformFee.toStringAsFixed(0)} 平台手续费',
            '× ${leg2Rate.toStringAsFixed(5)} ($leg2Label) = ¥${cnyNet.toStringAsFixed(2)} CNY',
          ],
        ));
      }
    }

    // 按到手 CNY 降序,标最优差
    rows.sort((a, b) => b.cnyNet.compareTo(a.cnyNet));
    if (rows.isNotEmpty) {
      final best = rows.first.cnyNet;
      for (int i = 0; i < rows.length; i++) {
        final r = rows[i];
        final pct = best > 0 ? (r.cnyNet - best) / best * 100 : 0.0;
        rows[i] = ForecastRow(
            channel: r.channel,
            cnyNet: r.cnyNet,
            jpyIn: r.jpyIn,
            breakdown: r.breakdown,
            pctVsBest: pct,
            isMeasured: r.isMeasured);
      }
    }
    return rows;
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
