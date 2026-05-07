import '../models/exchange_record.dart';
import '../models/quote.dart';

/// 一次预测结果。
class ForecastRow {
  final ChannelMeta channel;
  final double cnyNet;          // 预计到手 CNY
  final double? jpyIn;          // 中转 JPY (仅两段)
  final List<String> breakdown; // 费用明细
  final double? pctVsBest;      // 相对最优渠道差 %
  ForecastRow({
    required this.channel,
    required this.cnyNet,
    this.jpyIn,
    this.breakdown = const [],
    this.pctVsBest,
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

    final wiseUsdCny = q('Wise', 'USD/CNY')?.mid;
    final wiseUsdJpy = q('Wise', 'USD/JPY')?.mid;
    final wiseJpyCny = q('Wise', 'JPY/CNY')?.mid;
    final visaUsdCny = q('Visa', 'USD/CNY')?.mid;
    final binanceBlueDiamond = q('Binance-蓝钻', 'USDT/CNY')?.mid;
    final binanceBlock = q('Binance-大宗', 'USDT/CNY')?.mid;
    final okx = q('OKX-C2C', 'USDT/CNY')?.mid;
    final pandaJpyCny = q('熊猫速汇', 'JPY/CNY')?.mid;
    final bocJpyCny = q('中行(日本)', 'JPY/CNY')?.mid;
    final sevenBankJpyCny = q('Seven Bank', 'JPY/CNY')?.mid;

    final rows = <ForecastRow>[];

    // --- 直连渠道 ---
    void addDirect(ChannelMeta c, double? rate, {String rateLabel = ''}) {
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
          channel: c, cnyNet: net, breakdown: parts));
    }

    for (final c in kChannels.where((c) => !c.twoHop)) {
      switch (c.name) {
        case 'Binance OTC':
          addDirect(c, binanceBlueDiamond ?? binanceBlock,
              rateLabel: 'Binance 蓝钻 OTC');
          break;
        case 'OKX OTC':
          addDirect(c, okx, rateLabel: 'OKX C2C');
          break;
        case '线下人民币':
          addDirect(c, wiseUsdCny, rateLabel: '按 Wise 中间价(乐观)');
          break;
        case 'Visa 卡取现':
          addDirect(c, visaUsdCny, rateLabel: 'Visa 官方');
          break;
      }
    }

    // --- 两段渠道 USDT → JPY → CNY ---
    if (wiseUsdJpy != null) {
      for (final c in kChannels.where((c) => c.twoHop)) {
        double? leg2Rate;
        String leg2Label;
        switch (c.jpyCnyRateSource) {
          case '熊猫速汇':
            leg2Rate = pandaJpyCny;
            leg2Label = '熊猫';
            break;
          case '中行(日本)':
            leg2Rate = bocJpyCny;
            leg2Label = '中行';
            break;
          case 'Seven Bank':
            leg2Rate = sevenBankJpyCny;
            leg2Label = '7Bank';
            break;
          default:
            // Wise / JRF 没有平台实时价,用 Wise mid-market 减 markup 模拟
            leg2Rate =
                wiseJpyCny != null ? wiseJpyCny * (1 - c.markupPct) : null;
            leg2Label = 'Wise mid − ${(c.markupPct * 100).toStringAsFixed(2)}%';
        }
        if (leg2Rate == null) continue;

        final jpyGross = usdt * wiseUsdJpy;
        final jpyAfterAtm = jpyGross - c.atmFeeJpy;
        final jpyAfterPlatform = jpyAfterAtm - c.platformFeeJpy;
        final cnyNet = jpyAfterPlatform * leg2Rate;

        rows.add(ForecastRow(
          channel: c,
          cnyNet: cnyNet,
          jpyIn: jpyGross,
          breakdown: [
            '$usdt × ${wiseUsdJpy.toStringAsFixed(2)} = ¥${jpyGross.toStringAsFixed(0)} JPY',
            if (c.atmFeeJpy > 0)
              '减 ¥${c.atmFeeJpy.toStringAsFixed(0)} ATM 振込费',
            if (c.platformFeeJpy > 0)
              '减 ¥${c.platformFeeJpy.toStringAsFixed(0)} 平台手续费',
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
            pctVsBest: pct);
      }
    }
    return rows;
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
