import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/asset.dart';
import '../models/portfolio_snapshot.dart';
import '../services/currency_converter.dart';
import '../services/position_performance.dart';
import '../theme/app_theme.dart';
import '../ui/kinetic/kinetic_widgets.dart';

class PortfolioTrendCard extends StatelessWidget {
  const PortfolioTrendCard({
    super.key,
    required this.snapshots,
    required this.performance,
    this.displayCurrency = CurrencyConverter.defaultCurrency,
  });

  final List<PortfolioSnapshot> snapshots;
  final PositionPerformanceSummary performance;
  final String displayCurrency;

  @override
  Widget build(BuildContext context) {
    final colors = context.kinetic;
    final points = _historyPointsFor(snapshots, performance, displayCurrency);
    final series = _trendSeriesFor(points, performance, colors);

    return LedgerFrame(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          KineticText(
            'PORTFOLIO HISTORY',
            style: AppTheme.displayStyle(colors).copyWith(fontSize: 34),
          ),
          const SizedBox(height: 5),
          KineticText('CASH / GOLD / SILVER BOUGHT VS CURRENT', muted: true),
          const SizedBox(height: 18),
          if (points.isEmpty)
            const KineticText(
              'ADD CURRENT VALUES OR SAVE SNAPSHOTS TO BUILD YOUR PORTFOLIO HISTORY CHART.',
              muted: true,
            )
          else ...[
            RepaintBoundary(
              child: SizedBox(
                key: const Key('portfolio_line_chart'),
                height: 238,
                width: double.infinity,
                child: CustomPaint(
                  painter: _TrendPainter(
                    points,
                    series,
                    colors,
                    displayCurrency,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 16,
              runSpacing: 12,
              children: series
                  .map(
                    (item) => _SeriesLegend(
                      label: item.label,
                      color: item.color,
                      paidUsd: item.paidUsd,
                      currentUsd: item.currentUsd,
                      currency: displayCurrency,
                    ),
                  )
                  .toList(),
            ),
          ],
        ],
      ),
    );
  }
}

List<_TrendPoint> _historyPointsFor(
  List<PortfolioSnapshot> snapshots,
  PositionPerformanceSummary performance,
  String displayCurrency,
) {
  final sortedSnapshots = [...snapshots]
    ..sort((a, b) => a.capturedAt.compareTo(b.capturedAt));
  final points = sortedSnapshots
      .map(
        (snapshot) => _TrendPoint(
          label: _shortDate(snapshot.capturedAt),
          cashUsd: _fromUsd(
            snapshot.cashUsd + snapshot.bankSavingsUsd,
            displayCurrency,
          ),
          goldUsd: _fromUsd(snapshot.goldUsd, displayCurrency),
          silverUsd: _fromUsd(snapshot.silverUsd, displayCurrency),
        ),
      )
      .toList();

  if (points.isEmpty) {
    if (!performance.hasTrackedCurrentWorth &&
        !performance.hasComparablePositions) {
      return const [];
    }
    return [
      _TrendPoint(
        label: 'Bought',
        cashUsd: performance.paidFor(AssetType.cash),
        goldUsd: performance.paidFor(AssetType.gold),
        silverUsd: performance.paidFor(AssetType.silver),
      ),
      _TrendPoint(
        label: 'Now',
        cashUsd: performance.currentWorthFor(AssetType.cash),
        goldUsd: performance.currentWorthFor(AssetType.gold),
        silverUsd: performance.currentWorthFor(AssetType.silver),
      ),
    ];
  }

  if (performance.hasTrackedCurrentWorth) {
    points.add(
      _TrendPoint(
        label: 'Now',
        cashUsd: performance.currentWorthFor(AssetType.cash),
        goldUsd: performance.currentWorthFor(AssetType.gold),
        silverUsd: performance.currentWorthFor(AssetType.silver),
      ),
    );
  }
  return points;
}

double _fromUsd(double value, String displayCurrency) {
  return CurrencyConverter.convertFromUsd(value, displayCurrency) ?? 0;
}

List<_TrendSeries> _trendSeriesFor(
  List<_TrendPoint> points,
  PositionPerformanceSummary performance,
  KineticColors colors,
) {
  final series = <_TrendSeries>[];
  if (_hasValue(points, _cashValue) ||
      performance.paidFor(AssetType.cash) > 0 ||
      performance.currentWorthFor(AssetType.cash) > 0) {
    series.add(
      _TrendSeries(
        label: 'Cash',
        color: colors.profit,
        valueOf: _cashValue,
        paidUsd: performance.paidFor(AssetType.cash),
        currentUsd: performance.currentWorthFor(AssetType.cash),
      ),
    );
  }
  if (_hasValue(points, _goldValue) ||
      performance.paidFor(AssetType.gold) > 0 ||
      performance.currentWorthFor(AssetType.gold) > 0) {
    series.add(
      _TrendSeries(
        label: 'Gold',
        color: colors.accent,
        valueOf: _goldValue,
        paidUsd: performance.paidFor(AssetType.gold),
        currentUsd: performance.currentWorthFor(AssetType.gold),
      ),
    );
  }
  if (_hasValue(points, _silverValue) ||
      performance.paidFor(AssetType.silver) > 0 ||
      performance.currentWorthFor(AssetType.silver) > 0) {
    series.add(
      _TrendSeries(
        label: 'Silver',
        color: AppTheme.cream,
        valueOf: _silverValue,
        paidUsd: performance.paidFor(AssetType.silver),
        currentUsd: performance.currentWorthFor(AssetType.silver),
      ),
    );
  }
  return series;
}

bool _hasValue(
  List<_TrendPoint> points,
  double Function(_TrendPoint point) valueOf,
) {
  return points.any((point) => valueOf(point) > 0);
}

double _cashValue(_TrendPoint point) => point.cashUsd;
double _goldValue(_TrendPoint point) => point.goldUsd;
double _silverValue(_TrendPoint point) => point.silverUsd;

String _shortDate(DateTime date) {
  return '${date.month.toString().padLeft(2, '0')}/'
      '${date.day.toString().padLeft(2, '0')}';
}

class _TrendPoint {
  const _TrendPoint({
    required this.label,
    required this.cashUsd,
    required this.goldUsd,
    required this.silverUsd,
  });

