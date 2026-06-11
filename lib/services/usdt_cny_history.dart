import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import '../models/quote.dart';

/// 历史 USDT/CNY(CoinGecko 官方口径日线)+ 用实时币安 P2P 溢价反推历史"币安卖出价"。
///
/// 用途: ATM 取现是直连 USDT→CNY(无中转日元), 其损耗要对比"成交当天若在币安 P2P
/// 卖出能拿到的 CNY"。币安 P2P 历史价无公开 API, 故用:
///   估算币安卖出价(date) = CoinGecko[date] × (实时币安P2P ÷ CoinGecko最新)
/// 拿不到实时币安时 premium=1, 退化为官方口径(会低估真实卖出价)。
class UsdtCnyHistory {
  static UsdtCnyHistory? _instance;

  final Map<String, double> _rates; // 'YYYY-MM-DD' -> CoinGecko USDT/CNY
  final List<String> _sortedKeys;
  final String from;
  final String to;
  UsdtCnyHistory._(this._rates, this._sortedKeys, this.from, this.to);

  static Future<UsdtCnyHistory> load() async {
    if (_instance != null) return _instance!;
    final raw =
        await rootBundle.loadString('assets/data/usdt_cny_history.json');
    final j = jsonDecode(raw) as Map<String, dynamic>;
    final rates = <String, double>{};
    (j['rates'] as Map<String, dynamic>)
        .forEach((k, v) => rates[k] = (v as num).toDouble());
    final keys = rates.keys.toList()..sort();
    _instance = UsdtCnyHistory._(
        rates, keys, j['from'] as String? ?? '', j['to'] as String? ?? '');
    return _instance!;
  }

  String _fmt(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// CoinGecko 官方口径 USDT/CNY: 取 ≤date 的最近一天; 早于数据范围则取最早。
  double? coingeckoAt(DateTime date) {
    if (_sortedKeys.isEmpty) return null;
    final key = _fmt(date);
    final exact = _rates[key];
    if (exact != null) return exact;
    String? best;
    for (final k in _sortedKeys) {
      if (k.compareTo(key) <= 0) {
        best = k;
      } else {
        break;
      }
    }
    best ??= _sortedKeys.first;
    return _rates[best];
  }

  double? get coingeckoLatest =>
      _sortedKeys.isEmpty ? null : _rates[_sortedKeys.last];

  /// 实时币安 P2P 相对 CoinGecko 最新值的溢价比例(>1 表示 P2P 更高)。
  double premium(List<Quote> liveQuotes) {
    final latest = coingeckoLatest;
    if (latest == null || latest <= 0) return 1.0;
    final liveBin = liveQuotes
        .where((q) =>
            (q.source == 'Binance-蓝钻' || q.source == 'Binance-大宗') &&
            q.pair == 'USDT/CNY')
        .map((q) => q.mid)
        .where((m) => m > 0)
        .cast<double?>()
        .firstWhere((_) => true, orElse: () => null);
    if (liveBin == null) return 1.0;
    return liveBin / latest;
  }

  /// 估算"成交当天币安 P2P 卖出价"(USDT/CNY)。
  double? estBinanceSellAt(DateTime date, List<Quote> liveQuotes) {
    final cg = coingeckoAt(date);
    if (cg == null) return null;
    return cg * premium(liveQuotes);
  }
}
