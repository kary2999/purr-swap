import 'package:flutter/material.dart';

/// Purr Swap 品牌暖色·猫咪主题 (匹配 design/PurrSwap-warm.html)
/// 奶油底 + 珊瑚橙品牌主色 + 暖色中性。
/// 注: 历史代码大量引用 IOS.blue 作为"主色", 这里保留命名但重定向为珊瑚橙,
///     这样全 app 一处换肤、不必改动各页面引用。
class IOS {
  // 品牌主色 — 降饱和橙, 仅用于按钮/选中态/关键数字 (历史命名沿用 blue=主色)
  static const blue = Color(0xFFE8704A); // --color-primary
  static const blueDark = Color(0xFFF5A988); // --color-primary-soft (渐变浅端/弱强调)
  static const coral = Color(0xFFE8704A);
  static const coral2 = Color(0xFFF5A988);
  static const peach = Color(0xFFFDF1EA); // --color-primary-bg 极浅橙 (选中行/卡片底)

  // 语义色
  static const green = Color(0xFF2E9E6B); // --color-success
  static const red = Color(0xFFDC4C4C); // --color-danger
  static const orange = Color(0xFFE8923A); // 警示橙 (降饱和, 区别于主色)
  static const yellow = Color(0xFFE8B339);
  static const violet = Color(0xFFAF52DE);
  static const indigo = Color(0xFF5856D6);

  // 中性 — 冷灰, 安静
  static const gray = Color(0xFF6B7280); // --color-text-secondary
  static const gray2 = Color(0xFFC9CDD3); // 占位 / chevron / 禁用
  static const gray3 = Color(0xFF9CA3AF); // section header / tertiary
  static const grayBg = Color(0xFFFBF6F0); // --color-bg 暖米白
  static const separator = Color(0xFFECECEF); // 中性发丝线
  static const textPrimary = Color(0xFF1F2937); // --color-text-primary 深灰非纯黑
  static const textSecondary = Color(0xFF6B7280);
  static const textTertiary = Color(0xFF9CA3AF);

  // 数字字体
  static const TextStyle mono = TextStyle(
    fontFamily: 'monospace',
    fontFamilyFallback: [
      'SF Mono', 'Menlo', 'Consolas', 'Courier New', 'monospace',
    ],
    fontFeatures: [FontFeature.tabularFigures()],
  );

  static TextStyle monoSize(double size, {FontWeight? weight, Color? color}) =>
      mono.copyWith(fontSize: size, fontWeight: weight, color: color);

  // 间距 / 圆角 (统一 4 的倍数; 卡片 16, 胶囊 999)
  static const double radCard = 16.0;
  static const double radHero = 16.0;
  static const double radPill = 100.0;
  static const double radTag = 8.0;

  // 轻柔投影 (禁止又黑又硬)
  static const List<BoxShadow> softShadow = [
    BoxShadow(color: Color(0x0A000000), blurRadius: 3, offset: Offset(0, 1)),
    BoxShadow(color: Color(0x0A000000), blurRadius: 12, offset: Offset(0, 4)),
  ];

  static ThemeData themeData() {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: blue,
        primary: blue,
        background: grayBg,
        surface: Colors.white,
      ),
      scaffoldBackgroundColor: grayBg,
      // iOS 风格点击反馈: 去掉 Material 水波纹, 改用克制的灰色高亮 (类似系统列表按压)
      splashFactory: NoSplash.splashFactory,
      splashColor: Colors.transparent,
      highlightColor: const Color(0x14000000), // ~8% black
      appBarTheme: const AppBarTheme(
        backgroundColor: grayBg,
        foregroundColor: textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: textPrimary,
          fontSize: 17,
          fontWeight: FontWeight.w600,
        ),
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radCard),
          side: const BorderSide(color: separator, width: 0.5),
        ),
      ),
      dividerColor: separator,
      dividerTheme: const DividerThemeData(
        color: separator,
        thickness: 0.5,
        space: 0,
      ),
      textTheme: const TextTheme(
        bodyLarge: TextStyle(color: textPrimary, fontSize: 16),
        bodyMedium: TextStyle(color: textPrimary, fontSize: 14),
        bodySmall: TextStyle(color: textSecondary, fontSize: 12),
      ),
      // 精致无衬线优先; LXGW 作为 web/CanvasKit 的 CJK 兜底(系统字体在 web 不可靠)
      fontFamily: 'PingFang SC',
      fontFamilyFallback: const [
        'HarmonyOS Sans SC',
        'Source Han Sans SC',
        'Noto Sans SC',
        'Hiragino Sans GB',
        'Microsoft YaHei',
        'LXGW',
        'sans-serif',
      ],
    );
  }
}
