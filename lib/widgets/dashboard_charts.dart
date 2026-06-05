import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/asset.dart';
import '../models/metal_price_snapshot.dart';
import '../models/portfolio_snapshot.dart';
import '../services/currency_converter.dart';
import '../services/position_performance.dart';
import '../theme/app_theme.dart';
import '../ui/kinetic/kinetic_widgets.dart';

enum _JumpWindow {
  thirtyDays('30D', 30),
  ninetyDays('90D', 90),
  all('ALL', null);

  const _JumpWindow(this.label, this.days);

  final String label;
  final int? days;
}

class PortfolioTrendCard extends StatefulWidget {
  const PortfolioTrendCard({
    super.key,
    required this.snapshots,
    required this.performance,
    required this.assets,
    required this.metalPriceHistory,
    this.displayCurrency = CurrencyConverter.defaultCurrency,
  });

  final List<PortfolioSnapshot> snapshots;
  final PositionPerformanceSummary performance;
  final List<Asset> assets;
  final List<MetalPriceSnapshot> metalPriceHistory;
  final String displayCurrency;

  @override
  State<PortfolioTrendCard> createState() => _PortfolioTrendCardState();
}

class _PortfolioTrendCardState extends State<PortfolioTrendCard> {
  var _jumpWindow = _JumpWindow.thirtyDays;

