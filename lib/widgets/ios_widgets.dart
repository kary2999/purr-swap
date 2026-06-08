// iOS Pro 公共组件库
// 全部对照 design/option-final-ios-pro.html 实现

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/ios_theme.dart';

/// === 通用按压反馈包装 ===
/// 给裸 GestureDetector 的元素加上 iOS/MD 标准的按压反馈:
/// opacity 淡出 + 可选轻微 scale + 可选触感, 120ms 落在 HIG/MD 的 150-300ms 区间内。
/// onTap 为 null 时视为禁用 (不响应、不反馈)。
class Pressable extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final double pressedOpacity;
  final double pressedScale;
  final bool haptic;
  final HitTestBehavior behavior;
  const Pressable({
    super.key,
    required this.child,
    this.onTap,
    this.pressedOpacity = 0.55,
    this.pressedScale = 1.0,
    this.haptic = false,
    this.behavior = HitTestBehavior.opaque,
  });
  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;
  void _set(bool v) {
    if (mounted && _down != v) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    return GestureDetector(
      behavior: widget.behavior,
      onTap: enabled
          ? () {
              if (widget.haptic) HapticFeedback.selectionClick();
              widget.onTap!();
            }
          : null,
      onTapDown: enabled ? (_) => _set(true) : null,
      onTapUp: enabled ? (_) => _set(false) : null,
      onTapCancel: enabled ? () => _set(false) : null,
      child: AnimatedScale(
        scale: _down ? widget.pressedScale : 1.0,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: AnimatedOpacity(
          opacity: _down ? widget.pressedOpacity : 1.0,
          duration: const Duration(milliseconds: 120),
          child: widget.child,
        ),
      ),
    );
  }
}

/// === 大型标题导航栏 ===
/// 上方一行操作按钮(可空),下方 34pt 大标题
class IOSLargeTitle extends StatelessWidget {
  final String title;
  final List<Widget>? leading;
  final List<Widget>? actions;
  const IOSLargeTitle({
    super.key,
    required this.title,
    this.leading,
    this.actions,
  });

  @override
  Widget build(BuildContext c) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 32,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(children: leading ?? const []),
                Row(
                  children: (actions ?? [])
                      .expand((w) => [w, const SizedBox(width: 14)])
                      .toList()
                    ..removeLast(),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.5,
                color: IOS.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class IOSNavLink extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final bool bold;
  const IOSNavLink(this.label, {super.key, this.onTap, this.bold = false});
  @override
  Widget build(BuildContext c) => Pressable(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Text(
            label,
            style: TextStyle(
              color: IOS.blue,
              fontSize: 16,
              fontWeight: bold ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ),
      );
}

class IOSNavIcon extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  const IOSNavIcon(this.icon, {super.key, this.onTap});
  @override
  Widget build(BuildContext c) => Pressable(
        onTap: onTap,
        pressedOpacity: 0.4,
        // 扩大触控区 (22pt 图标 + padding ≈ 38pt), 贴近 44pt 标准而不撑破 32pt 标题栏
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 5),
          child: Icon(icon, color: IOS.blue, size: 22),
        ),
      );
}

/// === 顶部 Live Ticker 实时行情条 ===
class IOSTickerBar extends StatelessWidget {
  final List<TickerItem> items;
  final String? trailing;
  const IOSTickerBar({super.key, required this.items, this.trailing});

  @override
  Widget build(BuildContext c) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: IOS.separator, width: 0.5),
        boxShadow: IOS.softShadow,
      ),
      child: Row(
        children: [
          const _BlinkDot(),
          const SizedBox(width: 6),
          Expanded(
            child: Wrap(
              spacing: 12,
              runSpacing: 4,
              children: items.map((it) => _PairChip(it)).toList(),
            ),
          ),
          if (trailing != null)
            Text(
              trailing!,
              style: IOS.monoSize(11, color: IOS.gray),
            ),
        ],
      ),
    );
  }
}

