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
  // CNY → CNY 全链路损耗（用户真实场景: CNY → USDT → JPY → CNY）
  final double? inputCny;       // 投入 CNY (= usdt × cnyToUsdtRate)
  final double? cnyLossPct;     // 损耗% = (inputCny - cnyNet) / inputCny × 100
  ForecastRow({
    required this.channel,
    required this.cnyNet,
    this.jpyIn,
    this.breakdown = const [],
    this.pctVsBest,
    this.isMeasured = true,
    this.inputCny,
    this.cnyLossPct,
  });
}

class ForecastService {
  /// 输入 USDT 数量 + 当前所有报价,输出每条渠道预计到手 CNY。
  ///
  /// [cnyToUsdtRate] = 用户当时买 USDT 时的 CNY/USDT 单价（如 7.20）。
  /// 用于反推 CNY → CNY 全链路损耗：
  ///   inputCny = usdt × cnyToUsdtRate
  ///   cnyLossPct = (inputCny - cnyNet) / inputCny × 100
  /// null 时按优先级取默认: Binance 蓝钻 > Binance 大宗 > OKX > Wise USD/CNY > 7.20
  static List<ForecastRow> forecast({
    required double usdt,
    required List<Quote> quotes,
    double? cnyToUsdtRate,
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
    //
    // leg1 (USDT/USD → JPY): 共用 Wise（用户实际把 U 变 JPY 的最常见路径）
    //   - 若拉到 Wise USD/JPY 线性 fee 模型 → fee = a + b × usdt (内扣, USD)
    //     真正进入下一段的 JPY = (usdt - fee_usd) × wiseUsdJpyMid
    //   - 否则 fallback: 不扣 leg1 fee, 用 mid 直接算 (高估约 0.4-1%)
    if (wiseUsdJpy != null) {
      final leg1FeeUsd = wiseUsdJpyQ?.feeFor(usdt.toDouble()) ?? 0;
      final usdEffective = (usdt - leg1FeeUsd).clamp(0.0, double.infinity);
      final jpyGross = usdEffective * wiseUsdJpy;
      final leg1Measured = wiseUsdJpyQ?.isMeasured ?? false;
      final leg1Label = leg1Measured
          ? 'Wise 实测扣 ${leg1FeeUsd.toStringAsFixed(2)} USD'
          : 'Wise mid (fee 不可知)';

      for (final c in kChannels.where((c) => c.twoHop)) {
        double? leg2Rate;
        String leg2Label;
        bool leg2Measured = false;
        // 实际从 JPY 端扣的 fee（外扣是固定 platformFee, 内扣按线性模型）
        double leg2FeeJpy = 0;
        // 渠道汇率类型说明（用于 breakdown）
        String leg2RateSource = '';

        switch (c.jpyCnyRateSource) {
          // === 实测牌价 + 外扣固定 fee ===
          case '熊猫速汇':
            leg2Rate = pandaJpyCny;
            leg2Label = '熊猫平台牌价';
            leg2RateSource = '熊猫 API';
            leg2Measured = true;
            leg2FeeJpy = c.platformFeeJpy;
            break;
          case '中行(日本)':
            leg2Rate = bocJpyCny;
            leg2Label = '中行牌价';
            leg2RateSource = '熊猫 API · 中行';
            leg2Measured = true;
            leg2FeeJpy = c.platformFeeJpy;
            break;
          case 'Seven Bank':
            leg2Rate = sevenBankJpyCny;
            leg2Label = '7Bank 牌价';
            leg2RateSource = '熊猫 API · 7Bank';
            leg2Measured = true;
            leg2FeeJpy = c.platformFeeJpy;
            break;
          // === 无自家牌价 API ===
          default:
            if (c.name == 'Wise(JPY)' && wiseJpyCnyQ != null && wiseJpyCnyQ.isMeasured) {
              // Wise 实测线性 fee 模型 (内扣)
              // 用 JPY 端实测 fee 公式，先算 fee 再用 mid 换
              final estJpy = (jpyGross - c.atmFeeJpy).clamp(0.0, double.infinity);
              final feeJpy = wiseJpyCnyQ.feeFor(estJpy) ?? c.platformFeeJpy;
              leg2FeeJpy = feeJpy;
              leg2Rate = wiseJpyCny; // 用 mid 单独扣 fee（不再用 effectiveRate 防止 double-count）
              leg2Label = 'Wise mid';
              leg2RateSource = 'Wise comparisons API';
              leg2Measured = true;
            } else if (c.name == '邮局(JPY)') {
              // 邮局: 外扣 165 + Wise mid 减 TTS spread 估算
              leg2FeeJpy = c.platformFeeJpy;
              leg2Rate = wiseJpyCny != null ? wiseJpyCny * (1 - c.markupPct) : null;
              leg2Label = 'Wise mid − ${(c.markupPct * 100).toStringAsFixed(1)}% TTS';
              leg2RateSource = 'Wise mid · TTS 估算';
              leg2Measured = false;
            } else {
              // JRF (无 API) / Wise fallback / 其他
              leg2FeeJpy = c.platformFeeJpy;
              leg2Rate = wiseJpyCny != null ? wiseJpyCny * (1 - c.markupPct) : null;
              leg2Label = 'Wise mid − ${(c.markupPct * 100).toStringAsFixed(2)}%';
              leg2RateSource = '内置估算';
              leg2Measured = false;
            }
        }
        if (leg2Rate == null) continue;

        final jpyAfterAtm = (jpyGross - c.atmFeeJpy).clamp(0.0, double.infinity);
        final jpyAfterPlatform = (jpyAfterAtm - leg2FeeJpy).clamp(0.0, double.infinity);
        final cnyNet = jpyAfterPlatform * leg2Rate;

        rows.add(ForecastRow(
          channel: c,
          cnyNet: cnyNet,
          jpyIn: jpyGross,
          isMeasured: leg1Measured && leg2Measured,
          breakdown: [
            '$usdt USDT − 扣 ${leg1FeeUsd.toStringAsFixed(2)} USD ($leg1Label) → '
                '${usdEffective.toStringAsFixed(2)} × ${wiseUsdJpy.toStringAsFixed(2)} '
                '= ¥${jpyGross.toStringAsFixed(0)} JPY',
            if (c.atmFeeJpy > 0)
              '减 ¥${c.atmFeeJpy.toStringAsFixed(0)} 入金振込费 (邮局默认; ATM 略高)',
            '减 ¥${leg2FeeJpy.toStringAsFixed(0)} ${c.feeKind.longLabel} 平台手续费',
            '× ${leg2Rate.toStringAsFixed(5)} ($leg2Label · 来源 $leg2RateSource) '
                '= ¥${cnyNet.toStringAsFixed(2)} CNY',
          ],
        ));
      }
    }

    // === CNY → USDT 默认汇率（用户的 leg0：在国内买 U 的成本）===
    // 优先用用户手输; 否则按 Binance 蓝钻 > 大宗 > OKX > Wise USD/CNY > 7.20 兜底
    final defaultCnyRate = cnyToUsdtRate ??
        binanceBlueDiamond ??
        binanceBlock ??
        okx ??
        wiseUsdCny ??
        7.20;
    final inputCny = usdt * defaultCnyRate;

    // 按到手 CNY 降序,标最优差 + 算 CNY 全链路损耗
    rows.sort((a, b) => b.cnyNet.compareTo(a.cnyNet));
    if (rows.isNotEmpty) {
      final best = rows.first.cnyNet;
      for (int i = 0; i < rows.length; i++) {
        final r = rows[i];
        final pct = best > 0 ? (r.cnyNet - best) / best * 100 : 0.0;
        final lossPct = inputCny > 0 ? (inputCny - r.cnyNet) / inputCny * 100 : null;
        rows[i] = ForecastRow(
            channel: r.channel,
            cnyNet: r.cnyNet,
            jpyIn: r.jpyIn,
            breakdown: r.breakdown,
            pctVsBest: pct,
            isMeasured: r.isMeasured,
            inputCny: inputCny,
            cnyLossPct: lossPct);
      }
    }
    return rows;
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
