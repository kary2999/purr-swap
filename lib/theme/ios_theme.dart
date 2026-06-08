import 'package:flutter/material.dart';

/// Purr Swap 品牌暖色·猫咪主题 (匹配 design/PurrSwap-warm.html)
/// 奶油底 + 珊瑚橙品牌主色 + 暖色中性。
/// 注: 历史代码大量引用 IOS.blue 作为"主色", 这里保留命名但重定向为珊瑚橙,
///     这样全 app 一处换肤、不必改动各页面引用。
class IOS {
  // 品牌主色 (原 blue/blueDark → 珊瑚橙渐变)
  static const blue = Color(0xFFFF6B45); // coral 主色
  static const blueDark = Color(0xFFFF8A63); // coral2 (渐变浅端)
  static const coral = Color(0xFFFF6B45);
  static const coral2 = Color(0xFFFF8A63);
  static const peach = Color(0xFFFFEDE4); // 浅桃色 (奖章底 / 进度槽)

  // 语义色 (暖化的涨绿跌红)
  static const green = Color(0xFF1FAE6B);
  static const red = Color(0xFFF0504A);
  static const orange = Color(0xFFFF9500);
  static const yellow = Color(0xFFFFCC00);
  static const violet = Color(0xFFAF52DE);
  static const indigo = Color(0xFF5856D6);

  // 暖色中性
  static const gray = Color(0xFFB7A795); // 次级文字
  static const gray2 = Color(0xFFCFC2B2); // 占位 / chevron
  static const gray3 = Color(0xFF8A7B6B); // section header
  static const grayBg = Color(0xFFFBF6EF); // 奶油底
  static const separator = Color(0xFFEFE6D8); // 暖色发丝线
  static const textPrimary = Color(0xFF2B2018);
  static const textSecondary = Color(0xFF8A7B6B);
  static const textTertiary = Color(0xFFB7A795);

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

  // 间距 (暖色版更圆润)
  static const double radCard = 18.0;
  static const double radHero = 22.0;
  static const double radPill = 13.0;

  // 暖色卡片柔和阴影
  static List<BoxShadow> get softShadow => [
        BoxShadow(
          color: const Color(0xFF785028).withValues(alpha: 0.05),
          blurRadius: 16,
          offset: const Offset(0, 6),
        ),
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
      // 中文字体保留 LXGW
      fontFamily: 'LXGW',
      fontFamilyFallback: const [
        'PingFang SC', 'Hiragino Sans GB', 'Microsoft YaHei', 'sans-serif',
      ],
    );
  }
}