class TickerItem {
  final String label;
  final String value;
  final TickerColor color;
  const TickerItem(this.label, this.value, [this.color = TickerColor.normal]);
}

enum TickerColor { normal, up, down }

class _PairChip extends StatelessWidget {
  final TickerItem item;
  const _PairChip(this.item);
  @override
  Widget build(BuildContext c) {
    final clr = switch (item.color) {
      TickerColor.up => IOS.green,
      TickerColor.down => IOS.red,
      _ => IOS.textPrimary,
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(item.label,
            style: IOS.monoSize(11, color: IOS.gray, weight: FontWeight.w500)),
        const SizedBox(width: 4),
        Text(item.value,
            style: IOS.monoSize(11, weight: FontWeight.w700, color: clr)),
      ],
    );
  }
}

class _BlinkDot extends StatefulWidget {
  const _BlinkDot();
  @override
  State<_BlinkDot> createState() => _BlinkDotState();
}

class _BlinkDotState extends State<_BlinkDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(seconds: 2))
        ..repeat(reverse: true);
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext c) => AnimatedBuilder(
        animation: _c,
        builder: (_, __) => Opacity(
          opacity: 0.4 + 0.6 * _c.value,
          child: const Icon(Icons.circle, size: 8, color: IOS.green),
        ),
      );
}

/// === Hero 蓝色渐变输入卡 ===
class HeroInputCard extends StatelessWidget {
  final String label;
  final String value;
  final String unit;
  final List<int> presets;
  final int activePreset;
  final ValueChanged<int>? onPresetTap;
  final VoidCallback? onTap;
  const HeroInputCard({
    super.key,
    required this.label,
    required this.value,
    required this.unit,
    required this.presets,
    required this.activePreset,
    this.onPresetTap,
    this.onTap,
  });

