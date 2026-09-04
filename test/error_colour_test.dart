import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:moniz/models/asset.dart';
import 'package:moniz/theme/app_theme.dart';
import 'package:moniz/widgets/asset_form_dialog.dart';

/// WCAG 2.1 relative luminance.
double _luminance(Color color) {
  double channel(double value) {
    return value <= 0.03928
        ? value / 12.92
        : math.pow((value + 0.055) / 1.055, 2.4).toDouble();
  }

  return 0.2126 * channel(color.r) +
      0.7152 * channel(color.g) +
      0.0722 * channel(color.b);
}

double _contrast(Color a, Color b) {
  final first = _luminance(a);
  final second = _luminance(b);
  final lighter = math.max(first, second);
  final darker = math.min(first, second);
  return (lighter + 0.05) / (darker + 0.05);
}

void main() {
  final palettes = {
    'light': AppTheme.lightColors,
    'dark': AppTheme.darkColors,
  };

  palettes.forEach((name, colors) {
    test('$name theme sets error text apart from ordinary text', () {
      // The bug this guards: errors were painted with `loss`, which in the
      // dark palette is the very same cream used for muted body copy. A
      // message saying the save failed looked exactly like a caption.
      expect(colors.danger, isNot(colors.foreground));
      expect(colors.danger, isNot(colors.mutedForeground));
      expect(colors.danger, isNot(colors.background));
      expect(colors.danger, isNot(colors.muted));
    });

    test('$name theme keeps error text readable on the background', () {
      expect(
        _contrast(colors.danger, colors.background),
        greaterThanOrEqualTo(4.5),
      );
    });
  });

  test('loss stays a market direction, not an alarm', () {
    // `loss` is still the neutral down-tick colour, so it must not quietly
    // become the error colour again.
    expect(AppTheme.darkColors.loss, isNot(AppTheme.darkColors.danger));
    expect(AppTheme.lightColors.loss, isNot(AppTheme.lightColors.danger));
  });

  testWidgets('a form validation error is painted in the error colour', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showDialog<Asset>(
              context: context,
              builder: (_) => const AssetFormDialog(),
            ),
            child: const Text('Open form'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open form'));
    await tester.pump(const Duration(milliseconds: 180));

    await tester.tap(find.byKey(const Key('asset_type_gold')));
    await tester.pump(const Duration(milliseconds: 180));
    await tester.enterText(find.byKey(const Key('asset_amount_field')), '20');
    await tester.tap(find.byKey(const Key('asset_save_button')));
    await tester.pump(const Duration(milliseconds: 180));

    final error = tester.widget<Text>(
      find.descendant(
        of: find.byKey(const Key('asset_purity_error')),
        matching: find.byType(Text),
      ),
    );
    expect(error.style?.color, AppTheme.darkColors.danger);
    expect(error.style?.color, isNot(AppTheme.darkColors.mutedForeground));
  });
}
