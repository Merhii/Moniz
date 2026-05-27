import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/asset.dart';
import '../providers/portfolio_snapshot_provider.dart';
import '../services/portfolio_analytics.dart';

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

  static const _categoryColors = {
    AssetType.cash: Color(0xFF22C55E),
    AssetType.bankSavings: Color(0xFF3B82F6),
    AssetType.gold: Color(0xFFD4AF37),
    AssetType.silver: Color(0xFFCBD5E1),
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: const Color(0xFF1A1D24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Asset Allocation',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          const Text(
            'Current valued holdings',
            style: TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 20),
          if (analytics.totalUsd == 0)
            const Text(
              'Add valued holdings to see category analytics.',
              style: TextStyle(color: Colors.grey),
            )
          else
            LayoutBuilder(
              builder: (context, constraints) {
                final categoryRows = Column(
                  children: AssetType.values
                      .where(
                        (type) => (analytics.categoryValuesUsd[type] ?? 0) > 0,
                      )
                      .map(
                        (type) => _CategoryRow(
                          type: type,
                          valueUsd: analytics.categoryValuesUsd[type]!,
                          percentage: analytics.percentageFor(type),
                        ),
                      )
                      .toList(),
                );
                final donut = _DonutHero(analytics: analytics);
                if (constraints.maxWidth < 560) {
                  return Column(
                    children: [donut, const SizedBox(height: 20), categoryRows],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    donut,
                    const SizedBox(width: 34),
                    Expanded(child: categoryRows),
                  ],
                );
              },
            ),
          const SizedBox(height: 22),
          Row(
            children: [
              _CountBadge(
                label: 'Active',
                count: analytics.activeAssetCount,
                color: const Color(0xFF22C55E),
              ),
              const SizedBox(width: 10),
              _CountBadge(
                label: 'Sold',
                count: analytics.soldAssetCount,
                color: Colors.grey,
              ),
            ],
          ),
          if (analytics.unvaluedAssetCount > 0)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                '${analytics.unvaluedAssetCount} holding(s) excluded until valued.',
                style: const TextStyle(color: Colors.grey),
              ),
            ),
          if (isFiltered)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'Snapshot saves your complete portfolio, not this filtered view.',
                style: TextStyle(color: Colors.grey, fontSize: 12),
              ),
            ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: FilledButton.tonalIcon(
                  key: const Key('capture_portfolio_snapshot'),
                  onPressed: (snapshotAnalytics ?? analytics).totalUsd == 0
                      ? null
                      : () async {
                          await ref
                              .read(portfolioSnapshotProvider.notifier)
                              .capture(snapshotAnalytics ?? analytics);
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Portfolio snapshot saved.'),
                              ),
                            );
                          }
                        },
                  icon: const Icon(Icons.camera_alt_outlined),
                  label: const Text('Save Snapshot'),
                ),
              ),
              const SizedBox(width: 10),
              OutlinedButton.icon(
                key: const Key('open_transaction_history'),
                onPressed: onOpenHistory,
                icon: const Icon(Icons.history),
                label: const Text('History'),
              ),
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
    return SizedBox(
      height: 176,
      width: 176,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            key: const Key('portfolio_pie_chart'),
            size: const Size.square(176),
            painter: _BreakdownPainter(
              values: analytics.categoryValuesUsd,
              total: analytics.totalUsd,
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Total',
                style: TextStyle(color: Colors.grey, fontSize: 12),
              ),
              const SizedBox(height: 4),
              Text(
                '\$${analytics.totalUsd.toStringAsFixed(0)}',
                style: const TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CountBadge extends StatelessWidget {
  const _CountBadge({
    required this.label,
    required this.count,
    required this.color,
  });

  final String label;
  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        '$count $label',
        style: TextStyle(color: color, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _CategoryRow extends StatelessWidget {
  const _CategoryRow({
    required this.type,
    required this.valueUsd,
    required this.percentage,
  });

  final AssetType type;
  final double valueUsd;
  final double percentage;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 9),
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF20242C),
        borderRadius: BorderRadius.circular(13),
      ),
      child: Row(
        children: [
          Container(
            height: 11,
            width: 11,
            decoration: BoxDecoration(
              color: PortfolioInsightsCard._categoryColors[type],
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              type.label,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
          Text(
            '${(percentage * 100).toStringAsFixed(0)}%',
            style: const TextStyle(color: Colors.grey),
          ),
          const SizedBox(width: 14),
          Text(
            '\$${valueUsd.toStringAsFixed(0)}',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}

class _BreakdownPainter extends CustomPainter {
  const _BreakdownPainter({required this.values, required this.total});

  final Map<AssetType, double> values;
  final double total;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    var startAngle = -math.pi / 2;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 24
      ..strokeCap = StrokeCap.round;

    for (final type in AssetType.values) {
      final value = values[type] ?? 0;
      if (value <= 0) continue;
      final sweepAngle = (value / total) * math.pi * 2;
      paint.color = PortfolioInsightsCard._categoryColors[type]!;
      canvas.drawArc(rect.deflate(16), startAngle, sweepAngle, false, paint);
      startAngle += sweepAngle;
    }
  }

  @override
  bool shouldRepaint(_BreakdownPainter oldDelegate) =>
      oldDelegate.values != values || oldDelegate.total != total;
}