  @override
  Widget build(BuildContext c) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 4, 16, 14),
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [IOS.blue, IOS.blueDark],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(IOS.radHero),
        ),
        child: Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            Positioned(
              right: 8,
              bottom: -10,
              child: Text(
                '🐾',
                style: TextStyle(
                  fontSize: 72,
                  color: Colors.white.withValues(alpha: 0.16),
                ),
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.85),
                      fontSize: 12,
                      letterSpacing: 0.4,
                    )),
                const SizedBox(height: 2),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Flexible(
                      child: RichText(
                        text: TextSpan(
                          style: IOS.monoSize(42,
                              weight: FontWeight.w700, color: Colors.white),
                          children: [
                            TextSpan(text: value),
                            TextSpan(
                              text: unit,
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w500,
                                color: Colors.white.withValues(alpha: 0.7),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(Icons.edit_outlined,
                        size: 17, color: Colors.white.withValues(alpha: 0.7)),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 6,
                  children: presets.map((v) {
                    final active = v == activePreset;
                    return Pressable(
                      onTap: () => onPresetTap?.call(v),
                      haptic: true,
                      pressedOpacity: 0.6,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        curve: Curves.easeOut,
                        padding:
                            const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                        decoration: BoxDecoration(
                          color: active
                              ? Colors.white
                              : Colors.white.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(IOS.radPill),
                        ),
                        child: Text(
                          _formatPreset(v),
                          style: IOS.monoSize(12,
                              weight: FontWeight.w500,
                              color: active ? IOS.blue : Colors.white),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatPreset(int v) {
    String comma(int n) => n.toString().replaceAllMapped(
        RegExp(r'(\d)(?=(\d{3})+(?!\d))'), (m) => '${m[1]},');
    if (unit == 'JPY') {
      if (v >= 10000) {
        final w = v / 10000;
        return '${w == w.roundToDouble() ? w.toStringAsFixed(0) : w.toStringAsFixed(1)}万';
      }
      return comma(v);
    }
    return v >= 10000 ? '${v ~/ 1000}K' : comma(v);
  }
}

/// === Grouped Section (header + list + footer) ===
class IOSSection extends StatelessWidget {
  final String? header;
  final String? footer;
  final List<Widget> children;
  final EdgeInsets margin;
  const IOSSection({
    super.key,
    this.header,
    this.footer,
    required this.children,
    this.margin = const EdgeInsets.fromLTRB(16, 10, 16, 18),
  });

  @override
  Widget build(BuildContext c) {
    return Padding(
      padding: margin,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (header != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 6),
              child: Text(
                header!.toUpperCase(),
                style: const TextStyle(
                  color: IOS.gray3,
                  fontSize: 13,
                  letterSpacing: 0.3,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(IOS.radCard),
              border: Border.all(color: IOS.separator, width: 0.5),
              boxShadow: IOS.softShadow,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(IOS.radCard),
              child: Column(
                children: _separated(children),
              ),
            ),
          ),
          if (footer != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 6, 14, 0),
              child: Text(
                footer!,
                style: const TextStyle(color: IOS.gray, fontSize: 12, height: 1.4),
              ),
            ),
        ],
      ),
    );
  }

  List<Widget> _separated(List<Widget> items) {
    final out = <Widget>[];
    for (int i = 0; i < items.length; i++) {
      out.add(items[i]);
      if (i != items.length - 1) {
        out.add(const Divider(height: 0.5, color: IOS.separator));
      }
    }
    return out;
  }
}

/// === 通用 List Row ===
class IOSRow extends StatelessWidget {
  final IconData? leadingIcon;
  final List<Color>? iconColors; // [start, end] gradient
  final String label;
  final String? sub;
  final Widget? trailing;
  final bool chevron;
  final VoidCallback? onTap;
  final Color? labelColor;
  const IOSRow({
    super.key,
    this.leadingIcon,
    this.iconColors,
    required this.label,
    this.sub,
    this.trailing,
    this.chevron = false,
    this.onTap,
    this.labelColor,
  });

  @override
  Widget build(BuildContext c) {
    return InkWell(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 48),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            if (leadingIcon != null) ...[
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  gradient: iconColors != null && iconColors!.length == 2
                      ? LinearGradient(
                          colors: iconColors!,
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        )
                      : null,
                  color: iconColors == null ? IOS.blue : null,
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Icon(leadingIcon, color: Colors.white, size: 16),
              ),
              const SizedBox(width: 14),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: TextStyle(
                          fontSize: 16,
                          color: labelColor ?? IOS.textPrimary)),
                  if (sub != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(sub!,
                          style: const TextStyle(
                              color: IOS.gray, fontSize: 12, height: 1.3)),
                    ),
                ],
              ),
            ),
            if (trailing != null) trailing!,
            if (chevron)
              const Padding(
                padding: EdgeInsets.only(left: 8),
                child:
                    Icon(Icons.chevron_right, color: IOS.gray2, size: 22),
              ),
          ],
        ),
      ),
    );
  }
}

/// === Form Row (左 label,右值)===
class IOSFormRow extends StatelessWidget {
  final String label;
  final String value;
  final bool placeholder;
  final bool chevron;
  final VoidCallback? onTap;
  final Color? valueColor;
  const IOSFormRow({
    super.key,
    required this.label,
    required this.value,
    this.placeholder = false,
    this.chevron = false,
    this.onTap,
    this.valueColor,
  });

  @override
  Widget build(BuildContext c) {
    return InkWell(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 48),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Text(label,
                style: const TextStyle(fontSize: 15, color: IOS.textPrimary)),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                value,
                textAlign: TextAlign.right,
                overflow: TextOverflow.ellipsis,
                style: IOS.monoSize(
                  16,
                  color: valueColor ?? (placeholder ? IOS.gray2 : IOS.blue),
                  weight: FontWeight.w400,
                ),
              ),
            ),
            if (chevron)
              const Padding(
                padding: EdgeInsets.only(left: 4),
                child: Icon(Icons.chevron_right, color: IOS.gray2, size: 18),
              ),
          ],
        ),
      ),
    );
  }
}

