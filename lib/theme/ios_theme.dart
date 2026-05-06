import 'package:flutter/material.dart';

/// iOS Pro 主题色 (匹配 design/option-final-ios-pro.html)
class IOS {
  // 系统色
  static const blue = Color(0xFF007AFF);
  static const blueDark = Color(0xFF0051D5);
  static const green = Color(0xFF34C759);
  static const red = Color(0xFFFF3B30);
  static const orange = Color(0xFFFF9500);
  static const yellow = Color(0xFFFFCC00);
  static const violet = Color(0xFFAF52DE);
  static const indigo = Color(0xFF5856D6);
  static const gray = Color(0xFF8E8E93);
  static const gray2 = Color(0xFFC7C7CC);
  static const gray3 = Color(0xFF6C6C70);
  static const grayBg = Color(0xFFF2F2F7);
  static const separator = Color(0x1A3C3C43);
  static const textPrimary = Color(0xFF000000);
  static const textSecondary = Color(0xFF3C3C43);
  static const textTertiary = Color(0xFF8E8E93);

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

  // 间距
  static const double radCard = 14.0;
  static const double radHero = 16.0;
  static const double radPill = 14.0;

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
