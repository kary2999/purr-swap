import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/quote.dart';

/// OKX C2C 订单簿。用户视角 side=sell = 我卖 USDT。
class OkxC2CClient {
  static const _base = 'https://www.okx.com/v3/c2c/tradingOrders/books';

  static Future<Quote> fetch({String side = 'sell', int limit = 10}) async {
    final qs = {
      'quoteCurrency': 'CNY',
      'baseCurrency': 'USDT',
      'side': side,
      'paymentMethod': 'all',
      'userType': 'all',
      'sortType': side == 'sell' ? 'price_desc' : 'price_asc',
      'limit': '$limit',
    };
    final url = Uri.parse(_base).replace(queryParameters: qs);
    final resp = await http.get(url, headers: {
      'User-Agent':
          'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) currency-probe/0.1',
    });
    if (resp.statusCode != 200) {
      throw Exception('OKX ${resp.statusCode}: ${resp.body.substring(0, 200)}');
    }
    final root = jsonDecode(resp.body) as Map<String, dynamic>;
    final data = root['data'] as Map? ?? {};
    final list = (side == 'sell' ? data['sell'] : data['buy']) as List? ?? [];
    final prices = <double>[];
    for (final e in list) {
      final p = (e as Map)['price'];
      if (p is String) {
        final d = double.tryParse(p);
        if (d != null) prices.add(d);
      } else if (p is num) {
        prices.add(p.toDouble());
      }
    }
    if (prices.isEmpty) throw Exception('OKX: no orders');

    prices.sort();
    return Quote(
      source: 'OKX-C2C',
      pair: 'USDT/CNY',
      mid: prices[prices.length ~/ 2],
      bestBid: side == 'sell' ? prices.last : prices.first,
      sampleSize: prices.length,
      note: 'side=$side',
    );
  }
}