/// === 风险/状态 Badge ===
enum RiskTag { veryLow, low, medium, high }

class IOSBadge extends StatelessWidget {
  final RiskTag risk;
  final String text;
  const IOSBadge({super.key, required this.risk, required this.text});

  @override
  Widget build(BuildContext c) {
    final (bg, fg) = switch (risk) {
      RiskTag.veryLow =>
        (IOS.blue.withValues(alpha: 0.14), const Color(0xFF0051D5)),
      RiskTag.low => (IOS.green.withValues(alpha: 0.16), const Color(0xFF248A3D)),
      RiskTag.medium =>
        (IOS.orange.withValues(alpha: 0.16), const Color(0xFFC93400)),
      RiskTag.high => (IOS.red.withValues(alpha: 0.16), const Color(0xFFC91D14)),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(text,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: fg,
            letterSpacing: 0.3,
          )),
    );
  }
}

/// 小标签胶囊 (浅底圆角, 用于 "估算" 等次要标记)
class _SoftTag extends StatelessWidget {
  final String text;
  const _SoftTag(this.text);
  @override
  Widget build(BuildContext c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(
          color: IOS.orange.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(IOS.radTag),
        ),
        child: Text(text,
            style: const TextStyle(
                fontSize: 10, fontWeight: FontWeight.w600, color: IOS.orange)),
      );
}

