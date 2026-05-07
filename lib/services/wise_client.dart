import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/quote.dart';

/// Wise 客户端。
///
/// **优先**: api.wise.com/v3/comparisons —— 拉到 Wise 自家**真实 fee + 实际汇率**
///   返回结构: providers[].alias=='wise' 的 quotes[0] 包含
///     - rate            (Wise 真实成交汇率, 接近 mid)
///     - fee             (sample sendAmount 下的实际 fee, source 货币)
///     - receivedAmount  (扣 fee 后用户拿到的 target 金额)
///   → 含 fee 的 effectiveRate = receivedAmount / sendAmount
///
/// **回退**: wise.com/rates/live —— 只能拿 mid-market 中间价（无 fee）
class WiseClient {
  static const _ua =
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36';

  /// 拉取一个币对的 Wise 报价。优先返回**含 fee 的实测值**。
  ///
  /// [sampleAmount] 用于 comparisons API 的抽样金额。fee 通常按金额阶梯，
  /// 1000 source 是个合理 sample，对应 fee% 可以外推到其他金额。
  static Future<Quote> fetch({
    String source = 'USD',
    String target = 'CNY',
    double sampleAmount = 1000,
  }) async {
    if (source == 'JPY') {
      // JPY 金额单位太小，1000 JPY 抽样 fee 比例严重偏高。改用 100000。
      if (sampleAmount == 1000) sampleAmount = 100000;
    }
    // 1) 优先 comparisons (含 fee)
    try {
      final cmp = await _fetchComparison(source, target, sampleAmount);
      if (cmp != null) return cmp;
    } catch (_) {}
    // 2) fallback mid-market only
    return _fetchMidOnly(source, target);
  }

  static Future<Quote?> _fetchComparison(
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
      final effective = amount > 0 ? received / amount : rate;
      return Quote(
        source: 'Wise',
        pair: '$source/$target',
        mid: rate,
        effectiveRate: effective,
        fee: fee,
        feePctApprox: amount > 0 ? fee / amount : null,
        sampleAmount: amount,
        isMeasured: true,
        note: 'fee $fee $source/$amount sample · 实测',
      );
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
      note: 'mid-market 中间价(comparisons API 不可用,fee 估算)',
    );
  }

  static double? _toD(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }

  static String _snip(String s) => s.length > 200 ? s.substring(0, 200) : s;
}
