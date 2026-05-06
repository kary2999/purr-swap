import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import '../models/quote.dart';

/// Visa 官方汇率。返回结构:
///   originalValues.fxRateVisa = 0.1466  (Visa 把 USD 当 base,返回 CNY→USD)
///   reverseAmount = 6.8218                (USD→CNY,我们需要的方向)
///
/// 周末/节假日 Visa 不发新汇率,今日 400 时回退到前 7 天。
class VisaClient {
  static const _ua =
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36';

  static Future<Quote> fetch({String from = 'USD', String to = 'CNY'}) async {
    String? lastErr;
    // 只试 今天、昨天、前天 三个日期,不然并发慢
    for (int back = 0; back <= 2; back++) {
      final date = DateFormat('MM/dd/yyyy')
          .format(DateTime.now().subtract(Duration(days: back)));
      final url = Uri.parse('https://usa.visa.com/cmsapi/fx/rates').replace(
        queryParameters: {
          'amount': '1',
          'fee': '0',
          'utcConvertedDate': date,
          'exchangedate': date,
          'fromCurr': from,
          'toCurr': to,
        },
      );
      try {
        final resp = await http.get(url, headers: {
          'User-Agent': _ua,
          'Accept': 'application/json',
        }).timeout(const Duration(seconds: 6));
        if (resp.statusCode != 200) {
          lastErr = 'HTTP ${resp.statusCode}';
          continue;
        }
        final root = jsonDecode(resp.body) as Map<String, dynamic>;
        // 首选 reverseAmount (USD→CNY 方向)
        final rev = root['reverseAmount'];
        double? rate;
        if (rev != null) {
          rate = (rev is num) ? rev.toDouble() : double.tryParse(rev.toString());
        }
        // 回退: 1 / fxRateVisa (若数据源方向反转)
        if (rate == null || rate <= 0) {
          final fx = root['originalValues']?['fxRateVisa'];
          final fxd = fx is num ? fx.toDouble() : double.tryParse(fx?.toString() ?? '');
          if (fxd != null && fxd > 0) rate = 1.0 / fxd;
        }
        if (rate == null) {
          lastErr = 'no rate fields';
          continue;
        }
        return Quote(
          source: 'Visa',
          pair: '$from/$to',
          mid: rate,
          note: 'Visa官方 $date (未扣千6+ATM)',
        );
      } catch (e) {
        lastErr = e.toString();
      }
    }
    throw Exception('Visa: 7 天内无可用数据 ($lastErr)');
  }

  /// 按用户默认规则估算 Visa 卡 ATM 到手 CNY:
  ///   net = usd * visaRate * (1 - 0.006) - atmFeeCny
  static double netCnyFromVisa({
    required double usdAmount,
    required double visaRate,
    double markup = 0.006,
    double atmFeeCny = 15.0,
  }) =>
      usdAmount * visaRate * (1 - markup) - atmFeeCny;
}