/// === 渠道排名行 (预测页用) ===
class ForecastRankRow extends StatelessWidget {
  final int rank;
  final String channelName;
  final String meta;
  final RiskTag risk;
  final String riskLabel;
  final String cny;
  final String pct;
  final bool isBest;
  final bool estimated;
  final VoidCallback? onTap;
  const ForecastRankRow({
    super.key,
    required this.rank,
    required this.channelName,
    required this.meta,
    required this.risk,
    required this.riskLabel,
    required this.cny,
    required this.pct,
    this.isBest = false,
    this.estimated = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext c) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                gradient: isBest
                    ? const LinearGradient(
                        colors: [IOS.coral, IOS.coral2],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      )
                    : null,
                color: isBest ? null : IOS.peach,
                shape: BoxShape.circle,
                boxShadow: isBest
                    ? [
                        BoxShadow(
                          color: IOS.coral.withValues(alpha: 0.4),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        )
                      ]
                    : null,
              ),
              alignment: Alignment.center,
              child: Text(
                rank.toString().padLeft(2, '0'),
                style: IOS.monoSize(
                  12,
                  weight: FontWeight.w800,
                  color: isBest ? Colors.white : IOS.coral,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 5,
                    runSpacing: 2,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(channelName,
                          style: const TextStyle(
                              fontSize: 15,
                              color: IOS.textPrimary,
                              fontWeight: FontWeight.w500)),
                      IOSBadge(risk: risk, text: riskLabel),
                      if (estimated) const _SoftTag('估算'),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(meta,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: IOS.monoSize(10, color: IOS.textTertiary)
                          .copyWith(height: 1.5)),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(cny,
                    style: IOS.monoSize(17,
                        weight: FontWeight.w600, color: IOS.textPrimary)),
                const SizedBox(height: 2),
                Text(
                  pct,
                  style: IOS.monoSize(
                    11,
                    weight: isBest ? FontWeight.w700 : FontWeight.w400,
                    color: isBest
                        ? IOS.green
                        : (pct.startsWith('-') || pct.startsWith('−')
                            ? IOS.red
                            : IOS.gray),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// === Section Header (List 外的小灰字) ===
class IOSSectionHeader extends StatelessWidget {
  final String text;
  const IOSSectionHeader(this.text, {super.key});
  @override
  Widget build(BuildContext c) => Padding(
        padding: const EdgeInsets.fromLTRB(30, 0, 14, 6),
        child: Text(text.toUpperCase(),
            style: const TextStyle(
              color: IOS.gray3,
              fontSize: 13,
              letterSpacing: 0.3,
              fontWeight: FontWeight.w500,
            )),
      );
}

/// === 月份 sticky 标签 ===
class MonthHeader extends StatelessWidget {
  final String text;
  const MonthHeader(this.text, {super.key});
  @override
  Widget build(BuildContext c) => Container(
        color: IOS.grayBg,
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
        child: Text(text.toUpperCase(),
            style: const TextStyle(
              color: IOS.gray3,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            )),
      );
}

/// === 渠道彩色图标(38x38 圆角 10) ===
class ChannelIcon extends StatelessWidget {
  final String channel;
  const ChannelIcon(this.channel, {super.key});

  @override
  Widget build(BuildContext c) {
    final (icon, c1, c2) = _meta(channel);
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [c1, c2],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(10),
      ),
      alignment: Alignment.center,
      child: Text(icon, style: const TextStyle(fontSize: 18)),
    );
  }

  static (String, Color, Color) _meta(String channel) {
    if (channel.contains('熊猫')) return ('🐼', IOS.orange, const Color(0xFFFF6B00));
    if (channel.contains('OKX')) return ('⚫', const Color(0xFF2C2C2E), const Color(0xFF1A1A1C));
    if (channel.contains('Binance')) return ('💎', IOS.yellow, const Color(0xFFB58000));
    if (channel.contains('Visa')) return ('💳', IOS.indigo, IOS.violet);
    if (channel.contains('Wise')) return ('🌐', IOS.green, const Color(0xFF00A86B));
    if (channel.contains('中国银行') || channel.contains('中行'))
      return ('🏦', IOS.red, const Color(0xFFC93400));
    if (channel.contains('JRF')) return ('🎴', IOS.violet, IOS.indigo);
    return ('💴', IOS.gray, const Color(0xFF636366));
  }
}

/// === 复制行(指南页 ツツジ支店 等)===
class IOSCopyRow extends StatelessWidget {
  final String keyText;
  final String valueText;
  const IOSCopyRow({super.key, required this.keyText, required this.valueText});

  @override
  Widget build(BuildContext c) {
    return InkWell(
      onTap: () async {
        await Clipboard.setData(ClipboardData(text: valueText));
        if (c.mounted) {
          ScaffoldMessenger.of(c).showSnackBar(
            SnackBar(
              content: Text('已复制 $keyText: $valueText'),
              duration: const Duration(seconds: 1),
            ),
          );
        }
      },
      child: Container(
        margin: const EdgeInsets.only(top: 8, left: 32),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: IOS.blue.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Text(keyText,
                style: IOS.monoSize(12, color: IOS.gray)),
            const Spacer(),
            Flexible(
              child: Text(valueText,
                  textAlign: TextAlign.right,
                  style: IOS.monoSize(
                    12,
                    color: IOS.blue,
                    weight: FontWeight.w600,
                  )),
            ),
          ],
        ),
      ),
    );
  }
}

/// === 警告 banner (红 / 黄)===
class IOSWarning extends StatelessWidget {
  final String text;
  final bool danger;
  const IOSWarning({super.key, required this.text, this.danger = false});

  @override
  Widget build(BuildContext c) {
    final (bg, brd, fg) = danger
        ? (IOS.red.withValues(alpha: 0.08), IOS.red, const Color(0xFFC91D14))
        : (IOS.orange.withValues(alpha: 0.08), IOS.orange, const Color(0xFFC93400));
    return Container(
      margin: const EdgeInsets.only(top: 8, left: 32),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: bg,
        border: Border(left: BorderSide(color: brd, width: 3)),
        borderRadius: const BorderRadius.only(
          topRight: Radius.circular(6),
          bottomRight: Radius.circular(6),
        ),
      ),
      child: Text(text,
          style: TextStyle(color: fg, fontSize: 11, height: 1.4)),
    );
  }
}

/// === 步骤卡 (Guide page) ===
class IOSStepCard extends StatelessWidget {
  final int num;
  final String title;
  final String body;
  final List<Widget> extras;
  const IOSStepCard({
    super.key,
    required this.num,
    required this.title,
    required this.body,
    this.extras = const [],
  });

