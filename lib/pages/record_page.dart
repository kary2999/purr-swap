import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/exchange_record.dart';
import '../services/quota.dart';
import '../services/rate_cache.dart';
import '../services/usdt_cny_history.dart';
import '../storage/local_store.dart';
import '../theme/ios_theme.dart';
import '../widgets/ios_widgets.dart';

class RecordPage extends StatefulWidget {
  const RecordPage({super.key});
  @override
  State<RecordPage> createState() => _RecordPageState();
}

class _RecordPageState extends State<RecordPage> {
  String _channel = '熊猫速汇(JPY)';
  String _recipient = '本人';
  DateTime _at = DateTime.now();
  final _usdtCtl = TextEditingController(text: '1000');
  final _jpyCtl = TextEditingController(text: '158700');
  final _cnyCtl = TextEditingController(text: '6720');
  // CNY/USDT 买入价（leg0 - 在国内买 U 的成本）。空白 = 用 RateCache 当前 mid
  final _cnyRateCtl = TextEditingController();
  final _noteCtl = TextEditingController();
  bool _saving = false;

  ChannelMeta get _meta => metaFor(_channel);
  UsdtCnyHistory? _hist;
  bool _leg0Edited = false;

  @override
  void initState() {
    super.initState();
    _prefillLeg0();
    _loadHist();
  }

  Future<void> _loadHist() async {
    try {
      final h = await UsdtCnyHistory.load();
      if (mounted) {
        setState(() => _hist = h);
        _prefillLeg0();
      }
    } catch (_) {}
  }

  void _prefillLeg0() {
    if (_leg0Edited) return;
    final d = _defaultLeg0();
    if (d != null) _cnyRateCtl.text = d;
  }

  /// leg0 买入价默认 = 成交当天**历史币安 USDT/CNY 估算价**; 拿不到则退回 Wise USD/CNY。
  String? _defaultLeg0() {
    final h = _hist;
    if (h != null) {
      final est = h.estBinanceSellAt(_at, RateCache.instance.snapshot);
      if (est != null && est > 0) return est.toStringAsFixed(4);
    }
    final r = RateCache.instance.referenceRate; // 兜底
    return (r != null && r > 0) ? r.toStringAsFixed(4) : null;
  }

  /// leg0 来源说明(写在金额区脚注)
  String _leg0Source() {
    final h = _hist;
    final d =
        '${_at.year}-${_at.month.toString().padLeft(2, '0')}-${_at.day.toString().padLeft(2, '0')}';
    if (h != null) {
      final cg = h.coingeckoAt(_at);
      final prem = h.premium(RateCache.instance.snapshot);
      if (cg != null) {
        return 'leg0 买入价默认 = 币安 USDT/CNY 估算 @$d · '
            '来源: CoinGecko 历史 ${cg.toStringAsFixed(4)} × 实时溢价 ${((prem - 1) * 100).toStringAsFixed(1)}% (可改)';
      }
    }
    return 'leg0 买入价默认 = Wise USD/CNY (历史币安数据未就绪, 可改)';
  }

