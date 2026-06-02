import 'package:flutter/material.dart';

@immutable
class KineticColors extends ThemeExtension<KineticColors> {
  const KineticColors({
    required this.background,
    required this.foreground,
    required this.muted,
    required this.mutedForeground,
    required this.accent,
    required this.accentForeground,
    required this.border,
    required this.profit,
    required this.loss,
  });

  final Color background;
  final Color foreground;
  final Color muted;
  final Color mutedForeground;
  final Color accent;
  final Color accentForeground;
  final Color border;
  final Color profit;
  final Color loss;

  @override
  KineticColors copyWith({
    Color? background,
    Color? foreground,
    Color? muted,
    Color? mutedForeground,
    Color? accent,
    Color? accentForeground,
    Color? border,
    Color? profit,
    Color? loss,
  }) {
    return KineticColors(
      background: background ?? this.background,
      foreground: foreground ?? this.foreground,
      muted: muted ?? this.muted,
      mutedForeground: mutedForeground ?? this.mutedForeground,
      accent: accent ?? this.accent,
      accentForeground: accentForeground ?? this.accentForeground,
      border: border ?? this.border,
      profit: profit ?? this.profit,
      loss: loss ?? this.loss,
    );
  }

  @override
  KineticColors lerp(ThemeExtension<KineticColors>? other, double t) {
    if (other is! KineticColors) return this;
    return KineticColors(
      background: Color.lerp(background, other.background, t)!,
      foreground: Color.lerp(foreground, other.foreground, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
      mutedForeground: Color.lerp(mutedForeground, other.mutedForeground, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      accentForeground: Color.lerp(
        accentForeground,
        other.accentForeground,
        t,
      )!,
      border: Color.lerp(border, other.border, t)!,
      profit: Color.lerp(profit, other.profit, t)!,
      loss: Color.lerp(loss, other.loss, t)!,
    );
  }
}

class AppTheme {
  AppTheme._();

  static const navy = Color(0xFF0A2447);
  static const gold = Color(0xFFF1AB3C);
  static const lightGold = Color(0xFFF7D398);
  static const white = Color(0xFFFCFCFC);
  static const cream = Color(0xFFE7E3DB);
  static const deepShadow = Color(0xFF02163B);

  static const fontFamily = 'SpaceGrotesk';
  static const ledgerFontFamily = 'Inter';
  static const radius = BorderRadius.all(Radius.circular(24));
  static const tightRadius = BorderRadius.all(Radius.circular(16));
  static const pillRadius = BorderRadius.all(Radius.circular(999));
  static const thickBorderWidth = 1.4;
  static const hairlineWidth = 1.0;
  static const fast = Duration(milliseconds: 150);

  static const darkColors = KineticColors(
    background: navy,
    foreground: white,
    muted: Color(0xFF102D55),
    mutedForeground: cream,
    accent: gold,
    accentForeground: deepShadow,
    border: Color(0x99F7D398),
    profit: lightGold,
    loss: cream,
  );

  static const lightColors = KineticColors(
    background: white,
    foreground: deepShadow,
    muted: cream,
    mutedForeground: navy,
    accent: gold,
    accentForeground: deepShadow,
    border: lightGold,
    profit: navy,
    loss: deepShadow,
  );

  static ThemeData get dark => _build(Brightness.dark, darkColors);
  static ThemeData get light => _build(Brightness.light, lightColors);

  static ThemeData _build(Brightness brightness, KineticColors colors) {
    final isDark = brightness == Brightness.dark;
    final textTheme = _textTheme(colors);
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      fontFamily: fontFamily,
      scaffoldBackgroundColor: colors.background,
      canvasColor: colors.background,
      cardColor: colors.muted,
      dividerColor: colors.border,
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
      hoverColor: colors.accent.withValues(alpha: 0.12),
      colorScheme: ColorScheme(
        brightness: brightness,
        primary: colors.accent,
        onPrimary: colors.accentForeground,
        secondary: lightGold,
        onSecondary: deepShadow,
        error: colors.loss,
        onError: colors.accentForeground,
        surface: colors.background,
        onSurface: colors.foreground,
      ),
      extensions: const <ThemeExtension<dynamic>>[darkColors],
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: Colors.transparent,
        foregroundColor: colors.foreground,
        centerTitle: false,
        titleTextStyle: textTheme.headlineSmall,
        shape: Border(bottom: BorderSide(color: colors.border, width: 1)),
      ),
      dialogTheme: DialogThemeData(
        elevation: 18,
        backgroundColor: colors.muted,
        shape: const RoundedRectangleBorder(borderRadius: radius),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: colors.muted,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(color: colors.border, width: thickBorderWidth),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        elevation: 0,
        backgroundColor: colors.accent,
        contentTextStyle: labelStyle(
          colors,
        ).copyWith(color: colors.accentForeground),
        shape: const RoundedRectangleBorder(borderRadius: radius),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colors.background.withValues(alpha: isDark ? 0.58 : 0.72),
        border: OutlineInputBorder(
          borderRadius: tightRadius,
          borderSide: BorderSide(color: colors.border, width: thickBorderWidth),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: tightRadius,
          borderSide: BorderSide(color: colors.border, width: thickBorderWidth),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: tightRadius,
          borderSide: BorderSide(color: colors.accent, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: tightRadius,
          borderSide: BorderSide(color: colors.loss, width: 2),
        ),
        labelStyle: labelStyle(colors),
        floatingLabelStyle: labelStyle(colors).copyWith(color: colors.accent),
        errorStyle: TextStyle(
          color: colors.loss,
          fontFamily: ledgerFontFamily,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
      datePickerTheme: DatePickerThemeData(
        elevation: 0,
        backgroundColor: colors.muted,
        headerBackgroundColor: colors.accent,
        headerForegroundColor: colors.accentForeground,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(color: colors.border, width: thickBorderWidth),
        ),
      ),
      dropdownMenuTheme: DropdownMenuThemeData(
        textStyle: bodyStyle(colors),
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(
            borderRadius: tightRadius,
            borderSide: BorderSide(
              color: colors.border,
              width: thickBorderWidth,
            ),
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: ButtonStyle(
          elevation: const WidgetStatePropertyAll(0),
          shape: const WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: radius),
          ),
          backgroundColor: WidgetStatePropertyAll(colors.accent),
          foregroundColor: WidgetStatePropertyAll(colors.accentForeground),
          textStyle: WidgetStatePropertyAll(labelStyle(colors)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: ButtonStyle(
          elevation: const WidgetStatePropertyAll(0),
          shape: const WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: radius),
          ),
          foregroundColor: WidgetStatePropertyAll(
            isDark ? colors.accent : colors.foreground,
          ),
          textStyle: WidgetStatePropertyAll(labelStyle(colors)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: ButtonStyle(
          elevation: const WidgetStatePropertyAll(0),
          shape: const WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: radius),
          ),
          side: WidgetStatePropertyAll(
            BorderSide(color: colors.border, width: thickBorderWidth),
          ),
          foregroundColor: WidgetStatePropertyAll(colors.foreground),
          textStyle: WidgetStatePropertyAll(labelStyle(colors)),
        ),
      ),
    ).copyWith(extensions: <ThemeExtension<dynamic>>[colors]);
  }

  static TextTheme _textTheme(KineticColors colors) {
    return TextTheme(
      displayLarge: displayStyle(colors).copyWith(fontSize: 80),
      displayMedium: displayStyle(colors).copyWith(fontSize: 56),
      headlineLarge: displayStyle(colors).copyWith(fontSize: 44),
      headlineMedium: displayStyle(colors).copyWith(fontSize: 34),
      headlineSmall: titleStyle(colors).copyWith(fontSize: 28),
      titleLarge: titleStyle(colors).copyWith(fontSize: 24),
      titleMedium: titleStyle(colors).copyWith(fontSize: 20),
      bodyLarge: bodyStyle(colors).copyWith(fontSize: 18),
      bodyMedium: bodyStyle(colors).copyWith(fontSize: 16),
      bodySmall: labelStyle(colors),
      labelLarge: labelStyle(colors).copyWith(fontSize: 14),
      labelMedium: labelStyle(colors).copyWith(fontSize: 12),
      labelSmall: labelStyle(colors).copyWith(fontSize: 11),
    );
  }

  static TextStyle displayStyle(KineticColors colors) {
    return TextStyle(
      color: colors.foreground,
      fontFamily: fontFamily,
      fontWeight: FontWeight.w800,
      height: 0.95,
      letterSpacing: -1.1,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
  }

  static TextStyle numberStyle(KineticColors colors) {
    return displayStyle(colors).copyWith(
      fontWeight: FontWeight.w900,
      letterSpacing: -2.5,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
  }

  static TextStyle titleStyle(KineticColors colors) {
    return TextStyle(
      color: colors.foreground,
      fontFamily: fontFamily,
      fontWeight: FontWeight.w800,
      height: 1.02,
      letterSpacing: -0.55,
    );
  }

  static TextStyle bodyStyle(KineticColors colors) {
    return TextStyle(
      color: colors.foreground,
      fontFamily: ledgerFontFamily,
      fontWeight: FontWeight.w500,
      height: 1.22,
      letterSpacing: -0.18,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
  }

  static TextStyle labelStyle(KineticColors colors) {
    return TextStyle(
      color: colors.mutedForeground,
      fontFamily: fontFamily,
      fontWeight: FontWeight.w800,
      fontSize: 12,
      height: 1,
      letterSpacing: 1.05,
    );
  }

  static BoxDecoration brutalBox(
    KineticColors colors, {
    Color? color,
    double width = thickBorderWidth,
  }) {
    return BoxDecoration(
      color: color ?? colors.background,
      borderRadius: radius,
      border: Border.all(color: colors.border, width: width),
      boxShadow: softShadow(colors),
    );
  }

  static BoxDecoration invertedBox(KineticColors colors) {
    return BoxDecoration(
      color: colors.accent,
      borderRadius: radius,
      border: Border.all(color: colors.accent, width: thickBorderWidth),
      boxShadow: glowShadow(colors),
    );
  }

  static BoxDecoration brandBackground(KineticColors colors) {
    final isLight = colors.background == white;
    return BoxDecoration(
      color: colors.background,
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: isLight
            ? [white, cream, lightGold.withValues(alpha: 0.84)]
            : [
                colors.background,
                deepShadow,
                colors.background.withValues(alpha: 0.96),
              ],
      ),
    );
  }

  static BoxDecoration heroSurface(KineticColors colors) {
    return BoxDecoration(
      color: colors.background,
      borderRadius: radius,
      border: Border.all(
        color: colors.border.withValues(alpha: 0.9),
        width: thickBorderWidth,
      ),
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [colors.background, deepShadow, colors.background],
      ),
      boxShadow: glowShadow(colors),
    );
  }

  static List<BoxShadow> softShadow(KineticColors colors) {
    return [
      BoxShadow(
        color: deepShadow.withValues(alpha: 0.34),
        offset: const Offset(0, 14),
        blurRadius: 28,
      ),
    ];
  }

  static List<BoxShadow> glowShadow(KineticColors colors) {
    return [
      BoxShadow(
        color: colors.accent.withValues(alpha: 0.20),
        offset: const Offset(0, 18),
        blurRadius: 34,
      ),
      BoxShadow(
        color: deepShadow.withValues(alpha: 0.42),
        offset: const Offset(0, 12),
        blurRadius: 24,
      ),
    ];
  }
}

extension KineticThemeContext on BuildContext {
  KineticColors get kinetic {
    return Theme.of(this).extension<KineticColors>() ?? AppTheme.darkColors;
  }

  bool get isWide {
    return MediaQuery.sizeOf(this).width >= 900;
  }
}
