import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/quote.dart';

/// 熊猫速汇价格接口(公开,prod 域名稳定)。
/// 一次返回 3 个平台的 JPY→CNY 实时费率:
///   • panda  — 熊猫本家
///   • boc    — 中国银行日本
///   • 7bank  — Seven Bank
///
/// 返回 rate 单位是 "每 100 JPY 得到多少 CNY",我们归一化为每 1 JPY。
/// fee 是每笔固定手续费(JPY),后续可用于估算"到手 CNY"。
class PandaRemitClient {
  static const _url =
      'https://prod.pandaremit.com/pricing/rate/all/JPY/CNY';

  /// 返回 3 条 JPY/CNY quote。
  static Future<List<Quote>> fetchAll() async {
    final resp = await http.get(
      Uri.parse(_url),
      headers: {
        'Accept': 'application/json',
        'User-Agent':
            'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) currency-probe/0.1',
      },
    );
    if (resp.statusCode != 200) {
      throw Exception('Panda ${resp.statusCode}: ${_snip(resp.body)}');
    }
    final root = jsonDecode(resp.body) as Map<String, dynamic>;
    if (root['suc'] != true) {
      throw Exception('Panda suc=false: ${_snip(resp.body)}');
    }
    final rates = (root['model']?['rates'] as List?) ?? [];
    return rates
        .map((e) => _parse(e as Map<String, dynamic>))
        .whereType<Quote>()
        .toList();
  }

  static Quote? _parse(Map<String, dynamic> j) {
    final platform = j['platform'] as String?;
    final rateStr = j['rate']?.toString();
    final unit = (j['unit'] as num?)?.toInt() ?? 100;
    final fee = double.tryParse(j['fee']?.toString() ?? '') ?? 0;
    if (platform == null || rateStr == null) return null;
    final raw = double.tryParse(rateStr);
    if (raw == null) return null;
    final perJpy = raw / unit; // 每 1 JPY 得到的 CNY

    final label = switch (platform) {
      'panda' => '熊猫速汇',
      'boc' => '中行(日本)',
      '7bank' => 'Seven Bank',
      _ => platform,
    };

    return Quote(
      source: label,
      pair: 'JPY/CNY',
      mid: perJpy,
      sampleSize: 1,
      note: '手续费 ¥${fee.toStringAsFixed(0)} JPY/笔',
    );
  }

  /// 到手 CNY 估算: (jpyAmount - feeJpy) × ratePerJpy
  static double netCnyAfterFee({
    required double jpyAmount,
    required double ratePerJpy,
    required double feeJpy,
  }) =>
      (jpyAmount - feeJpy) * ratePerJpy;

  static String _snip(String s) => s.length > 200 ? s.substring(0, 200) : s;
}
