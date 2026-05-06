import 'package:flutter/material.dart';
import '../models/quote.dart';
import '../services/forecast.dart';

/// 输入 USDT → 预测所有渠道到手 CNY。
class ForecastCard extends StatefulWidget {
  final double usdt;
  final List<Quote> quotes;
  final void Function(String channel)? onPick;
  const ForecastCard({
    super.key,
    required this.usdt,
    required this.quotes,
    this.onPick,
  });

  @override
  State<ForecastCard> createState() => _ForecastCardState();
}

class _ForecastCardState extends State<ForecastCard> {
  int? _expanded;

  @override
  Widget build(BuildContext c) {
    if (widget.quotes.isEmpty) return const SizedBox.shrink();
    final rows = ForecastService.forecast(
        usdt: widget.usdt, quotes: widget.quotes);
    if (rows.isEmpty) return const SizedBox.shrink();

    return Card(
      color: Colors.green.shade50,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.auto_awesome, size: 16, color: Colors.green.shade700),
                const SizedBox(width: 6),
                Text('${widget.usdt.toStringAsFixed(0)} USDT 预计到手',
                    style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: Colors.green.shade900)),
                const Spacer(),
                Text('点行展开明细',
                    style: TextStyle(fontSize: 10, color: Colors.green.shade700)),
              ],
            ),
            const SizedBox(height: 8),
            ...List.generate(rows.length, (i) => _row(i, rows[i])),
          ],
        ),
      ),
    );
  }

  Widget _row(int idx, ForecastRow r) {
    final isBest = idx == 0;
    final expanded = _expanded == idx;
    final pct = r.pctVsBest ?? 0;
    final pctStr = isBest
        ? '最优'
        : '${pct.toStringAsFixed(2)}%';
    final pctColor = isBest ? Colors.green.shade800 : Colors.red.shade700;

    return InkWell(
      onTap: () => setState(() => _expanded = expanded ? null : idx),
      onLongPress: () => widget.onPick?.call(r.channel.name),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        decoration: BoxDecoration(
          border: Border(
              bottom: BorderSide(color: Colors.green.shade100, width: 0.5)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                SizedBox(
                  width: 18,
                  child: Icon(
                    isBest ? Icons.emoji_events : Icons.chevron_right,
                    size: 16,
                    color: isBest ? Colors.amber.shade700 : Colors.grey,
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(r.channel.name,
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight:
                                  isBest ? FontWeight.w600 : FontWeight.w500)),
                      if (r.channel.tagline.isNotEmpty)
                        Text(r.channel.tagline,
                            style: const TextStyle(
                                fontSize: 10, color: Colors.grey)),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('¥ ${r.cnyNet.toStringAsFixed(2)}',
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: isBest ? Colors.green.shade800 : null)),
                    Text(pctStr,
                        style: TextStyle(fontSize: 10, color: pctColor)),
                  ],
                ),
              ],
            ),
            if (expanded) ...[
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.only(left: 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: r.breakdown
                      .map((line) => Padding(
                            padding: const EdgeInsets.only(bottom: 2),
                            child: Text('· $line',
                                style: const TextStyle(
                                    fontSize: 11, color: Colors.black54)),
                          ))
                      .toList(),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
