import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/asset.dart';
import '../models/portfolio_snapshot.dart';
import '../services/transaction_history_service.dart';

class PortfolioTrendCard extends StatelessWidget {
  const PortfolioTrendCard({super.key, required this.snapshots});

  final List<PortfolioSnapshot> snapshots;

  @override
  Widget build(BuildContext context) {
    final points = [...snapshots]
      ..sort((a, b) => a.capturedAt.compareTo(b.capturedAt));
    final series = _trendSeriesFor(points);
    final latest = points.isEmpty ? null : points.last;
    final change = points.length < 2
        ? null
        : points.last.totalUsd - points[points.length - 2].totalUsd;

    return _DashboardCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Portfolio History',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          const Text(
            'Value over time by asset class',
            style: TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 18),
          if (points.isEmpty)
            const Text(
              'Save snapshots to build your portfolio history chart.',
              style: TextStyle(color: Colors.grey),
            )
          else ...[
            SizedBox(
              key: const Key('portfolio_line_chart'),
              height: 238,
              width: double.infinity,
              child: CustomPaint(painter: _TrendPainter(points, series)),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 16,
              runSpacing: 9,
              children: series
                  .map(
                    (item) =>
                        _SeriesLegend(label: item.label, color: item.color),
                  )
                  .toList(),
            ),
            const SizedBox(height: 16),
            const Divider(height: 1, color: Color(0xFF30343D)),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Latest: \$${latest!.totalUsd.toStringAsFixed(2)}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                if (change != null)
                  Text(
                    '${change >= 0 ? '+' : '-'}\$'
                    '${change.abs().toStringAsFixed(2)}',
                    style: TextStyle(
                      color: change >= 0
                          ? const Color(0xFF22C55E)
                          : Colors.redAccent,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

List<_TrendSeries> _trendSeriesFor(List<PortfolioSnapshot> snapshots) {
  final series = <_TrendSeries>[
    const _TrendSeries(
      label: 'Total',
      color: Color(0xFF60A5FA),
      valueOf: _totalValue,
    ),
  ];
  if (snapshots.any((point) => point.cashUsd > 0)) {
    series.add(
      const _TrendSeries(
        label: 'Cash',
        color: Color(0xFF22C55E),
        valueOf: _cashValue,
      ),
    );
  }
  if (snapshots.any((point) => point.bankSavingsUsd > 0)) {
    series.add(
      const _TrendSeries(
        label: 'Savings',
        color: Color(0xFFA78BFA),
        valueOf: _savingsValue,
      ),
    );
  }
  if (snapshots.any((point) => point.goldUsd > 0)) {
    series.add(
      const _TrendSeries(
        label: 'Gold',
        color: Color(0xFFD4AF37),
        valueOf: _goldValue,
      ),
    );
  }
  if (snapshots.any((point) => point.silverUsd > 0)) {
    series.add(
      const _TrendSeries(
        label: 'Silver',
        color: Color(0xFFCBD5E1),
        valueOf: _silverValue,
      ),
    );
  }
  return series;
}

double _totalValue(PortfolioSnapshot point) => point.totalUsd;
double _cashValue(PortfolioSnapshot point) => point.cashUsd;
double _savingsValue(PortfolioSnapshot point) => point.bankSavingsUsd;
double _goldValue(PortfolioSnapshot point) => point.goldUsd;
double _silverValue(PortfolioSnapshot point) => point.silverUsd;

class _TrendSeries {
  const _TrendSeries({
    required this.label,
    required this.color,
    required this.valueOf,
  });

  final String label;
  final Color color;
  final double Function(PortfolioSnapshot point) valueOf;
}

class _SeriesLegend extends StatelessWidget {
  const _SeriesLegend({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 18,
          height: 3,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(99),
          ),
        ),
        const SizedBox(width: 7),
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12)),
      ],
    );
  }
}

class ProfitLossCard extends StatelessWidget {
  const ProfitLossCard({super.key, required this.results});

  final List<RealizedProfitLoss> results;