  @override
  Widget build(BuildContext context) {
    final colors = context.kinetic;
    final points = _historyPointsFor(
      widget.snapshots,
      widget.performance,
      widget.assets,
      widget.metalPriceHistory,
      widget.displayCurrency,
    );
    final visiblePoints = _visiblePointsFor(points, _jumpWindow);
    final jumpSummary = _jumpSummaryFor(points, _jumpWindow);
    final series = _trendSeriesFor(points, widget.performance, colors);
    final chartHeight = MediaQuery.sizeOf(context).width < 560 ? 286.0 : 348.0;

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
          KineticText('CASH / GOLD / SILVER VALUE JUMPS', muted: true),
          const SizedBox(height: 18),
          if (points.isEmpty)
            const KineticText(
              'ADD CURRENT VALUES OR SAVE SNAPSHOTS TO BUILD YOUR PORTFOLIO HISTORY CHART.',
              muted: true,
            )
          else ...[
            _JumpWindowPicker(
              selected: _jumpWindow,
              onSelected: (window) => setState(() => _jumpWindow = window),
            ),
            if (jumpSummary != null) ...[
              const SizedBox(height: 12),
              _JumpSummaryStrip(
                summary: jumpSummary,
                currency: widget.displayCurrency,
              ),
            ],
            const SizedBox(height: 18),
            RepaintBoundary(
              child: SizedBox(
                key: const Key('portfolio_line_chart'),
                height: chartHeight,
                width: double.infinity,
                child: CustomPaint(
                  painter: _TrendPainter(
                    visiblePoints,
                    series,
                    colors,
                    widget.displayCurrency,
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
                      currency: widget.displayCurrency,
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
  List<Asset> assets,
  List<MetalPriceSnapshot> metalPriceHistory,
  String displayCurrency,
) {
  final sortedSnapshots = [...snapshots]
    ..sort((a, b) => a.capturedAt.compareTo(b.capturedAt));
  final sortedHistory = [...metalPriceHistory]
    ..sort((a, b) => a.priceTimestamp.compareTo(b.priceTimestamp));
  final pointDays = <DateTime>{};
  var hasDatedAssetEvent = false;

  for (final price in sortedHistory) {
    pointDays.add(_dayKey(price.priceTimestamp));
  }
  for (final snapshot in sortedSnapshots) {
    pointDays.add(_dayKey(snapshot.capturedAt));
  }
  for (final asset in assets) {
    final boughtDate = asset.boughtDate;
    if (boughtDate != null) {
      pointDays.add(_dayKey(boughtDate));
      hasDatedAssetEvent = true;
    }
    final soldDate = asset.soldDate;
    if (soldDate != null) {
      pointDays.add(_dayKey(soldDate));
      hasDatedAssetEvent = true;
    }
  }

  if (hasDatedAssetEvent && pointDays.isNotEmpty) {
    final earliestDay = pointDays.reduce((a, b) => a.isBefore(b) ? a : b);
    pointDays.add(earliestDay.subtract(const Duration(days: 1)));
  }

  final startDay = hasDatedAssetEvent && pointDays.isNotEmpty
      ? pointDays.reduce((a, b) => a.isBefore(b) ? a : b)
      : null;
  final pointsByDay = <DateTime, _TrendPoint>{};
  for (final day in pointDays) {
    pointsByDay[day] = _pointForDay(
      day,
      sortedSnapshots,
      sortedHistory,
      assets,
      displayCurrency,
      label: startDay != null && day == startDay ? 'Start' : null,
    );
  }

  final points = pointsByDay.values.toList()
    ..sort((a, b) {
      final aDate = a.capturedAt;
      final bDate = b.capturedAt;
      if (aDate == null || bDate == null) return 0;
      return aDate.compareTo(bDate);
    });

  if (points.isEmpty) {
    if (!performance.hasTrackedCurrentWorth &&
        !performance.hasComparablePositions) {
      return const [];
    }
    return [
      _TrendPoint(
        label: 'Bought',
        capturedAt: null,
        cashUsd: performance.paidFor(AssetType.cash),
        goldUsd: performance.paidFor(AssetType.gold),
        silverUsd: performance.paidFor(AssetType.silver),
      ),
      _TrendPoint(
        label: 'Now',
        capturedAt: DateTime.now(),
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
        capturedAt: DateTime.now(),
        cashUsd: performance.currentWorthFor(AssetType.cash),
        goldUsd: performance.currentWorthFor(AssetType.gold),
        silverUsd: performance.currentWorthFor(AssetType.silver),
      ),
    );
  }
  return points;
}

DateTime _dayKey(DateTime date) {
  final localDate = date.toLocal();
  return DateTime(localDate.year, localDate.month, localDate.day);
}

DateTime _endOfDay(DateTime date) {
  final day = _dayKey(date);
  return day
      .add(const Duration(days: 1))
      .subtract(const Duration(microseconds: 1));
}

_TrendPoint _pointForDay(
  DateTime day,
  List<PortfolioSnapshot> sortedSnapshots,
  List<MetalPriceSnapshot> sortedHistory,
  List<Asset> assets,
  String displayCurrency, {
  String? label,
}) {
  final date = _endOfDay(day);
  final latestSnapshot = _snapshotAt(date, sortedSnapshots);
  final price = _priceAt(date, sortedHistory);
  final snapshotCash = latestSnapshot == null
      ? null
      : _fromUsd(
          latestSnapshot.cashUsd + latestSnapshot.bankSavingsUsd,
          displayCurrency,
        );

  return _TrendPoint(
    label: label ?? _shortDate(day),
    capturedAt: day,
    cashUsd: _cashValueAt(
      date,
      assets,
      displayCurrency,
      price,
      fallbackValue: snapshotCash,
    ),
    goldUsd: _metalValueAt(
      assets,
      AssetType.gold,
      price,
      displayCurrency,
      date,
      fallbackValue:
          _metalPaidValueAt(
            assets,
            AssetType.gold,
            date,
            displayCurrency,
            price,
          ) ??
          _fromUsd(latestSnapshot?.goldUsd ?? 0, displayCurrency),
    ),
    silverUsd: _metalValueAt(
      assets,
      AssetType.silver,
      price,
      displayCurrency,
      date,
      fallbackValue:
          _metalPaidValueAt(
            assets,
            AssetType.silver,
            date,
            displayCurrency,
            price,
          ) ??
          _fromUsd(latestSnapshot?.silverUsd ?? 0, displayCurrency),
    ),
  );
}

PortfolioSnapshot? _snapshotAt(
  DateTime date,
  List<PortfolioSnapshot> sortedSnapshots,
) {
  PortfolioSnapshot? latestSnapshot;
  for (final snapshot in sortedSnapshots) {
    if (snapshot.capturedAt.isAfter(date)) break;
    latestSnapshot = snapshot;
  }
  return latestSnapshot;
}

double _cashValueAt(
  DateTime date,
  List<Asset> assets,
  String displayCurrency,
  MetalPriceSnapshot? prices, {
  double? fallbackValue,
}) {
  final hasCashLedger = assets.any(
    (asset) =>
        _isCashLike(asset.type) &&
        (asset.boughtDate != null || asset.soldDate != null),
  );
  var ledgerValue = 0.0;
  var hasConvertibleCash = false;

  for (final asset in assets.where((asset) => _isCashLike(asset.type))) {
    if (!_assetHeldAt(asset, date)) continue;
    final value = CurrencyConverter.convert(
      asset.amount,
      from: asset.currency,
      to: displayCurrency,
      prices: prices,
    );
    if (value == null) continue;
    ledgerValue += value;
    hasConvertibleCash = true;
  }

  if (hasCashLedger || hasConvertibleCash) return ledgerValue;
  return fallbackValue ?? 0;
}

bool _isCashLike(AssetType type) {
  return type == AssetType.cash || type == AssetType.bankSavings;
}

MetalPriceSnapshot? _priceAt(
  DateTime date,
  List<MetalPriceSnapshot> sortedHistory,
) {
  MetalPriceSnapshot? latestPrice;
  for (final price in sortedHistory) {
    if (price.priceTimestamp.isAfter(date)) break;
    latestPrice = price;
  }
  return latestPrice;
}

double _metalValueAt(
  List<Asset> assets,
  AssetType type,
  MetalPriceSnapshot? prices,
  String displayCurrency,
  DateTime date, {
  double fallbackValue = 0,
}) {
  if (prices == null) return fallbackValue;
  var valueUsd = 0.0;
  for (final asset in assets.where(
    (asset) => asset.type == type && _assetHeldAt(asset, date),
  )) {
    final purityFactor = (asset.purity ?? 100) / 100;
    final pricePerGram = type == AssetType.gold
        ? prices.goldPerGramUsd
        : prices.silverPerGramUsd;
    valueUsd += asset.amount * purityFactor * pricePerGram;
  }
  return CurrencyConverter.convertFromUsd(
        valueUsd,
        displayCurrency,
        prices: prices,
      ) ??
      valueUsd;
}

double? _metalPaidValueAt(
  List<Asset> assets,
  AssetType type,
  DateTime date,
  String displayCurrency,
  MetalPriceSnapshot? prices,
) {
  var value = 0.0;
  var hasPaidValue = false;
  for (final asset in assets.where(
    (asset) => asset.type == type && _assetHeldAt(asset, date),
  )) {
    final boughtPrice = asset.boughtPrice;
    if (boughtPrice == null) continue;
    final converted = CurrencyConverter.convert(
      boughtPrice,
      from: asset.currency,
      to: displayCurrency,
      prices: prices,
    );
    if (converted == null) continue;
    value += converted;
    hasPaidValue = true;
  }
  return hasPaidValue ? value : null;
}

bool _assetHeldAt(Asset asset, DateTime date) {
  final boughtDate = asset.boughtDate;
  if (boughtDate != null && date.isBefore(boughtDate)) return false;
  final soldDate = asset.soldDate;
  if (soldDate != null && !date.isBefore(soldDate)) return false;
  return true;
}

List<_TrendPoint> _visiblePointsFor(
  List<_TrendPoint> points,
  _JumpWindow window,
) {
  final days = window.days;
  final latestDate = points.isEmpty ? null : points.last.capturedAt;
  if (points.length < 2 || days == null || latestDate == null) {
    return points;
  }

  final cutoff = latestDate.subtract(Duration(days: days));
  final visiblePoints = <_TrendPoint>[];
  _TrendPoint? baseline;

  for (final point in points) {
    final date = point.capturedAt;
    if (date == null || !date.isAfter(cutoff)) {
      baseline = point;
      continue;
    }
    visiblePoints.add(point);
  }

  if (baseline != null) {
    return [baseline, ...visiblePoints];
  }
  return visiblePoints.isEmpty ? [points.last] : visiblePoints;
}

_JumpSummary? _jumpSummaryFor(List<_TrendPoint> points, _JumpWindow window) {
  if (points.length < 2) return null;
  final latest = points.last;
  final baseline = _baselinePointFor(points, window);
  if (identical(baseline, latest)) return null;
  return _JumpSummary(
    window: window,
    fromLabel: baseline.label,
    toLabel: latest.label,
    totalDelta: latest.totalValue - baseline.totalValue,
    cashDelta: latest.cashUsd - baseline.cashUsd,
    goldDelta: latest.goldUsd - baseline.goldUsd,
    silverDelta: latest.silverUsd - baseline.silverUsd,
  );
}

_TrendPoint _baselinePointFor(List<_TrendPoint> points, _JumpWindow window) {
  final days = window.days;
  final latest = points.last;
  final latestDate = latest.capturedAt;
  if (days == null || latestDate == null) return points.first;

  final cutoff = latestDate.subtract(Duration(days: days));
  var baseline = points.first;
  for (final point in points) {
    if (identical(point, latest)) break;
    final date = point.capturedAt;
    if (date == null || !date.isAfter(cutoff)) {
      baseline = point;
      continue;
    }
    break;
  }
  return baseline;
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
        color: colors.foreground,
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
        color: AppTheme.gold,
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
        color: const Color(0xFF42A88B),
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
    required this.capturedAt,
    required this.cashUsd,
    required this.goldUsd,
    required this.silverUsd,
  });

  final String label;
  final DateTime? capturedAt;
  final double cashUsd;
  final double goldUsd;
  final double silverUsd;

  double get totalValue => cashUsd + goldUsd + silverUsd;
}

class _JumpSummary {
  const _JumpSummary({
    required this.window,
    required this.fromLabel,
    required this.toLabel,
    required this.totalDelta,
    required this.cashDelta,
    required this.goldDelta,
    required this.silverDelta,
  });

  final _JumpWindow window;
  final String fromLabel;
  final String toLabel;
  final double totalDelta;
  final double cashDelta;
  final double goldDelta;
  final double silverDelta;
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

class _JumpWindowPicker extends StatelessWidget {
  const _JumpWindowPicker({required this.selected, required this.onSelected});

  final _JumpWindow selected;
  final ValueChanged<_JumpWindow> onSelected;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: _JumpWindow.values
          .map(
            (window) => FilterBlock(
              key: Key('portfolio_jump_${window.label.toLowerCase()}'),
              label: window.label,
              selected: selected == window,
              onTap: () => onSelected(window),
            ),
          )
          .toList(),
    );
  }
}

class _JumpSummaryStrip extends StatelessWidget {
  const _JumpSummaryStrip({required this.summary, required this.currency});

  final _JumpSummary summary;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final colors = context.kinetic;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.background.withValues(alpha: 0.26),
        borderRadius: AppTheme.tightRadius,
        border: Border.all(
          color: colors.border.withValues(alpha: 0.72),
          width: AppTheme.hairlineWidth,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          KineticText(
            '${summary.window.label} JUMP / ${summary.fromLabel} TO ${summary.toLabel}',
            style: AppTheme.labelStyle(colors).copyWith(fontSize: 11),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 14,
            runSpacing: 10,
            children: [
              _JumpDeltaChip(
                label: 'Total',
                delta: summary.totalDelta,
                currency: currency,
                color: colors.accent,
              ),
              _JumpDeltaChip(
                label: _cashMovementLabel(summary.cashDelta),
                delta: summary.cashDelta,
                currency: currency,
                color: colors.foreground,
              ),
              _JumpDeltaChip(
                label: 'Gold change',
                delta: summary.goldDelta,
                currency: currency,
                color: AppTheme.gold,
              ),
              _JumpDeltaChip(
                label: 'Silver change',
                delta: summary.silverDelta,
                currency: currency,
                color: const Color(0xFF42A88B),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _JumpDeltaChip extends StatelessWidget {
  const _JumpDeltaChip({
    required this.label,
    required this.delta,
    required this.currency,
    required this.color,
  });

  final String label;
  final double delta;
  final String currency;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final colors = context.kinetic;
    final valueColor = delta < 0 ? colors.loss : colors.profit;
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 132),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 18, height: 5, color: color),
          const SizedBox(width: 7),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                KineticText(
                  label,
                  maxLines: 1,
                  style: AppTheme.labelStyle(colors).copyWith(fontSize: 10.5),
                ),
                const SizedBox(height: 3),
                KineticText(
                  _signedMoney(delta, currency),
                  maxLines: 1,
                  style: AppTheme.bodyStyle(
                    colors,
                  ).copyWith(color: valueColor, fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
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
              currency: summary.currency,
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

String _signedMoney(double value, String currency) {
  final sign = value > 0
      ? '+'
      : value < 0
      ? '-'
      : '';
  return '$sign${CurrencyConverter.formatMoney(value.abs(), currency, decimals: 0)}';
}

String _cashMovementLabel(double value) {
  if (value > 0) return 'Cash added';
  if (value < 0) return 'Cash removed';
  return 'Cash flat';
}

class _TrendPainter extends CustomPainter {
  const _TrendPainter(this.points, this.series, this.colors, this.currency);

  final List<_TrendPoint> points;
  final List<_TrendSeries> series;
  final KineticColors colors;
  final String currency;

  @override
  void paint(Canvas canvas, Size size) {
    final normalizedCurrency = CurrencyConverter.normalize(currency);
    final leftPadding = normalizedCurrency == 'USD' ? 58.0 : 82.0;
    const rightPadding = 18.0;
    const topPadding = 34.0;
    const bottomPadding = 48.0;
    final graphWidth = size.width - leftPadding - rightPadding;
    final graphHeight = size.height - topPadding - bottomPadding;
    final plotBottom = topPadding + graphHeight;
    final plotRight = size.width - rightPadding;
    final gridPaint = Paint()
      ..color = colors.foreground.withValues(alpha: 0.12)
      ..strokeWidth = 1;
    final axisPaint = Paint()
      ..color = colors.foreground.withValues(alpha: 0.24)
      ..strokeWidth = 1.2;

    final values = <double>[
      0,
      for (final item in series)
        for (final point in points) item.valueOf(point),
    ];
    final maximum = values.reduce(math.max);
    final graphMaximum = _niceMaximum(maximum);

    for (var row = 0; row <= 6; row++) {
      final y = topPadding + graphHeight * row / 6;
      canvas.drawLine(
        Offset(leftPadding, y),
        Offset(plotRight, y),
        row == 6 ? axisPaint : gridPaint,
      );
      final value = graphMaximum * (6 - row) / 6;
      _paintText(
        canvas,
        _compactCurrency(value),
        colors.foreground.withValues(alpha: 0.66),
        fontSize: 10,
        offsetFor: (textSize) =>
            Offset(leftPadding - textSize.width - 9, y - textSize.height / 2),
      );
    }

    for (var index = 0; index < points.length; index++) {
      final x = points.length == 1
          ? leftPadding + graphWidth / 2
          : leftPadding + graphWidth * index / (points.length - 1);
      canvas.drawLine(Offset(x, topPadding), Offset(x, plotBottom), gridPaint);
      final shouldShowLabel =
          points.length <= 8 ||
          index == 0 ||
          index == points.length - 1 ||
          graphWidth / math.max(points.length - 1, 1) > 56;
      if (!shouldShowLabel) continue;
      _paintText(
        canvas,
        points[index].label,
        colors.foreground.withValues(alpha: 0.66),
        fontSize: 10,
        offsetFor: (textSize) =>
            Offset(x - textSize.width / 2, plotBottom + 14),
      );
    }

    for (var seriesIndex = 0; seriesIndex < series.length; seriesIndex++) {
      final item = series[seriesIndex];
      final offsets = <Offset>[];
      for (var index = 0; index < points.length; index++) {
        final x = points.length == 1
            ? leftPadding + graphWidth / 2
            : leftPadding + graphWidth * index / (points.length - 1);
        final y =
            topPadding +
            graphHeight -
            (item.valueOf(points[index]) / graphMaximum) * graphHeight;
        offsets.add(Offset(x, y));
      }

      if (offsets.length > 1) {
        canvas.drawPath(
          _smoothPath(offsets),
          Paint()
            ..color = item.color
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.7
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round,
        );
      }

      for (var index = 0; index < offsets.length; index++) {
        final offset = offsets[index];
        _paintText(
          canvas,
          _compactPointValue(item.valueOf(points[index])),
          colors.foreground.withValues(alpha: 0.76),
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
          offsetFor: (textSize) => Offset(
            offset.dx - textSize.width / 2,
            offset.dy - 22 - seriesIndex * 3,
          ),
        );
        _paintMarker(canvas, offset, item.color, square: seriesIndex == 0);
      }
    }
  }

  Path _smoothPath(List<Offset> offsets) {
    final path = Path()..moveTo(offsets.first.dx, offsets.first.dy);
    for (var index = 0; index < offsets.length - 1; index++) {
      final previous = offsets[index == 0 ? 0 : index - 1];
      final current = offsets[index];
      final next = offsets[index + 1];
      final afterNext =
          offsets[index + 2 < offsets.length ? index + 2 : offsets.length - 1];
      final firstControl = current + (next - previous) / 6;
      final secondControl = next - (afterNext - current) / 6;
      path.cubicTo(
        firstControl.dx,
        firstControl.dy,
        secondControl.dx,
        secondControl.dy,
        next.dx,
        next.dy,
      );
    }
    return path;
  }

  void _paintMarker(
    Canvas canvas,
    Offset offset,
    Color color, {
    required bool square,
  }) {
    final fillPaint = Paint()..color = color;
    final outlinePaint = Paint()
      ..color = colors.background
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6;
    if (square) {
      final rect = Rect.fromCenter(center: offset, width: 8, height: 8);
      canvas.drawRect(rect, fillPaint);
      canvas.drawRect(rect, outlinePaint);
      return;
    }
    canvas.drawCircle(offset, 4.4, fillPaint);
    canvas.drawCircle(offset, 4.4, outlinePaint);
  }

  void _paintText(
    Canvas canvas,
    String text,
    Color color, {
    double fontSize = 10,
    FontWeight fontWeight = FontWeight.w700,
    required Offset Function(Size textSize) offsetFor,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: fontSize,
          fontFamily: AppTheme.ledgerFontFamily,
          fontWeight: fontWeight,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(canvas, offsetFor(painter.size));
  }

  String _compactCurrency(double value) {
    return CurrencyConverter.compactMoney(value, currency).replaceAll('k', 'K');
  }

  String _compactPointValue(double value) {
    if (value >= 1000000) {
      return '${(value / 1000000).toStringAsFixed(1)}M';
    }
    if (value >= 1000) {
      return '${(value / 1000).round()}K';
    }
    return value.toStringAsFixed(0);
  }

  double _niceMaximum(double maximum) {
    if (maximum <= 0) return 1;
    const intervalCount = 6;
    final rawStep = (maximum * 1.12) / intervalCount;
    final magnitude = math
        .pow(10, (math.log(rawStep) / math.ln10).floor())
        .toDouble();
    final normalized = rawStep / magnitude;
    final niceNormalizedStep = normalized <= 1
        ? 1
        : normalized <= 2
        ? 2
        : normalized <= 4
        ? 4
        : normalized <= 5
        ? 5
        : 10;
    final step = niceNormalizedStep * magnitude;
    return (maximum / step).ceil() * step;
  }

  @override
  bool shouldRepaint(_TrendPainter oldDelegate) {
    return oldDelegate.points != points ||
        oldDelegate.series != series ||
        oldDelegate.colors != colors ||
        oldDelegate.currency != currency;
  }
}
