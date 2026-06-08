import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/exchange_record.dart';
import '../services/forecast.dart';
import '../services/rate_cache.dart';
import '../services/update_checker.dart';
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
  UpdateInfo? _update;
  bool _updateDismissed = false;
  bool _updateBusy = false;
  // CNY → USDT 买入价（leg0）。null = 用 Binance 蓝钻实时；显式输入 = 用户的真实成本
  final TextEditingController _cnyRateController = TextEditingController();
  double? _cnyToUsdtRate;

  // 在 macOS .app (chrome --app 模式) 里 Flutter 跑的是 web build, kIsWeb=true,
  // 但 location 是 127.0.0.1, 跟真 web(github.io) 区分一下
  bool get _isLocalApp {
    if (!kIsWeb) return false;
    final h = Uri.base.host;
    return h == '127.0.0.1' || h == 'localhost' || h.isEmpty;
  }

  bool get _isTrueWebOnly =>
      kIsWeb && !_isLocalApp; // github.io 等公网部署 = 每次访问即最新, 不需要 update banner

  @override
  void initState() {
    super.initState();
    if (!RateCache.instance.hasData) _refresh();
    // chrome --app 模式也要检测更新 (之前误用 !kIsWeb 把本地 app 排除了)
    if (!_isTrueWebOnly) _checkUpdate();
  }

  @override
  void dispose() {
    _cnyRateController.dispose();
    super.dispose();
  }

  Future<void> _checkUpdate() async {
    final info = await UpdateChecker.check();
    if (!mounted || info == null || !info.hasUpdate || _updateDismissed) return;
    setState(() => _update = info);
  }

  String? _platformDownloadUrl(UpdateInfo info) {
    if (_isLocalApp) return info.macosUrl; // chrome --app 在 macOS .app 内
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return info.androidUrl;
      case TargetPlatform.macOS:
        return info.macosUrl;
      default:
        return info.webUrl ?? info.macosUrl ?? info.androidUrl;
    }
  }

  /// 一键在线更新 — 仅 macOS .app (本地有 Go server 跑 /api/download)
  /// 服务端下载 dmg 到 ~/Downloads + 自动 open (挂载) → Finder 弹窗供拖拽
  Future<void> _onlineUpdate(UpdateInfo info) async {
    final url = _platformDownloadUrl(info);
    if (url == null) return;
    setState(() => _updateBusy = true);
    try {
      final resp = await http
          .get(Uri.parse('/api/download?url=${Uri.encodeComponent(url)}'))
          .timeout(const Duration(minutes: 5));
      if (resp.statusCode == 200) {
        final j = jsonDecode(resp.body) as Map<String, dynamic>;
        if (j['ok'] == true && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✓ dmg 已下载并挂载,在 Finder 把 Purr Swap 拖到 Applications 替换即完成'),
              duration: Duration(seconds: 6),
            ),
          );
          return;
        }
        throw Exception(j['err']?.toString() ?? 'unknown');
      }
      throw Exception('HTTP ${resp.statusCode}');
    } catch (e) {
      if (!mounted) return;
      // 退路: 跳浏览器
      final uri = Uri.parse(url);
      await launchUrl(uri, mode: LaunchMode.externalApplication);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('自动下载失败,改走浏览器: $e'),
            duration: const Duration(seconds: 4)),
      );
    } finally {
      if (mounted) setState(() => _updateBusy = false);
    }
  }

  Future<void> _onUpdateTap() async {
    final info = _update;
    if (info == null) return;
    if (_isLocalApp) {
      await _onlineUpdate(info);
      return;
    }
    final url = _platformDownloadUrl(info);
    if (url == null) return;
    final uri = Uri.parse(url);
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      await Clipboard.setData(ClipboardData(text: url));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('无法打开浏览器,已复制下载链接')),
      );
    }
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
    final rows = ForecastService.forecast(
      usdt: _usdt.toDouble(),
      quotes: quotes,
      cnyToUsdtRate: _cnyToUsdtRate,
    );
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
            if (_update != null) _buildUpdateBanner(_update!),
            _ticker(quotes, lastFetch),
            HeroInputCard(
              label: 'USDT INPUT',
              value: NumberFormat('#,###').format(_usdt),
              unit: 'USDT',
              presets: _presets,
              activePreset: _usdt,
              onPresetTap: (v) => setState(() => _usdt = v),
            ),
            _cnyRateInput(quotes, rows.isNotEmpty ? rows.first.inputCny : null),
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
            estimated: !rows[i].isMeasured,
          ),
      ],
    );
  }

  // §4: 每行最多 2 段最关键描述。tagline 已是费率摘要;无 tagline 时退回数据来源。
  // "实测/估算" 不再混在文字流, 改由 ForecastRankRow 的小 tag 展示。
  String _channelMeta(ForecastRow r) {
    final tag = r.channel.tagline;
    if (tag.isNotEmpty) return tag;
    return _dataSource(r);
  }

  /// 数据来源说明 —— 显式区分 "实测" vs "估算"，方便用户判断数字可信度
  String _dataSource(ForecastRow r) {
    final name = r.channel.name;
    if (name.contains('Binance')) return '币安 C2C 蓝钻成交价';
    if (name.contains('OKX')) return 'OKX C2C 订单簿';
    if (name.contains('Visa')) return 'Visa 官方汇率(费率内置)';
    if (name.contains('Seven Bank') || name.contains('7Bank'))
      return '熊猫 API · 7Bank 牌价';
    if (name.contains('熊猫')) return '熊猫 API · 平台实时牌价';
    if (name.contains('中行') || name.contains('中国银行'))
      return '熊猫 API · 中行牌价';
    if (name == 'Wise(JPY)') {
      return r.isMeasured
          ? 'Wise comparisons API · 实测 fee'
          : 'Wise mid + 估算 fee(API 失败回退)';
    }
    if (name.contains('JRF')) return '内置估算(无公开 API)';
    if (name.contains('邮局') || name.contains('Japan Post'))
      return 'Wise mid · TTS spread 估算';
    if (name.contains('线下')) return 'Wise 中间价(无 fee 乐观)';
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

  /// CNY → USDT 买入价输入卡 — 用户在国内买 U 的真实价格（leg0 成本）。
  /// 空白时自动用 Binance 蓝钻实时价兜底。
  Widget _cnyRateInput(List quotes, double? currentInputCny) {
    final binance = quotes
        .where((q) => q.source == 'Binance-蓝钻' && q.pair == 'USDT/CNY')
        .firstOrNull;
    final wiseUsdCny = quotes
        .where((q) => q.source == 'Wise' && q.pair == 'USD/CNY')
        .firstOrNull;
    final defaultRate = binance?.mid ?? wiseUsdCny?.mid ?? 7.20;
    final defaultSource = binance != null
        ? 'Binance 蓝钻'
        : wiseUsdCny != null
            ? 'Wise mid (无 Binance 数据)'
            : '兜底 7.20';
    final activeRate = _cnyToUsdtRate ?? defaultRate;
    final hasInput = _cnyToUsdtRate != null;
    final inputCny = currentInputCny ?? (_usdt * activeRate);

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
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
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('CNY / USDT 买入价 (leg0)',
                  style: TextStyle(
                      fontSize: 13,
                      color: IOS.textSecondary,
                      fontWeight: FontWeight.w500)),
              Text(
                  '折合投入 ¥${NumberFormat('#,##0.00').format(inputCny)}',
                  style: const TextStyle(
                      fontSize: 13, color: IOS.blue, fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _cnyRateController,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    hintText: defaultRate.toStringAsFixed(4),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide:
                            BorderSide(color: IOS.separator, width: 0.5)),
                    enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide:
                            BorderSide(color: IOS.separator, width: 0.5)),
                    focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide:
                            const BorderSide(color: IOS.blue, width: 1)),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 11),
                    suffixText: 'CNY/USDT',
                    suffixStyle:
                        const TextStyle(fontSize: 12, color: IOS.gray),
                  ),
                  onChanged: (v) => setState(() {
                    final r = double.tryParse(v.trim());
                    _cnyToUsdtRate = (r != null && r > 0) ? r : null;
                  }),
                ),
              ),
              if (hasInput) ...[
                const SizedBox(width: 6),
                IconButton(
                  icon: const Icon(Icons.clear, size: 18, color: IOS.gray),
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 32, minHeight: 32),
                  onPressed: () {
                    _cnyRateController.clear();
                    setState(() => _cnyToUsdtRate = null);
                  },
                ),
              ],
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              hasInput
                  ? '✓ 使用你的成交价 ¥${activeRate.toStringAsFixed(4)}'
                  : '空白 = 默认 $defaultSource ¥${defaultRate.toStringAsFixed(4)}',
              style: const TextStyle(fontSize: 11, color: IOS.gray),
            ),
          ),
        ],
      ),
    );
  }

  /// app 自更新提示横幅 — 检测到 releases 分支 version.json 有新版时显示
  Widget _buildUpdateBanner(UpdateInfo info) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 6),
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        color: IOS.blue.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: IOS.blue.withValues(alpha: 0.35), width: 0.6),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: _onUpdateTap,
        child: Row(
          children: [
            const Icon(Icons.system_update, color: IOS.blue, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('新版 v${info.latestVersion} 可用',
                      style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: IOS.blue)),
                  const SizedBox(height: 2),
                  Text(
                      (info.notes ?? '').isEmpty
                          ? '当前 v${info.currentVersion} · 点击下载安装'
                          : '${info.notes}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11, color: IOS.gray)),
                ],
              ),
            ),
            if (_isLocalApp)
              SizedBox(
                height: 30,
                child: FilledButton.tonal(
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    minimumSize: const Size(0, 30),
                    backgroundColor: IOS.blue.withValues(alpha: 0.2),
                  ),
                  onPressed: _updateBusy ? null : _onUpdateTap,
                  child: _updateBusy
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: IOS.blue))
                      : const Text('立即更新',
                          style: TextStyle(
                              color: IOS.blue,
                              fontSize: 12,
                              fontWeight: FontWeight.w600)),
                ),
              ),
            IconButton(
              icon: const Icon(Icons.close, size: 18, color: IOS.gray),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              onPressed: () => setState(() {
                _update = null;
                _updateDismissed = true;
              }),
            ),
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
