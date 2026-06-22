import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

class KineticText extends StatelessWidget {
  const KineticText(
    this.text, {
    super.key,
    this.style,
    this.align,
    this.maxLines,
    this.muted = false,
    this.uppercase = false,
  });

  final String text;
  final TextStyle? style;
  final TextAlign? align;
  final int? maxLines;
  final bool muted;
  final bool uppercase;

  @override
  Widget build(BuildContext context) {
    final colors = context.kinetic;
    final base = style ?? Theme.of(context).textTheme.bodyLarge!;
    return Text(
      uppercase ? text.toUpperCase() : text,
      textAlign: align,
      maxLines: maxLines,
      overflow: maxLines == null ? null : TextOverflow.ellipsis,
      style: base.copyWith(
        color: muted ? colors.mutedForeground : base.color ?? colors.foreground,
      ),
    );
  }
}

class KineticNumber extends StatelessWidget {
  const KineticNumber(
    this.value, {
    super.key,
    this.fontSize,
    this.color,
    this.currency,
    this.align,
    this.maxLines = 1,
  });

  final String value;
  final double? fontSize;
  final Color? color;
  final String? currency;
  final TextAlign? align;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final colors = context.kinetic;
    final effectiveFontSize = fontSize ?? 48;
    final textColor = color ?? colors.foreground;
    final normalizedCurrency = currency?.trim().toUpperCase();
    final displayValue = _numberTextWithoutCurrency(value, normalizedCurrency);
    final text = Text(
      displayValue,
      textAlign: align,
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
      style: AppTheme.numberStyle(
        colors,
      ).copyWith(fontSize: effectiveFontSize, color: textColor),
    );
    if (normalizedCurrency == null || normalizedCurrency.isEmpty) {
      return text;
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final markSize = (effectiveFontSize * 0.70).clamp(18.0, 48.0);
        final gap = (effectiveFontSize * 0.08).clamp(3.0, 8.0);
        final maxTextWidth = constraints.maxWidth.isFinite
            ? math.max(0.0, constraints.maxWidth - markSize - gap)
            : double.infinity;
        return Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            CurrencyLogoMark(
              currency: normalizedCurrency,
              selected: false,
              size: markSize,
              iconColor: textColor,
              raw: true,
            ),
            SizedBox(width: gap),
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxTextWidth),
              child: text,
            ),
          ],
        );
      },
    );
  }
}

String _numberTextWithoutCurrency(String value, String? currency) {
  if (currency == null || currency.isEmpty) return value;
  final sign = value.startsWith('+') || value.startsWith('-')
      ? value.substring(0, 1)
      : '';
  var text = sign.isEmpty ? value.trim() : value.substring(1).trim();

  if (currency == 'USD' && text.startsWith(r'$')) {
    text = text.substring(1).trim();
  }

  if (text.toUpperCase().startsWith('$currency ')) {
    text = text.substring(currency.length).trim();
  }

  if (text.toUpperCase().endsWith(' $currency')) {
    text = text.substring(0, text.length - currency.length).trim();
  }

  return '$sign$text';
}

class PressableScale extends StatefulWidget {
  const PressableScale({
    super.key,
    required this.child,
    this.onTap,
    this.scale = 0.96,
  });

  final Widget child;
  final VoidCallback? onTap;
  final double scale;

  @override
  State<PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<PressableScale>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: AppTheme.fast);
    _scale = Tween<double>(
      begin: 1,
      end: widget.scale,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final disableAnimations = MediaQuery.disableAnimationsOf(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      onTapDown: widget.onTap == null || disableAnimations
          ? null
          : (_) => _controller.forward(),
      onTapCancel: widget.onTap == null || disableAnimations
          ? null
          : () => _controller.reverse(),
      onTapUp: widget.onTap == null || disableAnimations
          ? null
          : (_) => _controller.reverse(),
      child: AnimatedBuilder(
        animation: _scale,
        child: widget.child,
        builder: (context, child) => Transform.scale(
          scale: disableAnimations ? 1 : _scale.value,
          child: child,
        ),
      ),
    );
  }
}