  final String label;
  final double cashUsd;
  final double goldUsd;
  final double silverUsd;
}

class _TrendSeries {
  const _TrendSeries({
    required this.label,
    required this.color,
    required this.valueOf,
    required this.paidUsd,
    required this.currentUsd,
  });

  final String label;
  final Color color;
  final double Function(_TrendPoint point) valueOf;
  final double paidUsd;
  final double currentUsd;
}

class _SeriesLegend extends StatelessWidget {
  const _SeriesLegend({
    required this.label,
    required this.color,
    required this.paidUsd,
    required this.currentUsd,
    required this.currency,
  });

  final String label;
  final Color color;
  final double paidUsd;
  final double currentUsd;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final colors = context.kinetic;
    return SizedBox(
      width: 168,
      child: Row(
        children: [
          Container(width: 22, height: 5, color: color),
          const SizedBox(width: 7),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                KineticText(
                  label,
                  style: AppTheme.labelStyle(colors).copyWith(fontSize: 11),
                ),
                const SizedBox(height: 3),
                KineticText(
                  'Bought ${_compactMoney(paidUsd, currency)} / '
                  'Now ${_compactMoney(currentUsd, currency)}',
                  muted: true,
                  style: AppTheme.bodyStyle(colors).copyWith(fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class ProfitLossCard extends StatelessWidget {
  const ProfitLossCard({super.key, required this.summary});

  final PositionPerformanceSummary summary;

  @override
  Widget build(BuildContext context) {
    final colors = context.kinetic;
    final change = summary.changeUsd;
    final isGain = change >= 0;

    return LedgerFrame(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          KineticText(
            'PAID VS NOW',
            style: AppTheme.displayStyle(colors).copyWith(fontSize: 34),
          ),
          const SizedBox(height: 5),
          KineticText('CURRENT WORTH MINUS WHAT YOU PAID', muted: true),
          const SizedBox(height: 16),
          if (!summary.hasComparablePositions)
            const KineticText(
              'ADD BOUGHT PRICES TO ACTIVE HOLDINGS TO SEE THIS NUMBER.',
              muted: true,
            )
          else ...[
            KineticNumber(
              '${isGain ? '+' : '-'}'
              '${_formatMoney(change.abs(), summary.currency)}',
              key: const Key('paid_vs_now_amount'),
              fontSize: 58,
              color: isGain ? colors.profit : colors.loss,
            ),
            const SizedBox(height: 10),
            KineticText(
              'PAID ${_formatMoney(summary.paidUsd, summary.currency)} / '
              'NOW ${_formatMoney(summary.currentUsd, summary.currency)}',
              muted: true,
              style: AppTheme.bodyStyle(colors).copyWith(fontSize: 14),
            ),
            if (summary.missingBoughtPriceCount > 0 ||
                summary.unpricedAssetCount > 0 ||
                summary.unsupportedCurrencyCount > 0) ...[
              const SizedBox(height: 8),
              KineticText(
                _performanceNote(summary),
                muted: true,
                uppercase: false,
                style: AppTheme.bodyStyle(colors).copyWith(fontSize: 13),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

String _performanceNote(PositionPerformanceSummary summary) {
  final notes = <String>[
    if (summary.missingBoughtPriceCount > 0)
      '${summary.missingBoughtPriceCount} active metal holding needs a bought price',
    if (summary.unpricedAssetCount > 0)
      '${summary.unpricedAssetCount} metal holding needs live prices',
    if (summary.unsupportedCurrencyCount > 0)
      '${summary.unsupportedCurrencyCount} holding uses an unsupported currency',
  ];
  return notes.join('. ');
}

String _formatMoney(double value, String currency) {
  return CurrencyConverter.formatMoney(value, currency);
}

String _compactMoney(double value, String currency) {
  return CurrencyConverter.compactMoney(value, currency);
}

class _TrendPainter extends CustomPainter {
  const _TrendPainter(this.points, this.series, this.colors, this.currency);

  final List<_TrendPoint> points;
  final List<_TrendSeries> series;
  final KineticColors colors;
  final String currency;

  @override
  void paint(Canvas canvas, Size size) {
    const leftPadding = 53.0;
    const rightPadding = 12.0;
    const topPadding = 10.0;
    const bottomPadding = 29.0;
    final graphWidth = size.width - leftPadding - rightPadding;
    final graphHeight = size.height - topPadding - bottomPadding;
    final gridPaint = Paint()
      ..color = colors.border
      ..strokeWidth = 1;

    final values = <double>[
      0,
      for (final item in series)
        for (final point in points) item.valueOf(point),
    ];
    final maximum = values.reduce(math.max);
    final graphMaximum = maximum == 0 ? 1.0 : maximum * 1.08;

    for (var row = 0; row <= 4; row++) {
      final y = topPadding + graphHeight * row / 4;
      canvas.drawLine(
        Offset(leftPadding, y),
        Offset(size.width - rightPadding, y),
        gridPaint,
      );
      final value = graphMaximum * (4 - row) / 4;
      _paintText(
        canvas,
        _compactCurrency(value),
        colors.mutedForeground,
        offsetFor: (textSize) =>
            Offset(leftPadding - textSize.width - 9, y - textSize.height / 2),
      );
    }

    for (var index = 0; index < points.length; index++) {
      if (points.length > 6 &&
          index != 0 &&
          index != points.length - 1 &&
          index.isOdd) {
        continue;
      }
      final x = points.length == 1
          ? leftPadding + graphWidth / 2
          : leftPadding + graphWidth * index / (points.length - 1);
      _paintText(
        canvas,
        points[index].label,
        colors.mutedForeground,
        offsetFor: (textSize) =>
            Offset(x - textSize.width / 2, size.height - textSize.height),
      );
    }

    for (final item in series) {
      final path = Path();
      final pointPaint = Paint()..color = item.color;
      for (var index = 0; index < points.length; index++) {
        final x = points.length == 1
            ? leftPadding + graphWidth / 2
            : leftPadding + graphWidth * index / (points.length - 1);
        final y =
            topPadding +
            graphHeight -
            (item.valueOf(points[index]) / graphMaximum) * graphHeight;
        if (index == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
        canvas.drawRect(
          Rect.fromCenter(center: Offset(x, y), width: 7, height: 7),
          pointPaint,
        );
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = item.color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3,
      );
    }
  }

  void _paintText(
    Canvas canvas,
    String text,
    Color color, {
    required Offset Function(Size textSize) offsetFor,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontFamily: AppTheme.ledgerFontFamily,
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(canvas, offsetFor(painter.size));
  }

  String _compactCurrency(double value) {
    return CurrencyConverter.compactMoney(value, currency);
  }

  @override
  bool shouldRepaint(_TrendPainter oldDelegate) {
    return oldDelegate.points != points ||
        oldDelegate.series != series ||
        oldDelegate.colors != colors ||
        oldDelegate.currency != currency;
  }
}
