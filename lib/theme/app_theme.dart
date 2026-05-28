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
      accentForeground:
          Color.lerp(accentForeground, other.accentForeground, t)!,
      border: Color.lerp(border, other.border, t)!,
      profit: Color.lerp(profit, other.profit, t)!,
      loss: Color.lerp(loss, other.loss, t)!,
    );
  }
}

class AppTheme {
  AppTheme._();

  static const fontFamily = 'SpaceGrotesk';
  static const ledgerFontFamily = 'Inter';
  static const radius = BorderRadius.zero;
  static const thickBorderWidth = 2.0;
  static const hairlineWidth = 1.0;
  static const fast = Duration(milliseconds: 90);

  static const darkColors = KineticColors(
    background: Color(0xFF09090B),
    foreground: Color(0xFFFAFAFA),
    muted: Color(0xFF27272A),
    mutedForeground: Color(0xFFA1A1AA),
    accent: Color(0xFFDFE104),
    accentForeground: Color(0xFF000000),
    border: Color(0xFF3F3F46),
    profit: Color(0xFF00FF66),
    loss: Color(0xFFFF0033),
  );

  static const lightColors = KineticColors(
    background: Color(0xFFFAFAFA),
    foreground: Color(0xFF09090B),
    muted: Color(0xFFE4E4E7),
    mutedForeground: Color(0xFF52525B),
    accent: Color(0xFFDFE104),
    accentForeground: Color(0xFF000000),
    border: Color(0xFFD4D4D8),
    profit: Color(0xFF00B84D),
    loss: Color(0xFFFF0033),
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
      cardColor: colors.background,
      dividerColor: colors.border,
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
      hoverColor: colors.accent.withValues(alpha: 0.08),
      colorScheme: ColorScheme(
        brightness: brightness,
        primary: colors.accent,
        onPrimary: colors.accentForeground,
        secondary: colors.foreground,
        onSecondary: colors.background,
        error: colors.loss,
        onError: colors.accentForeground,
        surface: colors.background,
        onSurface: colors.foreground,
      ),
      extensions: const <ThemeExtension<dynamic>>[
        darkColors,
      ],
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: colors.background,
        foregroundColor: colors.foreground,
        centerTitle: false,
        titleTextStyle: textTheme.headlineSmall,
        shape: Border(bottom: BorderSide(color: colors.border, width: 2)),
      ),
      dialogTheme: DialogThemeData(
        elevation: 0,
        backgroundColor: colors.background,
        shape: const RoundedRectangleBorder(borderRadius: radius),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: colors.background,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(color: colors.border, width: 2),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        elevation: 0,
        backgroundColor: colors.accent,
        contentTextStyle: labelStyle(colors).copyWith(
          color: colors.accentForeground,
        ),
        shape: const RoundedRectangleBorder(borderRadius: radius),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: false,
        border: UnderlineInputBorder(
          borderSide: BorderSide(color: colors.border, width: 2),
        ),
        enabledBorder: UnderlineInputBorder(
          borderSide: BorderSide(color: colors.border, width: 2),
        ),
        focusedBorder: UnderlineInputBorder(
          borderSide: BorderSide(color: colors.accent, width: 3),
        ),
        errorBorder: UnderlineInputBorder(
          borderSide: BorderSide(color: colors.loss, width: 2),
        ),
        labelStyle: labelStyle(colors),
        errorStyle: TextStyle(
          color: colors.loss,
          fontFamily: ledgerFontFamily,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
      datePickerTheme: DatePickerThemeData(
        elevation: 0,
        backgroundColor: colors.background,
        headerBackgroundColor: colors.accent,
        headerForegroundColor: colors.accentForeground,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(color: colors.border, width: 2),
        ),
      ),
      dropdownMenuTheme: DropdownMenuThemeData(
        textStyle: bodyStyle(colors),
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(
            borderRadius: radius,
            borderSide: BorderSide(color: colors.border, width: 2),
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
            BorderSide(color: colors.border, width: 2),
          ),
          foregroundColor: WidgetStatePropertyAll(colors.foreground),
          textStyle: WidgetStatePropertyAll(labelStyle(colors)),
        ),
      ),
    ).copyWith(
      extensions: <ThemeExtension<dynamic>>[
        colors,
      ],
    );
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
      height: 0.9,
      letterSpacing: -1.5,
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
      height: 0.95,
      letterSpacing: -0.8,
    );
  }

  static TextStyle bodyStyle(KineticColors colors) {
    return TextStyle(
      color: colors.foreground,
      fontFamily: ledgerFontFamily,
      fontWeight: FontWeight.w500,
      height: 1.1,
      letterSpacing: -0.35,
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
      letterSpacing: 1.4,
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
    );
  }

  static BoxDecoration invertedBox(KineticColors colors) {
    return BoxDecoration(
      color: colors.accent,
      borderRadius: radius,
      border: Border.all(color: colors.accent, width: thickBorderWidth),
    );
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