enum BrutalistButtonTone { primary, outline, danger, muted }

class BrutalistButton extends StatelessWidget {
  const BrutalistButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.tone = BrutalistButtonTone.outline,
    this.expand = false,
    this.padding = const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
  });

  final String label;
  final VoidCallback? onPressed;
  final BrutalistButtonTone tone;
  final bool expand;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final colors = context.kinetic;
    final disabled = onPressed == null;
    final background = switch (tone) {
      BrutalistButtonTone.primary => colors.accent,
      BrutalistButtonTone.danger => colors.loss.withValues(alpha: 0.16),
      BrutalistButtonTone.muted => colors.muted,
      BrutalistButtonTone.outline => Colors.transparent,
    };
    final foreground = switch (tone) {
      BrutalistButtonTone.primary => colors.accentForeground,
      BrutalistButtonTone.danger => colors.loss,
      BrutalistButtonTone.muted => colors.foreground,
      BrutalistButtonTone.outline => colors.mutedForeground,
    };
    final child = AnimatedContainer(
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : AppTheme.fast,
      width: expand ? double.infinity : null,
      padding: padding,
      decoration: BoxDecoration(
        color: disabled ? colors.muted : background,
        borderRadius: AppTheme.pillRadius,
        border: Border.all(
          color: disabled
              ? colors.border.withValues(alpha: 0.55)
              : tone == BrutalistButtonTone.primary
              ? colors.accent
              : colors.border.withValues(alpha: 0.58),
          width: AppTheme.thickBorderWidth,
        ),
      ),
      child: KineticText(
        label,
        align: TextAlign.center,
        style: AppTheme.labelStyle(colors).copyWith(
          color: disabled ? colors.mutedForeground : foreground,
          fontSize: 13,
        ),
      ),
    );
    return PressableScale(onTap: disabled ? null : onPressed, child: child);
  }
}

class LedgerFrame extends StatelessWidget {
  const LedgerFrame({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.background,
    this.borderWidth = AppTheme.thickBorderWidth,
    this.cardless = false,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? background;
  final double borderWidth;
  final bool cardless;

  @override
  Widget build(BuildContext context) {
    final colors = context.kinetic;
    if (cardless) {
      return Padding(
        padding: padding,
        child: child,
      );
    }
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: background ?? colors.muted.withValues(alpha: 0.76),
        borderRadius: AppTheme.radius,
        border: Border.all(
          color: colors.border.withValues(alpha: 0.64),
          width: borderWidth,
        ),
      ),
      child: child,
    );
  }
}

class MetricBlock extends StatelessWidget {
  const MetricBlock({
    super.key,
    required this.label,
    required this.value,
    this.detail,
    this.valueColor,
    this.currency,
    this.valueFontSize = 28,
    this.valueMaxLines = 1,
    this.cardless = false,
  });

  final String label;
  final String value;
  final String? detail;
  final Color? valueColor;
  final String? currency;
  final double valueFontSize;
  final int valueMaxLines;
  final bool cardless;

