import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/exchange_record.dart';
import '../services/quota.dart';
import '../storage/local_store.dart';
import '../theme/ios_theme.dart';
import '../widgets/ios_widgets.dart';

class StatsPage extends StatefulWidget {
  const StatsPage({super.key});
  @override
  State<StatsPage> createState() => _StatsPageState();
}

class _StatsPageState extends State<StatsPage> {
  List<ExchangeRecord> _records = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final store = await LocalStore.instance;
    final rs = await store.loadRecords();
    setState(() => _records = rs..sort((a, b) => a.at.compareTo(b.at)));
  }

  @override
  Widget build(BuildContext c) {
    return Scaffold(
      backgroundColor: IOS.grayBg,
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            IOSLargeTitle(
              title: '统计',
              leading: [
                IOSNavLink('本月 ›', onTap: () {}),
              ],
              actions: [
                IOSNavIcon(Icons.refresh, onTap: _load),
              ],
            ),
            if (_records.isEmpty)
              _emptyState()
            else ...[
              _ticker(),
              _kpiGrid(),
              ..._quotaSection(),
              ..._monthlyOutflow(),
              ..._monthlyLoss(),
              ..._channelRanking(),
            ],
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
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
            const Icon(Icons.bar_chart, size: 48, color: IOS.gray),
            const SizedBox(height: 12),
            const Text('还没数据',
                style: TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w600, color: IOS.textPrimary)),
            const SizedBox(height: 4),
            const Text('记几笔或去设置加载示例数据',
                style: TextStyle(fontSize: 12, color: IOS.gray)),
          ],
        ),
      );

  Widget _ticker() {
    final monthsMap = <String>{};
    for (final r in _records) {
      monthsMap.add(DateFormat('yyyy-MM').format(r.at));
    }
    final usdt = _records.fold<double>(0, (s, r) => s + r.usdtAmount);
    final cny = _records.fold<double>(0, (s, r) => s + r.cnyReceived);
    final firstMonth =
        monthsMap.isEmpty ? '' : (monthsMap.toList()..sort()).first;
    final lastMonth =
        monthsMap.isEmpty ? '' : (monthsMap.toList()..sort()).last;
    return IOSTickerBar(items: [
      TickerItem(
        '区间',
        firstMonth == lastMonth
            ? lastMonth
            : '${firstMonth.split('-').last}月→${lastMonth.split('-').last}月',
      ),
      TickerItem('笔数', '${_records.length}'),
      TickerItem('总额', '¥${NumberFormat('#,##0').format(cny)}',
          TickerColor.up),
    ]);
  }

  Widget _kpiGrid() {
    double cny = 0, cost = 0, usdtTotal = 0;
    for (final r in _records) {
      usdtTotal += r.usdtAmount;
      cny += r.cnyReceived;
      cost += r.costVsReference;
    }
    final avgPct = _records.isEmpty
        ? 0.0
        : _records.fold<double>(0, (s, r) => s + r.pctVsReference) /
            _records.length;

    // 按渠道平均
    final byChannel = <String, List<double>>{};
    for (final r in _records) {
      byChannel.putIfAbsent(r.channel, () => []).add(r.pctVsReference);
    }
    final ranked = byChannel.entries
        .map((e) =>
            MapEntry(e.key, e.value.reduce((a, b) => a + b) / e.value.length))
        .toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final best = ranked.isEmpty ? null : ranked.first;
    final worst = ranked.isEmpty ? null : ranked.last;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
      child: GridView.count(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisCount: 2,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 1.55,
        children: [
          IOSKpiCard(
            header: '累计换汇',
            value: '¥${NumberFormat('#,##0').format(cny)}',
            sub: '${NumberFormat('#,##0').format(usdtTotal)} USDT',
            valueColor: IOS.blue,
            arrow: '▲',
            arrowColor: IOS.green,
          ),
          IOSKpiCard(
            header: '总汇损',
            value:
                '${cost >= 0 ? "−" : "+"}¥${NumberFormat('#,##0').format(cost.abs())}',
            sub: '平均 ${avgPct.toStringAsFixed(2)}%',
            valueColor: cost >= 0 ? IOS.red : IOS.green,
            arrow: cost >= 0 ? '▼' : '▲',
            arrowColor: cost >= 0 ? IOS.red : IOS.green,
          ),
          IOSKpiCard(
            header: '最优渠道',
            value: best == null ? '—' : _shortChannel(best.key),
            sub: best == null
                ? '需 ≥1 笔'
                : '${best.value >= 0 ? "+" : ""}${best.value.toStringAsFixed(2)}% 平均',
          ),
          IOSKpiCard(
            header: '最差渠道',
            value: worst == null ? '—' : _shortChannel(worst.key),
            sub: worst == null
                ? '—'
                : '${worst.value.toStringAsFixed(2)}% 平均',
            valueColor: IOS.red,
          ),
        ],
      ),
    );
  }

  String _shortChannel(String full) {
    return full.replaceAll('(JPY)', '').replaceAll(' OTC', '');
  }

  /// 月度出金 (USDT 投入,蓝色柱)
  List<Widget> _monthlyOutflow() {
    final byMonth = <String, double>{};
    for (final r in _records) {
      final k = DateFormat('yyyy-MM').format(r.at);
      byMonth[k] = (byMonth[k] ?? 0) + r.cnyReceived;
    }
    if (byMonth.isEmpty) return [];
    final keys = byMonth.keys.toList()..sort();
    final total = byMonth.values.reduce((a, b) => a + b);
    return [
      IOSBarChart(
        title: '月度出金',
        sub: 'USDT 投入 → CNY 到手',
        totalRight: '∑ ¥${_kFmt(total)}',
        bars: keys
            .map((k) => BarItem(
                  '${int.parse(k.split('-')[1])}月',
                  byMonth[k]!,
                  '¥${_kFmt(byMonth[k]!)}',
                ))
            .toList(),
      ),
    ];
  }

  /// 月度汇损 (红色柱)
  List<Widget> _monthlyLoss() {
    final byMonth = <String, double>{};
    for (final r in _records) {
      final k = DateFormat('yyyy-MM').format(r.at);
      byMonth[k] = (byMonth[k] ?? 0) + r.costVsReference;
    }
    if (byMonth.isEmpty) return [];
    final keys = byMonth.keys.toList()..sort();
    final total = byMonth.values.reduce((a, b) => a + b);
    return [
      IOSBarChart(
        title: '月度汇损',
        sub: 'vs Wise 中间价',
        totalRight: '−¥${_kFmt(total.abs())}',
        totalColor: IOS.red,
        bars: keys
            .map((k) => BarItem(
                  '${int.parse(k.split('-')[1])}月',
                  byMonth[k]!.abs(),
                  '−¥${_kFmt(byMonth[k]!.abs())}',
                  BarColor.red,
                ))
            .toList(),
      ),
    ];
  }

  /// 各渠道平均汇损 %
  List<Widget> _channelRanking() {
    final byChannel = <String, List<double>>{};
    for (final r in _records) {
      byChannel.putIfAbsent(r.channel, () => []).add(r.pctVsReference);
    }
    if (byChannel.isEmpty) return [];
    final list = byChannel.entries
        .map((e) =>
            MapEntry(e.key, e.value.reduce((a, b) => a + b) / e.value.length))
        .toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return [
      IOSBarChart(
        title: '各渠道平均汇损 %',
        sub: '越接近 0 越划算',
        bars: list
            .map((e) => BarItem(
                  _shortChannel(e.key).substring(
                      0,
                      _shortChannel(e.key).length > 4
                          ? 4
                          : _shortChannel(e.key).length),
                  e.value,
                  '${e.value >= 0 ? "+" : ""}${e.value.toStringAsFixed(2)}%',
                  e.value >= 0 ? BarColor.green : BarColor.red,
                ))
            .toList(),
      ),
    ];
  }

  String _kFmt(double v) {
    if (v.abs() >= 10000) return '${(v / 1000).toStringAsFixed(0)}k';
    return v.toStringAsFixed(0);
  }

  // ============ 额度追踪 + 预警 ============
  Color _quotaColor(double pct) =>
      pct >= 0.9 ? IOS.red : (pct >= 0.7 ? IOS.orange : IOS.green);

  /// JPY 简写: 大额用"万",小额用千分位
  String _jpyShort(double v) {
    if (v >= 10000) {
      final wan = v / 10000;
      return '${wan.toStringAsFixed(wan >= 100 ? 0 : 1)}万';
    }
    return NumberFormat('#,##0').format(v);
  }

  List<Widget> _quotaSection() {
    final now = DateTime.now();
    final year = now.year;

    // 受 JPY 额度管制的渠道(各自独立,不共享)
    final controlled =
        kChannels.where((c) => c.jpyQuotaControlled).map((c) => c.name).toList();
    final usedChannels = controlled
        .where((ch) => _records.any(
            (r) => r.channel == ch && r.at.year == year && r.jpyAmount != null))
        .toList();

    // 5万 USD/年 外汇管制 — 按收款人折 USD(≈USDT)
    final usdByRecip = QuotaService.yearlyUsdByRecipient(_records, now)
        .entries
        .where((e) => e.value > 0)
        .toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    // 预警收集 (≥90%)
    final warn = <String>[];
    for (final e in usdByRecip) {
      final p = e.value / 50000;
      if (p >= 0.9) {
        warn.add('${e.key} 年度购汇已达 ${(p * 100).toStringAsFixed(0)}% (5万USD)');
      }
    }
    for (final ch in usedChannels) {
      final q = QuotaService.forChannel(_records, ch, now);
      if (q.yearPct >= 0.9) {
        warn.add('${_shortChannel(ch)} 年度额度已达 ${(q.yearPct * 100).toStringAsFixed(0)}% (${_jpyShort(q.yearLimit)}JPY)');
      }
      if (q.monthPct >= 0.9) {
        warn.add('${_shortChannel(ch)} 本月额度已达 ${(q.monthPct * 100).toStringAsFixed(0)}% (${_jpyShort(q.monthLimit)}JPY)');
      }
    }

    final out = <Widget>[];
    if (warn.isNotEmpty) out.add(_quotaWarning(warn));

    // ① 5万 USD/年
    if (usdByRecip.isNotEmpty) {
      out.add(IOSSection(
        header: '外汇管制 · 个人年度购汇 5万 USD',
        footer: '按收款人统计 $year 年累计 USDT(≈USD)。接近 5万 需留意境内个人购汇监管。',
        children: [
          for (final e in usdByRecip)
            IOSQuotaBar(
              pct: e.value / 50000,
              leftText: e.key,
              rightText:
                  '\$${NumberFormat('#,##0').format(e.value)} / 50,000',
              color: _quotaColor(e.value / 50000),
            ),
        ],
      ));
    }

    // ② 渠道年度 600万 JPY
    if (usedChannels.isNotEmpty) {
      out.add(IOSSection(
        header: '渠道额度 · 年度上限',
        footer: '日本各汇款渠道额度独立、互不共享。熊猫速汇年度已提额至 800万 JPY。',
        children: [
          for (final ch in usedChannels)
            _channelQuotaBar(ch, now, isMonth: false),
        ],
      ));

      // ③ 本月 300万 JPY
      final monthUsed =
          usedChannels.where((ch) => QuotaService.forChannel(_records, ch, now).monthUsed > 0).toList();
      out.add(IOSSection(
        header: '本月额度 · 300万 JPY/渠道',
        footer: '按自然月重置${monthUsed.isEmpty ? ' · 本月(${now.month}月)各渠道暂未使用' : ''}。',
        children: monthUsed.isEmpty
            ? [
                const IOSRow(
                  leadingIcon: Icons.check_circle,
                  iconColors: [IOS.green, Color(0xFF00A86B)],
                  label: '本月暂无换汇',
                  sub: '各渠道 300万 JPY 额度全额可用',
                ),
              ]
            : [
                for (final ch in monthUsed)
                  _channelQuotaBar(ch, now, isMonth: true),
              ],
      ));
    }

    return out;
  }

  Widget _channelQuotaBar(String channel, DateTime now,
      {required bool isMonth}) {
    final q = QuotaService.forChannel(_records, channel, now);
    final used = isMonth ? q.monthUsed : q.yearUsed;
    final limit = isMonth ? q.monthLimit : q.yearLimit;
    final pct = isMonth ? q.monthPct : q.yearPct;
    return IOSQuotaBar(
      pct: pct,
      leftText: _shortChannel(channel),
      rightText: '¥${_jpyShort(used)} / ${_jpyShort(limit)}',
      color: _quotaColor(pct),
    );
  }

  Widget _quotaWarning(List<String> msgs) => Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 14),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: IOS.red.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(IOS.radCard),
          border: Border.all(color: IOS.red.withValues(alpha: 0.3), width: 0.5),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.warning_amber_rounded, color: IOS.red, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('额度预警',
                      style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: Color(0xFFC91D14),
                          fontSize: 13)),
                  const SizedBox(height: 3),
                  for (final m in msgs)
                    Padding(
                      padding: const EdgeInsets.only(top: 1),
                      child: Text('· $m',
                          style: const TextStyle(
                              color: Color(0xFFC91D14),
                              fontSize: 12,
                              height: 1.4)),
                    ),
                ],
              ),
            ),
          ],
        ),
      );
}
