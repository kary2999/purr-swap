import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/quote.dart';

/// Wise 实时中间价 (USDT ≈ USD)。
/// 端点返回: {"source":"USD","target":"CNY","value":6.818,"time":...}
class WiseClient {
  static Future<Quote> fetch({String source = 'USD', String target = 'CNY'}) async {
    final url = Uri.parse('https://wise.com/rates/live?source=$source&target=$target');
    final resp = await http.get(url, headers: {
      'User-Agent':
          'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36',
      'Accept': 'application/json',
    });
    if (resp.statusCode != 200) {
      throw Exception('Wise ${resp.statusCode}: ${_snip(resp.body)}');
    }
    final decoded = jsonDecode(resp.body);
    // 兼容两种返回: 单对象 or 数组
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
      note: 'mid-market',
    );
  }

  static String _snip(String s) => s.length > 200 ? s.substring(0, 200) : s;
}
