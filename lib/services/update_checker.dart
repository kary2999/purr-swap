import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import '../version.dart';

/// 远端最新版信息（来自 releases 分支根部的 version.json）。
class UpdateInfo {
  final String currentVersion;
  final String latestVersion;
  final String? androidUrl;
  final String? macosUrl;
  final String? webUrl;
  final String? notes;
  /// latestVersion 是否严格高于 currentVersion（semver）
  final bool hasUpdate;

  UpdateInfo({
    required this.currentVersion,
    required this.latestVersion,
    this.androidUrl,
    this.macosUrl,
    this.webUrl,
    this.notes,
    required this.hasUpdate,
  });
}

/// 检查 app 是否有新版本可用。
///
/// 数据源：`https://kary2999.github.io/purr-swap/version.json`（Pages 同源, 无 CORS 问题）
/// 备用：`https://github.com/kary2999/purr-swap/raw/releases/version.json`
///
/// 不做"自动替换二进制"——那需要 Sparkle/Squirrel + 签名机制。
/// 仅做：检测 → 通知 → 跳转下载链接（用户系统会触发安装弹窗）。
class UpdateChecker {
  // 优先走 GitHub Pages（CORS 友好），fallback raw.githubusercontent
  static const _primaryUrl =
      'https://kary2999.github.io/purr-swap/version.json';
  static const _fallbackUrl =
      'https://raw.githubusercontent.com/kary2999/purr-swap/releases/version.json';

  /// 拉远端 version.json 并比较。失败时返回 null（静默，不打扰用户）。
  static Future<UpdateInfo?> check() async {
    for (final url in [_primaryUrl, _fallbackUrl]) {
      try {
        final resp = await http
            .get(Uri.parse(url), headers: {'Accept': 'application/json'})
            .timeout(const Duration(seconds: 6));
        if (resp.statusCode != 200) continue;
        final j = jsonDecode(resp.body) as Map<String, dynamic>;
        final latest = (j['latest'] as String?)?.trim();
        if (latest == null || latest.isEmpty) continue;
        return UpdateInfo(
          currentVersion: kAppVersion,
          latestVersion: latest,
          androidUrl: j['android'] as String?,
          macosUrl: j['macos'] as String?,
          webUrl: j['web'] as String?,
          notes: j['notes'] as String?,
          hasUpdate: _isStrictlyNewer(latest, kAppVersion),
        );
      } catch (_) {
        // 试下一个 URL
      }
    }
    return null;
  }

  /// semver 比较: latest > current ?
  /// 解析 "0.2.5" / "1.0.0" 这种格式，长度不一致用 0 补齐。
  static bool _isStrictlyNewer(String latest, String current) {
    final pa = latest.split('.').map((s) => int.tryParse(s) ?? 0).toList();
    final pb = current.split('.').map((s) => int.tryParse(s) ?? 0).toList();
    final n = pa.length > pb.length ? pa.length : pb.length;
    while (pa.length < n) {
      pa.add(0);
    }
    while (pb.length < n) {
      pb.add(0);
    }
    for (int i = 0; i < n; i++) {
      if (pa[i] > pb[i]) return true;
      if (pa[i] < pb[i]) return false;
    }
    return false;
  }

  /// 平台特定的下载 URL（Web 上返回 web URL = 无需更新）。
  static String? platformDownloadUrl(UpdateInfo info) {
    if (kIsWeb) return info.webUrl;
    // 简化：根据 OS 字符串判断（在 main.dart 启动后通过 Platform 设置）
    // 这里仅给出通用决策；实际平台判断由调用方做
    return info.macosUrl ?? info.androidUrl;
  }
}
