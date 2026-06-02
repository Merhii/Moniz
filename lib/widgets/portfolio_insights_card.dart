import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/asset.dart';
import '../providers/portfolio_snapshot_provider.dart';
import '../services/currency_converter.dart';
import '../services/portfolio_analytics.dart';
import '../theme/app_theme.dart';
import '../ui/kinetic/kinetic_widgets.dart';

class PortfolioInsightsCard extends ConsumerWidget {
  const PortfolioInsightsCard({
    super.key,
    required this.analytics,
    required this.onOpenHistory,
    this.snapshotAnalytics,
    this.isFiltered = false,
  });

  final PortfolioAnalytics analytics;
  final PortfolioAnalytics? snapshotAnalytics;
  final VoidCallback onOpenHistory;
  final bool isFiltered;

  static Color categoryColor(AssetType type, KineticColors colors) {
    return switch (type) {
      AssetType.cash => AppTheme.white,
      AssetType.bankSavings => AppTheme.lightGold,
      AssetType.gold => colors.accent,
      AssetType.silver => AppTheme.cream,
    };
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.kinetic;
    return LedgerFrame(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          KineticText(
            'ASSET ALLOCATION',
            style: AppTheme.displayStyle(colors).copyWith(fontSize: 34),
          ),
          const SizedBox(height: 5),
          KineticText('CURRENT VALUED HOLDINGS', muted: true),
          const SizedBox(height: 20),
          if (analytics.totalUsd == 0)
            const KineticText(
              'ADD VALUED HOLDINGS TO SEE CATEGORY ANALYTICS.',
              muted: true,
            )
          else
            LayoutBuilder(
              builder: (context, constraints) {
                final categories = AssetType.values
                    .where(
                      (type) => (analytics.categoryValuesUsd[type] ?? 0) > 0,
                    )
                    .map(
                      (type) => _CategoryDatum(
                        type: type,
                        valueUsd: analytics.categoryValuesUsd[type]!,
                        percentage: analytics.percentageFor(type),
                        currency: analytics.currency,
                      ),
                    )
                    .toList();
                final legend = _AllocationLegend(categories: categories);
                final spotlight = _DonutHero(analytics: analytics);
                if (constraints.maxWidth < 620) {
                  return Column(
                    children: [
                      SizedBox(height: 280, child: spotlight),
                      const SizedBox(height: 14),
                      legend,
                    ],
                  );
                }
                return SizedBox(
                  height: 340,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(flex: 4, child: spotlight),
                      const SizedBox(width: 20),
                      Expanded(flex: 1, child: legend),
                    ],
                  ),
                );
              },
            ),
          const SizedBox(height: 18),
          BrutalistGrid(
            minTileWidth: 150,
            children: [
              MetricBlock(
                label: 'Active',
                value: analytics.activeAssetCount.toString(),
                valueColor: colors.profit,
              ),
              MetricBlock(
                label: 'Sold',
                value: analytics.soldAssetCount.toString(),
                valueColor: colors.mutedForeground,
              ),
              if (analytics.unvaluedAssetCount > 0)
                MetricBlock(
                  label: 'Unvalued',
                  value: analytics.unvaluedAssetCount.toString(),
                  valueColor: colors.loss,
                ),
            ],
          ),
          if (isFiltered) ...[
            const SizedBox(height: 12),
            const KineticText(
              'SNAPSHOT SAVES YOUR COMPLETE PORTFOLIO, NOT THIS FILTERED VIEW.',
              muted: true,
            ),
          ],
          const SizedBox(height: 18),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              BrutalistButton(
                key: const Key('capture_portfolio_snapshot'),
                label: 'SAVE SNAPSHOT',
                tone: BrutalistButtonTone.primary,
                onPressed: (snapshotAnalytics ?? analytics).totalUsd == 0
                    ? null
                    : () async {
                        await ref
                            .read(portfolioSnapshotProvider.notifier)
                            .capture(snapshotAnalytics ?? analytics);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('PORTFOLIO SNAPSHOT SAVED.'),
                            ),
                          );
                        }
                      },
              ),
              BrutalistButton(label: 'HISTORY', onPressed: onOpenHistory),
            ],
          ),
        ],
      ),
    );
  }
}