  @override
  Widget build(BuildContext c) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
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
            children: [
              Container(
                width: 22,
                height: 22,
                decoration: const BoxDecoration(
                    color: IOS.blue, shape: BoxShape.circle),
                alignment: Alignment.center,
                child: Text('$num',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w700)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(title,
                    style: const TextStyle(
                      color: IOS.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    )),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.only(left: 32),
            child: Text(body,
                style: const TextStyle(
                  color: IOS.textSecondary,
                  fontSize: 13,
                  height: 1.5,
                )),
          ),
          ...extras,
        ],
      ),
    );
  }
}

/// === KPI 4 卡 (统计页) ===
class IOSKpiCard extends StatelessWidget {
  final String header;
  final String value;
  final String sub;
  final Color? valueColor;
  final String? arrow; // ▲ / ▼
  final Color? arrowColor;
  const IOSKpiCard({
    super.key,
    required this.header,
    required this.value,
    required this.sub,
    this.valueColor,
    this.arrow,
    this.arrowColor,
  });

  @override
  Widget build(BuildContext c) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(IOS.radCard),
        border: Border.all(color: IOS.separator, width: 0.5),
        boxShadow: IOS.softShadow,
      ),
      child: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(header.toUpperCase(),
                  style: const TextStyle(
                    color: IOS.gray,
                    fontSize: 11,
                    letterSpacing: 0.5,
                    fontWeight: FontWeight.w500,
                  )),
              const SizedBox(height: 4),
              Text(value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: value.length > 10 ? 18 : 24,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.8,
                    color: valueColor ?? IOS.textPrimary,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  )),
              const SizedBox(height: 2),
              Text(sub,
                  style: IOS.monoSize(11, color: IOS.gray)),
            ],
          ),
          if (arrow != null)
            Positioned(
              top: 0,
              right: 0,
              child: Text(arrow!,
                  style: TextStyle(
                      color: arrowColor ?? IOS.green, fontSize: 11)),
            ),
        ],
      ),
    );
  }
}

/// === 柱状图卡 (统计页) ===
class IOSBarChart extends StatelessWidget {
  final String title;
  final String? sub;
  final String? totalRight;
  final Color? totalColor;
  final List<BarItem> bars;
  const IOSBarChart({
    super.key,
    required this.title,
    this.sub,
    this.totalRight,
    this.totalColor,
    required this.bars,
  });

