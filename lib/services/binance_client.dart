import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/quote.dart';

/// 币安 C2C / P2P 公开搜索。
/// 用户"卖 USDT 换 CNY" → tradeType = SELL。
/// merchantCheck=true → 只看认证/蓝钻商家。
/// minTransAmount 传 50000 即大宗区。
class BinanceP2PClient {
  static const _url =
      'https://p2p.binance.com/bapi/c2c/v2/friendly/c2c/adv/search';

  static Future<Quote> fetch({
    String tradeType = 'SELL',
    int rows = 10,
    bool merchantCheck = true,
    int? minTransAmount,
    String label = 'Binance-P2P',
  }) async {
    final body = {
      'proMerchantAds': false,
      'page': 1,
      'rows': rows,
      'payTypes': <String>[],
      'countries': <String>[],
      'publisherType': merchantCheck ? 'merchant' : null,
      if (minTransAmount != null) 'transAmount': minTransAmount.toString(),
      'fiat': 'CNY',
      'tradeType': tradeType,
      'asset': 'USDT',
      'merchantCheck': merchantCheck,
    };

    final resp = await http.post(
      Uri.parse(_url),
      headers: {
        'Content-Type': 'application/json',
        'User-Agent':
            'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) currency-probe/0.1',
      },
      body: jsonEncode(body),
    );
    if (resp.statusCode != 200) {
      throw Exception('Binance ${resp.statusCode}: ${resp.body.substring(0, 200)}');
    }

    final root = jsonDecode(resp.body) as Map<String, dynamic>;
    final data = root['data'] as List? ?? [];
    final prices = <double>[];
    for (final e in data) {
      final p = (e as Map)['adv']?['price'];
      if (p is String) {
        final d = double.tryParse(p);
        if (d != null) prices.add(d);
      }
    }
    if (prices.isEmpty) throw Exception('Binance: no ads returned');

    prices.sort();
    final median = prices[prices.length ~/ 2];
    final best = tradeType == 'SELL' ? prices.last : prices.first;

    return Quote(
      source: label,
      pair: 'USDT/CNY',
      mid: median,
      bestBid: best,
      sampleSize: prices.length,
      note: merchantCheck
          ? '认证商家${minTransAmount != null ? " · 大宗≥¥$minTransAmount" : ""}'
          : '全部',
    );
  }
}
