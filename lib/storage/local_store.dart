import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/exchange_record.dart';
import '../models/quote.dart';

/// 跨平台本地存储 (基于 SharedPreferences,支持 Android/iOS/macOS/Windows/Linux/Web)。
/// 卸载应用时随沙盒/localStorage 一起清除。
class LocalStore {
  static LocalStore? _instance;
  static Future<LocalStore> get instance async =>
      _instance ??= LocalStore._(await SharedPreferences.getInstance());

  static const _kRecords = 'records_v1';
  static const _kSnapshots = 'snapshots_v1';
  static const _kSnapshotLimit = 1000;

  final SharedPreferences _sp;
  LocalStore._(this._sp);

  // --- Records ---
  Future<List<ExchangeRecord>> loadRecords() async {
    final raw = _sp.getString(_kRecords);
    if (raw == null || raw.trim().isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list
          .map((e) => ExchangeRecord.fromJson(e as Map<String, dynamic>))
          .toList()
        ..sort((a, b) => b.at.compareTo(a.at));
    } catch (_) {
      return [];
    }
  }

  Future<void> saveRecords(List<ExchangeRecord> rs) async {
    final json = jsonEncode(rs.map((r) => r.toJson()).toList());
    await _sp.setString(_kRecords, json);
  }

  Future<void> addRecord(ExchangeRecord r) async {
    final rs = await loadRecords();
    rs.add(r);
    await saveRecords(rs);
  }

  Future<void> deleteRecord(String id) async {
    final rs = await loadRecords();
    rs.removeWhere((r) => r.id == id);
    await saveRecords(rs);
  }

  // --- Rate snapshots (for history curves) ---
  Future<void> appendSnapshot(List<Quote> quotes) async {
    if (quotes.isEmpty) return;
    final prev = await _loadSnapshotsRaw();
    prev.add({
      'at': DateTime.now().toIso8601String(),
      'quotes': quotes.map((q) => q.toMap()).toList(),
    });
    if (prev.length > _kSnapshotLimit) {
      prev.removeRange(0, prev.length - _kSnapshotLimit);
    }
    await _sp.setString(_kSnapshots, jsonEncode(prev));
  }

  Future<List<Map<String, dynamic>>> _loadSnapshotsRaw() async {
    final raw = _sp.getString(_kSnapshots);
    if (raw == null || raw.trim().isEmpty) return [];
    try {
      return (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
    } catch (_) {
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> loadSnapshots() => _loadSnapshotsRaw();

  // --- Maintenance ---
  Future<void> clearAll() async {
    await _sp.remove(_kRecords);
    await _sp.remove(_kSnapshots);
  }

  /// 导出为 JSON 字符串(备份/分享)
  Future<String> exportJson() async {
    return jsonEncode({
      'records': (await loadRecords()).map((r) => r.toJson()).toList(),
      'snapshots': await _loadSnapshotsRaw(),
      'exportedAt': DateTime.now().toIso8601String(),
    });
  }

  /// 从备份 JSON 恢复
  Future<void> importJson(String json) async {
    final data = jsonDecode(json) as Map<String, dynamic>;
    final recs = (data['records'] as List?)
            ?.map((e) => ExchangeRecord.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [];
    await saveRecords(recs);
    final snaps = (data['snapshots'] as List?)?.cast<Map<String, dynamic>>();
    if (snaps != null) {
      await _sp.setString(_kSnapshots, jsonEncode(snaps));
    }
  }
}