  @override
  Widget build(BuildContext c) {
    final maxV = bars.map((b) => b.value.abs()).fold<double>(0,
        (m, v) => v > m ? v : m).clamp(1, double.infinity);
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 14),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
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
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Text(title,
                    style: const TextStyle(
                      color: IOS.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    )),
              ),
              if (totalRight != null)
                Text(totalRight!,
                    style: IOS.monoSize(16,
                        weight: FontWeight.w700,
                        color: totalColor ?? IOS.blue)),
            ],
          ),
          if (sub != null)
            Padding(
              padding: const EdgeInsets.only(top: 2, bottom: 8),
              child: Text(sub!,
                  style: const TextStyle(color: IOS.gray, fontSize: 11)),
            )
          else
            const SizedBox(height: 12),
          ...bars.map((b) => _barRow(b, maxV.toDouble())),
        ],
      ),
    );
  }

  Widget _barRow(BarItem b, double maxV) {
    final pct = (b.value.abs() / maxV).clamp(0.0, 1.0);
    final isRed = b.value < 0 || b.color == BarColor.red;
    final isGreen = b.color == BarColor.green;
    final colors = isRed
        ? const [IOS.red, Color(0xFFC93400)]
        : isGreen
            ? const [IOS.green, Color(0xFF00A86B)]
            : const [IOS.blue, IOS.blueDark];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 30,
            child: Text(b.label,
                style: IOS.monoSize(12, color: IOS.gray)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Container(
              height: 16,
              decoration: BoxDecoration(
                color: IOS.peach,
                borderRadius: BorderRadius.circular(8),
              ),
              child: FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: pct,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: colors),
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 70,
            child: Text(
              b.valueText,
              textAlign: TextAlign.right,
              style: IOS.monoSize(
                12,
                weight: FontWeight.w600,
                color: isRed ? IOS.red : (isGreen ? IOS.green : IOS.textPrimary),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class BarItem {
  final String label;
  final double value;
  final String valueText;
  final BarColor color;
  const BarItem(this.label, this.value, this.valueText,
      [this.color = BarColor.blue]);
}

enum BarColor { blue, red, green }

/// === 主按钮 ===
class IOSButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;
  final bool danger;
  const IOSButton(
      {super.key, required this.text, this.onPressed, this.danger = false});

  @override
  Widget build(BuildContext c) {
    final enabled = onPressed != null;
    return Opacity(
      opacity: enabled ? 1.0 : 0.4, // disabled 态: 降透明度 + 不响应
      child: Pressable(
        onTap: onPressed,
        haptic: true,
        pressedOpacity: 0.85,
        pressedScale: 0.98, // 主按钮轻微回弹, 增强"按下"实感
        child: Container(
          margin: const EdgeInsets.fromLTRB(16, 16, 16, 16),
          padding: const EdgeInsets.symmetric(vertical: 15),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: danger
                  ? const [IOS.red, Color(0xFFD63A34)]
                  : const [IOS.coral, IOS.coral2],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(IOS.radCard),
            boxShadow: [
              BoxShadow(
                color: (danger ? IOS.red : IOS.coral).withValues(alpha: 0.32),
                blurRadius: 22,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          alignment: Alignment.center,
          child: Text(text,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              )),
        ),
      ),
    );
  }
}

/// === 段控件 (指南渠道切换) ===
class IOSSegmentedControl extends StatelessWidget {
  final List<String> items;
  final int active;
  final ValueChanged<int> onChange;
  const IOSSegmentedControl({
    super.key,
    required this.items,
    required this.active,
    required this.onChange,
  });

  @override
  Widget build(BuildContext c) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 14),
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: const Color(0xFFF1E7D9),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        children: List.generate(items.length, (i) {
          final isActive = i == active;
          return Expanded(
            child: Pressable(
              onTap: () => onChange(i),
              haptic: true,
              pressedOpacity: 0.6,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOut,
                padding: const EdgeInsets.symmetric(vertical: 6),
                decoration: BoxDecoration(
                  color: isActive ? Colors.white : Colors.transparent,
                  borderRadius: BorderRadius.circular(7),
                  boxShadow: isActive
                      ? [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.06),
                            blurRadius: 3,
                            offset: const Offset(0, 1),
                          ),
                        ]
                      : null,
                ),
                alignment: Alignment.center,
                child: AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 200),
                  style: TextStyle(
                    color: IOS.textPrimary,
                    fontSize: 13,
                    fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                  ),
                  child: Text(items[i]),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

/// === 进度条(额度) ===
class IOSQuotaBar extends StatelessWidget {
  final double pct;
  final String leftText;
  final String rightText;
  final Color color;
  const IOSQuotaBar({
    super.key,
    required this.pct,
    required this.leftText,
    required this.rightText,
    this.color = IOS.green,
  });

  @override
  Widget build(BuildContext c) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        children: [
          Row(
            children: [
              Text(leftText,
                  style: const TextStyle(fontSize: 12, color: IOS.gray)),
              const Spacer(),
              Text(rightText,
                  style: IOS.monoSize(12, color: IOS.textPrimary)),
            ],
          ),
          const SizedBox(height: 6),
          Container(
            height: 6,
            decoration: BoxDecoration(
              color: IOS.peach,
              borderRadius: BorderRadius.circular(3),
            ),
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: pct.clamp(0.0, 1.0),
              child: Container(
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
