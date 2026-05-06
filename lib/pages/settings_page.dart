import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/rate_cache.dart';
import '../storage/local_store.dart';
import '../theme/ios_theme.dart';
import '../widgets/ios_widgets.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  Future<void> _loadSampleData() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('加载示例数据?'),
        content: const Text(
            '将追加 100 条 2026 年 1-4 月的示例换汇记录,覆盖所有渠道,方便体验统计和历史。\n\n不影响你已有的真实数据。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('加载')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final raw =
          await rootBundle.loadString('assets/data/sample_records.json');
      final store = await LocalStore.instance;
      final existing = await store.loadRecords();
      await store.importJson(raw);
      final imported = await store.loadRecords();
      final importedIds = imported.map((r) => r.id).toSet();
      final merged = [
        ...imported,
        ...existing.where((r) => !importedIds.contains(r.id)),
      ];
      await store.saveRecords(merged);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('已加载 ${imported.length} 条示例')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('加载失败: $e')));
      }
    }
  }

  Future<void> _export() async {
    final store = await LocalStore.instance;
    final json = await store.exportJson();
    await Clipboard.setData(ClipboardData(text: json));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已复制到剪贴板'), duration: Duration(seconds: 1)));
  }

  Future<void> _importPasted() async {
    final ctl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('从剪贴板/文本导入'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('粘贴之前导出的 JSON',
                style: TextStyle(fontSize: 12, color: IOS.gray)),
            const SizedBox(height: 8),
            TextField(
              controller: ctl,
              maxLines: 6,
              decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: '{"records":[...]}'),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('导入')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final store = await LocalStore.instance;
      await store.importJson(ctl.text);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('导入成功'), duration: Duration(seconds: 1)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('解析失败: $e')));
    }
  }

  Future<void> _confirmClear() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('清空全部本地数据?'),
        content: const Text('将删除所有记账记录和汇率快照,不可恢复。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: IOS.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (ok == true) {
      final s = await LocalStore.instance;
      await s.clearAll();
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('已清空')));
    }
  }

  Future<void> _open(String url) async {
    final uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      await Clipboard.setData(ClipboardData(text: url));
    }
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
            const IOSLargeTitle(
              title: '设置',
              actions: [_VersionBadge()],
            ),
            _dataSourceSection(),
            _dataMgmtSection(),
            _visaFeeSection(),
            _aboutSection(),
            _footer(),
            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }

  // === 数据源 (清晰列出每个来源 + 状态)
  Widget _dataSourceSection() {
    final lf = RateCache.instance.lastFetch;
    final lastTxt = lf == null
        ? '尚未拉取'
        : '上次更新 · ${DateFormat('MM-dd HH:mm:ss').format(lf)}';
    final qs = RateCache.instance.snapshot;
    final hit = <String, bool>{
      '币安 P2P': qs.any((q) => q.source.contains('Binance')),
      'OKX C2C': qs.any((q) => q.source.contains('OKX')),
      'Wise 中间价': qs.any((q) => q.source == 'Wise'),
      'Visa 官方': qs.any((q) => q.source == 'Visa'),
      '熊猫速汇 API': qs.any((q) => q.source == '熊猫速汇'),
      '中行(日本)': qs.any((q) => q.source.contains('中行')),
      'Seven Bank': qs.any((q) => q.source.contains('Seven')),
    };

    return IOSSection(
      header: '数据源',
      footer: lastTxt,
      children: [
        for (final e in hit.entries)
          IOSRow(
            leadingIcon: e.value ? Icons.check_circle : Icons.cloud_off,
            iconColors: e.value
                ? const [IOS.green, Color(0xFF00A86B)]
                : const [IOS.gray, Color(0xFF636366)],
            label: e.key,
            sub: _sourceUrl(e.key),
            trailing: Text(
              e.value ? '在线' : '—',
              style: TextStyle(
                fontSize: 11,
                color: e.value ? IOS.green : IOS.gray2,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
      ],
    );
  }

  String _sourceUrl(String name) {
    return switch (name) {
      '币安 P2P' => 'p2p.binance.com',
      'OKX C2C' => 'okx.com',
      'Wise 中间价' => 'wise.com/rates/live',
      'Visa 官方' => 'usa.visa.com/cmsapi',
      '熊猫速汇 API' => 'prod.pandaremit.com',
      '中行(日本)' => '熊猫 API · 平台费率',
      'Seven Bank' => '熊猫 API · 平台费率',
      _ => '—',
    };
  }

  // === 数据管理
  Widget _dataMgmtSection() {
    return IOSSection(
      header: '数据管理',
      footer: '所有数据仅本地。卸载即清空。建议定期导出备份。',
      children: [
        IOSRow(
          leadingIcon: Icons.auto_awesome,
          iconColors: const [IOS.violet, IOS.indigo],
          label: '加载示例数据',
          sub: '追加 100 条 2026 年 1-4 月记录',
          chevron: true,
          onTap: _loadSampleData,
        ),
        IOSRow(
          leadingIcon: Icons.file_download_outlined,
          iconColors: const [IOS.green, Color(0xFF00A86B)],
          label: '导出 JSON 备份',
          sub: '复制到剪贴板',
          chevron: true,
          onTap: _export,
        ),
        IOSRow(
          leadingIcon: Icons.file_upload_outlined,
          iconColors: const [IOS.orange, Color(0xFFFF6B00)],
          label: '从文本导入',
          sub: '粘贴之前导出的 JSON',
          chevron: true,
          onTap: _importPasted,
        ),
        IOSRow(
          leadingIcon: Icons.delete_outline,
          iconColors: const [IOS.red, Color(0xFFC93400)],
          label: '清空全部数据',
          sub: '不可恢复',
          labelColor: IOS.red,
          chevron: true,
          onTap: _confirmClear,
        ),
      ],
    );
  }

  // === Visa 费率(只读展示)
  Widget _visaFeeSection() {
    return const IOSSection(
      header: 'Visa 卡费率(默认)',
      footer: '可在记账时按实际填写',
      children: [
        IOSFormRow(label: '点差', value: '0.6%', valueColor: IOS.gray),
        IOSFormRow(label: 'ATM 手续费', value: '¥15 / 笔', valueColor: IOS.gray),
      ],
    );
  }

  // === 关于
  Widget _aboutSection() {
    return IOSSection(
      header: '关于',
      children: [
        const IOSRow(
          leadingIcon: Icons.info_outline,
          iconColors: [IOS.gray, Color(0xFF636366)],
          label: '版本',
          trailing: Text('v0.2.0', style: TextStyle(fontSize: 14, color: IOS.gray)),
        ),
        IOSRow(
          leadingIcon: Icons.menu_book,
          iconColors: const [IOS.gray, Color(0xFF636366)],
          label: '使用手册 PDF',
          chevron: true,
          onTap: () =>
              _open('https://github.com/your-repo/purr-swap/wiki/manual'),
        ),
        IOSRow(
          leadingIcon: Icons.gavel,
          iconColors: const [IOS.gray, Color(0xFF636366)],
          label: '法律 · 免责声明',
          chevron: true,
          onTap: _showLegal,
        ),
      ],
    );
  }

  void _showLegal() {
    showModalBottomSheet(
      context: context,
      backgroundColor: IOS.grayBg,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        maxChildSize: 0.9,
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
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 4, 20, 4),
              child: Text('法律 · 免责',
                  style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.5)),
            ),
            const Padding(
              padding: EdgeInsets.all(20),
              child: Text(
                '• Purr Swap 仅是「比价 + 记账」工具,不参与任何换汇行为本身。\n\n'
                '• USDT / 虚拟货币在中国大陆有法律风险。请自行核实合法性。\n\n'
                '• App 提供的渠道说明、风险新闻仅供参考,不构成法律建议。\n\n'
                '• 开发者对任何因使用 App 产生的资金损失、法律纠纷不负责。\n\n'
                '• 使用建议:\n'
                '  - 收款仅限本人或直系亲属\n'
                '  - 单笔不大额\n'
                '  - 保留收入证明\n'
                '  - 走合规渠道',
                style: TextStyle(fontSize: 14, height: 1.7, color: IOS.textSecondary),
              ),
            ),
            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }

  Widget _footer() => const Padding(
        padding: EdgeInsets.fromLTRB(20, 14, 20, 6),
        child: Text(
          '⚠️ 币安/OKX 在国内直连可能被拦截,如报错请走代理 WiFi 打开。\n'
          '⚠️ Wise/JRF 费率为估算值;熊猫/中行/7Bank 取自官方实时 API。',
          style: TextStyle(fontSize: 11, color: IOS.gray, height: 1.5),
        ),
      );
}

class _VersionBadge extends StatelessWidget {
  const _VersionBadge();
  @override
  Widget build(BuildContext c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: IOS.blue.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Text('v0.2.0',
            style: TextStyle(
                color: IOS.blue, fontSize: 11, fontWeight: FontWeight.w600)),
      );
}
