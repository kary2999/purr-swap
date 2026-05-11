import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'pages/record_page.dart';
import 'pages/forecast_page.dart';
import 'pages/history_page.dart';
import 'pages/stats_page.dart';
import 'pages/guide_page.dart';
import 'pages/settings_page.dart';
import 'services/rate_cache.dart';
import 'theme/ios_theme.dart';
import 'web_plugins_stub.dart' if (dart.library.html) 'web_plugins.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (kIsWeb) {
    registerWebPlugins();
    debugPrint('[web] registerWebPlugins DONE at ${DateTime.now()}');
  }
  await RateCache.instance.loadFromDisk();
  // 后台每 10 分钟自动刷新汇率（启动若数据已陈旧也立即刷一次）
  RateCache.instance.startAutoRefresh(interval: const Duration(minutes: 10));
  runApp(const PurrSwapApp());
}

class PurrSwapApp extends StatelessWidget {
  const PurrSwapApp({super.key});
  @override
  Widget build(BuildContext c) => MaterialApp(
        title: 'Purr Swap · 换金所',
        debugShowCheckedModeBanner: false,
        theme: IOS.themeData(),
        home: const RootShell(),
      );
}

class RootShell extends StatefulWidget {
  const RootShell({super.key});
  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> {
  int _idx = 0;
  final Map<int, Widget> _builtPages = {};

  Widget _buildPage(int i) {
    return _builtPages.putIfAbsent(i, () {
      switch (i) {
        case 0:
          return const ForecastPage();
        case 1:
          return const RecordPage();
        case 2:
          return const HistoryPage();
        case 3:
          return const StatsPage();
        case 4:
          return const GuidePage();
        case 5:
          return const SettingsPage();
      }
      return const SizedBox.shrink();
    });
  }

  @override
  Widget build(BuildContext c) => Scaffold(
        backgroundColor: IOS.grayBg,
        body: Stack(
          children: List.generate(6, (i) {
            if (!_builtPages.containsKey(i) && i != _idx) {
              return const SizedBox.shrink();
            }
            return Offstage(
              offstage: i != _idx,
              child: TickerMode(
                enabled: i == _idx,
                child: _buildPage(i),
              ),
            );
          }),
        ),
        bottomNavigationBar: _IOSTabBar(
          index: _idx,
          onTap: (i) => setState(() => _idx = i),
        ),
      );
}

/// iOS 风毛玻璃 tab bar
class _IOSTabBar extends StatelessWidget {
  final int index;
  final ValueChanged<int> onTap;
  const _IOSTabBar({required this.index, required this.onTap});

  @override
  Widget build(BuildContext c) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.92),
        border: Border(
          top: BorderSide(color: IOS.separator.withValues(alpha: 0.6), width: 0.5),
        ),
      ),
      padding: const EdgeInsets.only(top: 6, bottom: 16),
      child: Row(
        children: [
          _tab(0, Icons.auto_awesome, '预测'),
          _tab(1, Icons.add_circle_outline, '记一笔'),
          _tab(2, Icons.access_time, '历史'),
          _tab(3, Icons.bar_chart, '统计'),
          _tab(4, Icons.menu_book_outlined, '指南'),
          _tab(5, Icons.settings_outlined, '设置'),
        ],
      ),
    );
  }

  Widget _tab(int i, IconData icon, String lb) {
    final active = i == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => onTap(i),
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 22, color: active ? IOS.blue : IOS.gray),
              const SizedBox(height: 2),
              Text(lb,
                  style: TextStyle(
                    fontSize: 10,
                    color: active ? IOS.blue : IOS.gray,
                    fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                  )),
            ],
          ),
        ),
      ),
    );
  }
}
