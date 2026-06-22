import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/asset.dart';
import '../models/portfolio_snapshot.dart';
import '../providers/asset_provider.dart';
import '../providers/display_currency_provider.dart';
import '../providers/metal_price_provider.dart';
import '../providers/portfolio_snapshot_provider.dart';
import '../services/currency_converter.dart';
import '../services/position_performance.dart';
import '../services/transaction_history_service.dart';
import '../theme/app_theme.dart';
import '../ui/kinetic/kinetic_widgets.dart';

class TransactionHistoryScreen extends ConsumerWidget {
  const TransactionHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.kinetic;
    final assets = ref.watch(assetProvider);
    final snapshots = ref.watch(portfolioSnapshotProvider);
    final displayCurrency = ref.watch(displayCurrencyProvider);
    final events = TransactionHistoryService.eventsFor(assets);
    final performance = PositionPerformance.calculate(
      assets,
      ref.watch(metalPriceProvider).snapshot,
      displayCurrency: CurrencyConverter.defaultCurrency,
    );

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        toolbarHeight: 68,
        backgroundColor: colors.background,
        centerTitle: true,
        leading: IconButton(
          key: const Key('back_history'),
          tooltip: 'Back',
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        title: KineticText(
          'Transaction history',
          style: AppTheme.titleStyle(colors).copyWith(fontSize: 20),
        ),
      ),
      body: SafeArea(
        top: false,
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              sliver: SliverList.list(
                children: [
                  KineticText(
                    'PAID VS NOW',
                    style: AppTheme.labelStyle(colors).copyWith(
                      color: colors.accent,
                      fontSize: 13,
                      letterSpacing: 1.0,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (!performance.hasComparablePositions)
                    const LedgerFrame(
                      cardless: true,
                      padding: EdgeInsets.zero,
                      child: KineticText(
                        'Add bought prices to active holdings to compare paid vs current worth.',
                        muted: true,
                      ),
                    )
                  else
                    _PerformanceTile(summary: performance),
                  Divider(
                    height: 36,
                    thickness: 1,
                    color: colors.border.withValues(alpha: 0.12),
                  ),
                  KineticText(
                    'TIMELINE',
                    style: AppTheme.labelStyle(colors).copyWith(
                      color: colors.accent,
                      fontSize: 13,
                      letterSpacing: 1.0,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (events.isEmpty)
                    const LedgerFrame(
                      cardless: true,
                      padding: EdgeInsets.zero,
                      child: KineticText(
                        'Add holding start or sold dates to build your timeline.',
                        muted: true,
                      ),
                    )
                  else
                    ...events.asMap().entries.map((entry) {
                      final index = entry.key;
                      final event = entry.value;
                      return Column(
                        children: [
                          _EventTile(event: event),
                          if (index < events.length - 1)
                            Divider(
                              height: 16,
                              thickness: 1,
                              color: colors.border.withValues(alpha: 0.08),
                            ),
                        ],
                      );
                    }),
                  Divider(
                    height: 36,
                    thickness: 1,
                    color: colors.border.withValues(alpha: 0.12),
                  ),
                  KineticText(
                    'NET WORTH SNAPSHOTS',
                    style: AppTheme.labelStyle(colors).copyWith(
                      color: colors.accent,
                      fontSize: 13,
                      letterSpacing: 1.0,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (snapshots.isEmpty)
                    const LedgerFrame(
                      cardless: true,
                      padding: EdgeInsets.zero,
                      child: KineticText(
                        'Save a snapshot from Wealth to begin tracking history.',
                        muted: true,
                      ),
                    )
                  else
                    ...snapshots.asMap().entries.map((entry) {
                      final index = entry.key;
                      final snapshot = entry.value;
                      return Column(
                        children: [
                          _SnapshotTile(
                            snapshot: snapshot,
                            currency: displayCurrency,
                          ),
                          if (index < snapshots.length - 1)
                            Divider(
                              height: 16,
                              thickness: 1,
                              color: colors.border.withValues(alpha: 0.08),
                            ),
                        ],
                      );
                    }),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LedgerIcon extends StatelessWidget {
  const _LedgerIcon({
    required this.icon,
    required this.foreground,
    required this.background,
  });

  final IconData icon;
  final Color foreground;
  final Color background;
  static const double size = 40;

  @override
  Widget build(BuildContext context) {
    final colors = context.kinetic;
    return Container(
      height: size,
      width: size,
      decoration: BoxDecoration(
        color: background,
        borderRadius: AppTheme.tightRadius,
        border: Border.all(
          color: colors.border.withValues(alpha: 0.56),
          width: AppTheme.hairlineWidth,
        ),
      ),
      child: Icon(icon, color: foreground, size: size * 0.48),
    );
  }
}

class _PerformanceTile extends StatelessWidget {
  const _PerformanceTile({required this.summary});

  final PositionPerformanceSummary summary;

  @override
  Widget build(BuildContext context) {
    final colors = context.kinetic;
    final change = summary.changeUsd;
    final isGain = change >= 0;
    return LedgerFrame(
      cardless: true,
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                KineticText(
                  'Portfolio performance',
                  style: AppTheme.bodyStyle(colors).copyWith(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                KineticText(
                  'PAID ${CurrencyConverter.formatMoney(summary.paidUsd, summary.currency)} / '
                  'NOW ${CurrencyConverter.formatMoney(summary.currentUsd, summary.currency)}',
                  style: AppTheme.labelStyle(colors).copyWith(
                    fontSize: 11,
                    letterSpacing: 0.5,
                    color: colors.mutedForeground,
                  ),
                ),
              ],
            ),
          ),
          KineticNumber(
            '${isGain ? '+' : '-'}${CurrencyConverter.formatMoney(change.abs(), summary.currency)}',
            fontSize: 20,
            color: isGain ? colors.profit : colors.loss,
          ),
        ],
      ),
    );
  }
}

class _EventTile extends StatelessWidget {
  const _EventTile({required this.event});

  final TransactionEvent event;

  @override
  Widget build(BuildContext context) {
    final colors = context.kinetic;
    final isSale = event.type == TransactionEventType.sold;
    final price = event.price == null
        ? 'No price'
        : CurrencyConverter.formatMoney(event.price!, event.asset.currency);
    return LedgerFrame(
      cardless: true,
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          _LedgerIcon(
            icon: isSale ? Icons.south_west_rounded : Icons.north_east_rounded,
            foreground: isSale ? colors.loss : colors.profit,
            background: isSale
                ? colors.loss.withValues(alpha: 0.16)
                : colors.profit.withValues(alpha: 0.16),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                KineticText(
                  '${isSale ? 'Sold' : 'Acquired'} ${event.asset.type.label}',
                  style: AppTheme.titleStyle(colors).copyWith(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 5),
                KineticText(
                  '${_formatDate(event.date)} • $price',
                  muted: true,
                  style: AppTheme.bodyStyle(colors).copyWith(fontSize: 13),
                ),
              ],
            ),
          ),
          KineticNumber(
            '${CurrencyConverter.formatNumber(event.asset.amount)} ${event.asset.unit}',
            fontSize: 18,
            color: colors.foreground,
          ),
        ],
      ),
    );
  }
}

class _SnapshotTile extends StatelessWidget {
  const _SnapshotTile({required this.snapshot, required this.currency});

  final PortfolioSnapshot snapshot;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final colors = context.kinetic;
    final total = _fromUsd(snapshot.totalUsd, currency);
    final gold = _fromUsd(snapshot.goldUsd, currency);
    final cash = _fromUsd(snapshot.cashUsd + snapshot.bankSavingsUsd, currency);
    return LedgerFrame(
      cardless: true,
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                KineticNumber(
                  CurrencyConverter.formatMoney(total, currency),
                  fontSize: 20,
                  currency: currency,
                ),
                const SizedBox(height: 5),
                KineticText(
                  _formatDateTime(snapshot.capturedAt),
                  muted: true,
                  style: AppTheme.bodyStyle(colors).copyWith(fontSize: 13),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          KineticText(
            'GOLD ${CurrencyConverter.formatMoney(gold, currency, decimals: 0)}\n'
            'CASH ${CurrencyConverter.formatMoney(cash, currency, decimals: 0)}',
            align: TextAlign.end,
            style: AppTheme.labelStyle(colors).copyWith(
              fontSize: 11,
              letterSpacing: 0.5,
              color: colors.mutedForeground,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

double _fromUsd(double value, String currency) {
  return CurrencyConverter.convertFromUsd(value, currency) ?? value;
}

String _formatDate(DateTime date) {
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  return '${date.year}-$month-$day';
}

String _formatDateTime(DateTime date) {
  final hour = date.hour.toString().padLeft(2, '0');
  final minute = date.minute.toString().padLeft(2, '0');
  return '${_formatDate(date)} $hour:$minute';
}
