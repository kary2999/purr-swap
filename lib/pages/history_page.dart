import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../models/exchange_record.dart';
import '../services/rate_cache.dart';
import '../storage/local_store.dart';
import '../theme/ios_theme.dart';
import '../widgets/ios_widgets.dart';

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});
  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  List<ExchangeRecord> _records = [];
  String _filter = '全部';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final store = await LocalStore.instance;
    final rs = await store.loadRecords();
    setState(() => _records = rs);
  }

  Future<void> _delete(ExchangeRecord r) async {
    final store = await LocalStore.instance;
    await store.deleteRecord(r.id);
    await _load();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已删除'), duration: Duration(seconds: 1)));
    }
  }

  Future<void> _edit(ExchangeRecord r) async {
    final updated = await showDialog<ExchangeRecord>(
      context: context,
      builder: (_) => _EditDialog(record: r),
    );
    if (updated == null) return;
    final store = await LocalStore.instance;
    final all = await store.loadRecords();
    final i = all.indexWhere((x) => x.id == r.id);
    if (i >= 0) {
      all[i] = updated;
      await store.saveRecords(all);
    }
    await _load();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已更新'), duration: Duration(seconds: 1)));
    }
  }

  /// 算 CNY 全链路损耗需要的 fallback CNY/USDT 价 — 当 record 没存 cnyToUsdtRate 时用。
  /// 优先级: Binance 蓝钻 > Wise USD/CNY > 7.20 兜底
  double _fallbackCnyRate() {
    final qs = RateCache.instance.snapshot;
    for (final q in qs) {
      if (q.source == 'Binance-蓝钻' && q.pair == 'USDT/CNY') return q.mid;
    }
    for (final q in qs) {
      if (q.source == 'Wise' && q.pair == 'USD/CNY') return q.mid;
    }
    return 7.20;
  }

  @override
  Widget build(BuildContext c) {
    final shown = _filter == '全部'
        ? _records
        : _records.where((r) => r.channel == _filter).toList();
    final fb = _fallbackCnyRate();
    // CNY 全链路: cost 正值 = 亏 (与 costVsReference 同符号)
    final totalCost =
        shown.fold<double>(0, (s, r) => s + (r.cnyCostWith(fb) ?? 0));
    final totalUsdt = shown.fold<double>(0, (s, r) => s + r.usdtAmount);
    final totalCny = shown.fold<double>(0, (s, r) => s + r.cnyReceived);

    // 按月分组 (yyyy-MM)
    final byMonth = <String, List<ExchangeRecord>>{};
    for (final r in shown) {
      final k = DateFormat('yyyy-MM').format(r.at);
      byMonth.putIfAbsent(k, () => []).add(r);
    }
    final sortedMonths = byMonth.keys.toList()..sort((a, b) => b.compareTo(a));

    return Scaffold(
      backgroundColor: IOS.grayBg,
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            IOSLargeTitle(
              title: '历史',
              actions: [
                IOSNavLink('筛选', onTap: _showFilter),
                IOSNavIcon(Icons.refresh, onTap: _load),
              ],
            ),
            IOSTickerBar(items: [
              TickerItem('∑ USDT', NumberFormat('#,##0').format(totalUsdt)),
              TickerItem('∑ CNY', '¥${NumberFormat('#,##0').format(totalCny)}'),
              TickerItem(
                '∑ 汇损',
                '${totalCost >= 0 ? "−" : "+"}¥${NumberFormat('#,##0').format(totalCost.abs())}',
                totalCost >= 0 ? TickerColor.down : TickerColor.up,
              ),
            ]),
            if (shown.isEmpty)
              _emptyState()
            else ...[
              if (shown.length >= 2) _rateTrendChart(shown),
              for (final m in sortedMonths) ...[
                _monthHeader(m, byMonth[m]!.length),
                _monthSection(byMonth[m]!),
              ],
            ],
            const SizedBox(height: 60),
          ],
        ),
      ),
    );
  }

  /// 汇率走势曲线 — 每笔的全链路实际成交价 (CNY/USDT) vs Wise 中间价。
  /// 按时间升序;筛选单一渠道时趋势最清晰。
  Widget _rateTrendChart(List<ExchangeRecord> rs) {
    final data = [...rs]..sort((a, b) => a.at.compareTo(b.at));
    final actual = <FlSpot>[];
    final ref = <FlSpot>[];
    for (int i = 0; i < data.length; i++) {
      final r = data[i];
      if (r.usdtAmount <= 0) continue;
      actual.add(FlSpot(i.toDouble(), r.effectiveRate));
      ref.add(FlSpot(i.toDouble(), r.expectedCny / r.usdtAmount));
    }
    if (actual.length < 2) return const SizedBox.shrink();

    final ys = [...actual.map((s) => s.y), ...ref.map((s) => s.y)];
    double minY = ys.reduce(math.min);
    double maxY = ys.reduce(math.max);
    final pad = (maxY - minY) * 0.18 + 0.01;
    minY -= pad;
    maxY += pad;
    final lastIdx = (data.length - 1).toDouble();

    String dateAt(double x) {
      final i = x.round().clamp(0, data.length - 1);
      return DateFormat('MM/dd').format(data[i].at);
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(IOS.radCard),
        border: Border.all(color: IOS.separator, width: 0.5),
        boxShadow: IOS.softShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text('汇率走势 · CNY / USDT',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: IOS.textPrimary)),
              ),
              _legendDot(IOS.coral, '实际成交'),
              const SizedBox(width: 10),
              _legendDot(IOS.gray, 'Wise 中间价'),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(top: 2, bottom: 10),
            child: Text(
              _filter == '全部' ? '全部渠道 · 筛选单一渠道趋势更清晰' : '$_filter · 每笔实际到手价',
              style: const TextStyle(fontSize: 11, color: IOS.gray),
            ),
          ),
          SizedBox(
            height: 168,
            child: LineChart(
              LineChartData(
                minX: 0,
                maxX: lastIdx,
                minY: minY,
                maxY: maxY,
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: ((maxY - minY) / 3).clamp(0.001, double.infinity),
                  getDrawingHorizontalLine: (_) =>
                      const FlLine(color: IOS.separator, strokeWidth: 0.5),
                ),
                titlesData: FlTitlesData(
                  topTitles:
                      const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles:
                      const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 40,
                      interval: ((maxY - minY) / 3).clamp(0.001, double.infinity),
                      getTitlesWidget: (v, _) => Text(
                        v.toStringAsFixed(2),
                        style: IOS.monoSize(9, color: IOS.gray),
                      ),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 20,
                      interval: lastIdx <= 0 ? 1 : lastIdx,
                      getTitlesWidget: (v, meta) {
                        if (v != meta.min && v != meta.max) {
                          return const SizedBox.shrink();
                        }
                        return Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(dateAt(v),
                              style: IOS.monoSize(9, color: IOS.gray)),
                        );
                      },
                    ),
                  ),
                ),
                borderData: FlBorderData(show: false),
                lineTouchData: LineTouchData(
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipColor: (_) => IOS.textPrimary.withValues(alpha: 0.9),
                    getTooltipItems: (spots) => spots.map((s) {
                      final isActual = s.barIndex == 0;
                      return LineTooltipItem(
                        '${isActual ? "实际" : "Wise"} ${s.y.toStringAsFixed(3)}\n${dateAt(s.x)}',
                        TextStyle(
                          color: isActual ? IOS.coral2 : Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      );
                    }).toList(),
                  ),
                ),
                lineBarsData: [
                  // 实际成交 (珊瑚橙实线 + 渐变填充)
                  LineChartBarData(
                    spots: actual,
                    isCurved: true,
                    curveSmoothness: 0.25,
                    color: IOS.coral,
                    barWidth: 2.5,
                    dotData: FlDotData(
                      show: actual.length <= 24,
                      getDotPainter: (s, _, __, ___) => FlDotCirclePainter(
                          radius: 2.5,
                          color: IOS.coral,
                          strokeWidth: 0),
                    ),
                    belowBarData: BarAreaData(
                      show: true,
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          IOS.coral.withValues(alpha: 0.18),
                          IOS.coral.withValues(alpha: 0.0),
                        ],
                      ),
                    ),
                  ),
                  // Wise 中间价 (灰色虚线参考)
                  LineChartBarData(
                    spots: ref,
                    isCurved: true,
                    curveSmoothness: 0.25,
                    color: IOS.gray,
                    barWidth: 1.5,
                    dashArray: [4, 3],
                    dotData: const FlDotData(show: false),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _legendDot(Color c, String label) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 7, height: 7, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
          const SizedBox(width: 4),
          Text(label, style: const TextStyle(fontSize: 10, color: IOS.gray)),
        ],
      );

  Widget _monthHeader(String m, int count) {
    final parts = m.split('-');
    return MonthHeader('${parts[0]} 年 ${int.parse(parts[1])} 月 · $count 笔');
  }

  Widget _monthSection(List<ExchangeRecord> rs) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(IOS.radCard),
        border: Border.all(color: IOS.separator, width: 0.5),
        boxShadow: IOS.softShadow,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(IOS.radCard),
        child: Column(
          children: [
            for (int i = 0; i < rs.length; i++) ...[
              _historyRow(rs[i]),
              if (i != rs.length - 1) const Divider(height: 0.5, color: IOS.separator),
            ],
          ],
        ),
      ),
    );
  }

  Widget _historyRow(ExchangeRecord r) {
    final fb = _fallbackCnyRate();
    // CNY 全链路损耗 — input(USDT × cnyRate) − cnyReceived
    final cost = r.cnyCostWith(fb) ?? 0;
    final pct = r.cnyLossPctWith(fb) ?? 0;
    final isLoss = cost >= 0;
    return Dismissible(
      key: ValueKey(r.id),
      background: Container(
        color: IOS.red,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 18),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) async {
        return await showDialog<bool>(
              context: context,
              builder: (_) => AlertDialog(
                title: const Text('删除这条?'),
                content: Text(
                  '${DateFormat('MM-dd HH:mm').format(r.at)} ${r.channel}\n'
                  '${r.usdtAmount.toStringAsFixed(0)} USDT → ¥${r.cnyReceived.toStringAsFixed(2)}',
                ),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('取消')),
                  FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: IOS.red),
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('删除'),
                  ),
                ],
              ),
            ) ??
            false;
      },
      onDismissed: (_) => _delete(r),
      child: InkWell(
        onTap: () => _edit(r),
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          color: Colors.white,
          child: Row(
            children: [
              ChannelIcon(r.channel),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      r.isTwoHop
                          ? '${r.usdtAmount.toStringAsFixed(0)} USDT → ${(r.jpyAmount! / 10000).toStringAsFixed(1)}万 → ¥${r.cnyReceived.toStringAsFixed(0)}'
                          : '${r.usdtAmount.toStringAsFixed(0)} USDT → ¥${r.cnyReceived.toStringAsFixed(2)}',
                      style: IOS.monoSize(14,
                          weight: FontWeight.w500, color: IOS.textPrimary),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5),
                          decoration: BoxDecoration(
                            color: IOS.blue.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: Text(
                            _shortChannel(r.channel),
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: IOS.blue,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            '${DateFormat('MM-dd HH:mm').format(r.at)} → ${r.recipient}'
                            '${r.note.isNotEmpty ? ' · ${r.note}' : ''}',
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 11, color: IOS.gray),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${isLoss ? "−" : "+"}¥${cost.abs().toStringAsFixed(0)}',
                    style: IOS.monoSize(14,
                        weight: FontWeight.w600,
                        color: isLoss ? IOS.red : IOS.green),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${isLoss ? "−" : "+"}${pct.abs().toStringAsFixed(2)}%',
                    style: IOS.monoSize(11, color: IOS.gray),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _shortChannel(String full) {
    if (full.contains('熊猫')) return '熊猫';
    if (full.contains('OKX')) return 'OKX';
    if (full.contains('Binance')) return '币安';
    if (full.contains('Visa')) return 'Visa';
    if (full.contains('Wise')) return 'Wise';
    if (full.contains('中行') || full.contains('中国银行')) return '中行';
    if (full.contains('JRF')) return 'JRF';
    if (full.contains('线下')) return '线下';
    return full;
  }

  void _showFilter() async {
    final channels = <String>{'全部', ..._records.map((r) => r.channel)};
    final v = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: IOS.grayBg,
      builder: (_) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.symmetric(vertical: 12),
          children: [
            for (final c in channels)
              IOSRow(
                leadingIcon: c == '全部' ? Icons.list : Icons.filter_alt_outlined,
                iconColors: const [IOS.blue, IOS.blueDark],
                label: c,
                trailing: c == _filter
                    ? const Icon(Icons.check, color: IOS.blue)
                    : null,
                onTap: () => Navigator.pop(context, c),
              ),
          ],
        ),
      ),
    );
    if (v != null) setState(() => _filter = v);
  }

  Widget _emptyState() => Container(
        margin: const EdgeInsets.fromLTRB(16, 4, 16, 14),
        padding: const EdgeInsets.all(40),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(IOS.radCard),
          border: Border.all(color: IOS.separator, width: 0.5),
        ),
        alignment: Alignment.center,
        child: Column(
          children: [
            const Icon(Icons.history, size: 48, color: IOS.gray),
            const SizedBox(height: 12),
            const Text('还没有记录',
                style: TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w600, color: IOS.textPrimary)),
            const SizedBox(height: 4),
            const Text('去 + 记一笔,或设置 → 加载示例数据',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: IOS.gray)),
          ],
        ),
      );
}

