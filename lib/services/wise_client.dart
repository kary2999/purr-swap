import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/quote.dart';

/// Wise 客户端。
///
/// **优先**: `api.wise.com/v3/comparisons` —— Wise 自家**真实 fee + 实际汇率**
///   返回结构: providers[].alias=='wise' 的 quotes[0] 包含
///     - rate            (Wise 实际成交汇率, 接近 mid)
///     - fee             (sample sendAmount 下的实际 fee, source 币种)
///     - receivedAmount  (扣 fee 后用户拿到的 target 金额)
///
/// **关键**: Wise fee 是阶梯式 (`fee ≈ a + b × amount`)，单 sample 外推到其他金额会严重偏差。
/// 实测拟合极好 (JPY/CNY: 10k→708, 200k→3072, 1M→13027；线性 R² ≈ 1.000)
/// 因此本 client **拉小+大两个 sample**，建立线性 fee 模型存进 [Quote.feeIntercept] / [Quote.feeSlope]。
///
/// **回退**: `wise.com/rates/live` —— 只能拿 mid-market（无 fee）
class WiseClient {
  static const _ua =
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36';

  /// 拉一个币对的 Wise 报价（含线性 fee 模型）。
  static Future<Quote> fetch({
    String source = 'USD',
    String target = 'CNY',
  }) async {
    // 按 source 货币选两个合理 sample 金额(小+大，跨越用户常见金额)
    final samples = _samplesFor(source);

    // 并行拉两个 sample
    final results = await Future.wait([
      _fetchOneSample(source, target, samples[0]).catchError((_) => null),
      _fetchOneSample(source, target, samples[1]).catchError((_) => null),
    ]);
    final s1 = results[0];
    final s2 = results[1];

    if (s1 == null && s2 == null) {
      // 两个 sample 都失败 → fallback mid-only
      return _fetchMidOnly(source, target);
    }

    // 至少有一个 sample 可用
    final use = s2 ?? s1!;
    final mid = use['rate'] as double;
    double? feeIntercept;
    double? feeSlope;

    if (s1 != null && s2 != null) {
      // 线性拟合 fee = a + b × amount，两点确定一条线
      final x1 = samples[0], x2 = samples[1];
      final f1 = s1['fee'] as double, f2 = s2['fee'] as double;
      if (x2 != x1) {
        feeSlope = (f2 - f1) / (x2 - x1);
        feeIntercept = f1 - feeSlope * x1;
      }
    }

    final sampleAmount = samples[1]; // 用大 sample 作为参考
    final effectiveRate = use['receivedAmount'] / sampleAmount;

    return Quote(
      source: 'Wise',
      pair: '$source/$target',
      mid: mid,
      effectiveRate: effectiveRate,
      fee: use['fee'] as double,
      feePctApprox: (use['fee'] as double) / sampleAmount,
      sampleAmount: sampleAmount,
      feeIntercept: feeIntercept,
      feeSlope: feeSlope,
      isMeasured: true,
      note: feeIntercept != null && feeSlope != null
          ? '实测线性 fee = ${feeIntercept.toStringAsFixed(0)} + '
              '${(feeSlope * 100).toStringAsFixed(3)}% (内扣)'
          : '实测 (单点)',
    );
  }

  static List<double> _samplesFor(String source) {
    switch (source) {
      case 'JPY':
        return [10000.0, 200000.0]; // 用户常见 1-20w JPY
      case 'USD':
      case 'EUR':
      case 'GBP':
        return [100.0, 5000.0];
      default:
        return [100.0, 5000.0];
    }
  }

  static Future<Map<String, dynamic>?> _fetchOneSample(
      String source, String target, double amount) async {
    final url = Uri.parse(
      'https://api.wise.com/v3/comparisons/'
      '?sourceCurrency=$source&targetCurrency=$target&sendAmount=$amount',
    );
    final resp = await http.get(url, headers: {
      'User-Agent': _ua,
      'Accept': 'application/json',
    }).timeout(const Duration(seconds: 8));
    if (resp.statusCode != 200) return null;

    final root = jsonDecode(resp.body) as Map<String, dynamic>;
    final providers = (root['providers'] as List?) ?? const [];
    for (final p in providers) {
      if ((p as Map)['alias'] != 'wise') continue;
      final quotes = (p['quotes'] as List?) ?? const [];
      if (quotes.isEmpty) return null;
      final q = quotes.first as Map<String, dynamic>;
      final rate = _toD(q['rate']);
      final fee = _toD(q['fee']);
      final received = _toD(q['receivedAmount']);
      if (rate == null || fee == null || received == null) return null;
      return {'rate': rate, 'fee': fee, 'receivedAmount': received};
    }
    return null;
  }

  static Future<Quote> _fetchMidOnly(String source, String target) async {
    final url = Uri.parse(
        'https://wise.com/rates/live?source=$source&target=$target');
    final resp = await http.get(url, headers: {
      'User-Agent': _ua,
      'Accept': 'application/json',
    });
    if (resp.statusCode != 200) {
      throw Exception('Wise mid ${resp.statusCode}: ${_snip(resp.body)}');
    }
    final decoded = jsonDecode(resp.body);
    final obj = decoded is List
        ? (decoded.isNotEmpty ? decoded.first as Map<String, dynamic> : null)
        : decoded as Map<String, dynamic>;
    if (obj == null) throw Exception('Wise: empty response');
    final raw = obj['value'] ?? obj['rate'];
    if (raw == null) throw Exception('Wise: no value/rate field');
    final rate = (raw is num) ? raw.toDouble() : double.parse(raw.toString());

    return Quote(
      source: 'Wise',
      pair: '$source/$target',
      mid: rate,
      isMeasured: false,
      note: 'mid-market only (comparisons API 不可用, fee 走内置估算)',
    );
  }

  static double? _toD(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }

  static String _snip(String s) => s.length > 200 ? s.substring(0, 200) : s;
}