  @override
  Widget build(BuildContext context) {
    final colors = context.kinetic;
    return LedgerFrame(
      cardless: cardless,
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          KineticText(label, style: AppTheme.labelStyle(colors)),
          const SizedBox(height: 8),
          KineticNumber(
            value,
            fontSize: valueFontSize,
            color: valueColor ?? colors.foreground,
            currency: currency,
            maxLines: valueMaxLines,
          ),
          if (detail != null) ...[
            const SizedBox(height: 8),
            KineticText(
              detail!,
              muted: true,
              style: AppTheme.bodyStyle(colors).copyWith(fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }
}

class FilterBlock extends StatelessWidget {
  const FilterBlock({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.detail,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final colors = context.kinetic;

    // Premium active / inactive colors
    final background = selected
        ? colors.accent.withValues(alpha: 0.12)
        : Colors.transparent;
    final border = Colors.transparent;
    final textColor = selected
        ? colors.accent
        : colors.foreground.withValues(alpha: 0.60);
    final labelColor = selected
        ? colors.accent.withValues(alpha: 0.80)
        : colors.mutedForeground;

    final showEyebrow = detail != null;

    return PressableScale(
      onTap: onTap,
      scale: 0.97,
      child: AnimatedContainer(
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : AppTheme.fast,
        padding: EdgeInsets.symmetric(
          horizontal: showEyebrow ? 16 : 14,
          vertical: showEyebrow ? 8 : 6,
        ),
        decoration: BoxDecoration(
          color: background,
          borderRadius: AppTheme.pillRadius,
          border: Border.all(
            color: border,
            width: 1.0,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (showEyebrow) ...[
              KineticText(
                label.toUpperCase(),
                style: AppTheme.labelStyle(colors).copyWith(
                  color: labelColor,
                  fontWeight: FontWeight.w800,
                  fontSize: 9,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 3),
              KineticText(
                detail!,
                style: AppTheme.bodyStyle(colors).copyWith(
                  color: textColor,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ] else
              KineticText(
                label,
                style: AppTheme.bodyStyle(colors).copyWith(
                  color: textColor,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class CurrencyChip extends StatelessWidget {
  const CurrencyChip({
    super.key,
    required this.currency,
    required this.selected,
    required this.onTap,
    this.compact = false,
  });

  final String currency;
  final bool selected;
  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colors = context.kinetic;
    final background = selected
        ? colors.accent.withValues(alpha: 0.18)
        : Colors.transparent;
    final foreground = selected ? colors.accent : colors.mutedForeground;
    return PressableScale(
      onTap: onTap,
      scale: 0.98,
      child: AnimatedContainer(
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : AppTheme.fast,
        constraints: BoxConstraints(minHeight: compact ? 34 : 46),
        padding: EdgeInsets.fromLTRB(
          compact ? 12 : 7,
          compact ? 7 : 8,
          compact ? 12 : 11,
          compact ? 7 : 8,
        ),
        decoration: BoxDecoration(
          color: background,
          borderRadius: AppTheme.pillRadius,
          border: Border.all(
            color: selected
                ? colors.accent.withValues(alpha: 0.46)
                : Colors.transparent,
            width: AppTheme.hairlineWidth,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (!compact) ...[
              CurrencyLogoMark(currency: currency, selected: selected),
              const SizedBox(width: 7),
            ],
            KineticText(
              currency,
              uppercase: true,
              style: AppTheme.labelStyle(colors).copyWith(
                color: foreground,
                fontSize: compact ? 12 : 13,
                letterSpacing: 0,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class CurrencyLogoMark extends StatelessWidget {
  const CurrencyLogoMark({
    super.key,
    required this.currency,
    required this.selected,
    this.size = 30,
    this.iconColor,
    this.raw = false,
  });

  final String currency;
  final bool selected;
  final double size;
  final Color? iconColor;
  final bool raw;

  @override
  Widget build(BuildContext context) {
    final colors = context.kinetic;
    final asset = switch (currency) {
      'USD' => 'assets/images/currency/dollar.png',
      'EUR' => 'assets/images/currency/euro.png',
      'AED' => 'assets/images/currency/dirham.png',
      _ => null,
    };
    final foreground =
        iconColor ?? (selected ? colors.accent : colors.foreground);

    if (raw) {
      return asset == null
          ? Text(
              currency,
              textAlign: TextAlign.center,
              style: AppTheme.labelStyle(colors).copyWith(
                color: foreground,
                fontSize: size * 0.5,
                fontWeight: FontWeight.w900,
                letterSpacing: 0,
                height: 1,
              ),
            )
          : ImageIcon(
              AssetImage(asset),
              color: foreground,
              size: size,
            );
    }

    final background = selected
        ? colors.accent.withValues(alpha: 0.16)
        : colors.background.withValues(alpha: 0.24);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: background,
        shape: BoxShape.circle,
        border: Border.all(
          color: selected
              ? colors.accent.withValues(alpha: 0.32)
              : colors.border.withValues(alpha: 0.52),
          width: AppTheme.hairlineWidth,
        ),
      ),
      child: asset == null
          ? Text(
              currency,
              textAlign: TextAlign.center,
              style: AppTheme.labelStyle(colors).copyWith(
                color: foreground,
                fontSize: 9,
                fontWeight: FontWeight.w900,
                letterSpacing: 0,
                height: 1,
              ),
            )
          : ImageIcon(
              AssetImage(asset),
              color: foreground,
              size: currency == 'AED' ? size * 0.67 : size * 0.63,
            ),
    );
  }
}

class TickerTape extends StatefulWidget {
  const TickerTape({
    super.key,
    required this.items,
    this.height = 44,
    this.fontSize = 14,
  });

  final List<String> items;
  final double height;
  final double fontSize;

  @override
  State<TickerTape> createState() => _TickerTapeState();
}

class _TickerTapeState extends State<TickerTape>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 22),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.kinetic;
    final disableAnimations = MediaQuery.disableAnimationsOf(context);
    final repeated = List.generate(8, (_) => widget.items).expand((e) => e);
    return ClipRect(
      child: Container(
        height: widget.height,
        decoration: BoxDecoration(
          color: colors.accent,
          border: Border.symmetric(
            horizontal: BorderSide(
              color: colors.border,
              width: AppTheme.thickBorderWidth,
            ),
          ),
        ),
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            final offset = disableAnimations
                ? 0.0
                : -(_controller.value * 420.0);
            return Transform.translate(offset: Offset(offset, 0), child: child);
          },
          child: OverflowBox(
            alignment: Alignment.centerLeft,
            maxWidth: double.infinity,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: repeated
                  .map(
                    (item) => Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 18),
                      child: KineticText(
                        item,
                        uppercase: true,
                        style: AppTheme.labelStyle(colors).copyWith(
                          color: colors.accentForeground,
                          fontSize: widget.fontSize,
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
        ),
      ),
    );
  }
}

class StickyDateHeader extends SliverPersistentHeaderDelegate {
  StickyDateHeader({required this.label});

  final String label;

  @override
  double get minExtent => 42;

  @override
  double get maxExtent => 42;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    final colors = context.kinetic;
    return Container(
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: colors.accent,
        border: Border(
          top: BorderSide(color: colors.border, width: AppTheme.hairlineWidth),
          bottom: BorderSide(
            color: colors.border,
            width: AppTheme.hairlineWidth,
          ),
        ),
      ),
      child: KineticText(
        label,
        style: AppTheme.labelStyle(
          colors,
        ).copyWith(color: colors.accentForeground, fontSize: 13),
      ),
    );
  }

  @override
  bool shouldRebuild(covariant StickyDateHeader oldDelegate) {
    return oldDelegate.label != label;
  }
}

class KineticInput extends StatelessWidget {
  const KineticInput({
    super.key,
    this.fieldKey,
    required this.controller,
    required this.label,
    this.validator,
    this.keyboardType,
    this.minLines = 1,
    this.maxLines = 1,
    this.hero = false,
  });

  final Key? fieldKey;
  final TextEditingController controller;
  final String label;
  final String? Function(String?)? validator;
  final TextInputType? keyboardType;
  final int minLines;
  final int maxLines;
  final bool hero;

  @override
  Widget build(BuildContext context) {
    final colors = context.kinetic;
    final isMultiline = maxLines != 1;
    return TextFormField(
      key: fieldKey,
      controller: controller,
      keyboardType: keyboardType,
      textInputAction: isMultiline
          ? TextInputAction.newline
          : TextInputAction.done,
      onFieldSubmitted: isMultiline
          ? null
          : (_) => FocusScope.of(context).unfocus(),
      onTapOutside: (_) => FocusScope.of(context).unfocus(),
      validator: validator,
      minLines: minLines,
      maxLines: maxLines,
      cursorColor: colors.accent,
      style: (hero ? AppTheme.numberStyle(colors) : AppTheme.bodyStyle(colors))
          .copyWith(fontSize: hero ? 36 : 16),
      decoration: InputDecoration(
        labelText: label,
        contentPadding: EdgeInsets.symmetric(
          horizontal: 14,
          vertical: hero ? 18 : 13,
        ),
      ),
    );
  }
}

class BrutalistGrid extends StatelessWidget {
  const BrutalistGrid({
    super.key,
    required this.children,
    this.minTileWidth = 240,
    this.gap = 12,
  });

  final List<Widget> children;
  final double minTileWidth;
  final double gap;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = math.max(
          1,
          (constraints.maxWidth / minTileWidth).floor(),
        );
        final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: children
              .map((child) => SizedBox(width: width, child: child))
              .toList(),
        );
      },
    );
  }
}

class KineticDropdown<T> extends StatelessWidget {
  const KineticDropdown({
    super.key,
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
    required this.itemLabelBuilder,
  });

  final String label;
  final T value;
  final List<T> items;
  final ValueChanged<T?> onChanged;
  final String Function(T) itemLabelBuilder;

  @override
  Widget build(BuildContext context) {
    final colors = context.kinetic;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        KineticText(
          label.toUpperCase(),
          style: AppTheme.labelStyle(colors).copyWith(
            fontSize: 10,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.0,
            color: colors.mutedForeground,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          decoration: BoxDecoration(
            color: colors.foreground.withValues(alpha: 0.03),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: colors.border.withValues(alpha: 0.12),
              width: 1,
            ),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<T>(
              value: value,
              isExpanded: true,
              icon: Icon(
                Icons.keyboard_arrow_down_rounded,
                color: colors.accent,
                size: 22,
              ),
              dropdownColor: colors.background,
              borderRadius: BorderRadius.circular(10),
              style: AppTheme.bodyStyle(colors).copyWith(
                color: colors.foreground,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
              onChanged: onChanged,
              items: items.map((item) {
                return DropdownMenuItem<T>(
                  value: item,
                  child: Text(itemLabelBuilder(item)),
                );
              }).toList(),
            ),
          ),
        ),
      ],
    );
  }
}

class KineticDatePickerTile extends StatelessWidget {
  const KineticDatePickerTile({
    super.key,
    required this.label,
    required this.value,
    required this.onTap,
    this.selected = false,
  });

  final String label;
  final String value;
  final VoidCallback onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final colors = context.kinetic;
    return PressableScale(
      onTap: onTap,
      scale: 0.98,
      child: AnimatedContainer(
        duration: AppTheme.fast,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: selected
              ? colors.accent.withValues(alpha: 0.06)
              : colors.foreground.withValues(alpha: 0.01),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected
                ? colors.accent.withValues(alpha: 0.16)
                : colors.border.withValues(alpha: 0.08),
            width: 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              Icons.calendar_today_rounded,
              size: 15,
              color: selected ? colors.accent : colors.mutedForeground,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  KineticText(
                    label.toUpperCase(),
                    style: AppTheme.labelStyle(colors).copyWith(
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                      color: selected ? colors.accent : colors.mutedForeground,
                    ),
                  ),
                  const SizedBox(height: 2),
                  KineticText(
                    value,
                    style: AppTheme.bodyStyle(colors).copyWith(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: colors.foreground,
                    ),
                  ),
                ],
              ),
            ),
            if (selected)
              Icon(
                Icons.check_circle_rounded,
                size: 14,
                color: colors.accent,
              ),
          ],
        ),
      ),
    );
  }
}