  @override
  Widget build(BuildContext context) {
    final largestMagnitude = results.fold<double>(
      0,
      (largest, result) => math.max(largest, result.amount.abs()),
    );

    return _DashboardCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Realized Profit / Loss',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          const Text(
            'Completed investment sales in recorded currency',
            style: TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 14),
          if (results.isEmpty)
            const Text(
              'No completed buy/sell investments match these filters.',
              style: TextStyle(color: Colors.grey),
            )
          else
            ...results.map(
              (result) => _ProfitLossBar(
                result: result,
                scale: largestMagnitude == 0
                    ? 0
                    : result.amount.abs() / largestMagnitude,
              ),
            ),
        ],
      ),
    );
  }
}

class _ProfitLossBar extends StatelessWidget {
  const _ProfitLossBar({required this.result, required this.scale});

  final RealizedProfitLoss result;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final isGain = result.amount >= 0;
    final color = isGain ? const Color(0xFF22C55E) : Colors.redAccent;
    return Padding(
      key: Key('profit_loss_${result.asset.id}'),
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(result.asset.type.label)),
              Text(
                '${isGain ? '+' : '-'}${result.currency} '
                '${result.amount.abs().toStringAsFixed(2)}',
                style: TextStyle(color: color, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 6),
          FractionallySizedBox(
            widthFactor: math.max(scale, 0.04),
            child: Container(
              height: 7,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TrendPainter extends CustomPainter {
  const _TrendPainter(this.snapshots, this.series);

  final List<PortfolioSnapshot> snapshots;
  final List<_TrendSeries> series;

  @override
  void paint(Canvas canvas, Size size) {
    const leftPadding = 53.0;
    const rightPadding = 12.0;
    const topPadding = 10.0;
    const bottomPadding = 29.0;
    const gridColor = Color(0xFF30343D);
    const labelColor = Color(0xFF8B929D);
    final graphWidth = size.width - leftPadding - rightPadding;
    final graphHeight = size.height - topPadding - bottomPadding;
    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;

    final values = <double>[
      0,
      for (final item in series)
        for (final point in snapshots) item.valueOf(point),
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
        labelColor,
        offsetFor: (textSize) =>
            Offset(leftPadding - textSize.width - 9, y - textSize.height / 2),
      );
    }

    for (var index = 0; index < snapshots.length; index++) {
      if (snapshots.length > 6 &&
          index != 0 &&
          index != snapshots.length - 1 &&
          index.isOdd) {
        continue;
      }
      final x = snapshots.length == 1
          ? leftPadding + graphWidth / 2
          : leftPadding + graphWidth * index / (snapshots.length - 1);
      final date = snapshots[index].capturedAt;
      final label =
          '${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')}';
      _paintText(
        canvas,
        label,
        labelColor,
        offsetFor: (textSize) =>
            Offset(x - textSize.width / 2, size.height - textSize.height),
      );
    }

    for (final item in series) {
      final path = Path();
      final pointPaint = Paint()..color = item.color;
      for (var index = 0; index < snapshots.length; index++) {
        final x = snapshots.length == 1
            ? leftPadding + graphWidth / 2
            : leftPadding + graphWidth * index / (snapshots.length - 1);
        final y =
            topPadding +
            graphHeight -
            (item.valueOf(snapshots[index]) / graphMaximum) * graphHeight;
        if (index == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
        canvas.drawCircle(Offset(x, y), 3.5, pointPaint);
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = item.color
          ..style = PaintingStyle.stroke
          ..strokeWidth = item.label == 'Total' ? 2.6 : 2,
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
        style: TextStyle(color: color, fontSize: 10),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(canvas, offsetFor(painter.size));
  }

  String _compactCurrency(double value) {
    if (value >= 1000) return '\$${(value / 1000).toStringAsFixed(1)}k';
    return '\$${value.toStringAsFixed(0)}';
  }

  @override
  bool shouldRepaint(_TrendPainter oldDelegate) =>
      oldDelegate.snapshots != snapshots || oldDelegate.series != series;
}

class _DashboardCard extends StatelessWidget {
  const _DashboardCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: const Color(0xFF1A1D24),
      ),
      child: child,
    );
  }
}
