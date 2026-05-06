// CLI 探针: dart run bin/probe.dart
import 'package:currency_exchange/services/rate_fetcher.dart';

Future<void> main() async {
  print('=== 多渠道汇率快照 ===\n');
  final t = DateTime.now();
  final quotes = await RateFetcher.fetchAll();
  final ms = DateTime.now().difference(t).inMilliseconds;

  if (quotes.isEmpty) {
    print('没有任何源连通。');
    return;
  }

  // 分组输出
  final groups = <String, List>{};
  for (final q in quotes) {
    groups.putIfAbsent(q.pair, () => []).add(q);
  }
  for (final e in groups.entries) {
    print('-- ${e.key} --');
    final sorted = List.of(e.value)..sort((a, b) => (b.mid as num).compareTo(a.mid as num));
    for (final q in sorted) {
      print('  ${q.source.padRight(16)} ${q.mid.toStringAsFixed(4)}   ${q.note}');
    }
    print('');
  }
  print('共 ${quotes.length} 条, 耗时 ${ms}ms');
}