  Future<void> _save() async {
    final usdt = double.tryParse(_usdtCtl.text.trim());
    final cny = double.tryParse(_cnyCtl.text.trim());
    final twoHop = _meta.twoHop;
    final jpy = twoHop ? double.tryParse(_jpyCtl.text.trim()) : null;

    if (usdt == null || usdt <= 0 || cny == null || cny <= 0) {
      _toast('请输入有效的 USDT / CNY 金额');
      return;
    }
    if (twoHop && (jpy == null || jpy <= 0)) {
      _toast('两段路径需要填中转日元');
      return;
    }

    double? ref1, ref2;
    if (twoHop) {
      ref1 = RateCache.instance.usdJpyReference;
      ref2 = RateCache.instance.jpyCnyReference;
      if (ref1 == null || ref2 == null) {
        _toast('Wise 参考价未就绪,先去预测页刷新');
        return;
      }
    } else {
      ref1 = RateCache.instance.referenceRate;
      if (ref1 == null) {
        _toast('Wise USD/CNY 未就绪,先去预测页刷新');
        return;
      }
    }

    // leg0 CNY/USDT 买入价 - 空白表示用当时市场 mid (fallback)
    final cnyRate = double.tryParse(_cnyRateCtl.text.trim());

    setState(() => _saving = true);
    final r = ExchangeRecord(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      at: _at,
      channel: _channel,
      usdtAmount: usdt,
      jpyAmount: jpy,
      cnyReceived: cny,
      referenceRate: ref1,
      jpyCnyReference: ref2,
      cnyToUsdtRate: (cnyRate != null && cnyRate > 0) ? cnyRate : null,
      recipient: _recipient,
      note: _noteCtl.text.trim(),
    );
    try {
      final store = await LocalStore.instance;
      await store.addRecord(r);
    } catch (e) {
      _toast('保存失败: $e');
      setState(() => _saving = false);
      return;
    }
    _usdtCtl.text = '1000';
    _leg0Edited = false;
    _cnyRateCtl.text = _defaultLeg0() ?? '';
    _jpyCtl.text = '158700';
    _cnyCtl.text = '6720';
    _noteCtl.clear();
    setState(() => _saving = false);
    final signed = r.costVsReference >= 0
        ? '汇损 ¥${r.costVsReference.toStringAsFixed(2)}'
        : '溢价 ¥${(-r.costVsReference).toStringAsFixed(2)}';
    _toast('已保存 · $signed');
  }

