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
    this.uppercase = true,
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
    this.align,
    this.maxLines = 1,
  });

  final String value;
  final double? fontSize;
  final Color? color;
  final TextAlign? align;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final colors = context.kinetic;
    return Text(
      value,
      textAlign: align,
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
      style: AppTheme.numberStyle(colors).copyWith(
        fontSize: fontSize ?? 64,
        color: color ?? colors.foreground,
      ),
    );
  }
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
    _scale = Tween<double>(begin: 1, end: widget.scale).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );
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
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
      BrutalistButtonTone.danger => colors.loss,
      BrutalistButtonTone.muted => colors.muted,
      BrutalistButtonTone.outline => colors.background,
    };
    final foreground = switch (tone) {
      BrutalistButtonTone.primary => colors.accentForeground,
      BrutalistButtonTone.danger => colors.accentForeground,
      BrutalistButtonTone.muted => colors.foreground,
      BrutalistButtonTone.outline => colors.foreground,
    };
    final child = AnimatedContainer(
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : AppTheme.fast,
      width: expand ? double.infinity : null,
      padding: padding,
      decoration: BoxDecoration(
        color: disabled ? colors.muted : background,
        borderRadius: BorderRadius.zero,
        border: Border.all(
          color: disabled ? colors.border : colors.foreground,
          width: 2,
        ),
      ),
      child: KineticText(
        label,
        align: TextAlign.center,
        style: AppTheme.labelStyle(colors).copyWith(
          color: disabled ? colors.mutedForeground : foreground,
          letterSpacing: -0.2,
          fontSize: 14,
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
    this.padding = const EdgeInsets.all(16),
    this.background,
    this.borderWidth = 2,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? background;
  final double borderWidth;

  @override
  Widget build(BuildContext context) {
    final colors = context.kinetic;
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: background ?? colors.background,
        borderRadius: BorderRadius.zero,
        border: Border.all(color: colors.border, width: borderWidth),
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
    this.valueFontSize = 28,
    this.valueMaxLines = 1,
  });

  final String label;
  final String value;
  final String? detail;
  final Color? valueColor;
  final double valueFontSize;
  final int valueMaxLines;

  @override
  Widget build(BuildContext context) {
    final colors = context.kinetic;
    return LedgerFrame(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          KineticText(label, style: AppTheme.labelStyle(colors)),
          const SizedBox(height: 10),
          KineticNumber(
            value,
            fontSize: valueFontSize,
            color: valueColor ?? colors.foreground,
            maxLines: valueMaxLines,
          ),
          if (detail != null) ...[
            const SizedBox(height: 8),
            KineticText(
              detail!,
              muted: true,
              style: AppTheme.bodyStyle(colors).copyWith(fontSize: 13),
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
    final foreground = selected ? colors.accentForeground : colors.foreground;
    return PressableScale(
      onTap: onTap,
      scale: 0.98,
      child: AnimatedContainer(
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : AppTheme.fast,
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
        decoration: BoxDecoration(
          color: selected ? colors.accent : colors.background,
          borderRadius: BorderRadius.zero,
          border: Border.all(
            color: selected ? colors.accent : colors.border,
            width: 2,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            KineticText(
              label,
              style: AppTheme.labelStyle(colors).copyWith(
                color: foreground,
                letterSpacing: -0.1,
              ),
            ),
            if (detail != null) ...[
              const SizedBox(height: 5),
              KineticText(
                detail!,
                style: AppTheme.bodyStyle(colors).copyWith(
                  color: foreground,
                  fontSize: 12,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class TickerTape extends StatefulWidget {
  const TickerTape({
    super.key,
    required this.items,
    this.height = 44,
  });

  final List<String> items;
  final double height;

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
            horizontal: BorderSide(color: colors.foreground, width: 2),
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
                        style: AppTheme.labelStyle(colors).copyWith(
                          color: colors.accentForeground,
                          fontSize: 14,
                          letterSpacing: -0.1,
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
          top: BorderSide(color: colors.foreground, width: 2),
          bottom: BorderSide(color: colors.foreground, width: 2),
        ),
      ),
      child: KineticText(
        label,
        style: AppTheme.labelStyle(colors).copyWith(
          color: colors.accentForeground,
          fontSize: 13,
        ),
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
    return TextFormField(
      key: fieldKey,
      controller: controller,
      keyboardType: keyboardType,
      validator: validator,
      minLines: minLines,
      maxLines: maxLines,
      cursorColor: colors.accent,
      style: (hero ? AppTheme.numberStyle(colors) : AppTheme.bodyStyle(colors))
          .copyWith(fontSize: hero ? 44 : 18),
      decoration: InputDecoration(
        labelText: label.toUpperCase(),
        contentPadding: EdgeInsets.only(bottom: hero ? 18 : 12),
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
