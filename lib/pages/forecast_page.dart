import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/exchange_record.dart';
import '../services/forecast.dart';
import '../services/rate_cache.dart';
import '../theme/ios_theme.dart';
import '../widgets/ios_widgets.dart';

class ForecastPage extends StatefulWidget {
  const ForecastPage({super.key});
  @override
  State<ForecastPage> createState() => _ForecastPageState();
}

class _ForecastPageState extends State<ForecastPage> {
  static const _presets = [100, 500, 1000, 5000, 10000];
  int _usdt = 1000;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    if (!RateCache.instance.hasData) _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    try {
      await RateCache.instance.refresh();
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext c) {
    final quotes = RateCache.instance.snapshot;
    final rows = ForecastService.forecast(usdt: _usdt.toDouble(), quotes: quotes);
    final lastFetch = RateCache.instance.lastFetch;

    return Scaffold(
      backgroundColor: IOS.grayBg,
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            IOSLargeTitle(
              title: '预测到账',
              actions: [
                _loading
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : IOSNavIcon(Icons.refresh, onTap: _refresh),
              ],
            ),
            _ticker(quotes, lastFetch),
            HeroInputCard(
              label: 'USDT INPUT',
              value: NumberFormat('#,###').format(_usdt),
              unit: 'USDT',
              presets: _presets,
              activePreset: _usdt,
              onPresetTap: (v) => setState(() => _usdt = v),
            ),
            if (quotes.isEmpty && !_loading)
              _emptyState()
            else
              _channelRanking(rows, quotes),
            _riskRanking(),
            _disclaimer(),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  // ===== 顶部 Ticker =====
  Widget _ticker(List quotes, DateTime? lastFetch) {
    final wiseUsdCny = quotes
        .where((q) => q.source == 'Wise' && q.pair == 'USD/CNY')
        .firstOrNull;
    final wiseJpyCny = quotes
        .where((q) => q.source == 'Wise' && q.pair == 'JPY/CNY')
        .firstOrNull;
    final binance = quotes
        .where((q) => q.source == 'Binance-蓝钻' && q.pair == 'USDT/CNY')
        .firstOrNull;
    return IOSTickerBar(
      items: [
        TickerItem(
          'USD/CNY',
          wiseUsdCny != null ? wiseUsdCny.mid.toStringAsFixed(4) : '—',
        ),
        TickerItem(
          'USDT/CNY',
          binance != null ? binance.mid.toStringAsFixed(4) : '—',
          TickerColor.up,
        ),
        TickerItem(
          'JPY/CNY',
          wiseJpyCny != null ? wiseJpyCny.mid.toStringAsFixed(4) : '—',
        ),
      ],
      trailing: lastFetch != null ? DateFormat('HH:mm:ss').format(lastFetch) : '',
    );
  }

  // ===== 渠道排名 =====
  Widget _channelRanking(List<ForecastRow> rows, List quotes) {
    return IOSSection(
      header: '渠道排名 · ${rows.length}',
      footer: quotes.isEmpty ? null : '汇率 ${_relativeTime()} · 下拉刷新',
      children: [
        for (int i = 0; i < rows.length; i++)
          ForecastRankRow(
            rank: i + 1,
            channelName: rows[i].channel.name,
            meta: _channelMeta(rows[i]),
            risk: _toBadgeRisk(rows[i].channel.risk),
            riskLabel: _riskLabel(rows[i].channel.risk),
            cny: '¥${NumberFormat('#,##0.00').format(rows[i].cnyNet)}',
            pct: i == 0
                ? '★ 最优'
                : '${(rows[i].pctVsBest ?? 0) >= 0 ? "+" : "−"}${(rows[i].pctVsBest ?? 0).abs().toStringAsFixed(2)}%',
            isBest: i == 0,
          ),
      ],
    );
  }

  String _channelMeta(ForecastRow r) {
    final src = _dataSource(r.channel.name);
    final tag = r.channel.tagline;
    if (tag.isNotEmpty) return '$tag · 来源 $src';
    return '来源 $src';
  }

  String _dataSource(String channelName) {
    if (channelName.contains('Binance')) return '币安 P2P';
    if (channelName.contains('OKX')) return 'OKX C2C';
    if (channelName.contains('Visa')) return 'Visa 官方';
    if (channelName.contains('熊猫')) return '熊猫实时 API';
    if (channelName.contains('中国银行') || channelName.contains('中行'))
      return '熊猫 API · 平台费率';
    if (channelName.contains('JRF') || channelName.contains('Wise'))
      return 'Wise 中间价 + 估算费率';
    if (channelName.contains('线下')) return 'Wise 中间价(乐观)';
    return 'Wise 中间价';
  }

  RiskTag _toBadgeRisk(RiskLevel l) => switch (l) {
        RiskLevel.veryLow => RiskTag.veryLow,
        RiskLevel.low => RiskTag.low,
        RiskLevel.medium => RiskTag.medium,
        RiskLevel.high => RiskTag.high,
      };

  String _riskLabel(RiskLevel l) => switch (l) {
        RiskLevel.veryLow => '极低',
        RiskLevel.low => '低',
        RiskLevel.medium => '中',
        RiskLevel.high => '高',
      };

  String _relativeTime() {
    final lf = RateCache.instance.lastFetch;
    if (lf == null) return '尚未拉取';
    final diff = DateTime.now().difference(lf);
    if (diff.inSeconds < 60) return '${diff.inSeconds} 秒前更新';
    if (diff.inMinutes < 60) return '${diff.inMinutes} 分钟前更新';
    return '${diff.inHours} 小时前更新';
  }

  // ===== 风险排名 =====
  Widget _riskRanking() {
    final byRisk = <RiskLevel, List<ChannelMeta>>{};
    for (final c in kChannels) {
      byRisk.putIfAbsent(c.risk, () => []).add(c);
    }
    return IOSSection(
      header: '风险排名(由低到高)',
      children: [
        if (byRisk[RiskLevel.veryLow] != null)
          _riskRow(
            Icons.shield_outlined,
            const [IOS.blue, IOS.blueDark],
            byRisk[RiskLevel.veryLow]!.map((c) => c.name).join(' / '),
            _firstNote(byRisk[RiskLevel.veryLow]!),
            RiskTag.veryLow,
            '极低',
          ),
        if (byRisk[RiskLevel.low] != null)
          _riskRow(
            Icons.check_circle_outline,
            const [IOS.green, Color(0xFF00A86B)],
            byRisk[RiskLevel.low]!.map((c) => c.name.replaceAll('(JPY)', '')).join(' / '),
            '日本金融厅注册 · 收款仅微信支付宝',
            RiskTag.low,
            '低',
          ),
        if (byRisk[RiskLevel.medium] != null)
          _riskRow(
            Icons.warning_amber_outlined,
            const [IOS.orange, Color(0xFFFF6B00)],
            byRisk[RiskLevel.medium]!.map((c) => c.name).join(' / '),
            '监管灰区 · 无法证明收入来源',
            RiskTag.medium,
            '中',
          ),
        if (byRisk[RiskLevel.high] != null)
          _riskRow(
            Icons.error_outline,
            const [IOS.red, Color(0xFFC93400)],
            byRisk[RiskLevel.high]!.map((c) => c.name).join(' / '),
            '冻卡风险 · 个人卡可能被定为涉案',
            RiskTag.high,
            '高',
          ),
      ],
    );
  }

  String _firstNote(List<ChannelMeta> cs) {
    if (cs.isEmpty) return '';
    final n = cs.first.tagline;
    return n.isNotEmpty ? n : '合规合法';
  }

  Widget _riskRow(IconData icon, List<Color> colors, String label, String sub,
      RiskTag risk, String riskLabel) {
    return IOSRow(
      leadingIcon: icon,
      iconColors: colors,
      label: label,
      sub: sub,
      trailing: IOSBadge(risk: risk, text: riskLabel),
      chevron: true,
      onTap: () => _showRiskDetail(label, risk),
    );
  }

  void _showRiskDetail(String label, RiskTag risk) {
    final ch = kChannels.firstWhere(
        (c) => label.contains(c.name.replaceAll('(JPY)', '')) ||
            c.name.contains(label.split(' / ').first),
        orElse: () => kChannels.first);
    showModalBottomSheet(
      context: context,
      backgroundColor: IOS.grayBg,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        maxChildSize: 0.92,
        minChildSize: 0.4,
        expand: false,
        builder: (_, ctrl) => ListView(
          controller: ctrl,
          children: [
            const SizedBox(height: 8),
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                    color: IOS.gray2, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 12),
            IOSSection(
              header: '${ch.name} · ${_riskLabelOf(risk)}风险',
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    ch.riskNote.isEmpty ? '暂无备注' : ch.riskNote,
                    style: const TextStyle(
                        fontSize: 14, color: IOS.textSecondary, height: 1.6),
                  ),
                ),
              ],
            ),
            if (ch.riskRefs.isNotEmpty)
              IOSSection(
                header: '相关资讯',
                children: ch.riskRefs
                    .map((r) => IOSRow(
                          leadingIcon: Icons.link,
                          iconColors: const [IOS.blue, IOS.blueDark],
                          label: r.title,
                          chevron: true,
                          onTap: () => _open(r.url),
                        ))
                    .toList(),
              ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  String _riskLabelOf(RiskTag r) => switch (r) {
        RiskTag.veryLow => '极低',
        RiskTag.low => '低',
        RiskTag.medium => '中',
        RiskTag.high => '高',
      };

  Future<void> _open(String url) async {
    final uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('无法打开,已复制链接'), duration: Duration(seconds: 1)),
        );
        await Clipboard.setData(ClipboardData(text: url));
      }
    }
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
            const Icon(Icons.cloud_off, size: 48, color: IOS.gray),
            const SizedBox(height: 12),
            const Text('尚未拉取汇率',
                style: TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w600, color: IOS.textPrimary)),
            const SizedBox(height: 4),
            const Text('点右上角 ↻ 刷新',
                style: TextStyle(fontSize: 12, color: IOS.gray)),
          ],
        ),
      );

  Widget _disclaimer() => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
        child: Text(
          '⚠️ 预测基于 Wise 中间价 + 各平台实时费率,实际到手可能因金额/时段/点差浮动 ±0.3%。\n'
          '风险说明仅供参考,不构成法律建议。',
          style: TextStyle(fontSize: 11, color: IOS.gray.withValues(alpha: 0.8), height: 1.5),
        ),
      );
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