  void _toast(String s) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(s), duration: const Duration(seconds: 2)),
    );
  }

  Future<void> _pickDateTime() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _at,
      firstDate: DateTime(2023),
      lastDate: DateTime(2030),
    );
    if (d == null || !mounted) return;
    final t = await showTimePicker(
        context: context, initialTime: TimeOfDay.fromDateTime(_at));
    if (t == null) return;
    setState(() => _at = DateTime(d.year, d.month, d.day, t.hour, t.minute));
    _prefillLeg0(); // 日期变了, 未手改则按新日期重填历史币安价
  }

  Future<void> _pickChannel() async {
    final v = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: IOS.grayBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.symmetric(vertical: 12),
          children: [
            for (final c in kChannels)
              IOSRow(
                leadingIcon: c.twoHop ? Icons.currency_yen : Icons.attach_money,
                iconColors: c.twoHop
                    ? const [IOS.violet, IOS.indigo]
                    : const [IOS.blue, IOS.blueDark],
                label: c.name,
                sub: c.tagline,
                trailing: c.name == _channel
                    ? const Icon(Icons.check, color: IOS.blue)
                    : null,
                onTap: () => Navigator.pop(context, c.name),
              ),
          ],
        ),
      ),
    );
    if (v != null) setState(() => _channel = v);
  }

  Future<void> _pickRecipient() async {
    final v = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: IOS.grayBg,
      builder: (_) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.symmetric(vertical: 12),
          children: [
            for (final r in kRecipients)
              IOSRow(
                leadingIcon: r == '本人' ? Icons.person : Icons.people,
                iconColors: const [IOS.blue, IOS.blueDark],
                label: r,
                trailing: r == _recipient
                    ? const Icon(Icons.check, color: IOS.blue)
                    : null,
                onTap: () => Navigator.pop(context, r),
              ),
          ],
        ),
      ),
    );
    if (v != null) setState(() => _recipient = v);
  }

  @override
  Widget build(BuildContext c) {
    final twoHop = _meta.twoHop;
    return Scaffold(
      backgroundColor: IOS.grayBg,
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            IOSLargeTitle(
              title: '新记录',
              leading: [
                IOSNavLink('清空', onTap: () {
                  _usdtCtl.text = '1000';
                  _leg0Edited = false;
                  _cnyRateCtl.text = _defaultLeg0() ?? '';
                  _jpyCtl.text = '158700';
                  _cnyCtl.text = '6720';
                  _noteCtl.clear();
                  setState(() {});
                }),
              ],
              actions: [
                _saving
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : IOSNavLink('保存', bold: true, onTap: _save),
              ],
            ),
            _ticker(),
            IOSSection(
              header: '交易信息',
              children: [
                IOSFormRow(
                  label: '渠道',
                  value: _channel,
                  chevron: true,
                  onTap: _pickChannel,
                ),
                IOSFormRow(
                  label: '收款人',
                  value: _recipient,
                  chevron: true,
                  onTap: _pickRecipient,
                ),
                IOSFormRow(
                  label: '日期时间',
                  value: DateFormat('MM月dd日 HH:mm').format(_at),
                  chevron: true,
                  onTap: _pickDateTime,
                ),
              ],
            ),
            IOSSection(
              header: '金额',
              footer: _leg0Source(),
              children: [
                _amountRow('USDT 投入', _usdtCtl, ' '),
                _amountRow('CNY/USDT 买入价 (leg0)', _cnyRateCtl, '',
                    hint: _defaultLeg0() ?? '选填',
                    onChanged: (v) => _leg0Edited = true),
                if (twoHop) _amountRow('中转 JPY', _jpyCtl, ''),
                _amountRow('实收 CNY', _cnyCtl, '¥'),
              ],
            ),
            IOSSection(
              header: '备注',
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: TextField(
                    controller: _noteCtl,
                    decoration: const InputDecoration(
                      hintText: '比如:3 月工资',
                      hintStyle: TextStyle(color: IOS.gray2, fontSize: 16),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                    style: const TextStyle(fontSize: 16, color: IOS.textPrimary),
                  ),
                ),
              ],
            ),
            _previewBanner(),
            _quotaSection(),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _ticker() {
    final usdJpy = RateCache.instance.usdJpyReference;
    final jpyCny = RateCache.instance.jpyCnyReference;
    final usdCny = RateCache.instance.referenceRate;
    return IOSTickerBar(
      items: [
        if (_meta.twoHop) ...[
          TickerItem(
            'Wise USD/JPY',
            usdJpy?.toStringAsFixed(2) ?? '—',
          ),
          TickerItem(
            'JPY/CNY',
            jpyCny?.toStringAsFixed(4) ?? '—',
          ),
        ] else
          TickerItem(
            'Wise USD/CNY',
            usdCny?.toStringAsFixed(4) ?? '—',
          ),
      ],
    );
  }

  Widget _amountRow(String label, TextEditingController ctl, String prefix,
      {String? hint, ValueChanged<String>? onChanged}) {
    return Container(
      constraints: const BoxConstraints(minHeight: 48),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          // label 不参与 flex(否则会占一份 flex 没用满, 把输入框挤到中间留右侧空白)
          Text(label,
              style: const TextStyle(fontSize: 15, color: IOS.textPrimary)),
          const SizedBox(width: 12),
          if (prefix.isNotEmpty)
            Text(prefix, style: IOS.monoSize(16, color: IOS.blue)),
          Expanded(
            child: TextField(
              controller: ctl,
              textAlign: TextAlign.right,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              style: IOS.monoSize(16, color: IOS.blue),
              decoration: InputDecoration(
                border: InputBorder.none,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
                hintText: hint,
                hintStyle: IOS.monoSize(15, color: IOS.gray2),
              ),
              onChanged: (v) {
                onChanged?.call(v);
                setState(() {});
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _previewBanner() {
    final usdt = double.tryParse(_usdtCtl.text.trim());
    final cny = double.tryParse(_cnyCtl.text.trim());
    final twoHop = _meta.twoHop;
    final jpy = twoHop ? double.tryParse(_jpyCtl.text.trim()) : null;
    if (usdt == null || cny == null || usdt <= 0 || cny <= 0) {
      return const SizedBox.shrink();
    }

    final ref1 = twoHop
        ? RateCache.instance.usdJpyReference
        : RateCache.instance.referenceRate;
    final ref2 = twoHop ? RateCache.instance.jpyCnyReference : null;
    if (ref1 == null) return const SizedBox.shrink();

    final expected = twoHop && ref2 != null
        ? usdt * ref1 * ref2
        : usdt * ref1;
    final cost = expected - cny;
    final pct = expected > 0 ? cost / expected * 100 : 0;
    final isLoss = cost > 0;

    String? leg1Pct, leg2Pct;
    String? leg1Rate, leg2Rate;
    if (twoHop && jpy != null && jpy > 0 && ref2 != null) {
      final l1 = jpy / usdt;
      final l2 = cny / jpy;
      leg1Rate = l1.toStringAsFixed(2);
      leg2Rate = l2.toStringAsFixed(5);
      leg1Pct = '${((l1 - ref1) / ref1 * 100).toStringAsFixed(2)}%';
      leg2Pct = '${((l2 - ref2) / ref2 * 100).toStringAsFixed(2)}%';
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(IOS.radCard),
        border: Border.all(color: IOS.separator, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('实时损耗预览',
                  style: TextStyle(
                    color: IOS.gray,
                    fontSize: 11,
                    letterSpacing: 0.5,
                    fontWeight: FontWeight.w500,
                  )),
              const Spacer(),
              Container(
                width: 6,
                height: 6,
                decoration: const BoxDecoration(
                    shape: BoxShape.circle, color: IOS.green),
              ),
              const SizedBox(width: 4),
              const Text('LIVE',
                  style: TextStyle(
                      color: IOS.green,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5)),
            ],
          ),
          const SizedBox(height: 10),
          if (twoHop && leg1Rate != null) ...[
            _previewKv('段① USDT→JPY', leg1Rate, leg1Pct, IOS.red),
            const SizedBox(height: 4),
            _previewKv('段② JPY→CNY', leg2Rate!, leg2Pct, IOS.red),
          ] else ...[
            _previewKv('实际汇率', (cny / usdt).toStringAsFixed(4),
                '${pct.toStringAsFixed(2)}%', isLoss ? IOS.red : IOS.green),
          ],
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 10),
            child: Divider(height: 1, color: IOS.separator),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '本笔${isLoss ? "汇损" : "溢价"} / 预期 ¥${expected.toStringAsFixed(2)}',
                      style: const TextStyle(color: IOS.gray, fontSize: 12),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${isLoss ? "−" : "+"}¥${cost.abs().toStringAsFixed(2)} '
                      '(${isLoss ? "−" : "+"}${pct.abs().toStringAsFixed(2)}%)',
                      style: IOS.monoSize(22,
                          weight: FontWeight.w700,
                          color: isLoss ? IOS.red : IOS.green),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _previewKv(String label, String value, String? pct, Color pctColor) {
    return Row(
      children: [
        Expanded(
          child: Text(label,
              style: IOS.monoSize(11, color: IOS.gray)),
        ),
        Text(value,
            style: IOS.monoSize(11, weight: FontWeight.w600)),
        if (pct != null) ...[
          const SizedBox(width: 12),
          SizedBox(
            width: 70,
            child: Text(
              'vs Wise ${pct.startsWith("-") ? "−${pct.substring(1)}" : "+$pct"}',
              textAlign: TextAlign.right,
              style: IOS.monoSize(11, color: pctColor, weight: FontWeight.w600),
              overflow: TextOverflow.visible,
            ),
          ),
        ],
      ],
    );
  }

  Widget _quotaSection() {
    if (!_meta.jpyQuotaControlled) return const SizedBox.shrink();
    return FutureBuilder(
      future: LocalStore.instance.then((s) => s.loadRecords()),
      builder: (c, snap) {
        if (!snap.hasData) return const SizedBox.shrink();
        final usage =
            QuotaService.forChannel(snap.data!, _channel, DateTime.now());
        final pct = usage.monthPct;
        final remaining = (usage.monthLimit - usage.monthUsed) / 10000;
        final color = pct > 0.8 ? IOS.red : (pct > 0.5 ? IOS.orange : IOS.green);
        return IOSSection(
          header: '本月额度 · $_channel',
          children: [
            IOSQuotaBar(
              pct: pct,
              leftText: '本月已用',
              rightText:
                  '${(usage.monthUsed / 10000).toStringAsFixed(0)} 万 / 300 万 JPY',
              color: color,
            ),
            Container(height: 0.5, color: IOS.separator),
            IOSQuotaBar(
              pct: usage.yearPct,
              leftText: '本年已用',
              rightText:
                  '${(usage.yearUsed / 10000).toStringAsFixed(0)} 万 / 600 万 JPY',
              color: usage.yearPct > 0.8
                  ? IOS.red
                  : (usage.yearPct > 0.5 ? IOS.orange : IOS.green),
            ),
          ],
          footer: '剩余 ${remaining.toStringAsFixed(0)} 万 JPY 额度。各平台不共享。',
        );
      },
    );
  }
}
