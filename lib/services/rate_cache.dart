import 'dart:async';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/quote.dart';
import 'rate_fetcher.dart';

/// 汇率内存缓存 + 本地持久化。
///
/// 策略:
///   • 启动时 [loadFromDisk] 瞬间填充缓存(0 网络请求),UI 秒开。
///   • 手动点刷新按钮才调用 [refresh] 发网络请求。
///   • 同一时刻多个 refresh 共享同一 future。
///   • 成功后写回磁盘。
class RateCache {
  static final RateCache instance = RateCache._();
  RateCache._();

  static const _storageKey = 'cached_quotes_v1';
  static const _fetchTimeKey = 'cached_quotes_time_v1';

  List<Quote> _quotes = [];
  DateTime? _lastFetch;
  Future<List<Quote>>? _pending;
  Timer? _autoTimer;

  List<Quote> get snapshot => List.unmodifiable(_quotes);
  DateTime? get lastFetch => _lastFetch;
  bool get hasData => _quotes.isNotEmpty;
  bool get isLoading => _pending != null;

  /// App 启动调一次:从 SharedPreferences 读取上次保存的快照。
  Future<void> loadFromDisk() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final raw = sp.getString(_storageKey);
      final t = sp.getInt(_fetchTimeKey);
      if (raw != null) {
        final list = jsonDecode(raw) as List;
        _quotes = list
            .map((e) => _quoteFromJson(e as Map<String, dynamic>))
            .whereType<Quote>()
            .toList();
      }
      if (t != null) {
        _lastFetch = DateTime.fromMillisecondsSinceEpoch(t);
      }
    } catch (_) {}
  }

  /// 手动刷新 — 一定走网络。
  Future<List<Quote>> refresh() {
    if (_pending != null) return _pending!;
    final f = RateFetcher.fetchAll().then((qs) async {
      if (qs.isNotEmpty) {
        _quotes = qs;
        _lastFetch = DateTime.now();
        await _saveToDisk();
      }
      _pending = null;
      return qs;
    }).catchError((e) {
      _pending = null;
      throw e;
    });
    _pending = f;
    return f;
  }

  Future<void> _saveToDisk() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final json = jsonEncode(_quotes.map(_quoteToJson).toList());
      await sp.setString(_storageKey, json);
      if (_lastFetch != null) {
        await sp.setInt(_fetchTimeKey, _lastFetch!.millisecondsSinceEpoch);
      }
    } catch (_) {}
  }

  /// 启动后台自动刷新。默认每小时一次。
  ///
  /// - 启动后立即触发一次 refresh（如果距上次拉取超过 [interval]）
  /// - 之后每隔 [interval] 后台调用 refresh()
  /// - 单源失败不影响整体（RateFetcher._safe 已包裹）
  /// - 多次调用会先 cancel 上一个 Timer
  void startAutoRefresh({Duration interval = const Duration(hours: 1)}) {
    _autoTimer?.cancel();
    final stale = _lastFetch == null ||
        DateTime.now().difference(_lastFetch!) >= interval;
    if (stale && _pending == null) {
      // 不 await，让调用方继续启动
      refresh().catchError((_) => <Quote>[]);
    }
    _autoTimer = Timer.periodic(interval, (_) {
      if (_pending == null) {
        refresh().catchError((_) => <Quote>[]);
      }
    });
  }

  /// 停止自动刷新（卸载页面或 app 退出时调用）
  void stopAutoRefresh() {
    _autoTimer?.cancel();
    _autoTimer = null;
  }

  /// 清空缓存(导出/重置用)
  Future<void> clear() async {
    _quotes = [];
    _lastFetch = null;
    final sp = await SharedPreferences.getInstance();
    await sp.remove(_storageKey);
    await sp.remove(_fetchTimeKey);
  }

  // ---------------- 参考价 getters ----------------
  double? get referenceRate => _quotes
      .where((q) => q.pair == 'USD/CNY' && q.source == 'Wise')
      .firstOrNull
      ?.mid;

  double? get usdJpyReference => _quotes
      .where((q) => q.pair == 'USD/JPY' && q.source == 'Wise')
      .firstOrNull
      ?.mid;

  double? get jpyCnyReference => _quotes
      .where((q) => q.pair == 'JPY/CNY' && q.source == 'Wise')
      .firstOrNull
      ?.mid;

  // ---------------- 序列化 ----------------
  Map<String, dynamic> _quoteToJson(Quote q) => {
        'source': q.source,
        'pair': q.pair,
        'mid': q.mid,
        'bestBid': q.bestBid,
        'sampleSize': q.sampleSize,
        'sampledAt': q.sampledAt.toIso8601String(),
        'note': q.note,
      };

  Quote? _quoteFromJson(Map<String, dynamic> j) {
    try {
      return Quote(
        source: j['source'] as String,
        pair: j['pair'] as String,
        mid: (j['mid'] as num).toDouble(),
        bestBid: (j['bestBid'] as num?)?.toDouble(),
        sampleSize: (j['sampleSize'] as int?) ?? 0,
        sampledAt: DateTime.parse(j['sampledAt'] as String),
        note: (j['note'] as String?) ?? '',
      );
    } catch (_) {
      return null;
    }
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
