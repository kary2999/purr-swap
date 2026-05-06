import '../models/quote.dart';
import 'binance_client.dart';
import 'okx_client.dart';
import 'panda_client.dart';
import 'visa_client.dart';
import 'wise_client.dart';

/// 统一编排层: 并发拉所有源。单源失败不影响其他。
class RateFetcher {
  static Future<List<Quote>> fetchAll() async {
    final tasks = <Future<List<Quote>>>[
      _safe(() async => [
            await BinanceP2PClient.fetch(
                merchantCheck: true, label: 'Binance-蓝钻'),
          ]),
      _safe(() async => [
            await BinanceP2PClient.fetch(
                merchantCheck: true,
                minTransAmount: 50000,
                label: 'Binance-大宗'),
          ]),
      _safe(() async => [await OkxC2CClient.fetch()]),
      _safe(() async => [await WiseClient.fetch()]), // USD/CNY
      _safe(() async =>
          [await WiseClient.fetch(source: 'USD', target: 'JPY')]),
      _safe(() async =>
          [await WiseClient.fetch(source: 'JPY', target: 'CNY')]),
      _safe(() async => [await VisaClient.fetch()]),
      _safe(() => PandaRemitClient.fetchAll()), // 熊猫/BOC/7Bank 三合一
    ];
    final results = await Future.wait(tasks);
    return results.expand((e) => e).toList();
  }

  static Future<List<Quote>> _safe(Future<List<Quote>> Function() f) async {
    try {
      return await f();
    } catch (e) {
      // ignore: avoid_print
      print('[ERR] ${e.toString().split('\n').first}');
      return [];
    }
  }
}