class _DonutHero extends StatelessWidget {
  const _DonutHero({required this.analytics});

  final PortfolioAnalytics analytics;

  @override
  Widget build(BuildContext context) {
    final colors = context.kinetic;
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = math.min(constraints.maxWidth, constraints.maxHeight);
        final numberSize = (size * 0.15).clamp(24.0, 46.0);
        return Center(
          child: SizedBox.square(
            dimension: size,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Positioned.fill(
                  child: RepaintBoundary(
                    child: CustomPaint(
                      key: const Key('portfolio_pie_chart'),
                      painter: _BreakdownPainter(
                        values: analytics.categoryValuesUsd,
                        total: analytics.totalUsd,
                        colors: colors,
                      ),
                    ),
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    KineticText('TOTAL', style: AppTheme.labelStyle(colors)),
                    const SizedBox(height: 5),
                    KineticNumber(
                      CurrencyConverter.formatMoney(
                        analytics.totalUsd,
                        analytics.currency,
                        decimals: 0,
                      ),
                      fontSize: numberSize,
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _CategoryDatum {
  const _CategoryDatum({
    required this.type,
    required this.valueUsd,
    required this.percentage,
    required this.currency,
  });

  final AssetType type;
  final double valueUsd;
  final double percentage;
  final String currency;
}

class _AllocationLegend extends StatelessWidget {
  const _AllocationLegend({required this.categories});

  final List<_CategoryDatum> categories;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 190;
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: categories
              .map((category) => _CategoryRow(category, compact: compact))
              .toList(),
        );
      },
    );
  }
}

class _CategoryRow extends StatelessWidget {
  const _CategoryRow(this.category, {required this.compact});

  final _CategoryDatum category;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colors = context.kinetic;
    final color = PortfolioInsightsCard.categoryColor(category.type, colors);
    final detail = compact
        ? CurrencyConverter.formatMoney(
            category.valueUsd,
            category.currency,
            decimals: 0,
          )
        : '${(category.percentage * 100).toStringAsFixed(0)}% / '
              '${CurrencyConverter.formatMoney(category.valueUsd, category.currency, decimals: 0)}';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Container(width: 12, height: 36, color: color),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                KineticText(
                  category.type.label,
                  maxLines: 1,
                  style: AppTheme.bodyStyle(colors).copyWith(fontSize: 15),
                ),
                const SizedBox(height: 3),
                KineticText(
                  detail,
                  maxLines: 1,
                  muted: true,
                  style: AppTheme.labelStyle(colors).copyWith(fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BreakdownPainter extends CustomPainter {
  const _BreakdownPainter({
    required this.values,
    required this.total,
    required this.colors,
  });

  final Map<AssetType, double> values;
  final double total;
  final KineticColors colors;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final strokeWidth = math.max(
      18.0,
      math.min(size.shortestSide * 0.11, 34.0),
    );
    var startAngle = -math.pi / 2;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.butt;

    for (final type in AssetType.values) {
      final value = values[type] ?? 0;
      if (value <= 0) continue;
      final sweepAngle = (value / total) * math.pi * 2;
      paint.color = PortfolioInsightsCard.categoryColor(type, colors);
      canvas.drawArc(
        rect.deflate(strokeWidth / 2 + 4),
        startAngle,
        sweepAngle,
        false,
        paint,
      );
      startAngle += sweepAngle;
    }
  }

  @override
  bool shouldRepaint(_BreakdownPainter oldDelegate) {
    return oldDelegate.values != values ||
        oldDelegate.total != total ||
        oldDelegate.colors != colors;
  }
}