class _EditDialog extends StatefulWidget {
  final ExchangeRecord record;
  const _EditDialog({required this.record});
  @override
  State<_EditDialog> createState() => _EditDialogState();
}

class _EditDialogState extends State<_EditDialog> {
  late TextEditingController _usdt, _jpy, _cny, _cnyRate, _note;
  late DateTime _at;
  late String _recipient;

  @override
  void initState() {
    super.initState();
    final r = widget.record;
    _usdt = TextEditingController(text: r.usdtAmount.toString());
    _jpy = TextEditingController(text: r.jpyAmount?.toStringAsFixed(0) ?? '');
    _cny = TextEditingController(text: r.cnyReceived.toString());
    _cnyRate = TextEditingController(
        text: r.cnyToUsdtRate?.toStringAsFixed(4) ?? '');
    _note = TextEditingController(text: r.note);
    _at = r.at;
    _recipient = r.recipient;
  }

  @override
  void dispose() {
    _usdt.dispose();
    _jpy.dispose();
    _cny.dispose();
    _cnyRate.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _pickDateTime() async {
    final d = await showDatePicker(
        context: context,
        initialDate: _at,
        firstDate: DateTime(2023),
        lastDate: DateTime(2030));
    if (d == null || !mounted) return;
    final t = await showTimePicker(
        context: context, initialTime: TimeOfDay.fromDateTime(_at));
    if (t == null) return;
    setState(() => _at = DateTime(d.year, d.month, d.day, t.hour, t.minute));
  }

  @override
  Widget build(BuildContext c) {
    final r = widget.record;
    return AlertDialog(
      title: Text('编辑 · ${r.channel}', style: const TextStyle(fontSize: 14)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            InkWell(
              onTap: _pickDateTime,
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  border: Border.all(color: IOS.separator),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(children: [
                  const Icon(Icons.event, size: 16, color: IOS.blue),
                  const SizedBox(width: 8),
                  Text(DateFormat('yyyy-MM-dd HH:mm').format(_at)),
                ]),
              ),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              value: _recipient,
              decoration: const InputDecoration(labelText: '收款人', isDense: true),
              items: kRecipients
                  .map((x) => DropdownMenuItem(value: x, child: Text(x)))
                  .toList(),
              onChanged: (v) => setState(() => _recipient = v!),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _usdt,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'USDT', isDense: true),
            ),
            if (r.isTwoHop) ...[
              const SizedBox(height: 10),
              TextField(
                controller: _jpy,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration:
                    const InputDecoration(labelText: '中转 JPY', isDense: true),
              ),
            ],
            const SizedBox(height: 10),
            TextField(
              controller: _cny,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: '实收 CNY', isDense: true),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _cnyRate,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                  labelText: 'CNY/USDT 买入价 (留空=用市场 mid 兜底)',
                  isDense: true),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _note,
              decoration: const InputDecoration(labelText: '备注', isDense: true),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消')),
        FilledButton(
          onPressed: () {
            final u = double.tryParse(_usdt.text);
            final cny = double.tryParse(_cny.text);
            final jpy = widget.record.isTwoHop
                ? double.tryParse(_jpy.text)
                : null;
            if (u == null ||
                u <= 0 ||
                cny == null ||
                cny <= 0 ||
                (widget.record.isTwoHop && (jpy == null || jpy <= 0))) {
              ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('金额必须为正数')));
              return;
            }
            Navigator.pop(
              context,
              ExchangeRecord(
                id: widget.record.id,
                at: _at,
                channel: widget.record.channel,
                usdtAmount: u,
                jpyAmount: jpy,
                cnyReceived: cny,
                referenceRate: widget.record.referenceRate,
                jpyCnyReference: widget.record.jpyCnyReference,
                cnyToUsdtRate: (() {
                  final v = double.tryParse(_cnyRate.text.trim());
                  return (v != null && v > 0) ? v : null;
                })(),
                recipient: _recipient,
                note: _note.text.trim(),
              ),
            );
          },
          child: const Text('保存'),
        ),
      ],
    );
  }
}
